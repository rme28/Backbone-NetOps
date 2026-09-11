extends RefCounted
## Host applications share this adapter; all configuration goes through the
## existing persistence callback and all diagnostics query NetSim.
signal ping_succeeded(source: String, destination: String, hops: int)
var configs: Dictionary
var persist: Callable
var sim: Node

func _init(device_configs: Dictionary, save_config: Callable, model: Node) -> void:
	configs = device_configs
	persist = save_config
	sim = model

func configure(device: String, iface: String, dhcp: bool, ip: String, prefix: String, gateway: String) -> String:
	if not configs.get(device,{}).get("interfaces",{}).has(iface): return "Interface inconnue."
	if not dhcp:
		if not ip.is_valid_ip_address() or ":" in ip: return "Adresse IPv4 invalide."
		prefix = prefix.trim_prefix("/")
		if not prefix.is_valid_int() or int(prefix) < 1 or int(prefix) > 32: return "Le CIDR doit être compris entre 1 et 32."
		if not gateway.is_empty() and (not gateway.is_valid_ip_address() or ":" in gateway): return "Passerelle IPv4 invalide."
	var config: Dictionary = configs[device]
	config["interfaces"][iface]["address"] = "dhcp" if dhcp else ip+"/"+prefix
	config["interfaces"][iface]["shutdown"] = false
	config["default_gateway"] = "" if dhcp else gateway
	persist.call(device)
	return "Configuration appliquée."

func network_info(device: String) -> String:
	var lines: Array[String] = []
	for iface in configs.get(device,{}).get("interfaces",{}):
		lines.append("%s  ·  %s\nIPv4 : %s" % [iface,"Connecté" if sim.link_protocol_up(device,iface) else "Déconnecté",sim.effective_address(device,iface)])
	lines.append("Passerelle : "+sim.effective_gateway(device))
	return "\n".join(lines)

func command(device: String, input: String) -> String:
	var words := input.strip_edges().split(" ",false)
	if words.is_empty(): return ""
	match words[0].to_lower():
		"help", "?": return "ipconfig · ifconfig · ip addr · route · ping IPv4 · tracert IPv4 · clear"
		"ipconfig", "ifconfig": return network_info(device)
		"ip":
			if words.size() == 2 and words[1] == "addr": return network_info(device)
		"route": return "Passerelle : %s\nRoutes : %s" % [sim.effective_gateway(device),str(configs[device].get("routes",[]))]
		"ping", "traceroute", "tracert":
			if words.size() != 2: return "Usage : %s IPv4" % words[0]
			var result: Dictionary = sim.ping(device,words[1])
			if result.success: ping_succeeded.emit(device,words[1],result.path.size())
			return "%s\n%s" % ["Destination joignable" if result.success else sim.reason_text(result.reason)," → ".join(result.path)]
	return "Commande inconnue. Saisir help. Configuration IP dans l’application Réseau."

func browse(device: String, address: String) -> String:
	var host := address.strip_edges().trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	# Local application bookmark, not a pretend DNS resolver or live Internet.
	var ip := "198.51.100.10" if host == "connectivity.backbone.test" else host
	if not ip.is_valid_ip_address() or ":" in ip: return "Ressource inconnue. Utiliser connectivity.backbone.test ou une IPv4 simulée."
	var result: Dictionary = sim.ping(device,ip)
	return ("Connexion disponible\nService de connectivité Backbone · "+ip) if result.success else ("Impossible de joindre "+ip+"\n"+sim.reason_text(result.reason))
