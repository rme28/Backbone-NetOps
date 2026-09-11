extends RefCounted
## Network appliance command grammar. The scene owns session widgets/config storage;
## this module interprets commands and persists through its existing callback.
var room: Node3D

func _init(host: Node3D) -> void:
	room = host

func _is_switch_device() -> bool:
	return str(room._device_configs[room._terminal_device].get("category", "")) in ["switch", "switch_l3"]


func _is_host_device() -> bool:
	return str(room._device_configs[room._terminal_device].get("category", "")) in ["pc", "client_laptop", "server", "nas"]


func _execute_terminal_command(command: String) -> void:
	var words := command.to_lower().split(" ", false)
	if _handle_nat_command(words): return
	if command == "?": room._show_terminal_help(""); return
	if _command_matches(words, ["clear"]): room._terminal_output.text = ""; return
	if _command_matches(words, ["end"]):
		room._terminal_mode = "exec"; room._terminal_interface = ""; room._update_terminal_prompt(); return
	if _command_matches(words, ["exit"]):
		if room._terminal_mode in ["interface", "vlan"]:
			room._terminal_mode = "config"; room._terminal_interface = ""; room._update_terminal_prompt()
		elif room._terminal_mode == "config":
			room._terminal_mode = "exec"; room._update_terminal_prompt()
		else: room._close_terminal()
		return
	if _command_matches(words, ["show", "running-config"]): _show_running_config(); return
	if _command_matches(words, ["show", "ip", "route"]): _show_ip_routes(); return
	if _command_matches(words, ["show", "ip", "interface", "brief"]): _show_ip_interfaces(); return
	if _command_matches(words, ["show", "interfaces"]): _show_interfaces_detail(); return
	if _command_matches(words, ["show", "vlan"]) or _command_matches(words, ["show", "vlan", "brief"]):
		_show_vlans(); return
	if _command_starts(words, ["ping"]): _run_ping_command(words); return
	if _command_starts(words, ["traceroute"]): _run_traceroute_command(words); return

	if room._terminal_mode == "exec":
		if _command_matches(words, ["configure", "terminal"]):
			room._terminal_mode = "config"; room._update_terminal_prompt()
			room._append_terminal("Enter configuration commands, one per line.\n")
		else: room._append_terminal("% Invalid command in EXEC mode\n")
	elif room._terminal_mode == "config":
		if _command_starts(words, ["hostname"]): _set_hostname(command)
		elif _command_starts(words, ["interface"]): _enter_interface(words)
		elif _command_starts(words, ["no", "ip", "route"]): _remove_static_route(words)
		elif _command_starts(words, ["ip", "route"]):
			if room._device_configs[room._terminal_device]["category"] == "switch": room._append_terminal("% IP routing is not available on a Layer 2 switch\n")
			else: _add_static_route(words)
		elif _command_starts(words, ["ip", "default-gateway"]): _set_default_gateway(words)
		elif _command_starts(words, ["no", "ip", "dhcp", "pool"]): _remove_dhcp_pool(words)
		elif _command_starts(words, ["ip", "dhcp", "pool"]): _add_dhcp_pool(words)
		elif _command_starts(words, ["no", "vlan"]): _remove_vlan(words)
		elif _command_starts(words, ["vlan"]): _enter_vlan(words)
		else: room._append_terminal("% Invalid configuration command\n")
	elif room._terminal_mode == "vlan":
		if _command_starts(words, ["name"]): _set_vlan_name(command)
		else: room._append_terminal("% Invalid VLAN configuration command\n")
	elif room._terminal_mode == "interface":
		if _command_matches(words, ["no", "ip", "address"]): _clear_interface_address()
		elif _command_matches(words, ["ip", "address", "dhcp"]):
			if room._device_configs[room._terminal_device]["category"] == "switch": room._append_terminal("% Layer 3 addressing is not available on this switch port\n")
			else:
				room._device_configs[room._terminal_device]["interfaces"][room._terminal_interface]["address"] = "dhcp"
				room._save_device_config(room._terminal_device)
		elif _command_starts(words, ["ip", "address"]):
			if room._device_configs[room._terminal_device]["category"] == "switch": room._append_terminal("% Layer 3 addressing is not available on this switch port\n")
			else: _set_interface_address(words)
		elif _command_matches(words, ["no", "shutdown"]): _set_interface_shutdown(false)
		elif _command_matches(words, ["shutdown"]): _set_interface_shutdown(true)
		elif _command_starts(words, ["description"]): _set_interface_description(command)
		elif _command_starts(words, ["switchport"]): _handle_switchport(words)
		else: room._append_terminal("% Invalid interface command\n")


