# Backbone NetOps

**The ultimate network engineer simulator.**

Backbone NetOps is a 3D first-person network simulation game built with Godot 4. Walk through a small company building, install equipment, connect exact ports, configure devices from a realistic command line, and build a working infrastructure. Every command and every cable affects a real logical network model: what should not work, does not work, for an understandable reason.

The project runs locally without virtual machines, containers, paid services, or proprietary network software.

## Current Status: Alpha 0.5.0 (development)

The project is an early playable alpha. The current version includes:

- A furnished workplace with glazed partitions, meeting and staging areas, textured materials, shared UI styling and real-model inventory thumbnails
- Metre-scale equipment, numbered RJ45 sockets, curved cables, tabletop placement and subtle spatial sound
- A first-person company building: server room, corridor, open space offices, reception, entrance, break room, and a technical closet with the operator WAN entry
- An authoritative logical network model: interface and line protocol states, IPv4 subnets, static routing with longest prefix match, default gateways, access VLANs, trunks, return path checks, and clear failure reasons
- Distinct procedural models for routers, switches, access points, firewalls, computers, servers, and NAS devices, plus a 19 inch patch rack and a work table
- Visible and selectable network interfaces
- Port-to-port cabling with RJ45 and optical cable types
- Automatic racking: aim a placed patch rack and place compact network gear on it to mount it in the next free unit
- A categorized equipment inventory opened with Tab, showing the selected item held in the player's view
- Routers, L2 switches, multilayer switches, wireless routers, firewalls, and access points
- Desktop computers, servers, NAS devices, a client laptop, and a unique technician laptop
- An interactive network command line with command history, shortcuts, contextual help, and Tab completion
- Per-device interface configuration, IP addressing, static routes, VLANs, trunks, default gateways, DHCP, and administrative state
- ping and traceroute with instant feedback, the layer 3 path, and real failure reasons
- Cable disconnection, device removal, and port status LEDs driven by the simulation
- An optional local ns-3 engine as a deep simulation backend
- Saved games based on a replayable event journal
- Objectives, score, optional rewards, and the B-Coin currency
- A technician hub with mail, jobs, shop, dashboard, and settings sections
- A landing screen, redesigned main, pause, inventory, terminal, and settings interfaces
- Audio, video, mouse sensitivity, and interface settings that apply immediately and persist across sessions
- A first set of CC0 3D assets (Kenney Furniture Kit and Space Kit) used for break room furniture and wireless equipment

Some equipment, applications, and advanced network features are present as foundations and will be expanded in future releases.

## Project Structure

The project has three main components:

- `game/`: Godot 4 game, 3D world, interfaces, interactions, saves, objectives, and command line
- `bridge/`: local Python service connecting Godot to the simulation engine
- `engine/ns3/`: Backbone NetOps simulation program compiled with ns-3

Gameplay logic runs on an authoritative network model inside the game (see docs/ARCHITECTURE.md). The bridge and the ns-3 program remain available as an optional deep simulation backend. Scenario and mission developers should start with docs/ARCHITECTURE.md.

## Requirements

- Godot 4.7 or newer
- Python 3
- Flask
- ns-3.47
- A Vulkan-compatible graphics driver, or Godot compatibility rendering on older hardware

## Development Setup

Clone and build ns-3.47 next to the project directory:

```bash
cd ~/Projects
git clone https://gitlab.com/nsnam/ns-3-dev.git ns-3
cd ns-3
git checkout ns-3.47
./ns3 configure --build-profile=release
```

Link the Backbone NetOps engine source into ns-3, then build only that target:

```bash
ln -s ~/Projects/Backbone-NetOps/engine/ns3/backbone-engine.cc scratch/backbone-engine.cc
./ns3 build backbone-engine
```

Create the Python environment:

```bash
cd ~/Projects/Backbone-NetOps/bridge
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

Open the `game/` directory with Godot and run the project. The game can also start the local bridge automatically when its Python environment is available.

## Default Controls

- `WASD` or `ZQSD`: move
- Mouse: look around
- `Tab`: open the equipment inventory
- `E`: place the selected equipment
- Hold right click: precision view for small connectors
- Left click on a port: start or complete a cable connection, or unplug an occupied port
- `T`: open an equipment console or interact with the technician laptop
- `X`: remove the targeted equipment (its cables are unplugged first)
- `Escape`: close the current interface or open the pause menu
- Up and Down arrows in the terminal: browse command history
- `Tab` in the terminal: complete a command
- `?` in the terminal: display contextual command help

## Network Console

The command line follows a familiar network equipment workflow. Examples:

```text
enable
configure terminal
hostname R1
interface eth0
ip address 10.0.1.1 255.255.255.0
no shutdown
end
show ip interface brief
show ip route
ping 10.0.1.2
traceroute 10.0.1.2
```

On switches, VLANs use the same conventions:

```text
vlan 10
name USERS
interface eth0
switchport access vlan 10
interface eth5
switchport mode trunk
switchport trunk allowed vlan 10,20
show vlan brief
```

Hosts accept `ip default-gateway A.B.C.D` so routed pings answer correctly.

Common abbreviations such as `sh run`, `conf t`, `int eth0`, and `ip add` are supported.

## Releases

Versions follow SemVer and use the `vX.Y.Z-alpha` format until the project reaches a more stable stage.

See [CHANGELOG.md](CHANGELOG.md) for the version history and [RELEASING.md](RELEASING.md) for the release process.
