"""
Pont HTTP entre le jeu Godot et PTBuilder (dans Cisco Packet Tracer).

Endpoints :
  POST /command   -> le jeu dépose une commande de haut niveau (JSON), reçoit un job_id
  GET  /result/<job_id> -> le jeu vient lire le résultat d'un job (pending / ok / error)
  GET  /next       -> PTBuilder (polling) vient chercher le prochain code JS à exécuter
  POST /result     -> PTBuilder repose le résultat d'un job exécuté

Voir CLAUDE.md section 3 et 4 pour le protocole complet et les pièges connus.
"""

import json
import threading
import time
import uuid
from collections import deque

from flask import Flask, request, jsonify, Response

app = Flask(__name__)
lock = threading.Lock()


@app.after_request
def add_cors_headers(response):
    # PT 9.x applique le CORS strictement sur son webview : sans ces en-têtes, le JS
    # peut envoyer la requête (le serveur la reçoit) mais ne peut PAS lire la réponse
    # -> onerror se déclenche et $se('runCode',...) n'est jamais appelé. Voir diag.
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response

queue = deque()      # jobs en attente d'être servis à PTBuilder : {id, js, not_before}
results = {}         # job_id -> {"status": "pending"|"ok"|"error", "result"/"error": ...}

BRIDGE_URL = "http://127.0.0.1:8081"


def js_string(value):
    """Sérialise une valeur Python en littéral JS sûr (via JSON)."""
    return json.dumps(value)


def build_action_code(cmd):
    """Traduit une commande de haut niveau en code JS PTBuilder qui pose `result`."""
    action = cmd.get("action")

    if action == "addDevice":
        return "addDevice({name},{model},{x},{y}); result=true;".format(
            name=js_string(cmd["name"]),
            model=js_string(cmd["model"]),
            x=js_string(cmd.get("x", 0)),
            y=js_string(cmd.get("y", 0)),
        )

    if action == "addLink":
        return "addLink({d1},{i1},{d2},{i2},{cable}); result=true;".format(
            d1=js_string(cmd["dev1"]), i1=js_string(cmd["iface1"]),
            d2=js_string(cmd["dev2"]), i2=js_string(cmd["iface2"]),
            cable=js_string(cmd.get("cable", "straight")),
        )

    if action == "configureIos":
        ios = "\n".join(cmd["commands"])
        return "configureIosDevice({name},{ios}); result=true;".format(
            name=js_string(cmd["name"]), ios=js_string(ios),
        )

    if action == "configurePcIp":
        return "configurePcIp({name},{dhcp},{ip},{mask},{gw}); result=true;".format(
            name=js_string(cmd["name"]), dhcp=js_string(cmd.get("dhcp", False)),
            ip=js_string(cmd.get("ip", "")), mask=js_string(cmd.get("mask", "")),
            gw=js_string(cmd.get("gateway", "")),
        )

    if action == "getDevices":
        return "result = getDevices();"

    if action == "raw":
        # échappatoire : code JS PTBuilder brut fourni tel quel (doit poser `result`)
        return cmd["code"]

    raise ValueError("action inconnue: {}".format(action))


def wrap_job(job_id, action_code):
    """Enrobe le code d'action pour qu'il renvoie son résultat au pont via XHR sortant
    (voir CLAUDE.md 4.5). Pas de commentaires JS ici, tout sur une portée fonctionnelle
    unique -- le Script Engine de PTBuilder est sensible à ça (4.6)."""
    report_ok = (
        "var payload=JSON.stringify({{id:{jid},ok:true,result:result}});"
        "window.webview.evaluateJavaScriptAsync("
        "\"var x=new XMLHttpRequest();x.open('POST','{url}/result',true);x.send(\"+JSON.stringify(payload)+\");\");"
    ).format(jid=js_string(job_id), url=BRIDGE_URL)

    report_err = (
        "var payload=JSON.stringify({{id:{jid},ok:false,error:String(e)}});"
        "window.webview.evaluateJavaScriptAsync("
        "\"var x=new XMLHttpRequest();x.open('POST','{url}/result',true);x.send(\"+JSON.stringify(payload)+\");\");"
    ).format(jid=js_string(job_id), url=BRIDGE_URL)

    return "(function(){{var result=null;try{{{action}{report_ok}}}catch(e){{{report_err}}}}})();".format(
        action=action_code, report_ok=report_ok, report_err=report_err,
    )


@app.route("/command", methods=["POST"])
def post_command():
    cmd = request.get_json(force=True)
    try:
        action_code = build_action_code(cmd)
    except (KeyError, ValueError) as e:
        return jsonify({"error": str(e)}), 400

    job_id = uuid.uuid4().hex
    delay_before = float(cmd.get("delay_before", 0))
    job = {
        "id": job_id,
        "js": wrap_job(job_id, action_code),
        "not_before": time.time() + delay_before,
    }

    with lock:
        queue.append(job)
        results[job_id] = {"status": "pending"}

    return jsonify({"job_id": job_id})


@app.route("/result/<job_id>", methods=["GET"])
def get_result(job_id):
    with lock:
        res = results.get(job_id)
    if res is None:
        return jsonify({"error": "job inconnu"}), 404
    return jsonify(res)


@app.route("/health", methods=["GET"])
def health():
    # Sonde de vitalité pour le jeu (ne consomme PAS la file, contrairement à /next).
    return jsonify({"ok": True})


@app.route("/next", methods=["GET"])
def get_next():
    with lock:
        if queue and queue[0]["not_before"] <= time.time():
            job = queue.popleft()
            return Response(job["js"], mimetype="text/plain")
    return Response("", mimetype="text/plain")


@app.route("/result", methods=["POST"])
def post_result():
    # PTBuilder envoie le payload JSON en corps brut (pas forcément Content-Type json)
    raw = request.get_data(as_text=True)
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return jsonify({"error": "payload invalide"}), 400

    job_id = payload.get("id")
    with lock:
        if payload.get("ok"):
            results[job_id] = {"status": "ok", "result": payload.get("result")}
        else:
            results[job_id] = {"status": "error", "error": payload.get("error")}

    return jsonify({"received": True})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8081, threaded=True)