func _command_matches(input: PackedStringArray, canonical: Array[String]) -> bool:
	return input.size() == canonical.size() and _command_starts(input, canonical)


func _command_starts(input: PackedStringArray, canonical: Array[String]) -> bool:
	if input.size() < canonical.size(): return false
	for index in canonical.size():
		if not canonical[index].begins_with(input[index]): return false
	return true


func _set_hostname(command: String) -> void:
	var value := command.get_slice(" ", 1).strip_edges()
	if value.is_empty(): room._append_terminal("% Hostname required\n"); return
	room._device_configs[room._terminal_device]["hostname"] = value
	room._save_device_config(room._terminal_device)
	room._update_terminal_prompt()


func _enter_interface(words: PackedStringArray) -> void:
	if words.size() < 2: room._append_terminal("% Interface name required\n"); return
	var iface := words[1]
	var interfaces: Dictionary = room._device_configs[room._terminal_device]["interfaces"]
	if not interfaces.has(iface): room._append_terminal("% Unknown interface %s\n" % iface); return
	room._terminal_interface = iface; room._terminal_mode = "interface"; room._update_terminal_prompt()


func _set_interface_address(words: PackedStringArray) -> void:
	if words.size() < 3:
		room._append_terminal("% Expected: ip address A.B.C.D/prefix\n"); return
	var address := words[2]
	if not "/" in address:
		if words.size() < 4:
			room._append_terminal("% Subnet mask or prefix required\n"); return
		var prefix := _mask_to_prefix(words[3])
		if prefix < 0:
			room._append_terminal("% Invalid subnet mask\n"); return
		address += "/%d" % prefix
	if not _valid_cidr(address,1):
		room._append_terminal("% Invalid IPv4 address or prefix\n"); return
	room._device_configs[room._terminal_device]["interfaces"][room._terminal_interface]["address"] = address
	room._save_device_config(room._terminal_device)


func _clear_interface_address() -> void:
	room._device_configs[room._terminal_device]["interfaces"][room._terminal_interface]["address"] = ""
	room._save_device_config(room._terminal_device)


func _mask_to_prefix(mask: String) -> int:
	var masks := {
		"0.0.0.0": 0, "128.0.0.0": 1, "192.0.0.0": 2,
		"224.0.0.0": 3, "240.0.0.0": 4, "248.0.0.0": 5,
		"252.0.0.0": 6, "254.0.0.0": 7, "255.0.0.0": 8,
		"255.128.0.0": 9, "255.192.0.0": 10, "255.224.0.0": 11,
		"255.240.0.0": 12, "255.248.0.0": 13, "255.252.0.0": 14,
		"255.254.0.0": 15, "255.255.0.0": 16, "255.255.128.0": 17,
		"255.255.192.0": 18, "255.255.224.0": 19, "255.255.240.0": 20,
		"255.255.248.0": 21, "255.255.252.0": 22, "255.255.254.0": 23,
		"255.255.255.0": 24, "255.255.255.128": 25, "255.255.255.192": 26,
		"255.255.255.224": 27, "255.255.255.240": 28, "255.255.255.248": 29,
		"255.255.255.252": 30, "255.255.255.254": 31, "255.255.255.255": 32,
	}
	return int(masks.get(mask, -1))


func _set_interface_shutdown(value: bool) -> void:
	room._device_configs[room._terminal_device]["interfaces"][room._terminal_interface]["shutdown"] = value
	room._save_device_config(room._terminal_device)


