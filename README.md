# Backbone NetOps

**The ultimate network engineer simulator.**

A 3D first-person game where you walk through a server room, place real Cisco devices, connect them with cables, and configure them using genuine Cisco IOS commands to complete objectives and climb the leaderboard. The difference is that nothing is faked: all networking (routing, switching, CLI) runs live on the real **Cisco Packet Tracer** engine while you play.

No fake terminal that accepts anything. If you misconfigure an interface, it won't work-exactly as it would on a real router. Unless it's a Cisco Packet Tracer issue, as usual. In a future release, a Debug button will be added, allowing you to restart or reload the Packet Tracer topology running in the background to rule out potential Cisco Packet Tracer bugs.
## The Concept

You start in a server room. You place a router, a switch, and a PC. You connect them with cables. You open a console session and type real Cisco IOS commands. The game simply gives you a body and hands inside a server room; **Packet Tracer** handles the network simulation behind the scenes, as if you were sitting in front of the real Cisco software-except you're physically inside it.

## How It Works

The project consists of three components:

- **The game** (Godot 4 / GDScript): the 3D environment, movement, and interactions.
- **The bridge** (Python): connects the game to Packet Tracer.
- **Packet Tracer + PTBuilder**: the real Cisco networking engine running in the background.

Packet Tracer is **not** included with the game (due to Cisco licensing). You must install it yourself, free of charge, through a Cisco NetAcad account, just as you would for any other Cisco tool.

## Current Status: Alpha 0.1.0

The project is still in its very early stages. The following features are already working and have been validated with **Packet Tracer 9.0.0**:

- Move around a 3D server room in first-person (WASD + mouse)
- Place a router in the game and have it instantly appear in Packet Tracer
- Connect devices with cables
- Configure devices using real Cisco IOS commands (hostname, IP addresses, interfaces) and see the configuration applied live

Not implemented yet: a full equipment palette, mouse-based cabling, an in-game interactive IOS terminal, objectives and scoring, automatic validation (ping tests, VLAN verification, etc.). At this stage, the project is a proof of concept demonstrating that the idea works—not yet a complete game.

See [CHANGELOG.md](CHANGELOG.md) for the complete version history.

## Running the Project

**Prerequisites:** [Cisco Packet Tracer](https://www.netacad.com/) (latest version) + the [PTBuilder](https://github.com/kimmknight/PTBuilder) extension, with IPC enabled.

```bash
# 1. Start the bridge
cd bridge
pip install -r requirements.txt
python server.py

# 2. In Packet Tracer: Extensions > Builder Code Editor,
#    paste the polling bootstrap (see bridge/README.md)

# 3. Launch the game in Godot 4
```

Full setup instructions are available in [bridge/README.md](bridge/README.md).

## Releases

Versions are tagged using the `vX.Y.Z-alpha` format until the project reaches a stable release.

See [RELEASING.md](RELEASING.md) for the full release process, and the [Releases](../../releases) page to download a specific version.