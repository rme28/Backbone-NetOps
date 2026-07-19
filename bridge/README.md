# Pont Python - Jeu Godot ↔ Packet Tracer (PTBuilder)

Boîte aux lettres HTTP sur `127.0.0.1:8081`. Voir `CLAUDE.md` section 3-4 pour le
protocole complet.

## Lancer le pont

```bash
cd bridge
pip install -r requirements.txt
python server.py
```

## Endpoints

- `POST /command` - le jeu dépose une commande de haut niveau, reçoit `{"job_id": "..."}`.
- `GET /result/<job_id>` - le jeu lit le résultat : `{"status":"pending"}` /
  `{"status":"ok","result":...}` / `{"status":"error","error":"..."}`.
- `GET /next` - PTBuilder poll ici (toutes les 500ms) pour récupérer le prochain
  code JS à exécuter. Vide si rien à faire.
- `POST /result` - PTBuilder y repose le résultat brut de l'exécution.

## Actions supportées par `POST /command`

```json
{"action":"addDevice","name":"R1","model":"2911","x":100,"y":100}
{"action":"addLink","dev1":"R1","iface1":"GigabitEthernet0/0","dev2":"R2","iface2":"GigabitEthernet0/0","cable":"straight"}
{"action":"configureIos","name":"R1","commands":["enable","configure terminal","hostname R1","exit"]}
{"action":"configurePcIp","name":"PC1","dhcp":false,"ip":"192.168.0.10","mask":"255.255.255.0","gateway":"192.168.0.1"}
{"action":"getDevices"}
{"action":"raw","code":"result = 1+1;"}
```

Chaque commande accepte un champ optionnel `"delay_before": <secondes>` : le job
reste en file sans être servi tant que ce délai n'est pas écoulé (utile pour
laisser un équipement fraîchement posé finir de booter avant de le configurer -
voir CLAUDE.md 4.7).

## Tester seul avec curl (sans PT ni jeu)

```bash
curl -X POST http://127.0.0.1:8081/command -H "Content-Type: application/json" \
  -d '{"action":"addDevice","name":"R1","model":"2911","x":100,"y":100}'
# -> {"job_id": "..."}

curl http://127.0.0.1:8081/next
# -> le code JS que PTBuilder est censé exécuter

curl -X POST http://127.0.0.1:8081/result -d '{"id":"<job_id>","ok":true,"result":true}'

curl http://127.0.0.1:8081/result/<job_id>
# -> {"status":"ok","result":true}
```

## Bootstrap à coller dans le Builder Code Editor de PTBuilder

Une seule fois, après avoir activé l'IPC (voir CLAUDE.md 4.0). Ce code fait
tourner le polling qui va chercher les commandes sur le pont :

```javascript
window.webview.evaluateJavaScriptAsync("setInterval(function(){var x=new XMLHttpRequest();x.open('GET','http://127.0.0.1:8081/next',true);x.onload=function(){if(x.status===200&&x.responseText){$se('runCode',x.responseText)}};x.onerror=function(){};x.send()},500)");
```

## ⚠️ CORS (Packet Tracer 9.x)

Le serveur renvoie des en-têtes `Access-Control-Allow-Origin: *` sur **toutes** ses
réponses (`@app.after_request`). C'est **obligatoire** : sans ça, le webview de PT 9.x
bloque la lecture des réponses `GET /next` et le polling est cassé en silence (le
serveur répond 200 mais PTBuilder ne peut pas lire le code à exécuter). Voir CLAUDE.md
section 4.6bis. Ne pas retirer ces en-têtes.

## Étape suivante

Étape 2 du CLAUDE.md : valider la chaîne complète avec un vrai PT ouvert (poser
2 routeurs, les câbler, les configurer, via curl uniquement - pas encore de jeu).
