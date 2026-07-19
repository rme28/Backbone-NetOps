extends Node3D
## Salle 3D + boucle d'interaction. Construit la salle par code (aucune manip
## souris necessaire). Chaque pose d'equipement / cablage est un EVENEMENT :
## applique visuellement, envoye a Packet Tracer, et enregistre dans GameState
## pour la sauvegarde par rejeu. Au chargement d'une partie, les evenements
## sont rejoues.

const MENU_SCENE := "res://scenes/ui/menu.tscn"
const CABLE_MAX_DISTANCE := 8.0

var _paused := false
var _pt_replayed := false

var _player: CharacterBody3D
var _status_label: Label
var _feedback_label: Label
var _help_label: Label
var _pause_menu: CanvasLayer
var _score_label: Label
var _objectives_list: VBoxContainer

# --- Equipements / cablage -----------------------------------------------------
var _catalog: Array[Dictionary] = []
var _selected_index := 0
var _palette_layer: CanvasLayer
var _palette_open := false
var _type_counters: Dictionary = {}       # category -> compteur (pour les noms GameR1, GameSW1...)
var _device_categories: Dictionary = {}   # device_name -> category
var _device_positions: Dictionary = {}    # device_name -> Vector3
var _used_interfaces: Dictionary = {}     # device_name -> Array[String]
var _cable_start: String = ""


func _ready() -> void:
	_player = $Player
	_catalog = EquipmentCatalog.load_all()
	_build_environment()
	_build_room()
	_build_ui()
	_build_palette()
	_build_objectives_panel()
	_build_pause_menu()

	Bridge.status_changed.connect(_on_bridge_status_changed)
	Bridge.ensure_running()

	Objectives.objective_completed.connect(_on_objective_completed)
	Objectives.objectives_changed.connect(_refresh_objectives_panel)

	# Reconstruit immediatement les visuels 3D depuis la sauvegarde (sans PT).
	_rebuild_visuals_from_save()
	# Rattrape les objectifs eventuellement ajoutes au catalogue depuis la sauvegarde.
	Objectives.evaluate()
	_refresh_objectives_panel()


# --- Construction de la scene -------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)


func _build_room() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.22, 0.25)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.35, 0.37, 0.4)

	_add_box(Vector3(0, -0.1, 0), Vector3(20, 0.2, 20), floor_mat)  # sol
	_add_box(Vector3(0, 1.5, -10), Vector3(20, 3, 0.2), wall_mat)   # mur nord
	_add_box(Vector3(0, 1.5, 10), Vector3(20, 3, 0.2), wall_mat)    # mur sud
	_add_box(Vector3(10, 1.5, 0), Vector3(0.2, 3, 20), wall_mat)    # mur est
	_add_box(Vector3(-10, 1.5, 0), Vector3(0.2, 3, 20), wall_mat)   # mur ouest


func _add_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _build_ui() -> void:
	var layer := CanvasLayer.new()

	_help_label = Label.new()
	_help_label.position = Vector2(16, 12)
	layer.add_child(_help_label)

	_status_label = Label.new()
	_status_label.position = Vector2(16, 40)
	layer.add_child(_status_label)

	_feedback_label = Label.new()
	_feedback_label.position = Vector2(16, 68)
	_feedback_label.modulate = Color(0.5, 0.9, 0.5)
	layer.add_child(_feedback_label)

	add_child(layer)
	_update_help_text()


func _update_help_text() -> void:
	var selected := "?"
	if not _catalog.is_empty():
		selected = _catalog[_selected_index]["label"]
	_help_label.text = (
		"ZQSD : deplacer    Souris : regarder    Tab : choisir materiel (%s)    "
		+ "E : poser    Clic gauche : cabler    Echap : pause"
	) % selected


func _build_palette() -> void:
	_palette_layer = CanvasLayer.new()
	_palette_layer.visible = false
	add_child(_palette_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-140, -100)
	panel.custom_minimum_size = Vector2(280, 0)
	_palette_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Choisir le materiel a poser"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	for i in range(_catalog.size()):
		var row := Label.new()
		row.text = "%d - %s" % [i + 1, _catalog[i]["label"]]
		vbox.add_child(row)


func _build_objectives_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-260, 12)
	panel.custom_minimum_size = Vector2(240, 0)
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_score_label)

	vbox.add_child(HSeparator.new())

	_objectives_list = VBoxContainer.new()
	_objectives_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_objectives_list)


