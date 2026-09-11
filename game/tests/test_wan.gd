extends SceneTree
var failures: Array[String] = []
var count := 0
func check(value: bool, label: String) -> void:
	count += 1
	print("WAN ",label,": ",value)
	if not value: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var sim: Node = load("res://scripts/network/network_sim.gd").new()
	root.add_child(sim)
	var operator = load("res://scripts/network/operator_network.gd")
	var configs: Dictionary = operator.configs()
	configs.merge({
		"WAN-ONT":{"category":"passive","interfaces":{"client":{"shutdown":false},"uplink":{"shutdown":false}}},
		"CPE":{"category":"router","nat_enabled":true,"interfaces":{
			"wan":{"address":"203.0.113.20/24","shutdown":false,"nat_role":"outside"},
			"lan":{"address":"192.168.10.1/24","shutdown":false,"nat_role":"inside"}},
			"routes":[{"network":"0.0.0.0/0","next_hop":"203.0.113.1"}]},
		"PC":{"category":"pc","interfaces":{"eth0":{"address":"192.168.10.20/24","shutdown":false}},"default_gateway":"192.168.10.1"}})
	var links: Array = operator.links()
	links.append({"dev1":"CPE","iface1":"wan","dev2":"WAN-ONT","iface2":"client"})
	links.append({"dev1":"PC","iface1":"eth0","dev2":"CPE","iface2":"lan"})
	var saved := JSON.stringify(configs)
	sim.rebuild(configs,links)
	var response: Dictionary = sim.ping("PC",operator.SERVICE_IP)
	check(response.success,"LAN reaches external service")
	check(response.get("translations",[]).size() == 1,"source translated on CPE")
	check(sim.can_reach("CPE",operator.SERVICE_IP),"CPE reaches provider")
	configs.CPE.nat_enabled = false
	sim.rebuild(configs,links)
	check(sim.ping("PC",operator.SERVICE_IP).reason == "no-return-path","without NAT no private return path")
	configs = JSON.parse_string(saved)
	configs.PC.default_gateway = ""
	sim.rebuild(configs,links)
	check(not sim.can_reach("PC",operator.SERVICE_IP),"client gateway required")
	configs = JSON.parse_string(saved)
	configs.CPE.interfaces.wan.shutdown = true
	sim.rebuild(configs,links)
	check(not sim.can_reach("PC",operator.SERVICE_IP),"shutdown WAN stops Internet")
	configs = JSON.parse_string(saved)
	configs.CPE.routes[0].next_hop = "203.0.113.254"
	sim.rebuild(configs,links)
	check(not sim.can_reach("PC",operator.SERVICE_IP),"wrong default route stops Internet")
	configs = JSON.parse_string(saved)
	configs.CPE.interfaces.wan.address = "203.0.114.20/24"
	sim.rebuild(configs,links)
	check(not sim.can_reach("PC",operator.SERVICE_IP),"wrong WAN subnet stops Internet")
	configs = JSON.parse_string(saved)
	configs.CPE.interfaces.wan.nat_role = "inside"
	sim.rebuild(configs,links)
	check(not sim.can_reach("PC",operator.SERVICE_IP),"NAT direction matters")
	configs = JSON.parse_string(saved)
	configs.CPE.interfaces.wan.address = "dhcp"
	sim.rebuild(configs,links)
	check(sim.effective_address("CPE","wan").begins_with("203.0.113."),"provider DHCP")
	check(sim.can_reach("PC",operator.SERVICE_IP),"DHCP WAN supports translated traffic")
	var disconnected := links.duplicate(true)
	disconnected.remove_at(2)
	sim.rebuild(configs,disconnected)
	check(not sim.can_reach("PC",operator.SERVICE_IP),"WAN cable removed stops Internet")
	sim.rebuild(JSON.parse_string(saved),links)
	check(sim.can_reach("PC",operator.SERVICE_IP),"JSON config replay restores Internet")
	check(not sim.can_reach("INTERNET-TEST","192.168.10.20"),"no unsolicited inbound NAT")
	configs = JSON.parse_string(saved)
	configs.PC.interfaces.eth0.address = ""
	sim.rebuild(configs,links)
	check(not sim.can_reach("PC",operator.SERVICE_IP),"unaddressed client cannot use NAT")
	sim.queue_free()
	await process_frame
	print("WAN ",count," checks, failures=",failures)
	quit(0 if failures.is_empty() else 1)
