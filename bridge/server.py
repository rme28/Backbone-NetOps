"""
Pont HTTP entre le jeu Godot et PTBuilder (dans Cisco Packet Tracer).

Endpoints :
  POST /command   -> le jeu dépose une commande de haut niveau (JSON), reçoit un job_id
  GET  /result/<job_id> -> le jeu vient lire le résultat d'un job (pending / ok / error)
  GET  /health     -> sonde de vitalité pour le jeu (ne consomme pas la file)
  GET  /next       -> PTBuilder (polling) vient chercher le prochain code JS à exécuter
  POST /result     -> PTBuilder repose le résultat d'un job exécuté

Voir bridge/README.md pour le protocole complet et les pièges connus (CORS, timing).
"""

import json
import threading
import time
import uuid
from collections import deque

from flask import Flask, request, jsonify, Response

from commands import build_action_code
from packettracer import wrap_job

app = Flask(__name__)
lock = threading.Lock()

queue = deque()      # jobs en attente d'être servis à PTBuilder : {id, js, not_before}
results = {}         # job_id -> {"status": "pending"|"ok"|"error", "result"/"error": ...}


@app.after_request
def add_cors_headers(response):
    # PT 9.x applique le CORS strictement sur son webview : sans ces en-têtes, le JS
    # peut envoyer la requête (le serveur la reçoit) mais ne peut PAS lire la réponse
    # -> onerror se déclenche et $se('runCode',...) n'est jamais appelé.
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response


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
