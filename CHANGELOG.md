# Changelog

Toutes les évolutions notables du projet sont consignées ici.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
versions selon [SemVer](https://semver.org/lang/fr/) avec canal de pré-version
(`-alpha`, `-beta`, `-rc`) tant qu'on est avant la `1.0.0`.

## [Non publié]

### Ajouté
- **Auto-lancement du pont** : le jeu detecte le pont au demarrage et le lance
  automatiquement s'il est absent, avec un statut visible en jeu (connecte / erreur).
- **Menu principal** : nouvelle partie, charger une partie, supprimer une sauvegarde.
- **Systeme de sauvegarde par rejeu** (event sourcing) : chaque action est
  journalisee ; sauvegarder ecrit le journal, charger le rejoue dans un PT vide.
  Le jeu est la seule source de verite (ne depend d'aucune sauvegarde de PT).
- **Menu pause** (Echap) : reprendre, sauvegarder, retour au menu principal.
- **Vider PT automatiquement** : nouvelle partie et chargement partent d'un canvas
  Packet Tracer propre, via `ipc.appWindow().fileNew(false)` (decouvert en explorant
  l'API interne de PT). PT reflete desormais exactement la partie en cours.

## [0.1.0-alpha] - 2026-07-19

Première tranche verticale jouable : marcher dans une salle 3D → poser un
équipement → le voir apparaître dans le vrai moteur Cisco Packet Tracer.

### Ajouté
- **Pont Python** (`bridge/server.py`) : serveur HTTP boîte aux lettres entre le
  jeu et PTBuilder (`POST /command`, `GET /next`, `POST /result`,
  `GET /result/<id>`, `GET /health`).
- Traduction des commandes haut-niveau (`addDevice`, `addLink`, `configureIos`,
  `configurePcIp`, `getDevices`, `raw`) en code JS PTBuilder + enrobage XHR sortant.
- File d'attente avec `delay_before` pour espacer création et configuration
  (temps de boot des équipements).
- **Jeu Godot 4.7** (`game/`) : salle 3D FPS construite par code, déplacement
  ZQSD + souris, autoload `Bridge` (client HTTP), touche `E` pour poser un
  routeur (cube en jeu + équipement réel dans Packet Tracer).

### Corrigé / découvert
- **CORS obligatoire pour Packet Tracer 9.x** : sans en-têtes
  `Access-Control-Allow-Origin` sur le pont, le webview de PT bloque la lecture
  des réponses `GET /next` et le polling échoue en silence. Ajout d'un
  `@app.after_request`. Documenté dans `CLAUDE.md` §4.6bis.

### Validé sur le terrain
- PT 9.0.0 : `addDevice`, `addLink` (lien UP), `configureIosDevice` (hostname +
  IP + `no shutdown` appliqués), `getDevices`.
- Chaîne complète depuis le jeu : les routeurs posés en 3D apparaissent dans PT.

[Non publié]: https://github.com/rme28/Backbone-NetOps/compare/v0.1.0-alpha...HEAD
[0.1.0-alpha]: https://github.com/rme28/Backbone-NetOps/releases/tag/v0.1.0-alpha