func _refresh_objectives_panel() -> void:
	_score_label.text = "Score : %d" % GameState.score

	for child in _objectives_list.get_children():
		child.queue_free()

	for obj in Objectives.get_display_list():
		var row := Label.new()
		var mark := "[x]" if obj["done"] else "[ ]"
		row.text = "%s %s (+%d)" % [mark, obj["title"], obj["points"]]
		row.modulate = Color(0.5, 0.9, 0.5) if obj["done"] else Color(0.8, 0.8, 0.8)
		_objectives_list.add_child(row)


func _on_objective_completed(objective: Dictionary) -> void:
	_flash_feedback("Objectif accompli : %s (+%d pts)" % [objective["title"], objective["points"]])


func _build_pause_menu() -> void:
	_pause_menu = CanvasLayer.new()
	_pause_menu.visible = false
	add_child(_pause_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Reprendre"
	resume_btn.pressed.connect(_toggle_pause)
	vbox.add_child(resume_btn)

	var save_btn := Button.new()
	save_btn.text = "Sauvegarder"
	save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(save_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu principal"
	menu_btn.pressed.connect(_on_quit_to_menu)
	vbox.add_child(menu_btn)


# --- Sauvegarde / rejeu -------------------------------------------------------

## Reconstruit les cubes 3D et les cables depuis le journal (sans toucher a PT).
func _rebuild_visuals_from_save() -> void:
	for event in GameState.events:
		_apply_event_visual(event)


## Synchronise Packet Tracer avec l'etat du jeu, une fois le pont pret :
## vide PT (nouvelle partie comme chargement partent d'un canvas propre), puis
## rejoue les evenements de la partie chargee (aucun si nouvelle partie).
func _replay_to_pt() -> void:
	if _pt_replayed:
		return
	_pt_replayed = true
	Bridge.clear_topology()
	for event in GameState.events:
		_apply_event_pt(event)
	if GameState.has_content():
		print("[game] %d evenement(s) rejoue(s) vers Packet Tracer" % GameState.events.size())


func _apply_event_visual(event: Dictionary) -> void:
	match event.get("type", ""):
		"place_device":
			var wp: Array = event.get("world_pos", [0, 0.5, 0])
			var pos := Vector3(wp[0], wp[1], wp[2])
			var device_name: String = event.get("name", "")
			var category: String = event.get("category", "router")
			_spawn_device_mesh(pos, device_name)
			_device_categories[device_name] = category
			_device_positions[device_name] = pos
			var count: int = _type_counters.get(category, 0) + 1
			_type_counters[category] = count
		"add_link":
			var dev1: String = event.get("dev1", "")
			var dev2: String = event.get("dev2", "")
			_mark_interface_used(dev1, event.get("iface1", ""))
			_mark_interface_used(dev2, event.get("iface2", ""))
			if _device_positions.has(dev1) and _device_positions.has(dev2):
				_draw_cable(_device_positions[dev1], _device_positions[dev2])


func _apply_event_pt(event: Dictionary) -> void:
	match event.get("type", ""):
		"place_device":
			Bridge.add_device(
				event.get("name", ""), event.get("model", "2911"),
				int(event.get("pt_x", 100)), int(event.get("pt_y", 100))
			)
		"add_link":
			Bridge.add_link(
				event.get("dev1", ""), event.get("iface1", ""),
				event.get("dev2", ""), event.get("iface2", ""),
				event.get("cable", "straight"),
			)


func _mark_interface_used(device_name: String, iface: String) -> void:
	if iface.is_empty():
		return
	var used: Array = _used_interfaces.get(device_name, [])
	if not (iface in used):
		used.append(iface)
	_used_interfaces[device_name] = used


func _spawn_device_mesh(pos: Vector3, device_name: String) -> void:
	# StaticBody3D nomme + collision, pour pouvoir viser/cliquer l'equipement (cablage).
	var body := StaticBody3D.new()
	body.name = device_name if not device_name.is_empty() else "Device"
	body.set_meta("device_name", device_name)

	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 0.6, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.9)
	mesh.material = mat
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 0.6, 1)
	col.shape = shape
	body.add_child(col)

	add_child(body)
	body.global_position = pos


func _draw_cable(a: Vector3, b: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.03
	mesh.height = a.distance_to(b)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.1)
	mesh.material = mat
	mesh_inst.mesh = mesh
	add_child(mesh_inst)

	mesh_inst.global_position = (a + b) / 2.0
	var dir := (b - a).normalized()
	if abs(dir.dot(Vector3.UP)) < 0.999:
		mesh_inst.look_at(b, Vector3.UP)
		mesh_inst.rotate_object_local(Vector3.RIGHT, PI / 2.0)


