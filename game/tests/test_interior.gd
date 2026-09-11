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
	# Every equipment category, including rotated faces, keeps individually selectable real-size jacks.
	var categories := ["switch","router","firewall","wireless_router","access_point","pc","server","nas","client_laptop"]
	for i in categories.size():
		var category: String = categories[i]
		var device := "QA-" + category
		var yaw := (i % 3) * PI / 2
		room._apply_event_visual({"type":"place_device","name":device,"category":category,"world_pos":[-8.0+i*1.8,0.825,-1.0],"world_yaw":yaw})
	await room.get_tree().physics_frame
	await room.get_tree().physics_frame
	for key in room._interface_positions:
		if not key.begins_with("QA-"): continue
		var target: Vector3 = room._interface_positions[key]
		var direction: Vector3 = room._port_direction(target)
		var query := PhysicsRayQueryParameters3D.create(target+direction*0.3,target)
		var hit: Dictionary = room.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider.get_meta("device_name", "") != key.split("|")[0] or hit.collider.get_meta("interface_name", "") != key.split("|")[1]: failures.append("port " + key)
		port_count += 1
	room._apply_event_visual({"type":"place_device","name":"QA-TABLE","category":"table","world_pos":[0,0,1.5],"world_yaw":0.0})
	await room.get_tree().physics_frame
	room._player.global_position = Vector3(0,1,3)
	room._player.get_node("Camera3D").look_at(Vector3(0,0.78,1.5),Vector3.UP)
	room._selected_index = 0
	room._place_device()
	var placed: Dictionary = room.get_node("/root/GameState").events.back()
	if not placed.get("supported",false): failures.append("tabletop placement did not hit support")
	var device: String = placed.get("name", "")
	var expected: Vector3 = room._interface_positions.get(device+"|eth0",Vector3.INF)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(placed))
	room._apply_event_visual({"type":"remove_device","name":device})
	await room.get_tree().process_frame
	room._apply_event_visual(roundtrip)
	if room._interface_positions.get(device+"|eth0",Vector3.ZERO).distance_to(expected) > 0.001: failures.append("tabletop replay moved port")
	print("  ok  tabletop placement/replay" if failures.is_empty() else "tabletop/replay inspected")
	print("INTERIOR %s: %d capsule passages, glass collision, %d port raycasts; failures=%s" % ["PASSED" if failures.is_empty() else "FAILED", passages.size(), port_count, failures])
	room.get_tree().quit(0 if failures.is_empty() else 1)
