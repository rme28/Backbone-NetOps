extends RefCounted
## Real physics sweeps verify doors fit the player capsule and glass blocks passage.
## Port raycasts verify the new cabinet dressing does not cover interaction targets.
func run(room: Node3D) -> void:
	room._player.set_active(false)
	await room.get_tree().physics_frame
	await room.get_tree().physics_frame
	var failures: Array[String] = []
	var passages := [
		["network entrance", Vector3(-6, 1, -2.5), Vector3(-6, 1, -4.5)],
		["operations entrance", Vector3(4, 1, -2.5), Vector3(4, 1, -4.5)],
		["meeting entrance", Vector3(2.3, 1, 5), Vector3(4.3, 1, 5)],
		["south corridor", Vector3(0, 1, 9), Vector3(0, 1, 12)],
		["office entrance", Vector3(-4, 1, 12.5), Vector3(-4, 1, 14.6)],
		["reception entrance", Vector3(5.5, 1, 12.5), Vector3(5.5, 1, 14.6)],
		["break room entrance", Vector3(9, 1, 0), Vector3(11, 1, 0)],
		["WAN entrance", Vector3(-9, 1, 12), Vector3(-11, 1, 12)],
	]
	for passage in passages:
		var blocked: bool = room._player.test_move(Transform3D(Basis.IDENTITY, passage[1]), passage[2] - passage[1])
		if blocked: failures.append(passage[0])
		print("  %s  %s" % ["FAIL" if blocked else "ok", passage[0]])
	var glass_blocks: bool = room._player.test_move(Transform3D(Basis.IDENTITY, Vector3(-8, 1, -2.5)), Vector3(0, 0, -2))
	if not glass_blocks: failures.append("glass collision")
	var port_count := 0
	for key in room._interface_positions:
		if not key.begins_with("SW-CORE|"): continue
		var target: Vector3 = room._interface_positions[key]
		var query := PhysicsRayQueryParameters3D.create(target + Vector3(0, 0, 0.8), target)
		var hit: Dictionary = room.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider.get_meta("device_name", "") != "SW-CORE" or hit.collider.get_meta("interface_name", "") != key.split("|")[1]:
			failures.append("port " + key)
		port_count += 1
	print("INTERIOR %s: %d capsule passages, glass collision, %d port raycasts; failures=%s" % ["PASSED" if failures.is_empty() else "FAILED", passages.size(), port_count, failures])
	room.get_tree().quit(0 if failures.is_empty() else 1)
