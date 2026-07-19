extends Node
## Systeme d'objectifs + score (autoload "Objectives").
##
## Les objectifs sont verifies sur la source de verite du jeu : le journal
## d'evenements de GameState. Verification reactive (a chaque evenement
## enregistre), pas besoin d'interroger Packet Tracer pour ce socle.
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
		"check": func(events: Array) -> bool:
			return _count_events(events, "place_device") >= 1,
	},
	{
		"id": "place_three_routers",
		"title": "Poser 3 routeurs",
		"points": 20,
		"check": func(events: Array) -> bool:
			return _count_events(events, "place_device") >= 3,
	},
	{
		"id": "place_five_routers",
		"title": "Poser 5 routeurs",
		"points": 30,
		"check": func(events: Array) -> bool:
			return _count_events(events, "place_device") >= 5,
	},
]


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
