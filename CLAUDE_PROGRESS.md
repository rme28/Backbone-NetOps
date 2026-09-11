# Session progress

> Current functional/visual work and tested state: see [DEV_PROGRESS.md](DEV_PROGRESS.md). This file preserves the previous technical handover.

Working file for session handover. Branch: custom-cli. All commits tested.

## Done (this session, committed)

- NetSim autoload (scripts/network/network_sim.gd): authoritative network model. L2 VLAN-aware switching, trunks, IPv4, longest prefix routing, default gateways, DHCP leases, line protocol states, return path checks, loop detection, stable failure reasons. Scenario query API (can_reach, port_in_vlan, route_exists...). ns-3 kept as optional backend only.
- Terminal fully wired to NetSim: vlan, switchport access/trunk, trunk allowed vlan, ip default-gateway, ip address dhcp, ip dhcp pool, no ip route, show vlan brief, show interfaces, traceroute, show ip int brief with Status/Protocol, ping with real reasons and path.
- Cabling: unplug (click occupied port), device removal (X key), port status LEDs, cable node registry, remove_link/remove_device/ping_ok journal events.
- World: south wing (corridor, open space with desks, reception, entrance, WAN technical closet), signage, per zone lighting. Starter infrastructure seeded through STARTER_EVENTS on new games.
- Objectives driven by real network state (first cable, link up, first ping, routed ping). Technician hub dashboard shows live NetSim stats. UI: contextual prompt above crosshair, panel open fades, smaller held item.
- Docs: docs/ARCHITECTURE.md (scenario dev guide, EN), README and CHANGELOG updated.
- Tests: tests/test_network_sim.gd (28 checks) and BACKBONE_SELFTEST=1 runtime selftest (13 checks). Both green.

## In progress

- Nothing half done. Tree clean at each commit.

## Remaining priorities

1. Further visual pass on network gear models if the owner still dislikes them (reference photos in /home/romain/Bureau/Projets/Images/; ports are now bezeled RJ45, racks have patch panels)
2. Sound effects (none exist; needs assets)
3. Not modeled yet: DNS, NAT, MAC tables, STP, wireless radio, router subinterfaces (documented in ARCHITECTURE.md)
4. Real key remapping (explicitly postponed by the owner earlier)
5. Scenario framework itself is out of scope by request; the query API and event seeding are ready for it

## Important bugs

- None known. Verify commands: see Tests section of docs/ARCHITECTURE.md.

## Next action

- Optional polish only. The base is complete and tested. If resuming: run both test suites first, then pick from Remaining priorities.
