extends SceneTree
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	print("HOST ",label,": ",value)
	if not value: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var sim: Node = load("res://scripts/network/network_sim.gd").new()
	root.add_child(sim)
	var configs := {"PC":{"category":"pc","interfaces":{"eth0":{"shutdown":false,"address":""}}},
		"R":{"category":"router","interfaces":{"eth0":{"shutdown":false,"address":"10.0.0.1/24"}},"dhcp_pools":[{"network":"10.0.0.0/24","gateway":"10.0.0.1"}]}}
	var links := [{"dev1":"PC","iface1":"eth0","dev2":"R","iface2":"eth0"}]
	var saved := {}
	var persist := func(name_):
		saved[name_] = configs[name_].duplicate(true)
		sim.rebuild(configs,links)
	var service: RefCounted = load("res://scripts/network/host_service.gd").new(configs,persist,sim)
	service.configure("PC","eth0",false,"10.0.0.20","24","10.0.0.1")
	check(sim.can_reach("PC","10.0.0.1"),"static configuration takes effect")
	var before := JSON.stringify(configs.PC)
	service.configure("PC","eth0",false,"999.1.2.3","24","")
	check(JSON.stringify(configs.PC) == before,"invalid IP is atomic")
	service.configure("PC","eth0",false,"10.0.0.20","99","")
	check(JSON.stringify(configs.PC) == before,"invalid CIDR is atomic")
	service.configure("PC","eth0",true,"","","")
	check(sim.effective_address("PC","eth0").begins_with("10.0.0."),"DHCP lease")
	check(sim.effective_gateway("PC") == "10.0.0.1","DHCP gateway")
	check("Destination joignable" in service.command("PC","ping 10.0.0.1"),"host ping")
	check("Connecté" in service.command("PC","ip addr"),"host IP inspection")
	check("Commande inconnue" in service.command("PC","configure terminal"),"IOS excluded")
	check("Connexion disponible" in service.browse("PC","http://10.0.0.1"),"browser uses network")
	configs.PC = JSON.parse_string(JSON.stringify(saved.PC))
	sim.rebuild(configs,links)
	check(sim.can_reach("PC","10.0.0.1"),"saved DHCP config replay")
	links.clear()
	sim.rebuild(configs,links)
	check("Impossible" in service.browse("PC","10.0.0.1"),"unplug breaks browser")
	sim.queue_free()
	await process_frame
	print("HOST failures=",failures)
	quit(0 if failures.is_empty() else 1)
