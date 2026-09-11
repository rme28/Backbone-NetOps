extends Node
## Modele reseau logique autoritaire (autoload "NetSim").
##
## Source de verite unique pour la logique reseau du jeu : L2 (commutation,
## VLANs, trunks), L3 (sous-reseaux, passerelles, routes statiques), etats des
## liens. Reconstruit entierement a chaque changement (topologies petites, le
## rebuild est instantane) a partir des configs d'equipements et des liens.
##
## Aucune dependance a la scene : utilisable en headless pour les tests et
## interrogeable par un futur systeme de scenarios (voir docs/ARCHITECTURE.md).
## Requetes disponibles : ping(), traceroute(), can_reach(), interface_up(),
## link_protocol_up(), ip_configured(), vlan_exists(), port_in_vlan(),
## route_exists(), cable_connected(), device_exists().

## Categories qui commutent les trames (VLAN-aware pour les switches).
const L2_CATEGORIES := ["switch", "switch_l3", "access_point"]
## Categories qui routent les paquets qui ne leur sont pas destines.
const L3_FORWARDERS := ["router", "wireless_router", "firewall", "switch_l3"]
## Categories hotes : n'emettent/recoivent que pour elles-memes, via passerelle.
const HOST_CATEGORIES := ["pc", "client_laptop", "server", "nas"]

const NATIVE_VLAN := 1
const HOP_LIMIT := 32

var _configs: Dictionary = {}   # name -> config (hostname, category, interfaces, routes, vlans, default_gateway)
var _links: Array = []          # [{dev1, iface1, dev2, iface2}]
var _link_index: Dictionary = {}  # "dev|iface" -> {peer_dev, peer_iface}


## Reconstruit le modele. configs : device_name -> config du jeu.
## links : liste de liens actifs {dev1, iface1, dev2, iface2}.
func rebuild(configs: Dictionary, links: Array) -> void:
	_configs = configs
	_links = links
	_link_index.clear()
	for link in links:
		_link_index["%s|%s" % [link["dev1"], link["iface1"]]] = {
			"peer_dev": link["dev2"], "peer_iface": link["iface2"],
		}
		_link_index["%s|%s" % [link["dev2"], link["iface2"]]] = {
			"peer_dev": link["dev1"], "peer_iface": link["iface1"],
		}


## Derive la liste de liens actifs du journal d'evenements (add_link/remove_link).
static func links_from_events(events: Array) -> Array:
	var links: Array = []
	for event in events:
		match event.get("type", ""):
			"add_link":
				links.append({
					"dev1": event.get("dev1", ""), "iface1": event.get("iface1", ""),
					"dev2": event.get("dev2", ""), "iface2": event.get("iface2", ""),
				})
			"remove_link":
				for i in links.size():
					var l: Dictionary = links[i]
					if (l["dev1"] == event.get("dev1", "") and l["iface1"] == event.get("iface1", "")
							and l["dev2"] == event.get("dev2", "") and l["iface2"] == event.get("iface2", "")):
						links.remove_at(i)
						break
	return links


# --- Requetes elementaires (API scenarios) -------------------------------------

func device_exists(name: String) -> bool:
	return _configs.has(name)


func cable_connected(dev: String, iface: String) -> bool:
	return _link_index.has("%s|%s" % [dev, iface])


## Etat administratif : l'interface n'est pas "shutdown".
func interface_admin_up(dev: String, iface: String) -> bool:
	var state := _iface(dev, iface)
	return not state.is_empty() and not bool(state.get("shutdown", true))


## Etat protocole : cable branche + les deux extremites admin up.
func link_protocol_up(dev: String, iface: String) -> bool:
	if not interface_admin_up(dev, iface):
		return false
	var key := "%s|%s" % [dev, iface]
	if not _link_index.has(key):
		return false
	var peer: Dictionary = _link_index[key]
	return interface_admin_up(peer["peer_dev"], peer["peer_iface"])


func interface_up(dev: String, iface: String) -> bool:
	return link_protocol_up(dev, iface)


func ip_configured(dev: String, iface: String) -> bool:
	return not str(_iface(dev, iface).get("address", "")).is_empty()


func vlan_exists(dev: String, vlan_id: int) -> bool:
	return _configs.get(dev, {}).get("vlans", {}).has(str(vlan_id))


