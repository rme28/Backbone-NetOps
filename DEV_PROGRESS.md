# Visual handover — 2026-09-11
- Done: interior_art.gd separates architecture/dressing from gameplay. Glass network/operations rooms, meeting space, staging, ceiling grids, windows, reception lounge, kitchenette; CC0 furniture/material palette; desktop displays; compact HUD and physical labels.
- Fixed: racked gear width, overlapping switch port hitboxes. NetSim untouched.
- Tested: Godot Flatpak 4.7.2: 28 model + 13 runtime checks; BACKBONE_INTERIOR_TEST=1 passes 8 capsule passages, glass collision, 6 individual port raycasts. Rendered main room/offices/racks.
- In progress: final art refinement, all-zone renders, minimal audio and screenshot/performance tooling.
- Next: inspect reception/break room, verify collision scaling, final screenshots and stable commit.
- Known limitations: older saves retain their coordinates (user-placed objects may overlap new partitions); WAN wall outlets/patch panel remain decoration as before. No network feature expansion or scenarios.
