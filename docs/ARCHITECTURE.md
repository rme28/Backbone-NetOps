# Architecture overview

This document targets developers building scenarios and missions on top of the
simulator base. Code comments are in French; public docs are in English.

## Layers

```
game/scripts/
  core/game_state.gd       GameState autoload: event journal, saves, settings
  network/network_sim.gd   NetSim autoload: authoritative network logic model
  network/bridge_client.gd Bridge autoload: optional local ns-3 helper service
  network/interfaces.gd    Interface lists per device category
  missions/objectives.gd   Objectives autoload: declarative objective catalog
  world/server_room.gd     Level: 3D world, interactions, terminal UI, visuals
```

Separation rule: NetSim never touches the scene tree or UI. The level feeds it
data and reads back results. Objectives read the journal and query NetSim.

## The event journal (single source of truth)

Every world mutation is an event appended to `GameState.events` and replayed on
load. Current event types:

| type | fields |
|---|---|
| place_device | name, model, category, world_pos, world_yaw, supported (optional) |
| add_link | dev1, iface1, dev2, iface2, cable |
| remove_link | dev1, iface1, dev2, iface2 |
| remove_device | name (cables must be removed first; the game does this) |
| ping_ok | src, dst, hops (progress marker, no visual effect) |

Device configuration (IP, VLANs, routes...) lives in
`GameState.device_configs[name]` and is persisted with the save.

To seed an initial infrastructure for a mission, append events to
`GameState.events` before the level rebuilds visuals. See `STARTER_EVENTS` in
`server_room.gd` for a working example.

## NetSim: the network model

Rebuilt from scratch after every change (topologies are small):

```gdscript
NetSim.rebuild(device_configs, NetSim.links_from_events(GameState.events))
```

Supported semantics: interface admin state and line protocol (cable + both
ends up), IPv4 with CIDR, connected routes, static routes with longest prefix
match, host default gateways, L2 switching with access VLANs, trunks (allowed
lists, native VLAN 1), VLAN-aware flooding, forward and return path checks,
loop detection, and DHCP (interfaces set to "dhcp" lease an address and a
gateway from a pool served inside their L2 domain; see effective_address()).

### Query API for objectives

```gdscript
NetSim.device_exists(name)
NetSim.cable_connected(dev, iface)
NetSim.interface_admin_up(dev, iface)
NetSim.link_protocol_up(dev, iface)
NetSim.ip_configured(dev, iface)
NetSim.vlan_exists(dev, vlan_id)
NetSim.port_in_vlan(dev, iface, vlan_id)
NetSim.route_exists(dev, "10.0.0.0/24")
NetSim.can_reach(src_dev, "10.0.0.2")
NetSim.ping(src_dev, dst_ip)        # {success, reason, path, dst_dev}
NetSim.traceroute(src_dev, dst_ip)
```

`ping()` failure reasons are stable strings ("no-route", "egress-down",
"next-hop-unreachable", "no-return-path", ...) usable in mission feedback.

## Objectives

`objectives.gd` holds a declarative catalog: id, title, points, bcoins, and a
`check` callable receiving the event journal. Checks may also query NetSim.
`Objectives.evaluate()` runs after every event and every configuration change.
Completed ids and score persist in the save. Adding a mission objective means
appending an entry to the catalog (or, later, loading a catalog per scenario).

## Terminal

The in-game CLI in `server_room.gd` follows a Cisco-like grammar with modes
(exec, config, config-if, config-vlan). Every command reads or writes
`_device_configs` then calls `_save_device_config()`, which persists and
resyncs NetSim. Nothing in the terminal is cosmetic. To add a command: extend
`_execute_terminal_command` dispatch and `TERMINAL_COMMANDS` (completion).

Implemented: hostname, interface, ip address, no ip address, shutdown,
no shutdown, description, ip route, no ip route, ip default-gateway, vlan,
name, no vlan, switchport mode access|trunk, switchport access vlan,
switchport trunk allowed vlan, ip address dhcp, ip dhcp pool, no ip dhcp
pool, show running-config, show ip interface brief,
show interfaces, show ip route, show vlan brief, ping, traceroute.

## Tests

```
godot --headless --path game --script tests/test_network_sim.gd
BACKBONE_SELFTEST=1 godot --headless --path game scenes/world/server_room.tscn
```

The first is a pure model suite. The second drives the full runtime (device
placement, cabling, terminal commands, VLAN isolation, unplugging, objectives)
and exits nonzero on failure.

## Dev helpers

Environment variables, inert in normal play:

| var | effect |
|---|---|
| BACKBONE_SCREENSHOT=path.png | take a screenshot then quit |
| BACKBONE_SHOT_POS / BACKBONE_SHOT_LOOK | "x,y,z" camera placement |
| BACKBONE_SCREENSHOT_SETUP=func | call a setup method before the shot |
| BACKBONE_SELFTEST=1 | run the end to end selftest |

## Known limitations (candidates for future work)

Not modeled yet: DNS, NAT, MAC address tables, spanning tree, wireless
radio coverage (access points bridge their wired ports), tagged subinterfaces
on routers. The NetSim rebuild-on-change design makes these straightforward to
add without touching the level code.

## ns-3 bridge

`bridge/server.py` plus `engine/ns3/` remain available as an optional deep
simulation backend (see README). Gameplay currently relies on NetSim, which
covers VLANs and gateways that the ns-3 scenario format does not.

## Interior art pass

`world/interior_art.gd` builds architecture and decoration, independent of NetSim.
It retains starter equipment coordinates and the event journal. Furniture uses
shared materials and licensed Kenney GLBs; `docs/THIRD_PARTY_ASSETS.md` lists sources.
`BACKBONE_INTERIOR_TEST=1 godot --headless --path game scenes/world/server_room.tscn`
checks player capsule clearance through eight doors, glass collision, 33 ports
across the starter switch and all equipment types (including rotated bodies),
and tabletop placement with JSON replay.

`equipment_art.gd` is the canonical metre-scale model factory used for equipment,
held previews and inventory thumbnails. Switch/router chassis are 1U (44 mm),
RJ45 shields 18 mm. Rack mounting keeps five-U service spacing between six
available slots. `supported=true` on a placement event suppresses its folding
stand when placed on a physical work surface. NetSim is unchanged.

Static dressing and device details use material batches (MultiMesh); live port
LEDs remain separate. Opaque walls act as occluders. Mobile Vulkan is the default
renderer with 2x MSAA; two spot shadow lights provide local contact shadows.

`BACKBONE_VISUAL_TOUR=/absolute/existing/directory` renders seven world views and
five interfaces, reporting sampled FPS/draw counts. `BACKBONE_CATALOG_ICONS=dir`
regenerates real-model thumbnails. `BACKBONE_MENU_SCREENSHOT=path.png` captures
the menu; `BACKBONE_HIDE_HUD=1` hides HUD for the existing screenshot helper.
Screenshots are stored locally in ignored `artifacts/`.

`soundscape.gd` adds footsteps, UI/connector clicks and local rack fan ambience,
through the existing Effects/Master buses. Original deterministic WAV assets can
be regenerated with `python3 tools/generate_audio.py` (standard library only).
