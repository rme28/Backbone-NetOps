# Changelog

All notable changes to this project are documented here.

Versions follow SemVer with an alpha pre-release channel until the project reaches a more stable stage.

## [Unreleased]

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
