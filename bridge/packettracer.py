"""
Couche protocole bas niveau : génère le code JS exécuté par PTBuilder et gère
l'échappement du bac à sable (sandbox) pour renvoyer un résultat au pont.

Le moteur JS du Builder Code Editor est sandboxé (pas de XMLHttpRequest direct).
Pour faire un appel réseau sortant, on passe par `window.webview.evaluateJavaScriptAsync`
qui exécute du code dans le vrai contexte webview (qui, lui, a XMLHttpRequest).

Le webview de Packet Tracer 9.x applique le CORS strictement : sans en-têtes CORS sur
les réponses du pont, le GET part et le serveur répond 200, mais le JS ne peut pas lire
la réponse (onerror se déclenche, $se('runCode', ...) n'est jamais appelé). Voir server.py
pour l'ajout des en-têtes CORS.
"""

import json

BRIDGE_URL = "http://127.0.0.1:8081"


def js_string(value):
    """Sérialise une valeur Python en littéral JS sûr (via JSON)."""
    return json.dumps(value)


def wrap_job(job_id, action_code):
    """Enrobe le code d'action pour qu'il renvoie son résultat au pont via XHR sortant.
    Pas de commentaires JS ici, tout sur une portée fonctionnelle unique : le Script
    Engine de PTBuilder supprime les retours à la ligne, ce qui casserait un `//`."""
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