func _set_interface_description(command: String) -> void:
	var first_space := command.find(" ")
	var value := command.substr(first_space + 1).strip_edges() if first_space >= 0 else ""
	room._device_configs[room._terminal_device]["interfaces"][room._terminal_interface]["description"] = value
	room._save_device_config(room._terminal_device)


func _add_static_route(words: PackedStringArray) -> void:
	if words.size() < 4: room._append_terminal("% Expected: ip route NETWORK/PREFIX NEXT-HOP\n"); return
	var network := words[2]
	var next_hop := words[3]
	if not "/" in network:
		if words.size() < 5: room._append_terminal("% Subnet mask and next-hop required\n"); return
		var prefix := _mask_to_prefix(words[3])
		if prefix < 0: room._append_terminal("% Invalid subnet mask\n"); return
		network += "/%d" % prefix
		next_hop = words[4]
	if not _valid_cidr(network) or not next_hop.is_valid_ip_address() or ":" in next_hop:
		room._append_terminal("% Invalid network or next hop\n"); return
	room._device_configs[room._terminal_device]["routes"].append({"network": network, "next_hop": next_hop})
	room._save_device_config(room._terminal_device)


func _remove_static_route(words: PackedStringArray) -> void:
	if words.size() < 4: room._append_terminal("% Expected: no ip route NETWORK/PREFIX NEXT-HOP\n"); return
	var network := words[3]
	var next_hop := words[4] if words.size() > 4 else ""
	var routes: Array = room._device_configs[room._terminal_device]["routes"]
	for i in routes.size():
		var route: Dictionary = routes[i]
		if str(route["network"]) == network and (next_hop.is_empty() or str(route["next_hop"]) == next_hop):
			routes.remove_at(i)
			room._save_device_config(room._terminal_device)
			return
	room._append_terminal("% No matching route\n")


func _set_default_gateway(words: PackedStringArray) -> void:
	if words.size() < 3: room._append_terminal("% Expected: ip default-gateway A.B.C.D\n"); return
	if not words[2].is_valid_ip_address() or ":" in words[2]:
		room._append_terminal("% Invalid IPv4 gateway\n"); return
	room._device_configs[room._terminal_device]["default_gateway"] = words[2]
	room._save_device_config(room._terminal_device)


## Pool DHCP simplifie en une ligne : ip dhcp pool NETWORK/PREFIX gateway A.B.C.D
## Le serveur doit posseder une adresse dans le reseau du pool pour repondre.
func _add_dhcp_pool(words: PackedStringArray) -> void:
	if room._device_configs[room._terminal_device]["category"] == "switch":
		room._append_terminal("% DHCP server is not available on a Layer 2 switch\n"); return
	if words.size() < 6 or words[4] != "gateway" or not "/" in words[3]:
		room._append_terminal("% Expected: ip dhcp pool NETWORK/PREFIX gateway A.B.C.D\n"); return
	if not _valid_cidr(words[3],1) or int(words[3].get_slice("/",1)) > 30 or not words[5].is_valid_ip_address() or ":" in words[5]:
		room._append_terminal("% Invalid DHCP subnet or gateway\n"); return
	var pools: Array = room._device_configs[room._terminal_device].get("dhcp_pools", [])
	pools.append({"network": words[3], "gateway": words[5]})
	room._device_configs[room._terminal_device]["dhcp_pools"] = pools
	room._save_device_config(room._terminal_device)


func _remove_dhcp_pool(words: PackedStringArray) -> void:
	if words.size() < 5: room._append_terminal("% Expected: no ip dhcp pool NETWORK/PREFIX\n"); return
	var pools: Array = room._device_configs[room._terminal_device].get("dhcp_pools", [])
	for i in pools.size():
		if str(pools[i].get("network", "")) == words[4]:
			pools.remove_at(i)
			room._save_device_config(room._terminal_device)
			return
	room._append_terminal("% No matching pool\n")


# --- VLANs / switchport ---------------------------------------------------------

