# Visual handover — 2026-09-11
- Done: furnished glazed workplace; canonical metre-scale equipment/chamfered chassis/RJ45; real-model inventory icons; curved cables; shared UI theme; quiet foley/fans; tabletop placement/replay; precision view (right click).
- NetSim unchanged. Original starter journal and equipment names retained. External furniture is Kenney CC0 (docs/THIRD_PARTY_ASSETS.md).
- Tested: Godot Flatpak 4.7.2, 28 model + 13 runtime checks; interior suite: 8 capsule passages, glass collision, 33 individual port rays, tabletop placement/JSON replay. Import and diff checks clean.
- Rendering: Mobile Vulkan + 2x MSAA, material batches and wall occlusion. Seven 1080p views sampled 52–61 FPS on Quadro K2100M; not a long-duration benchmark.
- In progress: none. Final Godot captures reviewed, including equipment ports, inventory and centered settings.
- Next: user playtest of the art pass; keep network/scenario work separate. Run tools/verify.sh for the model/runtime/interior suites. Local captures: artifacts/visual/.
- Limitations: old arbitrary user placements may intersect new partitions; wall outlets/patch panel remain decoration. Radio Wi-Fi, DNS/NAT/STP remain unimplemented as before.