func port_in_vlan(dev: String, iface: String, vlan_id: int) -> bool:
	var state := _iface(dev, iface)
	if state.is_empty():
		return false
	if str(state.get("mode", "access")) == "trunk":
		return _trunk_allows(state, vlan_id)
	return int(state.get("vlan", NATIVE_VLAN)) == vlan_id


func route_exists(dev: String, network: String) -> bool:
	for route in _configs.get(dev, {}).get("routes", []):
		if str(route.get("network", "")) == network:
			return true
	return false


func can_reach(src_dev: String, dst_ip: String) -> bool:
	return bool(ping(src_dev, dst_ip).get("success", false))


# --- Ping / traceroute ----------------------------------------------------------

## Simule un ping. Retourne {success, reason, path: [noms], dst_dev}.
## reason est une chaine stable (voir _fail) exploitable par l'UI et les tests.
func ping(src_dev: String, dst_ip: String) -> Dictionary:
	if not _configs.has(src_dev):
		return _fail("unknown-source", [])
	var dst := _parse_ip(dst_ip)
	if dst < 0:
		return _fail("bad-address", [])
	var forward := _walk(src_dev, dst, [src_dev])
	if not forward["success"]:
		return forward
	# Chemin retour : la cible doit savoir joindre l'IP source utilisee.
	var src_ip: int = forward.get("src_ip", -1)
	if src_ip >= 0:
		var back := _walk(forward["dst_dev"], src_ip, [forward["dst_dev"]])
		if not back["success"]:
			var result := _fail("no-return-path", forward["path"])
			result["dst_dev"] = forward["dst_dev"]
			return result
	return forward


## Traceroute : memes regles que ping, retourne la liste des sauts L3.
func traceroute(src_dev: String, dst_ip: String) -> Dictionary:
	return ping(src_dev, dst_ip)


## Coeur du parcours L3 : suit les sauts routeur par routeur jusqu'au
## proprietaire de dst. Retourne {success, reason, path, dst_dev, src_ip}.
func _walk(start_dev: String, dst: int, path: Array) -> Dictionary:
	var current := start_dev
	var first_src_ip := -1
	for _hop in HOP_LIMIT:
		# Livraison : l'equipement courant possede l'adresse sur une iface active.
		var owned := _owned_iface_for_ip(current, dst)
		if not owned.is_empty():
			return {"success": true, "reason": "ok", "path": path, "dst_dev": current, "src_ip": first_src_ip}
		var route := _route_lookup(current, dst)
		if route.is_empty():
			return _fail("no-route", path)
		var egress: String = route["iface"]
		if not link_protocol_up(current, egress):
			return _fail("egress-down", path)
		if first_src_ip < 0:
			first_src_ip = _parse_ip(str(_iface(current, egress).get("address", "")).get_slice("/", 0))
		var arp_target: int = route["arp_target"]
		var owner := _find_l2_neighbor_owning(current, egress, arp_target)
		if owner.is_empty():
			return _fail("next-hop-unreachable", path)
		var next_dev: String = owner["dev"]
		if next_dev in path and next_dev != current:
			return _fail("routing-loop", path)
		path = path + [next_dev]
		if _owned_iface_for_ip(next_dev, dst).is_empty():
			# Le voisin n'est pas la destination : il doit accepter de router.
			var category := str(_configs.get(next_dev, {}).get("category", ""))
			if not (category in L3_FORWARDERS):
				return _fail("host-will-not-forward", path)
		current = next_dev
	return _fail("ttl-exceeded", path)


