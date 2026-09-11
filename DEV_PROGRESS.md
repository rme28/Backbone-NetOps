# Handover — 2026-09-11 — custom-cli
- Done: visual pass retained; Ctrl crouch with clearance; mounted sockets and independent passive patch runs; desk/TV/sign placement corrections; real PC desktop with network form, host terminal and connectivity browser; functional ONT/operator DHCP/NAT.
- Cleanup: building.gd, level_ui.gd and terminal/network_cli.gd extracted; coordinator reduced to ~1,800 lines. Dead helpers removed. docs/ARCHITECTURE.md covers extension points and a working WAN configuration.
- Tested: 33 network cases, 6 player checks, 11 host-app checks, 15 WAN model cases, 13 runtime checks; 8 passages, 33 equipment ports, 25 fixed ports; actual GUI/CLI WAN path and disposable disk save/new-scene restore. See tools/verify.sh.
- Current: final QA screenshots after shelf-scale/conduit alignment fixes; release preparation v0.5.0-alpha, following existing RELEASING.md.
- Git: stable P1/PC/WAN blocks pushed to origin/custom-cli. Refactor/cleanup being finalized; no force push or LFS changes.
- Limits: exterior door is a level boundary; movable-rack decorative panels are not the functional wall patch panel. Old arbitrary placements can overlap furnishings. DNS/STP/radio Wi-Fi absent; NAT is probe-scoped, not TCP/UDP sessions.
