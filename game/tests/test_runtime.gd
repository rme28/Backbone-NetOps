extends RefCounted
## End-to-end placement, host configuration, VLANs, objectives and removal.
func run(room: Node3D) -> void:
	var failures: Array[String] = []
	var check := func(name: String, condition: bool) -> void:
		print(("  ok   " if condition else "  FAIL ") + name)
		if not condition: failures.append(name)

	# Deux PC cables sur le switch de depart SW-CORE.
	for setup in [["PC-A", 4.0], ["PC-B", 5.2]]:
		room._apply_event_visual({"type": "place_device", "name": setup[0], "model": "desktop",
			"category": "pc", "world_pos": [setup[1], 0.41, -2.0], "world_yaw": 0.0})
	GameState.record({"type": "add_link", "dev1": "PC-A", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth0", "cable": "rj45"})
	GameState.record({"type": "add_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1", "cable": "rj45"})
	room._sync_netsim()
	check.call("liens proto up (defauts switch/pc)", NetSim.link_protocol_up("PC-A", "eth0") and NetSim.link_protocol_up("PC-B", "eth0"))

	# The runtime drives the same adapter as the PC network application.
	for setup in [["PC-A", "10.0.0.1"], ["PC-B", "10.0.0.2"]]:
		room._open_terminal(setup[0])
		room._host_service.configure(setup[0],"eth0",false,setup[1],"24","")
		room._close_terminal()
	check.call("ip configuree via application PC", NetSim.ip_configured("PC-A", "eth0"))
	check.call("ping PC-A -> PC-B", NetSim.can_reach("PC-A", "10.0.0.2"))

	# Isolation VLAN via le terminal du switch.
	room._open_terminal("SW-CORE")
	for cmd in ["configure terminal", "vlan 10", "exit", "interface eth0", "switchport access vlan 10", "end"]:
		room._execute_terminal_command(cmd)
	room._close_terminal()
	check.call("vlan 10 existe", NetSim.vlan_exists("SW-CORE", 10))
	check.call("vlan isole le ping", not NetSim.can_reach("PC-A", "10.0.0.2"))

	# Retour au meme VLAN puis debranchement physique.
	room._open_terminal("SW-CORE")
	for cmd in ["configure terminal", "interface eth1", "switchport access vlan 10", "end"]:
		room._execute_terminal_command(cmd)
	room._close_terminal()
	check.call("meme vlan retablit le ping", NetSim.can_reach("PC-A", "10.0.0.2"))
	room._disconnect_link("PC-B", "eth0")
	check.call("debranchement coupe le ping", not NetSim.can_reach("PC-A", "10.0.0.2"))
	check.call("port libere apres debranchement", not ("eth0" in room._used_interfaces.get("PC-B", [])))

	# Ping via la commande terminal (journalise ping_ok pour les objectifs).
	GameState.record({"type": "add_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1", "cable": "rj45"})
	room._sync_netsim()
	room._open_terminal("PC-A")
	room._host_service.command("PC-A","ping 10.0.0.2")
	room._close_terminal()
	var has_ping_event := false
	for event in GameState.events:
		if event.get("type", "") == "ping_ok": has_ping_event = true
	check.call("ping_ok journalise", has_ping_event)
	check.call("objectif premier ping accompli", Objectives.is_completed("first_ping"))

	# Retrait d'equipement : liens debranches, config purgee, replay coherent.
	var pcb_body: Node3D = room._device_bodies.get("PC-B")
	room._apply_event_visual({"type": "remove_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1"})
	GameState.record({"type": "remove_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1"})
	room._apply_event_visual({"type": "remove_device", "name": "PC-B"})
	GameState.record({"type": "remove_device", "name": "PC-B"})
	check.call("equipement retire du modele", not NetSim.device_exists("PC-B"))
	check.call("corps 3d supprime", pcb_body == null or pcb_body.is_queued_for_deletion())
	check.call("port du switch libere", not ("eth1" in room._used_interfaces.get("SW-CORE", [])))

	print("SELFTEST %s (%d checks)" % ["PASSED" if failures.is_empty() else "FAILED", 13])
	room.get_tree().quit(0 if failures.is_empty() else 1)