## Meilleure route pour dst depuis dev : connectees, statiques, passerelle.
## Retourne {} ou {iface, arp_target} (arp_target = IP a resoudre sur le lien).
func _route_lookup(dev: String, dst: int) -> Dictionary:
	var best_prefix := -1
	var best := {}
	var config: Dictionary = _configs.get(dev, {})
	# Reseaux directement connectes (interfaces protocol up avec IP).
	for iface in config.get("interfaces", {}):
		var state: Dictionary = config["interfaces"][iface]
		var address := str(state.get("address", ""))
		if address.is_empty() or not link_protocol_up(dev, iface):
			continue
		var prefix := _prefix_of(address)
		if _same_subnet(dst, _parse_ip(address.get_slice("/", 0)), prefix) and prefix > best_prefix:
			best_prefix = prefix
			best = {"iface": iface, "arp_target": dst}
	# Routes statiques (network/prefix via next_hop).
	for route in config.get("routes", []):
		var network := str(route.get("network", ""))
		var prefix := _prefix_of(network)
		if not _same_subnet(dst, _parse_ip(network.get_slice("/", 0)), prefix):
			continue
		if prefix <= best_prefix:
			continue
		var via := _egress_for_next_hop(dev, _parse_ip(str(route.get("next_hop", ""))))
		if not via.is_empty():
			best_prefix = prefix
			best = {"iface": via, "arp_target": _parse_ip(str(route.get("next_hop", "")))}
	# Passerelle par defaut des hotes (equivaut a 0.0.0.0/0).
	var gateway := str(config.get("default_gateway", ""))
	if best_prefix < 0 and not gateway.is_empty():
		var via := _egress_for_next_hop(dev, _parse_ip(gateway))
		if not via.is_empty():
			best = {"iface": via, "arp_target": _parse_ip(gateway)}
	return best


## Interface (protocol up) dont le sous-reseau contient next_hop.
func _egress_for_next_hop(dev: String, next_hop: int) -> String:
	if next_hop < 0:
		return ""
	var interfaces: Dictionary = _configs.get(dev, {}).get("interfaces", {})
	for iface in interfaces:
		var address := str(interfaces[iface].get("address", ""))
		if address.is_empty() or not link_protocol_up(dev, iface):
			continue
		if _same_subnet(next_hop, _parse_ip(address.get_slice("/", 0)), _prefix_of(address)):
			return iface
	return ""


## Nom d'interface active de dev qui possede exactement l'IP donnee, ou "".
func _owned_iface_for_ip(dev: String, ip: int) -> Dictionary:
	var interfaces: Dictionary = _configs.get(dev, {}).get("interfaces", {})
	for iface in interfaces:
		var state: Dictionary = interfaces[iface]
		if bool(state.get("shutdown", true)):
			continue
		var address := str(state.get("address", ""))
		if not address.is_empty() and _parse_ip(address.get_slice("/", 0)) == ip:
			return {"iface": iface}
	return {}


## Cherche, dans le domaine L2 joignable depuis (dev, egress) en untagged,
## un equipement possedant l'IP cible sur une interface active.
func _find_l2_neighbor_owning(dev: String, egress: String, target_ip: int) -> Dictionary:
	for endpoint in _l2_flood(dev, egress):
		var candidate: String = endpoint["dev"]
		var iface: String = endpoint["iface"]
		var state := _iface(candidate, iface)
		if bool(state.get("shutdown", true)):
			continue
		var address := str(state.get("address", ""))
		if not address.is_empty() and _parse_ip(address.get_slice("/", 0)) == target_ip:
			return {"dev": candidate, "iface": iface}
	return {}


## Propagation L2 d'une trame untagged emise par (dev, iface) : traverse les
## switches en respectant VLANs access/trunk. Retourne les extremites hotes /
## routeurs atteintes : [{dev, iface}].
func _l2_flood(start_dev: String, start_iface: String) -> Array:
	var delivered: Array = []
	var visited := {}  # "dev|iface|tag" cote entree switch, pour couper les boucles
	# File d'ondes : trames en transit sur un cable, format {dev, iface, tag}
	# = la trame sort de (dev, iface) avec le tag donne (-1 = untagged).
	var queue: Array = [{"dev": start_dev, "iface": start_iface, "tag": -1}]
	while not queue.is_empty():
		var frame: Dictionary = queue.pop_front()
		var out_dev: String = frame["dev"]
		var out_iface: String = frame["iface"]
		if not link_protocol_up(out_dev, out_iface):
			continue
		var peer: Dictionary = _link_index.get("%s|%s" % [out_dev, out_iface], {})
		if peer.is_empty():
			continue
		var in_dev: String = peer["peer_dev"]
		var in_iface: String = peer["peer_iface"]
		var tag: int = frame["tag"]
		var category := str(_configs.get(in_dev, {}).get("category", ""))
		if not (category in L2_CATEGORIES):
			# Hote ou routeur : ne recoit que les trames untagged.
			if tag == -1:
				delivered.append({"dev": in_dev, "iface": in_iface})
			continue
		# Commutation : classification a l'entree.
		var vlan := _classify_ingress(in_dev, in_iface, tag)
		if vlan < 0:
			continue
		var key := "%s|%s|%d" % [in_dev, in_iface, vlan]
		if visited.has(key):
			continue
		visited[key] = true
		# Diffusion sur tous les autres ports du meme VLAN.
		for iface in _configs.get(in_dev, {}).get("interfaces", {}):
			if iface == in_iface:
				continue
			var egress_tag := _classify_egress(in_dev, iface, vlan)
			if egress_tag >= -1:
				queue.append({"dev": in_dev, "iface": iface, "tag": egress_tag})
	return delivered