func _enter_vlan(words: PackedStringArray) -> void:
	if not _is_switch_device():
		room._append_terminal("% VLAN configuration is only available on switches\n"); return
	if words.size() < 2 or not words[1].is_valid_int():
		room._append_terminal("% Expected: vlan <1-4094>\n"); return
	var vlan_id := int(words[1])
	if vlan_id < 1 or vlan_id > 4094:
		room._append_terminal("% VLAN id out of range\n"); return
	var vlans: Dictionary = room._device_configs[room._terminal_device]["vlans"]
	if not vlans.has(str(vlan_id)):
		vlans[str(vlan_id)] = "VLAN%04d" % vlan_id
		room._save_device_config(room._terminal_device)
	room._terminal_interface = str(vlan_id)
	room._terminal_mode = "vlan"
	room._update_terminal_prompt()


func _remove_vlan(words: PackedStringArray) -> void:
	if not _is_switch_device():
		room._append_terminal("% VLAN configuration is only available on switches\n"); return
	if words.size() < 3 or not words[2].is_valid_int():
		room._append_terminal("% Expected: no vlan <id>\n"); return
	if words[2] == "1":
		room._append_terminal("% Default VLAN 1 cannot be deleted\n"); return
	room._device_configs[room._terminal_device]["vlans"].erase(words[2])
	room._save_device_config(room._terminal_device)


func _set_vlan_name(command: String) -> void:
	var value := command.get_slice(" ", 1).strip_edges()
	if value.is_empty(): room._append_terminal("% Name required\n"); return
	room._device_configs[room._terminal_device]["vlans"][room._terminal_interface] = value
	room._save_device_config(room._terminal_device)


func _handle_switchport(words: PackedStringArray) -> void:
	if not _is_switch_device():
		room._append_terminal("% switchport is only available on switch ports\n"); return
	var state: Dictionary = room._device_configs[room._terminal_device]["interfaces"][room._terminal_interface]
	if _command_matches(words, ["switchport", "mode", "access"]):
		state["mode"] = "access"
	elif _command_matches(words, ["switchport", "mode", "trunk"]):
		state["mode"] = "trunk"
	elif _command_starts(words, ["switchport", "access", "vlan"]):
		if words.size() < 4 or not words[3].is_valid_int():
			room._append_terminal("% Expected: switchport access vlan <id>\n"); return
		if not room._device_configs[room._terminal_device]["vlans"].has(words[3]):
			room._append_terminal("%% VLAN %s does not exist (create it with: vlan %s)\n" % [words[3], words[3]]); return
		state["vlan"] = int(words[3])
	elif _command_starts(words, ["switchport", "trunk", "allowed", "vlan"]):
		if words.size() < 5:
			room._append_terminal("% Expected: switchport trunk allowed vlan <list|all>\n"); return
		state["trunk_allowed"] = words[4]
	else:
		room._append_terminal("% Invalid switchport command\n"); return
	room._save_device_config(room._terminal_device)


# --- Show commands ---------------------------------------------------------------

func _show_running_config() -> void:
	var config: Dictionary = room._device_configs[room._terminal_device]
	room._append_terminal("Building configuration...\n\nhostname %s\n!\n" % config["hostname"])
	if config.get("nat_enabled",false): room._append_terminal("ip nat overload\n")
	if _is_switch_device():
		for vlan_id in config.get("vlans", {}):
			if str(vlan_id) != "1":
				room._append_terminal("vlan %s\n name %s\n!\n" % [vlan_id, config["vlans"][vlan_id]])
	for iface in config["interfaces"]:
		var state: Dictionary = config["interfaces"][iface]
		room._append_terminal("interface %s\n" % iface)
		if not str(state["description"]).is_empty(): room._append_terminal(" description %s\n" % state["description"])
		if not str(state.get("nat_role","")).is_empty(): room._append_terminal(" ip nat "+state.nat_role+"\n")
		if not str(state["address"]).is_empty(): room._append_terminal(" ip address %s\n" % state["address"])
		if _is_switch_device():
			if str(state.get("mode", "access")) == "trunk":
				room._append_terminal(" switchport mode trunk\n")
				if str(state.get("trunk_allowed", "all")) != "all":
					room._append_terminal(" switchport trunk allowed vlan %s\n" % state["trunk_allowed"])
			elif int(state.get("vlan", 1)) != 1:
				room._append_terminal(" switchport access vlan %d\n" % int(state["vlan"]))
		room._append_terminal(" %s\n!\n" % ("shutdown" if state["shutdown"] else "no shutdown"))
	for route in config["routes"]: room._append_terminal("ip route %s %s\n" % [route["network"], route["next_hop"]])
	for pool in config.get("dhcp_pools", []):
		room._append_terminal("ip dhcp pool %s gateway %s\n" % [pool["network"], pool["gateway"]])
	if not str(config.get("default_gateway", "")).is_empty():
		room._append_terminal("ip default-gateway %s\n" % config["default_gateway"])
	room._append_terminal("end\n")


