extends SceneTree
## Tests headless du modele reseau logique (NetSim).
## Lancer : godot --headless --path game --script tests/test_network_sim.gd

var _failures := 0
var _count := 0


func _initialize() -> void:
	var sim: Node = load("res://scripts/network/network_sim.gd").new()
	root.add_child(sim)

	_test_direct_link(sim)
	_test_interface_down(sim)
	_test_wrong_subnet(sim)
	_test_switch_same_vlan(sim)
	_test_switch_vlan_isolation(sim)
	_test_trunk(sim)
	_test_routed_gateway(sim)
	_test_missing_return_gateway(sim)
	_test_static_routes(sim)
	_test_routing_loop(sim)
	_test_queries(sim)

	print("")
	if _failures == 0:
		print("ALL %d TESTS PASSED" % _count)
	else:
		print("%d/%d TESTS FAILED" % [_failures, _count])
	quit(1 if _failures > 0 else 0)


func _check(name: String, condition: bool, detail := "") -> void:
	_count += 1
	if condition:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s %s" % [name, detail])


func _host(ip: String, gateway := "") -> Dictionary:
	return {
		"category": "pc", "hostname": "host",
		"interfaces": {"eth0": {"address": ip, "shutdown": false}},
		"routes": [], "default_gateway": gateway,
	}


func _router(ifaces: Dictionary, routes: Array = []) -> Dictionary:
	var built := {}
	for name in ifaces:
		built[name] = {"address": ifaces[name], "shutdown": false}
	return {"category": "router", "hostname": "r", "interfaces": built, "routes": routes}


func _switch(port_count: int, port_config := {}) -> Dictionary:
	var interfaces := {}
	for i in port_count:
		var name := "eth%d" % i
		var state := {"address": "", "shutdown": false, "mode": "access", "vlan": 1}
		if port_config.has(name):
			state.merge(port_config[name], true)
		interfaces[name] = state
	return {"category": "switch", "hostname": "sw", "interfaces": interfaces, "routes": [], "vlans": {"1": "default"}}


func _link(d1: String, i1: String, d2: String, i2: String) -> Dictionary:
	return {"dev1": d1, "iface1": i1, "dev2": d2, "iface2": i2}


func _test_direct_link(sim: Node) -> void:
	print("direct link:")
	sim.rebuild(
		{"A": _host("10.0.0.1/24"), "B": _host("10.0.0.2/24")},
		[_link("A", "eth0", "B", "eth0")])
	_check("ping ok", sim.ping("A", "10.0.0.2")["success"])
	_check("link protocol up", sim.link_protocol_up("A", "eth0"))


func _test_interface_down(sim: Node) -> void:
	print("interface down:")
	var b := _host("10.0.0.2/24")
	b["interfaces"]["eth0"]["shutdown"] = true
	sim.rebuild({"A": _host("10.0.0.1/24"), "B": b}, [_link("A", "eth0", "B", "eth0")])
	var result: Dictionary = sim.ping("A", "10.0.0.2")
	_check("ping fails", not result["success"], str(result))
	_check("protocol down", not sim.link_protocol_up("A", "eth0"))


func _test_wrong_subnet(sim: Node) -> void:
	print("wrong subnet:")
	sim.rebuild(
		{"A": _host("10.0.0.1/24"), "B": _host("10.0.1.2/24")},
		[_link("A", "eth0", "B", "eth0")])
	var result: Dictionary = sim.ping("A", "10.0.1.2")
	_check("no route", not result["success"] and result["reason"] == "no-route", str(result))


func _test_switch_same_vlan(sim: Node) -> void:
	print("switch same vlan:")
	sim.rebuild(
		{"A": _host("10.0.0.1/24"), "B": _host("10.0.0.2/24"), "SW": _switch(4)},
		[_link("A", "eth0", "SW", "eth0"), _link("B", "eth0", "SW", "eth1")])
	_check("ping through switch", sim.ping("A", "10.0.0.2")["success"])


func _test_switch_vlan_isolation(sim: Node) -> void:
	print("vlan isolation:")
	var sw := _switch(4, {"eth0": {"vlan": 10}, "eth1": {"vlan": 20}})
	sw["vlans"] = {"1": "default", "10": "USERS", "20": "SERVERS"}
	sim.rebuild(
		{"A": _host("10.0.0.1/24"), "B": _host("10.0.0.2/24"), "SW": sw},
		[_link("A", "eth0", "SW", "eth0"), _link("B", "eth0", "SW", "eth1")])
	var result: Dictionary = sim.ping("A", "10.0.0.2")
	_check("vlan blocks ping", not result["success"], str(result))


func _test_trunk(sim: Node) -> void:
	print("trunk:")
	var sw1 := _switch(4, {"eth0": {"vlan": 10}, "eth3": {"mode": "trunk", "trunk_allowed": "all"}})
	var sw2 := _switch(4, {"eth0": {"vlan": 10}, "eth3": {"mode": "trunk", "trunk_allowed": "all"}})
	sim.rebuild(
		{"A": _host("10.0.0.1/24"), "B": _host("10.0.0.2/24"), "SW1": sw1, "SW2": sw2},
		[_link("A", "eth0", "SW1", "eth0"), _link("B", "eth0", "SW2", "eth0"),
		 _link("SW1", "eth3", "SW2", "eth3")])
	_check("vlan 10 crosses trunk", sim.ping("A", "10.0.0.2")["success"])
	# Trunk qui n'autorise pas le VLAN 10.
	var sw2b := _switch(4, {"eth0": {"vlan": 10}, "eth3": {"mode": "trunk", "trunk_allowed": "20,30"}})
	sim.rebuild(
		{"A": _host("10.0.0.1/24"), "B": _host("10.0.0.2/24"), "SW1": sw1, "SW2": sw2b},
		[_link("A", "eth0", "SW1", "eth0"), _link("B", "eth0", "SW2", "eth0"),
		 _link("SW1", "eth3", "SW2", "eth3")])
	var result: Dictionary = sim.ping("A", "10.0.0.2")
	_check("pruned trunk blocks", not result["success"], str(result))


