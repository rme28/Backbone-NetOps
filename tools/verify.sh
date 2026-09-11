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
check_log="$(mktemp)"
trap 'rm -f "$check_log"' EXIT
run_check() {
    local result=0
    timeout 45 "$@" > "$check_log" 2>&1 || result=$?
    cat "$check_log"
    if (( result != 0 )); then return "$result"; fi
    if rg -q 'SCRIPT ERROR|^ERROR:|FAILED|  FAIL ' "$check_log"; then return 1; fi
}
for suite in test_network_sim test_player test_host_service test_wan; do
    run_check "${godot_command[@]}" --headless --path game --script "tests/$suite.gd"
done
for suite in BACKBONE_SELFTEST BACKBONE_INTERIOR_TEST BACKBONE_WAN_TEST; do
    run_check env "$suite=1" "${godot_command[@]}" --headless --path game scenes/world/server_room.tscn
done
