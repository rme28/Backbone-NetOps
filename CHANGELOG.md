# Changelog

All notable changes to this project are documented here.

Versions follow SemVer with an alpha pre-release channel until the project reaches a more stable stage.

## [Unreleased]

### Added

- Workplace art pass: glazed server/operations rooms, meeting area, staging benches, window bays, furnished offices, reception and kitchenette
- Consistent metre-scale equipment with chamfered enclosures, 18 mm RJ45 connectors, numbered ports and shared inventory thumbnails
- Curved single-mesh cables, correctly oriented boots, precision view (right click) and hovered-port outline
- Shared menu/terminal/inventory theme and original subtle footsteps, connector/UI clicks and spatial fan ambience
- Tabletop placement retained through event replay; capsule/connector/replay regression checks and renderer screenshot tour

- Authoritative logical network model (NetSim): line protocol states, IPv4 subnets, longest prefix routing, host default gateways, access VLANs, trunks with allowed lists, forward and return path checking, loop detection, and clear failure reasons
- New terminal commands, all wired to the simulation: vlan, name, no vlan, switchport mode access, switchport mode trunk, switchport access vlan, switchport trunk allowed vlan, ip default-gateway, no ip route, show vlan brief, show interfaces, traceroute
- show ip interface brief now reports both Status and Protocol columns
- Cable disconnection: click an occupied port to unplug it, journaled and replayable
- Device removal: aim a device and press X to remove it (cables unplug first, rack slots are freed, saves replay correctly)
- Port status LEDs on every device: green when the link is up, amber when cabled but down
- Ports now render as real RJ45 connectors (light bezel, dark cavity), racks include a patch panel, offices gained a printer corner
- Contextual action prompt above the crosshair (connect, unplug, open console, rack)
- South building wing: corridor, open space offices with desks, reception, entrance, and a technical closet with the operator WAN entry point
- Starter infrastructure seeded on new games through regular journal events (two racks, a core switch, an office workstation)
- Network related objectives: first cable, first active link, first ping, ping across a router
- Scenario query API documented in docs/ARCHITECTURE.md, plus a headless model test suite and a full runtime selftest
- Switch and host interfaces now start enabled like real hardware; routers still boot shut down
- DHCP: hosts accept ip address dhcp, routers and servers serve one line pools (ip dhcp pool NETWORK/PREFIX gateway A.B.C.D); leases resolve through the layer 2 domain, appear in show ip interface brief, and provide the default gateway

### Changed

- Mobile Vulkan renderer, 2x MSAA, spatial static batching and wall occlusion; sampled 52–61 FPS at 1080p on the tested Quadro K2100M
- Decorative furniture is consistently scaled and uses a shared material palette; prominent fixtures no longer overexpose

- ping now runs against the logical model with instant feedback, real failure reasons, and the layer 3 path
- Held item preview is smaller and less intrusive
- Signage, lighting, and layout polish across the facility

### Fixed

- Terminal auto refresh dead code removed
- Racked and unplugged interface bookkeeping stays consistent after save replay

## [0.4.0-alpha] - 2026-08-23

### Added

- Option to hide the on-screen help overlay (Settings menu, Interface section)
- The selected inventory item is now shown held in the player's view
- Redesigned main menu with a consistent visual style (buttons, cards, saves list)
- Landing screen (Play, Play Online coming soon, Settings, Quit) in front of the mission menu
- Settings keybindings are now shown as visual key badges instead of plain text
- New placeable equipment: 19 inch patch rack (aim and place equipment on it to rack it automatically, 6U), work table, and a client laptop (functional network device, distinct from the technician's unique laptop)
- Small break room annex east of the server room, connected through a doorway
- First CC0 3D assets from Kenney's Furniture Kit and Space Kit (kenney.nl, public domain): table, chairs, and bookcase in the break room, wireless router and access point models, all with a coded fallback if the asset files are ever missing

### Changed

- Equipment shells now use subtle procedural surface variation and rim lighting so they stand out better against the dark floor
- Materials are now cached and shared instead of being regenerated for every placed device
- Equipment materials are less glossy and metallic (matte painted look instead of polished metal)
- Only compact network gear (routers, switches, access points, firewalls) can be racked; racked equipment now uses smaller labels and no floating port tags to avoid clutter when several units are stacked
- Rebuilt router, switch, and firewall proportions and port layout from reference product photos: flatter chassis, recessed front port panel, flush ports, two row port layout for switches, distinct compact firewall shape
- Routers and switches gained rack mount ears and status LED strips

### Fixed

- Video and audio settings are now applied at startup and persist across sessions
- Render scale now affects the 3D viewport, UI scale now scales the whole interface
- Music and Effects volume sliders now drive dedicated audio buses instead of doing nothing

## [0.3.0-alpha] - 2026-08-22

### Added

- Local ns-3.47 simulation engine and dynamic topology scenarios
- Routed ICMP tests using the equipment, interfaces, links, addresses, and routes configured in the game
- Interactive network command line with contextual help, history, completion, and common command abbreviations
- Device configuration modes, interface state, IPv4 addressing, static routing, and L2 restrictions
- Detailed server room with lighting, raised flooring, cable routing, and equipment carts
- Distinct procedural models for network and system equipment
- Visible ports with exact port-to-port cabling and interface inspection
- Categorized inventory for network equipment, systems, accessories, and tools
- RJ45 and optical cable selection
- Routers, L2 switches, multilayer switches, wireless routers, firewalls, access points, NAS devices, servers, and desktop computers
- Unique technician laptop with dashboard, mail, jobs, shop, and settings sections
- B-Coin currency and optional objective rewards
- Redesigned main menu, pause menu, inventory, terminal, and settings interface
- Persistent audio, video, mouse sensitivity, and interface settings

### Changed

- Replaced the previous external network engine with a local, open source ns-3 architecture
- Reworked the Python bridge to generate and execute local ns-3 scenarios
- Expanded saved games with device configurations and B-Coin balances
- Updated the equipment catalog to use generic device categories

### Removed

- Previous proprietary network engine integration
- Previous polling protocol, commands, and related documentation

## [0.2.0-alpha] - 2026-07-19

### Added

- Saved games based on a replayable event journal
- Main menu and pause menu
- Automatic local bridge startup

## [0.1.0-alpha] - 2026-07-19

### Added

- First playable 3D server room
- First-person movement
- Initial equipment placement

[Unreleased]: https://github.com/rme28/Backbone-NetOps/compare/v0.4.0-alpha...HEAD
[0.4.0-alpha]: https://github.com/rme28/Backbone-NetOps/compare/v0.3.0-alpha...v0.4.0-alpha
[0.3.0-alpha]: https://github.com/rme28/Backbone-NetOps/compare/v0.2.0-alpha...v0.3.0-alpha
[0.2.0-alpha]: https://github.com/rme28/Backbone-NetOps/compare/v0.1.0-alpha...v0.2.0-alpha
[0.1.0-alpha]: https://github.com/rme28/Backbone-NetOps/releases/tag/v0.1.0-alpha
