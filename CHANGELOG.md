# Changelog

All notable changes to this project are documented here.

Versions follow SemVer with an alpha pre-release channel until the project reaches a more stable stage.

## [Unreleased]

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

[Unreleased]: https://github.com/rme28/Backbone-NetOps/compare/v0.3.0-alpha...HEAD
[0.3.0-alpha]: https://github.com/rme28/Backbone-NetOps/compare/v0.2.0-alpha...v0.3.0-alpha
[0.2.0-alpha]: https://github.com/rme28/Backbone-NetOps/compare/v0.1.0-alpha...v0.2.0-alpha
[0.1.0-alpha]: https://github.com/rme28/Backbone-NetOps/releases/tag/v0.1.0-alpha
