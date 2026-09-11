extends Node
## Systeme d'objectifs + score (autoload "Objectives").
##
## Les objectifs sont verifies sur la source de verite du jeu : le journal
## d'evenements de GameState. Verification reactive (a chaque evenement
## enregistre), sans interroger le moteur pour ce socle.
## L'etat (objectifs accomplis, score) vit dans GameState et est donc
## sauvegarde/recharge avec la partie.

signal objective_completed(objective: Dictionary)
signal objectives_changed


## Definition declarative des objectifs. Chaque objectif :
##   id       : identifiant stable (persiste dans la save)
##   title    : texte affiche au joueur
##   points   : score gagne
##   check    : fonction (events: Array) -> bool
var catalog: Array[Dictionary] = [
	{
		"id": "place_first_router",
		"title": "Poser ton premier routeur",
		"points": 10,
		"bcoins": 25,
		"check": func(events: Array) -> bool:
			return _count_devices(events, "router") >= 1,
	},
	{
		"id": "first_cable",
		"title": "Relier deux equipements par un cable",
		"points": 10,
		"bcoins": 25,
		"check": func(events: Array) -> bool:
			return _count_events(events, "add_link") >= 1,
	},
	{
		"id": "first_link_up",
		"title": "Obtenir un lien actif (deux interfaces up)",
		"points": 20,
		"bcoins": 50,
		"check": func(_events: Array) -> bool:
			return _any_link_protocol_up(),
	},
	{
		"id": "first_ping",
		"title": "Reussir un premier ping",
		"points": 30,
		"bcoins": 100,
		"check": func(events: Array) -> bool:
			return _count_events(events, "ping_ok") >= 1,
	},
	{
		"id": "routed_ping",
		"title": "Reussir un ping a travers un routeur",
		"points": 50,
		"bcoins": 200,
		"check": func(events: Array) -> bool:
			for event in events:
				if event.get("type", "") == "ping_ok" and int(event.get("hops", 0)) >= 3:
					return true
			return false,
	},
]


## Un lien au moins avec le protocole actif des deux cotes, d'apres NetSim.
static func _any_link_protocol_up() -> bool:
	var netsim: Node = Engine.get_main_loop().root.get_node_or_null("NetSim")
	if netsim == null:
		return false
	for link in netsim.links_from_events(GameState.events):
		if netsim.link_protocol_up(link["dev1"], link["iface1"]):
			return true
	return false


func _ready() -> void:
	GameState.event_recorded.connect(_on_event_recorded)


## Objectifs accomplis (ids) - stockes dans GameState pour la persistance.
func completed_ids() -> Array:
	return GameState.completed_objectives


func is_completed(id: String) -> bool:
	return id in GameState.completed_objectives


## Liste d'affichage pour l'UI : [{id, title, points, done}, ...] dans l'ordre du catalogue.
func get_display_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for obj in catalog:
		out.append({
			"id": obj["id"],
			"title": obj["title"],
			"points": obj["points"],
			"bcoins": obj.get("bcoins", 0),
			"done": is_completed(obj["id"]),
		})
	return out


## Reevalue tous les objectifs (au chargement d'une partie et a chaque evenement).
func evaluate() -> void:
	var newly_completed := false
	for obj in catalog:
		if is_completed(obj["id"]):
			continue
		var check: Callable = obj["check"]
		if check.call(GameState.events):
			GameState.completed_objectives.append(obj["id"])
			GameState.score += obj["points"]
			GameState.bcoins += int(obj.get("bcoins", 0))
			newly_completed = true
			objective_completed.emit(obj)
			print("[objectifs] accompli : %s (+%d pts, score=%d)" % [obj["title"], obj["points"], GameState.score])
	if newly_completed:
		objectives_changed.emit()


func _on_event_recorded(_event: Dictionary) -> void:
	evaluate()


static func _count_events(events: Array, type: String) -> int:
	var n := 0
	for e in events:
		if e.get("type", "") == type:
			n += 1
	return n


static func _count_devices(events: Array, category: String) -> int:
	var n := 0
	for event in events:
		if event.get("type", "") == "place_device" and event.get("category", "") == category:
			n += 1
	return n
