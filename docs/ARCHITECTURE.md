# Architecture and developer handover

Godot 4.7, Mobile Vulkan. Open `game/project.godot`; `tools/verify.sh` runs all
headless suites using Godot/Godot4 or the installed Flatpak.

## Ownership

| Module | Responsibility |
|---|---|
| `core/game_state.gd` | Save files, event journal, device configuration, settings |
| `network/network_sim.gd` | Authoritative IPv4, VLAN, DHCP, routing, reachability and probe NAT; no scene dependency |
| `network/operator_network.gd` | Fixed simulated ISP topology and documentation IPv4 ranges |
| `network/host_service.gd` | PC configuration validation and diagnostic commands; persistence callback |
| `network/interfaces.gd` | Interface names by category |
| `equipment/catalog.gd` | Data-driven equipment catalog loader |
| `player/player.gd` | Movement, mouse view, crouch and overhead clearance |
| `world/server_room.gd` | Scene coordinator, journal-to-world replay, targeting, cable/placement interactions, UI session state |
| `world/building.gd` | Existing room layout, furniture and imported prop normalization |
| `world/interior_art.gd` | Architecture details, shared materials, static batching |
| `world/equipment_art.gd` | Canonical metre-scale equipment meshes, ports, thumbnails |
| `world/infrastructure/fixed_network.gd` | Wall sockets, matching patch jacks, ONT and fixed interaction targets |
| `ui/level_ui.gd` | Construction of level HUD, inventory, terminal, hub and pause widgets |
| `ui/terminal/network_cli.gd` | Appliance CLI parser and commands |
| `ui/pc_os/desktop.gd` | PC desktop and its Network/Terminal/Browser/System apps |
| `ui/design_system.gd`, `ui/settings_panel.gd` | Shared theme and settings |
| `missions/objectives.gd` | Declarative objective checks and rewards |

The scene still owns interaction/session registries. Builders receive that scene
explicitly; its small forwarding methods retain the existing integration points.
NetSim remains independent of render nodes. Changing a mesh must preserve its
logical `(device, interface)` identity and the port position registry.

## Persistence and fixed infrastructure

`GameState.events` replays `place_device`, `add_link`, `remove_link`,
`remove_device`; `ping_ok` records progress. Placement includes position, yaw and
optional `supported` for tabletop equipment. Configurations live separately in
`GameState.device_configs`, including host DHCP/static settings and NAT roles.

`office_hosts_v1` is a one-time journal migration: existing saves gain the office
hosts without duplicating their starter PC or resurrecting subsequently removed
hosts. Monitor interaction uses the matching host name.

Fixed wall runs and the ONT are rebuilt deterministically before cable replay;
they cannot be removed or configured as appliances. Each numbered wall jack is
one independent passive run to the same numbered patch jack at the north wall
of the network room. It preserves VLAN tags and needs continuity through both
ends. It is not a switch joining neighbouring sockets. Player patch cords still
use normal journal events. Decorative panels in movable racks remain decorative.

The operator's hidden devices/links are merged into the NetSim snapshot, never
into player-created journal entries. `_sync_netsim()` is the single synchronization
point, followed by LED refresh and objective evaluation.

## PC and appliance interfaces

`T` on a PC/laptop or its office monitor opens the desktop. The Network form
validates inputs before applying them atomically through `HostService.configure`.
DHCP resolves an effective address and gateway; save files retain the DHCP intent.
The PC terminal supports `ipconfig`, `ifconfig`, `ip addr`, `route`, `ping`,
`tracert`/`traceroute`, `help`, `clear`. It does not expose IOS configuration modes.

The browser is a simulated connectivity test, not a real HTTP client. Its built-in
bookmark `connectivity.backbone.test` maps to `198.51.100.10` locally in the app;
this is not DNS. IPv4 destinations can also be entered directly. Reachability is
queried anew for every request.

Switches/routers keep the existing CLI and modes. Add appliance commands in
`ui/terminal/network_cli.gd`, register completion strings in `TERMINAL_COMMANDS`
in the coordinator, and persist through `_save_device_config`. Add PC commands
in `network/host_service.gd` and corresponding tests.

## WAN exercise

Connect a router's `eth0` to `WAN-ONT/client`, and its `eth1` to the LAN switch.
A minimal router configuration is:

```
configure terminal
interface eth0
ip address dhcp
no shutdown
ip nat outside
exit
interface eth1
ip address 192.168.10.1/24
no shutdown
ip nat inside
exit
ip nat overload
ip route 0.0.0.0/0 203.0.113.1
end
```

Give a LAN PC `192.168.10.20/24`, gateway `192.168.10.1`, then test
`198.51.100.10`. Static WAN addressing in `203.0.113.0/24` is also supported;
avoid `.1` (gateway), network/broadcast addresses and DHCP lease collisions.

NAT translates sources only when a probe crosses an inside interface to an
outside interface on an enabled router/firewall. NetSim checks the external
return path and each reverse mapping. Mappings are scoped to one probe; there
is no persistent TCP/UDP/PAT session simulation or unsolicited inbound mapping.
`no ip nat overload` disables it; `no ip nat inside/outside` clears a role.

## Extending equipment and scenarios

Equipment data lives in `game/resources/equipment/devices.json`. Follow an existing entry,
add interface names to `DeviceInterfaces.BY_CATEGORY`, and add its dimensions,
body/port layout to `equipment_art.gd`. Keep physical jack transforms consistent
with interaction positions. Update model/runtime port tests. New visual variants
should reuse logical categories whenever possible.

Scenario checks can query:

```gdscript
NetSim.device_exists(name)
NetSim.cable_connected(device, iface)
NetSim.interface_admin_up(device, iface)
NetSim.link_protocol_up(device, iface)
NetSim.effective_address(device, iface)
NetSim.effective_gateway(device)
NetSim.port_in_vlan(device, iface, vlan)
NetSim.route_exists(device, "0.0.0.0/0")
NetSim.ping(device, "198.51.100.10") # success, reason, path, dst_dev
NetSim.can_reach(device, "198.51.100.10")
```

`Objectives` checks the journal and model after changes. Add declarative checks
there; do not infer success from a mesh colour or GUI label. No campaign was added.

## QA helpers and boundaries

`tools/verify.sh`: model, player clearance, host apps, level interactions, interior
passages/ports/replay, WAN failure cases and actual GUI/CLI integration.
`BACKBONE_VISUAL_TOUR=/absolute/existing/dir` captures the building and interfaces.
`BACKBONE_WAN_TEST=1 BACKBONE_WAN_CAPTURES=/absolute/existing/dir` captures online
and unplugged browser results. Helpers never write a user's save unless a test
explicitly uses a unique disposable save name. Captures stay in ignored `artifacts/`.

Crouch is hold Ctrl; the capsule keeps its feet fixed and the camera transitions
smoothly. Standing requires overhead clearance. No sprint existed in the baseline.
Interior openings remain traversable; the exterior entry is a fixed level boundary.
Old arbitrary saved placements may overlap new furnishings. DNS, STP, MAC tables
and radio Wi-Fi remain future work. Optional `bridge/` + `engine/ns3/` are retained;
gameplay and these tests rely on NetSim. Asset sources are in THIRD_PARTY_ASSETS.md.
