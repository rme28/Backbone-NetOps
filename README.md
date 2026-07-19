# Backbone NetOps

**Le simulateur ultime d'ingenieur reseau.**

Un FPS 3D dans lequel tu marches dans une salle serveur, poses de vrais equipements Cisco, les cables, et les configures avec de vraies commandes IOS pour remplir des objectifs et grimper au score. Sauf qu'ici, aucune simulation n'est bidonnee : tout ce qui se passe reseau (routage, switching, CLI) tourne dans le vrai moteur de **Cisco Packet Tracer**, en live, pendant que tu joues.

Pas de faux terminal qui accepte n'importe quoi. Si tu configures mal une interface, ca ne marchera pas, exactement comme sur un vrai routeur.

## Le concept

Tu es dans une salle. Tu poses un routeur, un switch, un PC. Tu les cables. Tu ouvres une session sur l'equipement et tu tapes du vrai IOS. Le jeu ne fait que te donner un corps et des mains dans une salle serveur ; c'est Packet Tracer qui simule le reseau derriere, comme si tu etais assis devant le vrai logiciel Cisco, sauf que tu y es physiquement.

## Comment ca marche

Trois briques :

- **Le jeu** (Godot 4 / GDScript) : la salle 3D, le deplacement, les interactions.
- **Le pont** (Python) : fait la liaison entre le jeu et Packet Tracer.
- **Packet Tracer + PTBuilder** : le vrai moteur reseau Cisco, qui tourne en arriere-plan.

Packet Tracer n'est jamais fourni avec le jeu (licence Cisco oblige). Tu l'installes toi-meme, gratuitement, via un compte Cisco NetAcad, comme pour n'importe quel outil.

## Etat actuel : Alpha 0.1.0

C'est tres tot. Voici ce qui marche deja, valide en conditions reelles sur Packet Tracer 9.0.0 :

- Se deplacer dans une salle 3D en vue FPS (ZQSD + souris)
- Poser un routeur dans le jeu et le voir apparaitre instantanement dans Packet Tracer
- Le cabler entre deux equipements
- Le configurer avec de vraies commandes IOS (hostname, IP, interfaces) et voir la config s'appliquer reellement

Ce qui n'existe pas encore : palette d'equipements, cablage a la souris, terminal IOS jouable en jeu, objectifs et systeme de score, verification automatique (ping, VLAN...). Bref, c'est une fondation qui prouve que le concept tient la route, pas encore un jeu.

Voir [CHANGELOG.md](CHANGELOG.md) pour le detail des versions.

## Faire tourner le projet

Prerequis : [Cisco Packet Tracer](https://www.netacad.com/) (dernier version) + l'extension [PTBuilder](https://github.com/kimmknight/PTBuilder), avec l'IPC active.

```bash
# 1. Lancer le pont
cd bridge
pip install -r requirements.txt
python server.py

# 2. Dans Packet Tracer : Extensions > Builder Code Editor, coller le bootstrap de polling (voir bridge/README.md)

# 3. Lancer le jeu dans Godot 4
```

Details complets dans [bridge/README.md](bridge/README.md).

## Releases

Les versions sont taguees (`vX.Y.Z-alpha` tant qu'on n'est pas stable). Voir [RELEASING.md](RELEASING.md) pour le detail du processus, et l'onglet [Releases](../../releases) pour telecharger une version precise.
