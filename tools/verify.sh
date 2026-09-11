#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
if command -v godot >/dev/null 2>&1; then
    godot_command=(godot)
elif command -v godot4 >/dev/null 2>&1; then
    godot_command=(godot4)
else
    godot_command=(flatpak run org.godotengine.Godot)
fi
"${godot_command[@]}" --headless --path game --script tests/test_network_sim.gd
"${godot_command[@]}" --headless --path game --script tests/test_player.gd
"${godot_command[@]}" --headless --path game --script tests/test_host_service.gd
BACKBONE_SELFTEST=1 timeout 30 "${godot_command[@]}" --headless --path game scenes/world/server_room.tscn
BACKBONE_INTERIOR_TEST=1 timeout 30 "${godot_command[@]}" --headless --path game scenes/world/server_room.tscn
