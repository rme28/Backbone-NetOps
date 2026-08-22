extends Node
## Etat de jeu + journal d'evenements (autoload "GameState").
##
## Systeme de sauvegarde par REJEU (event sourcing) : chaque action du joueur qui
## modifie le reseau est enregistree comme un evenement. Le jeu est la seule source
## de verite. Sauvegarder = ecrire le journal sur disque. Charger = repartir d'un
## PT vide et rejouer le journal pour tout reconstruire (topologie PT + visuels 3D).
## Ne depend d'aucun moteur externe pour la sauvegarde.

const SAVE_DIR := "user://saves"
const SETTINGS_PATH := "user://settings.json"
const SAVE_VERSION := 2

signal event_recorded(event: Dictionary)

var save_name := ""
var score := 0
var bcoins := 250
var events: Array = []
var completed_objectives: Array = []
var device_configs: Dictionary = {}
var settings := {
	"master_volume": 80.0,
	"music_volume": 65.0,
	"effects_volume": 80.0,
	"fullscreen": false,
	"vsync": true,
	"render_scale": 100.0,
	"mouse_sensitivity": 50.0,
	"ui_scale": 100.0,
}


func _ready() -> void:
	load_settings()


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(settings, "\t"))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var loaded: Variant = JSON.parse_string(file.get_as_text())
	if typeof(loaded) == TYPE_DICTIONARY:
		settings.merge(loaded as Dictionary, true)


func new_game(p_name: String) -> void:
	save_name = p_name
	score = 0
	bcoins = 250
	events.clear()
	completed_objectives.clear()
	device_configs.clear()


## Enregistre un evenement dans le journal de la partie en cours.
func record(event: Dictionary) -> void:
	events.append(event)
	event_recorded.emit(event)


func has_content() -> bool:
	return not events.is_empty()


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"name": save_name,
		"saved_at": Time.get_datetime_string_from_system(),
		"score": score,
		"bcoins": bcoins,
		"events": events,
		"completed_objectives": completed_objectives,
		"device_configs": device_configs,
	}


## Ecrit la partie en cours dans user://saves/<nom>.json. Retourne true si ok.
func save() -> bool:
	if save_name.strip_edges().is_empty():
		push_error("[save] pas de nom de sauvegarde")
		return false
	_ensure_dir()
	var path := _path_for(save_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[save] impossible d'ecrire %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	print("[save] partie sauvegardee : %s (%d evenements)" % [path, events.size()])
	return true


## Charge une sauvegarde dans l'etat courant (sans encore rejouer). Retourne true si ok.
func load_from(p_name: String) -> bool:
	var path := _path_for(p_name)
	if not FileAccess.file_exists(path):
		push_error("[save] introuvable : %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[save] impossible de lire %s" % path)
		return false
	var raw := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[save] fichier corrompu : %s" % path)
		return false
	var dict := data as Dictionary
	save_name = dict.get("name", p_name)
	score = int(dict.get("score", 0))
	bcoins = int(dict.get("bcoins", 250))
	events.clear()
	for e in dict.get("events", []):
		if typeof(e) == TYPE_DICTIONARY:
			events.append(e)
	completed_objectives.clear()
	for id in dict.get("completed_objectives", []):
		completed_objectives.append(str(id))
	device_configs = dict.get("device_configs", {}).duplicate(true)
	print("[save] partie chargee : %s (%d evenements)" % [path, events.size()])
	return true


## Liste les noms de sauvegardes disponibles (sans extension).
func list_saves() -> Array:
	var names: Array = []
	_ensure_dir()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return names
	for file in dir.get_files():
		if file.ends_with(".json"):
			names.append(file.trim_suffix(".json"))
	names.sort()
	return names


func delete_save(p_name: String) -> void:
	var path := _path_for(p_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _path_for(p_name: String) -> String:
	return SAVE_DIR.path_join(p_name + ".json")


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