func _show_ip_interfaces() -> void:
	room._append_terminal("Interface        IP-Address          Status                 Protocol\n")
	var interfaces: Dictionary = room._device_configs[room._terminal_device]["interfaces"]
	for iface in interfaces:
		var state: Dictionary = interfaces[iface]
		var address := str(state["address"]) if not str(state["address"]).is_empty() else "unassigned"
		if address == "dhcp":
			var lease := str(NetSim.effective_address(room._terminal_device, iface))
			address = "%s (dhcp)" % (lease if not lease.is_empty() else "unassigned")
		var status := "administratively down" if state["shutdown"] else "up"
		var protocol := "up" if NetSim.link_protocol_up(room._terminal_device, iface) else "down"
		room._append_terminal("%-16s %-19s %-22s %s\n" % [iface, address, status, protocol])


func _show_interfaces_detail() -> void:
	var interfaces: Dictionary = room._device_configs[room._terminal_device]["interfaces"]
	for iface in interfaces:
		var state: Dictionary = interfaces[iface]
		var admin := "administratively down" if state["shutdown"] else "up"
		var protocol := "up" if NetSim.link_protocol_up(room._terminal_device, iface) else "down"
		room._append_terminal("%s is %s, line protocol is %s\n" % [iface, admin, protocol])
		if not str(state["description"]).is_empty():
			room._append_terminal("  Description: %s\n" % state["description"])
		var shown_address := str(state["address"])
		if shown_address == "dhcp":
			var lease := str(NetSim.effective_address(room._terminal_device, iface))
			shown_address = "%s (dhcp)" % lease if not lease.is_empty() else "dhcp (no lease)"
		if not shown_address.is_empty():
			room._append_terminal("  Internet address is %s\n" % shown_address)
		if _is_switch_device():
			if str(state.get("mode", "access")) == "trunk":
				room._append_terminal("  Switchport: trunk, allowed VLANs %s\n" % str(state.get("trunk_allowed", "all")))
			else:
				room._append_terminal("  Switchport: access, VLAN %d\n" % int(state.get("vlan", 1)))
		room._append_terminal("  Link: %s\n" % ("connected" if NetSim.cable_connected(room._terminal_device, iface) else "not connected"))


func _show_ip_routes() -> void:
	room._append_terminal("Codes: C - connected, S - static\n")
	var config: Dictionary = room._device_configs[room._terminal_device]
	for iface in config["interfaces"]:
		var state: Dictionary = config["interfaces"][iface]
		if not str(state["address"]).is_empty() and not state["shutdown"]:
			room._append_terminal("C  %s is directly connected, %s\n" % [state["address"], iface])
	for route in config["routes"]: room._append_terminal("S  %s via %s\n" % [route["network"], route["next_hop"]])
	var gateway := str(config.get("default_gateway", ""))
	if not gateway.is_empty():
		room._append_terminal("S* 0.0.0.0/0 via %s (default gateway)\n" % gateway)