func _test_routed_gateway(sim: Node) -> void:
	print("routed with gateways:")
	sim.rebuild(
		{
			"A": _host("10.0.1.10/24", "10.0.1.1"),
			"B": _host("10.0.2.10/24", "10.0.2.1"),
			"R": _router({"eth0": "10.0.1.1/24", "eth1": "10.0.2.1/24"}),
		},
		[_link("A", "eth0", "R", "eth0"), _link("B", "eth0", "R", "eth1")])
	var result: Dictionary = sim.ping("A", "10.0.2.10")
	_check("inter-subnet ping", result["success"], str(result))
	_check("path through R", result["path"] == ["A", "R", "B"], str(result["path"]))


func _test_missing_return_gateway(sim: Node) -> void:
	print("missing return gateway:")
	sim.rebuild(
		{
			"A": _host("10.0.1.10/24", "10.0.1.1"),
			"B": _host("10.0.2.10/24"),
			"R": _router({"eth0": "10.0.1.1/24", "eth1": "10.0.2.1/24"}),
		},
		[_link("A", "eth0", "R", "eth0"), _link("B", "eth0", "R", "eth1")])
	var result: Dictionary = sim.ping("A", "10.0.2.10")
	_check("fails without return route", not result["success"] and result["reason"] == "no-return-path", str(result))


func _test_static_routes(sim: Node) -> void:
	print("static routes (two routers):")
	sim.rebuild(
		{
			"A": _host("10.0.1.10/24", "10.0.1.1"),
			"B": _host("10.0.3.10/24", "10.0.3.1"),
			"R1": _router({"eth0": "10.0.1.1/24", "eth1": "10.0.2.1/24"},
				[{"network": "10.0.3.0/24", "next_hop": "10.0.2.2"}]),
			"R2": _router({"eth0": "10.0.2.2/24", "eth1": "10.0.3.1/24"},
				[{"network": "10.0.1.0/24", "next_hop": "10.0.2.1"}]),
		},
		[_link("A", "eth0", "R1", "eth0"), _link("R1", "eth1", "R2", "eth0"),
		 _link("R2", "eth1", "B", "eth0")])
	var result: Dictionary = sim.ping("A", "10.0.3.10")
	_check("two-router ping", result["success"], str(result))
	_check("path A R1 R2 B", result["path"] == ["A", "R1", "R2", "B"], str(result["path"]))
	# Sans la route retour sur R2.
	var r2 := _router({"eth0": "10.0.2.2/24", "eth1": "10.0.3.1/24"})
	sim.rebuild(
		{
			"A": _host("10.0.1.10/24", "10.0.1.1"),
			"B": _host("10.0.3.10/24", "10.0.3.1"),
			"R1": _router({"eth0": "10.0.1.1/24", "eth1": "10.0.2.1/24"},
				[{"network": "10.0.3.0/24", "next_hop": "10.0.2.2"}]),
			"R2": r2,
		},
		[_link("A", "eth0", "R1", "eth0"), _link("R1", "eth1", "R2", "eth0"),
		 _link("R2", "eth1", "B", "eth0")])
	var broken: Dictionary = sim.ping("A", "10.0.3.10")
	_check("fails without return static route", not broken["success"], str(broken))


func _test_routing_loop(sim: Node) -> void:
	print("routing loop:")
	sim.rebuild(
		{
			"R1": _router({"eth0": "10.0.0.1/24"}, [{"network": "0.0.0.0/0", "next_hop": "10.0.0.2"}]),
			"R2": _router({"eth0": "10.0.0.2/24"}, [{"network": "0.0.0.0/0", "next_hop": "10.0.0.1"}]),
		},
		[_link("R1", "eth0", "R2", "eth0")])
	var result: Dictionary = sim.ping("R1", "99.99.99.99")
	_check("loop detected", not result["success"]
		and result["reason"] in ["routing-loop", "ttl-exceeded"], str(result))


func _test_queries(sim: Node) -> void:
	print("scenario queries:")
	var sw := _switch(4, {"eth0": {"vlan": 10}, "eth1": {"mode": "trunk", "trunk_allowed": "10,20"}})
	sw["vlans"] = {"1": "default", "10": "USERS"}
	sim.rebuild(
		{"A": _host("10.0.0.1/24"), "SW": sw},
		[_link("A", "eth0", "SW", "eth0")])
	_check("device_exists", sim.device_exists("SW") and not sim.device_exists("X"))
	_check("cable_connected", sim.cable_connected("A", "eth0") and not sim.cable_connected("SW", "eth2"))
	_check("ip_configured", sim.ip_configured("A", "eth0") and not sim.ip_configured("SW", "eth0"))
	_check("vlan_exists", sim.vlan_exists("SW", 10) and not sim.vlan_exists("SW", 30))
	_check("port_in_vlan access", sim.port_in_vlan("SW", "eth0", 10) and not sim.port_in_vlan("SW", "eth0", 20))
	_check("port_in_vlan trunk", sim.port_in_vlan("SW", "eth1", 20) and not sim.port_in_vlan("SW", "eth1", 30))