## VLAN interne d'une trame entrant sur un port de switch, ou -1 si rejetee.
func _classify_ingress(dev: String, iface: String, tag: int) -> int:
	var state := _iface(dev, iface)
	var category := str(_configs.get(dev, {}).get("category", ""))
	if category == "access_point":
		return NATIVE_VLAN if tag == -1 else -1
	if str(state.get("mode", "access")) == "trunk":
		if tag == -1:
			return NATIVE_VLAN
		return tag if _trunk_allows(state, tag) else -1
	# Port access : n'accepte que l'untagged, dans son VLAN.
	return int(state.get("vlan", NATIVE_VLAN)) if tag == -1 else -1


## Tag de sortie pour le VLAN donne sur ce port : -1 untagged, >0 tagged,
## -2 = le port ne transporte pas ce VLAN.
func _classify_egress(dev: String, iface: String, vlan: int) -> int:
	var state := _iface(dev, iface)
	var category := str(_configs.get(dev, {}).get("category", ""))
	if category == "access_point":
		return -1 if vlan == NATIVE_VLAN else -2
	if str(state.get("mode", "access")) == "trunk":
		if not _trunk_allows(state, vlan):
			return -2
		return -1 if vlan == NATIVE_VLAN else vlan
	return -1 if int(state.get("vlan", NATIVE_VLAN)) == vlan else -2


func _trunk_allows(state: Dictionary, vlan: int) -> bool:
	var allowed := str(state.get("trunk_allowed", "all"))
	if allowed == "all":
		return true
	for part in allowed.split(",", false):
		if part.strip_edges().is_valid_int() and int(part.strip_edges()) == vlan:
			return true
	return false


# --- Utilitaires ----------------------------------------------------------------

func _iface(dev: String, iface: String) -> Dictionary:
	return _configs.get(dev, {}).get("interfaces", {}).get(iface, {})


func _fail(reason: String, path: Array) -> Dictionary:
	return {"success": false, "reason": reason, "path": path, "dst_dev": ""}


## "10.0.1.2" -> int 32 bits, ou -1 si invalide.
static func _parse_ip(text: String) -> int:
	var parts := text.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var value := 0
	for part in parts:
		if not part.is_valid_int():
			return -1
		var octet := int(part)
		if octet < 0 or octet > 255:
			return -1
		value = (value << 8) | octet
	return value


static func _prefix_of(cidr: String) -> int:
	if not "/" in cidr:
		return 32
	var suffix := cidr.get_slice("/", 1)
	return int(suffix) if suffix.is_valid_int() else 32


static func _same_subnet(a: int, b: int, prefix: int) -> bool:
	if a < 0 or b < 0:
		return false
	if prefix <= 0:
		return true
	var mask := (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
	return (a & mask) == (b & mask)


## Message d'erreur lisible pour le terminal, par code de raison.
static func reason_text(reason: String) -> String:
	match reason:
		"ok": return "Success"
		"bad-address": return "% Invalid address"
		"unknown-source": return "% Unknown source device"
		"no-route": return "% No route to destination (check ip route / default gateway)"
		"egress-down": return "% Outgoing interface is down"
		"next-hop-unreachable": return "% Next hop unreachable at layer 2 (check cabling, VLANs, interface states)"
		"host-will-not-forward": return "% A host on the path is not a router and dropped the packet"
		"routing-loop": return "% Routing loop detected"
		"ttl-exceeded": return "% TTL exceeded (possible routing loop)"
		"no-return-path": return "% Destination reached but no return route to source"
		_: return "% Unreachable (" + reason + ")"
