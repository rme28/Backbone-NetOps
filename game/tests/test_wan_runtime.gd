extends RefCounted
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	print("WAN-RUNTIME ",label,": ",value)
	if not value: failures.append(label)
func run(room: Node3D) -> void:
	room._player.set_active(false)
	for entry in [["QA-CPE","router",-12.0],["QA-PC","pc",-11.0]]:
		var event := {"type":"place_device","name":entry[0],"category":entry[1],"world_pos":[entry[2],0.41,12.0],"world_yaw":0.0}
		room._apply_event_visual(event)
		GameState.record(event)
	room._create_link("QA-CPE","WAN-ONT","eth0","client")
	room._create_link("QA-CPE","QA-PC","eth1","eth0")
	room._open_terminal("QA-CPE")
	for command in ["configure terminal","interface eth0","ip address dhcp","no shutdown","ip nat outside","exit","interface eth1","ip address 192.168.10.1/24","no shutdown","ip nat inside","exit","ip nat overload","ip route 0.0.0.0/0 203.0.113.1","end"]:
		room._execute_terminal_command(command)
	room._close_terminal()
	room._open_terminal("QA-PC")
	check(room._pc_os.visible and not room._terminal_layer.visible,"PC opens desktop, not IOS")
	room._pc_os.show_app("Réseau")
	var edits: Array[LineEdit] = []
	var apply_button: Button
	for child in room._pc_os.content.get_children():
		if child is LineEdit: edits.append(child)
		if child is Button and child.text == "Appliquer": apply_button = child
	edits[0].text = "192.168.10.20"
	edits[1].text = "24"
	edits[2].text = "192.168.10.1"
	apply_button.pressed.emit()
	check(NetSim.can_reach("QA-PC","198.51.100.10"),"GUI apply + CLI NAT reaches operator service")
	check("Connexion disponible" in room._host_service.browse("QA-PC","https://connectivity.backbone.test"),"browser external success")
	room._close_terminal()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(GameState.device_configs))
	check(snapshot["QA-CPE"].nat_enabled and snapshot["QA-CPE"].interfaces.eth0.nat_role == "outside","NAT configuration in save state")
	check(snapshot["QA-PC"].default_gateway == "192.168.10.1","GUI gateway in save state")
	room._disconnect_link("WAN-ONT","client")
	check(not NetSim.can_reach("QA-PC","198.51.100.10"),"physical ONT disconnect stops service")
	room._create_link("QA-CPE","WAN-ONT","eth0","client")
	check(NetSim.can_reach("QA-PC","198.51.100.10"),"reconnect restores service")
	# Each wall and patch jack must be reachable from its visible face.
	await room.get_tree().physics_frame
	await room.get_tree().physics_frame
	for key in room._fixed_network.directions:
		var pos: Vector3 = room._interface_positions[key]
		var direction: Vector3 = room._fixed_network.directions[key]
		var ray := PhysicsRayQueryParameters3D.create(pos+direction*0.15,pos-direction*0.02)
		var hit: Dictionary = room.get_world_3d().direct_space_state.intersect_ray(ray)
		var collider = hit.get("collider")
		check(collider != null and str(collider.get_meta("device_name",""))+"|"+str(collider.get_meta("interface_name","")) == key,"jack accessible "+key)
	var directory := OS.get_environment("BACKBONE_WAN_CAPTURES")
	if not directory.is_empty():
		room._open_terminal("QA-PC")
		room._pc_os.show_app("Navigateur")
		for child in room._pc_os.content.get_children():
			if child is Button: child.pressed.emit()
		await room.get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		room.get_viewport().get_texture().get_image().save_png(directory.path_join("15-browser-online.png"))
		room._disconnect_link("WAN-ONT","client")
		for child in room._pc_os.content.get_children():
			if child is Button: child.pressed.emit()
		await RenderingServer.frame_post_draw
		room.get_viewport().get_texture().get_image().save_png(directory.path_join("16-browser-offline.png"))
	print("WAN-RUNTIME failures=",failures)
	room.get_tree().quit(0 if failures.is_empty() else 1)