func _show_vlans() -> void:
	if not _is_switch_device():
		room._append_terminal("% This device does not support VLANs\n"); return
	var config: Dictionary = room._device_configs[room._terminal_device]
	room._append_terminal("VLAN  Name                 Ports\n")
	var vlan_ids: Array = config.get("vlans", {}).keys()
	vlan_ids.sort_custom(func(a, b): return int(a) < int(b))
	for vlan_id in vlan_ids:
		var ports: Array = []
		for iface in config["interfaces"]:
			var state: Dictionary = config["interfaces"][iface]
			if str(state.get("mode", "access")) == "access" and int(state.get("vlan", 1)) == int(vlan_id):
				ports.append(iface)
		room._append_terminal("%-5s %-20s %s\n" % [vlan_id, config["vlans"][vlan_id], ", ".join(ports)])
	var trunks: Array = []
	for iface in config["interfaces"]:
		if str(config["interfaces"][iface].get("mode", "access")) == "trunk":
			trunks.append("%s (allowed: %s)" % [iface, str(config["interfaces"][iface].get("trunk_allowed", "all"))])
	if not trunks.is_empty():
		room._append_terminal("Trunk ports: %s\n" % ", ".join(trunks))


# --- Ping / traceroute ------------------------------------------------------------

func _run_ping_command(words: PackedStringArray) -> void:
	if words.size() < 2: room._append_terminal("% Destination required\n"); return
	var destination := words[1]
	var result: Dictionary = NetSim.ping(room._terminal_device, destination)
	room._append_terminal("Sending 5 ICMP echos to %s:\n" % destination)
	if result["success"]:
		room._append_terminal("!!!!!\nSuccess rate is 100 percent (5/5)\n")
		var path: Array = result.get("path", [])
		if path.size() > 2:
			room._append_terminal("Path: %s\n" % " -> ".join(path))
		_record_ping_success(destination, path.size())
	else:
		room._append_terminal(".....\nSuccess rate is 0 percent (0/5)\n")
		room._append_terminal(NetSim.reason_text(str(result["reason"])) + "\n")


## Journalise un ping reussi (pour les objectifs), sans dupliquer les entrees
## identiques pour ne pas gonfler la sauvegarde.
func _record_ping_success(destination: String, hops: int) -> void:
	_record_host_ping_success(room._terminal_device,destination,hops)

func _record_host_ping_success(source: String, destination: String, hops: int) -> void:
	for event in GameState.events:
		if event.get("type", "") == "ping_ok" and event.get("src", "") == source and event.get("dst", "") == destination: return
	GameState.record({"type":"ping_ok","src":source,"dst":destination,"hops":hops})


func _run_traceroute_command(words: PackedStringArray) -> void:
	if words.size() < 2: room._append_terminal("% Destination required\n"); return
	var destination := words[1]
	var result: Dictionary = NetSim.traceroute(room._terminal_device, destination)
	room._append_terminal("Tracing the route to %s:\n" % destination)
	var path: Array = result.get("path", [])
	var hop := 1
	for i in range(1, path.size()):
		room._append_terminal("  %d  %s\n" % [hop, path[i]])
		hop += 1
	if result["success"]:
		room._append_terminal("Trace complete.\n")
	else:
		room._append_terminal("  %d  * * *\n%s\n" % [hop, NetSim.reason_text(str(result["reason"]))])


func _handle_nat_command(words: PackedStringArray) -> bool:
	var removing := words.size() > 0 and words[0] == "no"
	var parts := Array(words)
	if removing: parts.pop_front()
	if parts.size() < 2 or parts[0] != "ip" or parts[1] != "nat": return false
	var config: Dictionary = room._device_configs[room._terminal_device]
	if config.category not in ["router","wireless_router","firewall"]:
		room._append_terminal("% NAT requires a router or firewall.\n"); return true
	if parts.size() == 3 and parts[2] == "overload" and room._terminal_mode == "config":
		config["nat_enabled"] = not removing
	elif parts.size() == 3 and parts[2] in ["inside","outside"] and room._terminal_mode == "interface":
		config.interfaces[room._terminal_interface]["nat_role"] = "" if removing else parts[2]
	else:
		room._append_terminal("% Config: ip nat overload. Interface: ip nat inside|outside. Prefix no to disable.\n"); return true
	room._save_device_config(room._terminal_device)
	return true


static func _valid_cidr(value: String, minimum_prefix := 0) -> bool:
	var parts := value.split("/")
	return parts.size() == 2 and parts[0].is_valid_ip_address() and not ":" in parts[0] and parts[1].is_valid_int() and int(parts[1]) >= minimum_prefix and int(parts[1]) <= 32
