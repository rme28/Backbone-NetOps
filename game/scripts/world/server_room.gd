extends Node3D
## Salle 3D + boucle d'interaction. Construit la salle par code (aucune manip
## souris necessaire). Chaque pose d'equipement est un EVENEMENT : applique
## visuellement, envoye a Packet Tracer, et enregistre dans GameState pour la
## sauvegarde par rejeu. Au chargement d'une partie, les evenements sont rejoues.

const MENU_SCENE := "res://scenes/ui/menu.tscn"

var device_count := 0
var _paused := false
var _pt_replayed := false

var _player: CharacterBody3D
var _status_label: Label
var _feedback_label: Label
var _pause_menu: CanvasLayer
var _score_label: Label
var _objectives_list: VBoxContainer


func _ready() -> void:
	_player = $Player
	_build_environment()
	_build_room()
	_build_ui()
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

	var help := Label.new()
	help.text = "ZQSD : se deplacer    Souris : regarder    E : poser un routeur    Echap : menu pause"
	help.position = Vector2(16, 12)
	layer.add_child(help)

	_status_label = Label.new()
	_status_label.position = Vector2(16, 40)
	layer.add_child(_status_label)

	_feedback_label = Label.new()
	_feedback_label.position = Vector2(16, 68)
	_feedback_label.modulate = Color(0.5, 0.9, 0.5)
	layer.add_child(_feedback_label)

	add_child(layer)


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

## Reconstruit les cubes 3D depuis le journal (sans toucher a PT).
func _rebuild_visuals_from_save() -> void:
	device_count = 0
	for event in GameState.events:
		if event.get("type", "") == "place_device":
			device_count += 1
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
			_spawn_device_mesh(Vector3(wp[0], wp[1], wp[2]))


func _apply_event_pt(event: Dictionary) -> void:
	match event.get("type", ""):
		"place_device":
			Bridge.add_device(
				event.get("name", ""), event.get("model", "2911"),
				int(event.get("pt_x", 100)), int(event.get("pt_y", 100))
			)


func _spawn_device_mesh(pos: Vector3) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 0.6, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.9)
	mesh.material = mat
	box.mesh = mesh
	add_child(box)
	box.global_position = pos


# --- Entrees ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
	elif not _paused and event.is_action_pressed("interact"):
		_place_device()


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_menu.visible = _paused
	_player.set_active(not _paused)


func _place_device() -> void:
	device_count += 1
	var dev_name := "GameR%d" % device_count
	var forward := -_player.global_transform.basis.z
	var pos := _player.global_position + forward * 2.5
	pos.y = 0.5

	var event := {
		"type": "place_device",
		"name": dev_name,
		"model": "2911",
		"pt_x": 100 + device_count * 60,
		"pt_y": 100,
		"world_pos": [pos.x, pos.y, pos.z],
	}
	_apply_event_visual(event)
	_apply_event_pt(event)
	GameState.record(event)
	print("[game] pose %s" % dev_name)


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