# --- Entrees ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _palette_open:
			_close_palette()
		else:
			_toggle_pause()
		return

	if _paused:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_palette()
			return
		if _palette_open and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx: int = event.keycode - KEY_1
			if idx < _catalog.size():
				_selected_index = idx
				_update_help_text()
				_close_palette()
			return

	if _palette_open:
		return

	if event.is_action_pressed("interact"):
		_place_device()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_cable_click()


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_menu.visible = _paused
	_player.set_active(not _paused)


func _toggle_palette() -> void:
	_palette_open = not _palette_open
	_palette_layer.visible = _palette_open


func _close_palette() -> void:
	_palette_open = false
	_palette_layer.visible = false


func _place_device() -> void:
	if _catalog.is_empty():
		return
	var entry := _catalog[_selected_index]
	var category: String = entry["id"]
	var count: int = _type_counters.get(category, 0) + 1
	var dev_name := "%s%d" % [_name_prefix(category), count]

	var forward := -_player.global_transform.basis.z
	var pos := _player.global_position + forward * 2.5
	pos.y = 0.5

	var total_devices := _device_categories.size() + 1
	var event := {
		"type": "place_device",
		"name": dev_name,
		"model": entry["pt_model"],
		"category": category,
		"pt_x": 100 + total_devices * 60,
		"pt_y": 100,
		"world_pos": [pos.x, pos.y, pos.z],
	}
	_apply_event_visual(event)
	_apply_event_pt(event)
	GameState.record(event)
	print("[game] pose %s (%s)" % [dev_name, entry["label"]])


func _name_prefix(category: String) -> String:
	match category:
		"router": return "GameR"
		"switch": return "GameSW"
		"pc": return "GamePC"
		_: return "GameDev"


## Viser un equipement + clic = debut du cable ; viser un 2e + clic = fin du cable.
func _handle_cable_click() -> void:
	var target := _raycast_device_name()
	if target.is_empty():
		return

	if _cable_start.is_empty():
		_cable_start = target
		_flash_feedback("Cable : vise le 2e equipement (%s)" % target)
		return

	if target == _cable_start:
		_flash_feedback("Choisis un equipement different pour l'autre bout du cable")
		return

	_create_link(_cable_start, target)
	_cable_start = ""


func _create_link(dev1: String, dev2: String) -> void:
	var cat1: String = _device_categories.get(dev1, "router")
	var cat2: String = _device_categories.get(dev2, "router")
	var iface1 := DeviceInterfaces.next_free(cat1, _used_interfaces.get(dev1, []))
	var iface2 := DeviceInterfaces.next_free(cat2, _used_interfaces.get(dev2, []))

	if iface1.is_empty() or iface2.is_empty():
		_flash_feedback("Plus d'interface libre sur %s" % (dev1 if iface1.is_empty() else dev2))
		return

	var event := {
		"type": "add_link",
		"dev1": dev1, "iface1": iface1,
		"dev2": dev2, "iface2": iface2,
		"cable": "straight",
	}
	_apply_event_visual(event)
	_apply_event_pt(event)
	GameState.record(event)
	_flash_feedback("Cable : %s (%s) <-> %s (%s)" % [dev1, iface1, dev2, iface2])
	print("[game] cable %s(%s) <-> %s(%s)" % [dev1, iface1, dev2, iface2])


func _raycast_device_name() -> String:
	var space_state := get_world_3d().direct_space_state
	var cam := _player.get_node("Camera3D") as Camera3D
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * CABLE_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider = hit.get("collider")
	if collider and collider.has_meta("device_name"):
		return collider.get_meta("device_name")
	return ""


# --- Callbacks UI -------------------------------------------------------------

func _on_bridge_status_changed(state: String, message: String) -> void:
	_status_label.text = "[Pont] %s" % message
	match state:
		"connected":
			_status_label.modulate = Color(0.4, 0.9, 0.4)
			_replay_to_pt()
		"error":
			_status_label.modulate = Color(0.95, 0.3, 0.3)
		_:
			_status_label.modulate = Color(0.9, 0.8, 0.3)


func _on_save_pressed() -> void:
	if GameState.save():
		_flash_feedback("Partie sauvegardee : %s" % GameState.save_name)
	else:
		_flash_feedback("Echec de la sauvegarde")


func _on_quit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # souris libre pour le menu
	get_tree().change_scene_to_file(MENU_SCENE)


func _flash_feedback(text: String) -> void:
	_feedback_label.text = text
	var timer := get_tree().create_timer(2.5)
	timer.timeout.connect(func(): _feedback_label.text = "")
