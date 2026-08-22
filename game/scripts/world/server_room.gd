extends Node3D
## Salle 3D + boucle d'interaction. Construit la salle par code (aucune manip
## souris necessaire). Chaque pose d'equipement / cablage est un EVENEMENT :
## applique visuellement et enregistre dans GameState.
## pour la sauvegarde par rejeu. Au chargement d'une partie, les evenements
## sont rejoues.

const MENU_SCENE := "res://scenes/ui/menu.tscn"
const CABLE_MAX_DISTANCE := 8.0
const TERMINAL_AUTO_REFRESH := 0.5
const TERMINAL_COMMANDS := [
	"enable", "disable", "configure terminal", "end", "exit",
	"show running-config", "show startup-config", "show interfaces",
	"show ip interface brief", "show ip route", "show arp", "show vlan brief",
	"ping", "traceroute", "hostname", "interface", "description",
	"ip address", "ip route", "no shutdown", "shutdown",
	"copy running-config startup-config", "write memory",
]

var _paused := false

var _player: CharacterBody3D
var _status_label: Label
var _feedback_label: Label
var _help_label: Label
var _inspection_label: Label
var _pause_menu: CanvasLayer
var _settings_overlay: SettingsPanel
var _score_label: Label
var _objectives_list: VBoxContainer
var _technician_hub: CanvasLayer
var _technician_hub_open := false
var _hub_content: RichTextLabel
var _hub_bcoins: Label

# --- Equipements / cablage -----------------------------------------------------
var _catalog: Array[Dictionary] = []
var _selected_index := 0
var _palette_layer: CanvasLayer
var _palette_open := false
var _palette_content: VBoxContainer
var _palette_section_title: Label
var _palette_description: Label
var _palette_bcoins: Label
var _selected_cable_type := "rj45"
var _type_counters: Dictionary = {}       # category -> compteur (pour les noms GameR1, GameSW1...)
var _device_categories: Dictionary = {}   # device_name -> category
var _device_positions: Dictionary = {}    # device_name -> Vector3
var _interface_positions: Dictionary = {} # "device|interface" -> Vector3
var _used_interfaces: Dictionary = {}     # device_name -> Array[String]
var _cable_start: String = ""
var _cable_start_interface: String = ""
var _device_configs: Dictionary = {}      # device_name -> configuration CLI

# --- Terminal de configuration des équipements --------------------------------
var _terminal_layer: CanvasLayer
var _terminal_open := false
var _terminal_device := ""
var _terminal_title: Label
var _terminal_output: RichTextLabel
var _terminal_input: LineEdit
var _terminal_prompt: Label
var _terminal_suggestions: Label
var _terminal_history: Array[String] = []
var _terminal_history_index := 0
var _terminal_completion_matches: Array[String] = []
var _terminal_completion_index := 0
var _terminal_completion_seed := ""
var _terminal_completing := false
var _terminal_mode := "exec"
var _terminal_interface := ""
var _terminal_refresh_accum := 0.0
var _terminal_refresh_in_flight := false


func _ready() -> void:
	_player = $Player
	_catalog = EquipmentCatalog.load_all()
	_build_environment()
	_build_room()
	_build_technician_station()
	_build_ui()
	_build_palette()
	_build_terminal()
	_build_technician_hub()
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
	env.ambient_light_energy = 0.82
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.13, 0.18, 0.2)
	env.fog_density = 0.003
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.45
	light.shadow_enabled = true
	add_child(light)


func _build_room() -> void:
	var floor_mat := _material(Color("20272b"), 0.8, 0.15)
	var wall_mat := _material(Color("303b40"), 0.9)
	var ceiling_mat := _material(Color("171d20"), 0.95)

	_add_box(Vector3(0, -0.1, 0), Vector3(20, 0.2, 20), floor_mat)  # sol
	_add_box(Vector3(0, 1.5, -10), Vector3(20, 3, 0.2), wall_mat)   # mur nord
	_add_box(Vector3(0, 1.5, 10), Vector3(20, 3, 0.2), wall_mat)    # mur sud
	_add_box(Vector3(10, 1.5, 0), Vector3(0.2, 3, 20), wall_mat)    # mur est
	_add_box(Vector3(-10, 1.5, 0), Vector3(0.2, 3, 20), wall_mat)   # mur ouest
	_add_visual_box(Vector3(0, 3.05, 0), Vector3(20, 0.1, 20), ceiling_mat)

	# Dalles et joints du faux plancher.
	var grid_mat := _material(Color("3a464b"), 0.75, 0.25)
	for x in range(-10, 11, 2):
		_add_visual_box(Vector3(x, 0.012, 0), Vector3(0.025, 0.015, 20), grid_mat)
	for z in range(-10, 11, 2):
		_add_visual_box(Vector3(0, 0.013, z), Vector3(20, 0.015, 0.025), grid_mat)

	# Luminaires industriels au plafond.
	for x in [-6.0, 0.0, 6.0]:
		for z in [-6.0, 0.0, 6.0]:
			var lamp_mat := _material(Color("d8f5ff"), 0.2)
			lamp_mat.emission_enabled = true
			lamp_mat.emission = Color("b8ecff")
			lamp_mat.emission_energy_multiplier = 3.0
			_add_visual_box(Vector3(x, 2.96, z), Vector3(2.4, 0.04, 0.45), lamp_mat)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 2.75, z)
			lamp.light_color = Color("d7f4ff")
			lamp.light_energy = 1.45
			lamp.omni_range = 7.0
			add_child(lamp)

	# Chemins de câbles muraux et zones de travail au sol.
	var tray_mat := _material(Color("35434a"), 0.35, 0.65)
	_add_visual_box(Vector3(0, 2.25, -9.82), Vector3(18, 0.16, 0.18), tray_mat)
	_add_visual_box(Vector3(-9.82, 2.25, 0), Vector3(0.18, 0.16, 18), tray_mat)
	var marking := _material(Color("d7a928"), 0.65)
	for x in [-5.0, 0.0, 5.0]:
		_add_visual_box(Vector3(x, 0.018, -3.5), Vector3(3.6, 0.018, 0.045), marking)
		_add_visual_box(Vector3(x, 0.018, 3.5), Vector3(3.6, 0.018, 0.045), marking)


func _material(color: Color, roughness := 0.7, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _add_visual_box(pos: Vector3, size: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	mesh_instance.position = pos
	return mesh_instance


func _build_technician_station() -> void:
	var desk_mat := _material(Color("56636a"), 0.55, 0.38)
	var frame_mat := _material(Color("262f34"), 0.35, 0.7)
	var desk := StaticBody3D.new()
	desk.position = Vector3(0, 0, -7.2)
	add_child(desk)
	_add_local_box(desk, Vector3(0, 0.78, 0), Vector3(2.8, 0.12, 1.15), desk_mat)
	for x in [-1.2, 1.2]:
		for z in [-0.42, 0.42]:
			_add_local_box(desk, Vector3(x, 0.39, z), Vector3(0.08, 0.78, 0.08), frame_mat)
	var desk_collision := CollisionShape3D.new()
	var desk_shape := BoxShape3D.new()
	desk_shape.size = Vector3(2.8, 0.12, 1.15)
	desk_collision.shape = desk_shape
	desk_collision.position = Vector3(0, 0.78, 0)
	desk.add_child(desk_collision)

	var laptop := StaticBody3D.new()
	laptop.name = "TechnicianLaptop"
	laptop.position = Vector3(0, 0.9, -7.15)
	laptop.set_meta("technician_laptop", true)
	laptop.set_meta("device_name", "TECH-LAPTOP")
	add_child(laptop)
	var laptop_mat := _material(Color("2c363d"), 0.3, 0.7)
	_add_local_box(laptop, Vector3(0, 0, 0.18), Vector3(0.78, 0.055, 0.52), laptop_mat)
	_add_local_box(laptop, Vector3(0, 0.31, -0.05), Vector3(0.78, 0.58, 0.055), laptop_mat)
	var screen_mat := _material(Color("102b3a"), 0.25)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color("17638a")
	screen_mat.emission_energy_multiplier = 1.8
	_add_local_box(laptop, Vector3(0, 0.31, -0.083), Vector3(0.69, 0.48, 0.012), screen_mat)
	var laptop_col := CollisionShape3D.new()
	var laptop_shape := BoxShape3D.new()
	laptop_shape.size = Vector3(0.9, 0.72, 0.65)
	laptop_col.shape = laptop_shape
	laptop_col.position = Vector3(0, 0.22, 0.05)
	laptop.add_child(laptop_col)
	var label := Label3D.new()
	label.text = "POSTE TECHNICIEN  [T]"
	label.position = Vector3(0, 0.72, 0)
	label.font_size = 24
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	laptop.add_child(label)


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
	_help_label.add_theme_font_size_override("font_size", 13)
	layer.add_child(_help_label)

	_status_label = Label.new()
	_status_label.position = Vector2(16, 55)
	layer.add_child(_status_label)

	_feedback_label = Label.new()
	_feedback_label.position = Vector2(16, 82)
	_feedback_label.modulate = Color(0.5, 0.9, 0.5)
	layer.add_child(_feedback_label)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-5, -10)
	crosshair.add_theme_font_size_override("font_size", 20)
	crosshair.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 0.8))
	layer.add_child(crosshair)

	_inspection_label = Label.new()
	_inspection_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_inspection_label.position = Vector2(18, -155)
	_inspection_label.custom_minimum_size = Vector2(360, 125)
	_inspection_label.add_theme_font_override("font", _terminal_font())
	_inspection_label.add_theme_font_size_override("font_size", 13)
	_inspection_label.add_theme_color_override("font_color", Color("d9f4ff"))
	var inspect_style := StyleBoxFlat.new()
	inspect_style.bg_color = Color(0.02, 0.05, 0.065, 0.88)
	inspect_style.border_color = Color("2d6275")
	inspect_style.set_border_width_all(1)
	inspect_style.content_margin_left = 12
	inspect_style.content_margin_top = 8
	inspect_style.content_margin_right = 12
	inspect_style.content_margin_bottom = 8
	_inspection_label.add_theme_stylebox_override("normal", inspect_style)
	_inspection_label.visible = false
	layer.add_child(_inspection_label)

	add_child(layer)
	_update_help_text()


func _update_help_text() -> void:
	var selected := "?"
	if not _catalog.is_empty():
		selected = _catalog[_selected_index]["label"]
	_help_label.text = (
		"ZQSD deplacer   |   Souris regarder   |   Tab materiel (%s)   |   E poser\n"
		+ "Clic sur port cabler   |   T console   |   Echap pause"
	) % selected


func _build_palette() -> void:
	_palette_layer = CanvasLayer.new()
	_palette_layer.visible = false
	add_child(_palette_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.035, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_palette_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_palette_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1050, 650)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101a22")
	style.border_color = Color("31566b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "INVENTAIRE TECHNICIEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 25)
	header.add_child(title)
	_palette_bcoins = Label.new()
	_palette_bcoins.add_theme_font_size_override("font_size", 19)
	_palette_bcoins.add_theme_color_override("font_color", Color("ffd166"))
	header.add_child(_palette_bcoins)
	vbox.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	vbox.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(210, 0)
	sidebar.add_theme_constant_override("separation", 8)
	body.add_child(sidebar)
	var sections := {
		"network": "RÉSEAU", "systems": "SYSTÈMES",
		"accessories": "ACCESSOIRES", "tools": "OUTILS",
	}
	for section in sections:
		var button := Button.new()
		button.text = sections[section]
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(_show_palette_section.bind(section))
		sidebar.add_child(button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	_palette_section_title = Label.new()
	_palette_section_title.add_theme_font_size_override("font_size", 21)
	right.add_child(_palette_section_title)
	_palette_content = VBoxContainer.new()
	_palette_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_content.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.add_child(_palette_content)
	right.add_child(scroll)
	right.add_child(HSeparator.new())
	_palette_description = Label.new()
	_palette_description.custom_minimum_size = Vector2(0, 55)
	_palette_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_palette_description.add_theme_color_override("font_color", Color("a8bfcc"))
	right.add_child(_palette_description)
	var hint := Label.new()
	hint.text = "Cliquer pour sélectionner   •   TAB / Échap pour fermer"
	hint.add_theme_color_override("font_color", Color("688391"))
	vbox.add_child(hint)
	_show_palette_section("network")


func _show_palette_section(section: String) -> void:
	var titles := {"network":"Équipements réseau", "systems":"Systèmes", "accessories":"Accessoires", "tools":"Outils"}
	_palette_section_title.text = titles.get(section, section)
	for child in _palette_content.get_children(): child.queue_free()
	for index in _catalog.size():
		var entry: Dictionary = _catalog[index]
		if entry.get("section", "") != section: continue
		var button := Button.new()
		var suffix := ""
		if not entry.get("placeable", true): suffix = "   •   UNIQUE / OUTIL"
		button.text = "%s%s\n%s" % [entry.get("label", "?"), suffix, entry.get("description", "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 65)
		button.pressed.connect(_select_inventory_item.bind(index))
		_palette_content.add_child(button)
	_palette_description.text = "Choisis un élément pour voir son usage."


func _select_inventory_item(index: int) -> void:
	var entry: Dictionary = _catalog[index]
	_palette_description.text = entry.get("description", "")
	match entry.get("kind", "device"):
		"device":
			_selected_index = index
			_update_help_text()
			_close_palette()
		"cable":
			_selected_cable_type = entry.get("id", "rj45")
			_flash_feedback("Câble sélectionné : %s" % entry.get("label", ""))
			_close_palette()
		_:
			_flash_feedback("Cet objet sera disponible dans une prochaine mise à jour")


## Console du moteur de simulation ns-3.
func _build_terminal() -> void:
	_terminal_layer = CanvasLayer.new()
	_terminal_layer.visible = false
	add_child(_terminal_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terminal_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terminal_layer.add_child(center)

	var terminal := PanelContainer.new()
	terminal.custom_minimum_size = Vector2(900, 560)
	var terminal_style := StyleBoxFlat.new()
	terminal_style.bg_color = Color("101010")
	terminal_style.border_color = Color("555555")
	terminal_style.set_border_width_all(2)
	terminal_style.content_margin_left = 18
	terminal_style.content_margin_right = 18
	terminal_style.content_margin_top = 14
	terminal_style.content_margin_bottom = 14
	terminal.add_theme_stylebox_override("panel", terminal_style)
	center.add_child(terminal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	terminal.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	_terminal_title = Label.new()
	_terminal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terminal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_terminal_title.add_theme_color_override("font_color", Color("eeeeee"))
	_terminal_title.add_theme_font_size_override("font_size", 16)
	header.add_child(_terminal_title)
	var live := Label.new()
	live.text = "CONNECTED  |  ns-3"
	live.add_theme_color_override("font_color", Color("80d890"))
	header.add_child(live)
	vbox.add_child(HSeparator.new())
	var tabs := Label.new()
	tabs.text = "  PHYSICAL     CONFIG     [ CLI ]"
	tabs.add_theme_color_override("font_color", Color("bdbdbd"))
	tabs.add_theme_font_size_override("font_size", 13)
	vbox.add_child(tabs)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(panel)
	var output_style := StyleBoxFlat.new()
	output_style.bg_color = Color("000000")
	output_style.content_margin_left = 14
	output_style.content_margin_right = 14
	output_style.content_margin_top = 12
	output_style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", output_style)

	_terminal_output = RichTextLabel.new()
	_terminal_output.custom_minimum_size = Vector2(850, 400)
	_terminal_output.scroll_following = true
	_terminal_output.bbcode_enabled = false
	_terminal_output.add_theme_color_override("default_color", Color("e8e8e8"))
	_terminal_output.add_theme_font_size_override("normal_font_size", 14)
	_terminal_output.add_theme_font_override("normal_font", _terminal_font())
	panel.add_child(_terminal_output)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 0)
	vbox.add_child(input_row)
	_terminal_prompt = Label.new()
	_terminal_prompt.add_theme_font_override("font", _terminal_font())
	_terminal_prompt.add_theme_font_size_override("font_size", 15)
	_terminal_prompt.add_theme_color_override("font_color", Color("ffffff"))
	input_row.add_child(_terminal_prompt)
	_terminal_input = LineEdit.new()
	_terminal_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terminal_input.placeholder_text = "commande..."
	_terminal_input.keep_editing_on_text_submit = true
	_terminal_input.add_theme_font_override("font", _terminal_font())
	_terminal_input.add_theme_font_size_override("font_size", 15)
	_terminal_input.add_theme_color_override("font_color", Color("ffffff"))
	_terminal_input.add_theme_color_override("caret_color", Color("ffffff"))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("000000")
	input_style.border_color = Color("555555")
	input_style.set_border_width_all(1)
	input_style.content_margin_left = 6
	input_style.content_margin_right = 6
	_terminal_input.add_theme_stylebox_override("normal", input_style)
	_terminal_input.add_theme_stylebox_override("focus", input_style)
	_terminal_input.text_submitted.connect(_on_terminal_command_submitted)
	_terminal_input.text_changed.connect(_on_terminal_text_changed)
	_terminal_input.gui_input.connect(_on_terminal_input_event)
	_terminal_input.focus_exited.connect(_keep_terminal_focus)
	# Empeche Tab de faire fuir le focus vers un autre controle de l'UI (comportement
	# de navigation par defaut de Godot et garde le focus dans la console.
	_terminal_input.focus_mode = Control.FOCUS_ALL
	input_row.add_child(_terminal_input)
	_terminal_input.focus_next = _terminal_input.get_path()
	_terminal_input.focus_previous = _terminal_input.get_path()

	_terminal_suggestions = Label.new()
	_terminal_suggestions.add_theme_font_override("font", _terminal_font())
	_terminal_suggestions.add_theme_font_size_override("font_size", 12)
	_terminal_suggestions.add_theme_color_override("font_color", Color("799b88"))
	vbox.add_child(_terminal_suggestions)
	var hint := Label.new()
	hint.text = "TAB completer   ↑↓ historique   ? aide   Echap fermer"
	hint.add_theme_color_override("font_color", Color("60786b"))
	vbox.add_child(hint)


func _terminal_font() -> Font:
	var font := SystemFont.new()
	font.font_names = ["JetBrains Mono", "Fira Code", "DejaVu Sans Mono", "monospace"]
	return font


func _build_technician_hub() -> void:
	_technician_hub = CanvasLayer.new()
	_technician_hub.visible = false
	add_child(_technician_hub)
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.015, 0.025, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_technician_hub.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_technician_hub.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120, 690)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0d1821")
	style.border_color = Color("2e637e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var brand := Label.new()
	brand.text = "BACKBONE OS  /  TECHNICIAN HUB"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_font_size_override("font_size", 23)
	header.add_child(brand)
	_hub_bcoins = Label.new()
	_hub_bcoins.add_theme_font_size_override("font_size", 19)
	_hub_bcoins.add_theme_color_override("font_color", Color("ffd166"))
	header.add_child(_hub_bcoins)
	root.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(220, 0)
	sidebar.add_theme_constant_override("separation", 9)
	body.add_child(sidebar)
	for tab in [["dashboard","TABLEAU DE BORD"], ["mail","MESSAGERIE"], ["jobs","JOBS"], ["shop","BOUTIQUE"], ["settings","PARAMÈTRES"]]:
		var button := Button.new()
		button.text = tab[1]
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(_show_hub_tab.bind(tab[0]))
		sidebar.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(spacer)
	var close := Button.new()
	close.text = "FERMER"
	close.pressed.connect(_close_technician_hub)
	sidebar.add_child(close)
	_hub_content = RichTextLabel.new()
	_hub_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hub_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hub_content.bbcode_enabled = true
	_hub_content.add_theme_font_size_override("normal_font_size", 16)
	body.add_child(_hub_content)
	_show_hub_tab("dashboard")


func _open_technician_hub() -> void:
	_technician_hub_open = true
	_technician_hub.visible = true
	_hub_bcoins.text = "◈ %d B-COINS" % GameState.bcoins
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player.set_active(false)
	_show_hub_tab("dashboard")


func _close_technician_hub() -> void:
	_technician_hub_open = false
	_technician_hub.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.set_active(true)


func _show_hub_tab(tab: String) -> void:
	match tab:
		"mail":
			_hub_content.text = "[font_size=26]MESSAGERIE[/font_size]\n\n[color=#8fd8ff]NOC Central[/color]  •  Nouveau job disponible\nConfigure le réseau du nouveau site avant 18h.\n\n[color=#8fd8ff]Logistique[/color]  •  Inventaire initial\nTout le matériel est débloqué pendant l'alpha.\n\n[color=#8fd8ff]Sécurité[/color]  •  Rappel\nPense à fermer les ports inutilisés."
		"jobs":
			_hub_content.text = "[font_size=26]JOBS DISPONIBLES[/font_size]\n\n[color=#ffd166]◈ 120[/color]  PREMIER LAN\nRelier deux postes via un switch et réussir un ping.\n\n[color=#ffd166]◈ 280[/color]  ROUTAGE STATIQUE\nFaire communiquer deux réseaux à travers deux routeurs.\n\n[color=#9aabba]Les jobs seront bientôt acceptables depuis cet écran.[/color]"
		"shop":
			_hub_content.text = "[font_size=26]BOUTIQUE MATÉRIEL[/font_size]\n\nTous les articles sont actuellement débloqués pour les tests.\n\nRéseau : switches, routeurs, firewall, Wi-Fi\nSystèmes : PC, serveurs, NAS\nAccessoires : cuivre, fibre, console\n\n[color=#ffd166]Solde : ◈ %d B-Coins[/color]" % GameState.bcoins
		"settings":
			_hub_content.text = "[font_size=26]PARAMÈTRES RAPIDES[/font_size]\n\nAudio, vidéo, commandes et interface sont accessibles depuis le menu Pause.\n\nÉchap → Paramètres"
		_:
			_hub_content.text = "[font_size=28]BONSOIR, TECHNICIEN[/font_size]\n\n[color=#7fdbff]État du moteur[/color]    ns-3 connecté\n[color=#7fdbff]Jobs actifs[/color]       0\n[color=#7fdbff]Messages non lus[/color]  3\n[color=#7fdbff]Solde[/color]              ◈ %d B-Coins\n\n[font_size=20]OBJECTIF DU JOUR[/font_size]\nConstruis ton premier LAN fonctionnel depuis l'inventaire." % GameState.bcoins


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
	_score_label.text = "Score : %d    ◈ %d B-COINS" % [GameState.score, GameState.bcoins]

	for child in _objectives_list.get_children():
		child.queue_free()

	for obj in Objectives.get_display_list():
		var row := Label.new()
		var mark := "[x]" if obj["done"] else "[ ]"
		row.text = "%s %s (+%d XP / +%d ◈)" % [mark, obj["title"], obj["points"], obj.get("bcoins", 0)]
		row.modulate = Color(0.5, 0.9, 0.5) if obj["done"] else Color(0.8, 0.8, 0.8)
		_objectives_list.add_child(row)


func _on_objective_completed(objective: Dictionary) -> void:
	_flash_feedback("Objectif accompli : %s  +%d XP  +%d B-Coins" % [objective["title"], objective["points"], objective.get("bcoins", 0)])


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

	var settings_btn := Button.new()
	settings_btn.text = "Paramètres"
	settings_btn.pressed.connect(_open_game_settings)
	vbox.add_child(settings_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu principal"
	menu_btn.pressed.connect(_on_quit_to_menu)
	vbox.add_child(menu_btn)

	_settings_overlay = SettingsPanel.new()
	_settings_overlay.visible = false
	_settings_overlay.closed.connect(_close_game_settings)
	_pause_menu.add_child(_settings_overlay)


func _open_game_settings() -> void:
	_settings_overlay.visible = true


func _close_game_settings() -> void:
	_settings_overlay.visible = false


# --- Sauvegarde / rejeu -------------------------------------------------------

## Reconstruit les cubes 3D et les cables depuis le journal (sans toucher a PT).
func _rebuild_visuals_from_save() -> void:
	for event in GameState.events:
		_apply_event_visual(event)


func _apply_event_visual(event: Dictionary) -> void:
	match event.get("type", ""):
		"place_device":
			var wp: Array = event.get("world_pos", [0, 0.5, 0])
			var pos := Vector3(wp[0], wp[1], wp[2])
			var device_name: String = event.get("name", "")
			var category: String = event.get("category", "router")
			_spawn_device_mesh(pos, device_name, category, float(event.get("world_yaw", 0.0)))
			_device_categories[device_name] = category
			_device_positions[device_name] = pos
			_ensure_device_config(device_name, category)
			var count: int = _type_counters.get(category, 0) + 1
			_type_counters[category] = count
		"add_link":
			var dev1: String = event.get("dev1", "")
			var dev2: String = event.get("dev2", "")
			var iface1: String = event.get("iface1", "")
			var iface2: String = event.get("iface2", "")
			_mark_interface_used(dev1, iface1)
			_mark_interface_used(dev2, iface2)
			var key1 := "%s|%s" % [dev1, iface1]
			var key2 := "%s|%s" % [dev2, iface2]
			if _interface_positions.has(key1) and _interface_positions.has(key2):
				_draw_cable(_interface_positions[key1], _interface_positions[key2], event.get("cable", "rj45"))


func _mark_interface_used(device_name: String, iface: String) -> void:
	if iface.is_empty():
		return
	var used: Array = _used_interfaces.get(device_name, [])
	if not (iface in used):
		used.append(iface)
	_used_interfaces[device_name] = used


func _spawn_device_mesh(pos: Vector3, device_name: String, category: String, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = device_name if not device_name.is_empty() else "Device"
	body.set_meta("device_name", device_name)
	body.set_meta("category", category)
	add_child(body)
	body.global_position = pos
	body.rotation.y = yaw

	var size := Vector3(1.35, 0.22, 0.58)
	match category:
		"switch", "switch_l3": size = Vector3(1.65, 0.20, 0.52)
		"pc", "nas", "server": size = Vector3(0.46, 0.82, 0.52)
		"access_point": size = Vector3(0.75, 0.12, 0.75)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	match category:
		"switch", "switch_l3": _build_switch_model(body, device_name)
		"pc": _build_pc_model(body, device_name)
		"nas", "server": _build_server_model(body, device_name, category)
		"access_point": _build_access_point_model(body, device_name)
		_: _build_router_model(body, device_name)
	if category not in ["pc", "nas", "server"]:
		_build_equipment_cart(body)
	_add_device_ports(body, device_name, category)


func _add_local_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance


func _add_device_label(parent: Node3D, device_name: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = device_name
	label.position = pos
	label.font_size = 36
	label.pixel_size = 0.0042
	label.modulate = Color("e8f7ff")
	label.outline_size = 3
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


func _build_router_model(body: Node3D, device_name: String) -> void:
	var shell := _material(Color("52636d"), 0.32, 0.52)
	var front := _material(Color("182329"), 0.42, 0.62)
	_add_local_box(body, Vector3.ZERO, Vector3(1.35, 0.22, 0.58), shell)
	_add_local_box(body, Vector3(0, 0, 0.296), Vector3(1.25, 0.15, 0.025), front)
	for x in [-0.56, -0.5, 0.5, 0.56]:
		var antenna := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = 0.48
		cylinder.top_radius = 0.014
		cylinder.bottom_radius = 0.022
		cylinder.material = front
		antenna.mesh = cylinder
		antenna.position = Vector3(x, 0.34, -0.18)
		body.add_child(antenna)
	_add_device_label(body, device_name, Vector3(0, 0.22, 0.02))


func _build_switch_model(body: Node3D, device_name: String) -> void:
	var shell := _material(Color("49606b"), 0.27, 0.68)
	var front := _material(Color("10181c"), 0.4, 0.72)
	_add_local_box(body, Vector3.ZERO, Vector3(1.65, 0.20, 0.52), shell)
	_add_local_box(body, Vector3(0, 0, 0.266), Vector3(1.56, 0.14, 0.025), front)
	for x in [-0.76, 0.76]:
		_add_local_box(body, Vector3(x, 0, 0.0), Vector3(0.12, 0.28, 0.60), shell)
	_add_device_label(body, device_name, Vector3(0, 0.20, 0.02))


func _build_pc_model(body: Node3D, device_name: String) -> void:
	var shell := _material(Color("414b53"), 0.42, 0.42)
	var front := _material(Color("161d21"), 0.55, 0.35)
	_add_local_box(body, Vector3.ZERO, Vector3(0.46, 0.82, 0.52), shell)
	_add_local_box(body, Vector3(0, 0, 0.266), Vector3(0.38, 0.72, 0.025), front)
	var power := _material(Color("4ddf88"), 0.3)
	power.emission_enabled = true
	power.emission = Color("22aa55")
	_add_local_box(body, Vector3(0.14, 0.28, 0.282), Vector3(0.035, 0.035, 0.012), power)
	_add_device_label(body, device_name, Vector3(0, 0.50, 0.0))


func _build_server_model(body: Node3D, device_name: String, category: String) -> void:
	var shell := _material(Color("38464e"), 0.35, 0.58)
	var front := _material(Color("10171b"), 0.5, 0.55)
	_add_local_box(body, Vector3.ZERO, Vector3(0.52, 0.82, 0.62), shell)
	_add_local_box(body, Vector3(0, 0, 0.316), Vector3(0.43, 0.72, 0.025), front)
	for y in [-0.23, -0.08, 0.07, 0.22]:
		_add_local_box(body, Vector3(0, y, 0.335), Vector3(0.34, 0.09, 0.018), shell)
	var badge := Label3D.new()
	badge.text = "NAS" if category == "nas" else "SERVER"
	badge.position = Vector3(0, 0.32, 0.34)
	badge.font_size = 18
	badge.pixel_size = 0.0025
	badge.no_depth_test = true
	body.add_child(badge)
	_add_device_label(body, device_name, Vector3(0, 0.50, 0.0))


func _build_access_point_model(body: Node3D, device_name: String) -> void:
	var shell := _material(Color("d7e1e5"), 0.5, 0.15)
	var puck := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.height = 0.12
	cylinder.top_radius = 0.36
	cylinder.bottom_radius = 0.38
	cylinder.material = shell
	puck.mesh = cylinder
	body.add_child(puck)
	var led := _material(Color("55dd99"), 0.2)
	led.emission_enabled = true
	led.emission = Color("33cc77")
	_add_local_box(body, Vector3(0, 0.07, 0.18), Vector3(0.05, 0.02, 0.025), led)
	_add_device_label(body, device_name, Vector3(0, 0.22, 0.0))


func _build_equipment_cart(body: Node3D) -> void:
	var frame := _material(Color("3b4449"), 0.35, 0.65)
	var shelf := _material(Color("69767c"), 0.5, 0.4)
	_add_local_box(body, Vector3(0, -0.17, 0), Vector3(1.8, 0.07, 0.75), shelf)
	for x in [-0.78, 0.78]:
		for z in [-0.27, 0.27]:
			_add_local_box(body, Vector3(x, -0.50, z), Vector3(0.055, 0.65, 0.055), frame)


func _add_device_ports(body: Node3D, device_name: String, category: String) -> void:
	var interfaces: Array = DeviceInterfaces.BY_CATEGORY.get(category, [])
	for index in interfaces.size():
		var iface: String = interfaces[index]
		var local_pos := Vector3.ZERO
		match category:
			"switch", "switch_l3": local_pos = Vector3((index - (interfaces.size() - 1) / 2.0) * 0.22, -0.01, 0.305)
			"pc", "nas", "server": local_pos = Vector3(-0.12 + index * 0.16, -0.20, 0.355)
			"access_point": local_pos = Vector3(-0.10 + index * 0.20, -0.02, 0.40)
			_: local_pos = Vector3((index - (interfaces.size() - 1) / 2.0) * 0.30, -0.01, 0.335)
		var port := StaticBody3D.new()
		port.name = "%s_%s" % [device_name, iface]
		port.position = local_pos
		port.set_meta("device_name", device_name)
		port.set_meta("interface_name", iface)
		var port_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.145, 0.10, 0.055)
		box.material = _material(Color("050708"), 0.4, 0.7)
		port_mesh.mesh = box
		port.add_child(port_mesh)
		var port_col := CollisionShape3D.new()
		var port_shape := BoxShape3D.new()
		port_shape.size = Vector3(0.21, 0.17, 0.15)
		port_col.shape = port_shape
		port.add_child(port_col)
		body.add_child(port)
		var port_label := Label3D.new()
		port_label.text = iface
		port_label.position = local_pos + Vector3(0, -0.075, 0.04)
		port_label.font_size = 20
		port_label.pixel_size = 0.0022
		port_label.no_depth_test = true
		port_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		body.add_child(port_label)
		_interface_positions["%s|%s" % [device_name, iface]] = body.to_global(local_pos)


func _draw_cable(a: Vector3, b: Vector3, cable_type := "rj45") -> void:
	var floor_a := Vector3(a.x, 0.12, a.z)
	var floor_b := Vector3(b.x, 0.12, b.z)
	var corner := Vector3(floor_b.x, 0.12, floor_a.z)
	_add_cable_plug(a, cable_type)
	_add_cable_plug(b, cable_type)
	_draw_cable_segment(a, floor_a, cable_type)
	_draw_cable_segment(floor_a, corner, cable_type)
	_draw_cable_segment(corner, floor_b, cable_type)
	_draw_cable_segment(floor_b, b, cable_type)


func _add_cable_plug(pos: Vector3, cable_type: String) -> void:
	var plug := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.11, 0.08, 0.14)
	mesh.material = _material(Color("e1b84b") if cable_type == "fiber" else Color("42a5d9"), 0.32, 0.2)
	plug.mesh = mesh
	plug.global_position = pos
	add_child(plug)


func _draw_cable_segment(a: Vector3, b: Vector3, cable_type: String) -> void:
	if a.distance_to(b) < 0.02:
		return
	var mesh_inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012 if cable_type == "fiber" else 0.018
	mesh.bottom_radius = mesh.top_radius
	mesh.height = a.distance_to(b)
	var mat := _material(Color("f0c84f") if cable_type == "fiber" else Color("2498d1"), 0.38, 0.12)
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
		if _technician_hub_open:
			_close_technician_hub()
		elif _terminal_open:
			_close_terminal()
		elif _palette_open:
			_close_palette()
		else:
			_toggle_pause()
		return

	if _paused or _terminal_open or _technician_hub_open:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_palette()
			return
		if event.keycode == KEY_T:
			var hit := _raycast_target()
			var target: String = hit.get("device", "")
			if hit.get("technician_laptop", false):
				_open_technician_hub()
			elif target.is_empty():
				_flash_feedback("Vise un equipement pour ouvrir sa console")
			else:
				_open_terminal(target)
			return
	if _palette_open:
		return

	if event.is_action_pressed("interact"):
		_place_device()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_cable_click()


func _process(delta: float) -> void:
	if not _terminal_open:
		_update_inspection_panel()
		return
	_inspection_label.visible = false
	_terminal_refresh_accum += delta
	if _terminal_refresh_accum >= TERMINAL_AUTO_REFRESH:
		_terminal_refresh_accum = 0.0
		_refresh_terminal()


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_menu.visible = _paused
	_player.set_active(not _paused)


func _toggle_palette() -> void:
	_palette_open = not _palette_open
	_palette_layer.visible = _palette_open
	if _palette_open:
		_palette_bcoins.text = "◈ %d B-COINS" % GameState.bcoins
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_player.set_active(false)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_player.set_active(true)


func _close_palette() -> void:
	_palette_open = false
	_palette_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.set_active(true)


func _open_terminal(device_name: String) -> void:
	_terminal_device = device_name
	_terminal_open = true
	_terminal_refresh_accum = 0.0
	_terminal_layer.visible = true
	_terminal_title.text = "%s  —  Terminal" % device_name
	_terminal_mode = "exec"
	_terminal_interface = ""
	_update_terminal_prompt()
	_terminal_output.text = (
		"Backbone Network Operating System\n"
		+ "Connected to %s\n\n" % device_name
		+ "Type ? for available commands.\n"
	)
	_terminal_suggestions.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player.set_active(false)
	_focus_terminal_input()
	_refresh_terminal()


func _close_terminal() -> void:
	_terminal_open = false
	_terminal_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.set_active(true)


func _on_terminal_command_submitted(text: String) -> void:
	_terminal_input.text = ""
	var command := text.strip_edges()
	if command.is_empty():
		_focus_terminal_input()
		return
	_terminal_history.append(command)
	_terminal_history_index = _terminal_history.size()
	_append_terminal(_terminal_prompt.text + command + "\n")
	_execute_terminal_command(command)
	_focus_terminal_input()


func _focus_terminal_input() -> void:
	if _terminal_open:
		_terminal_input.call_deferred("grab_focus")


func _keep_terminal_focus() -> void:
	if _terminal_open:
		_focus_terminal_input()


func _ensure_device_config(device_name: String, category: String) -> void:
	if _device_configs.has(device_name): return
	if GameState.device_configs.has(device_name):
		_device_configs[device_name] = GameState.device_configs[device_name].duplicate(true)
		return
	var interfaces := {}
	for iface in DeviceInterfaces.BY_CATEGORY.get(category, []):
		interfaces[iface] = {"address": "", "shutdown": true, "description": ""}
	_device_configs[device_name] = {
		"hostname": device_name, "category": category,
		"interfaces": interfaces, "routes": [],
	}
	_save_device_config(device_name)


func _save_device_config(device_name: String) -> void:
	GameState.device_configs[device_name] = _device_configs[device_name].duplicate(true)


func _execute_terminal_command(command: String) -> void:
	var words := command.to_lower().split(" ", false)
	if command == "?": _show_terminal_help(""); return
	if _command_matches(words, ["clear"]): _terminal_output.text = ""; return
	if _command_matches(words, ["end"]):
		_terminal_mode = "exec"; _terminal_interface = ""; _update_terminal_prompt(); return
	if _command_matches(words, ["exit"]):
		if _terminal_mode == "interface":
			_terminal_mode = "config"; _terminal_interface = ""; _update_terminal_prompt()
		elif _terminal_mode == "config":
			_terminal_mode = "exec"; _update_terminal_prompt()
		else: _close_terminal()
		return
	if _command_matches(words, ["show", "running-config"]): _show_running_config(); return
	if _command_matches(words, ["show", "ip", "route"]): _show_ip_routes(); return
	if _command_matches(words, ["show", "ip", "interface", "brief"]): _show_ip_interfaces(); return
	if _command_starts(words, ["ping"]): _run_ping_command(words); return

	if _terminal_mode == "exec":
		if _command_matches(words, ["configure", "terminal"]):
			_terminal_mode = "config"; _update_terminal_prompt()
			_append_terminal("Enter configuration commands, one per line.\n")
		else: _append_terminal("% Invalid command in EXEC mode\n")
	elif _terminal_mode == "config":
		if _command_starts(words, ["hostname"]): _set_hostname(command)
		elif _command_starts(words, ["interface"]): _enter_interface(words)
		elif _command_starts(words, ["ip", "route"]):
			if _device_configs[_terminal_device]["category"] == "switch": _append_terminal("% IP routing is not available on a Layer 2 switch\n")
			else: _add_static_route(words)
		else: _append_terminal("% Invalid configuration command\n")
	elif _terminal_mode == "interface":
		if _command_matches(words, ["no", "ip", "address"]): _clear_interface_address()
		elif _command_starts(words, ["ip", "address"]):
			if _device_configs[_terminal_device]["category"] == "switch": _append_terminal("% Layer 3 addressing is not available on this switch port\n")
			else: _set_interface_address(words)
		elif _command_matches(words, ["no", "shutdown"]): _set_interface_shutdown(false)
		elif _command_matches(words, ["shutdown"]): _set_interface_shutdown(true)
		elif _command_starts(words, ["description"]): _set_interface_description(command)
		else: _append_terminal("% Invalid interface command\n")


func _command_matches(input: PackedStringArray, canonical: Array[String]) -> bool:
	return input.size() == canonical.size() and _command_starts(input, canonical)


func _command_starts(input: PackedStringArray, canonical: Array[String]) -> bool:
	if input.size() < canonical.size(): return false
	for index in canonical.size():
		if not canonical[index].begins_with(input[index]): return false
	return true


func _set_hostname(command: String) -> void:
	var value := command.get_slice(" ", 1).strip_edges()
	if value.is_empty(): _append_terminal("% Hostname required\n"); return
	_device_configs[_terminal_device]["hostname"] = value
	_save_device_config(_terminal_device)
	_update_terminal_prompt()


func _enter_interface(words: PackedStringArray) -> void:
	if words.size() < 2: _append_terminal("% Interface name required\n"); return
	var iface := words[1]
	var interfaces: Dictionary = _device_configs[_terminal_device]["interfaces"]
	if not interfaces.has(iface): _append_terminal("% Unknown interface %s\n" % iface); return
	_terminal_interface = iface; _terminal_mode = "interface"; _update_terminal_prompt()


func _set_interface_address(words: PackedStringArray) -> void:
	if words.size() < 3:
		_append_terminal("% Expected: ip address A.B.C.D/prefix\n"); return
	var address := words[2]
	if not "/" in address:
		if words.size() < 4:
			_append_terminal("% Subnet mask or prefix required\n"); return
		var prefix := _mask_to_prefix(words[3])
		if prefix < 0:
			_append_terminal("% Invalid subnet mask\n"); return
		address += "/%d" % prefix
	_device_configs[_terminal_device]["interfaces"][_terminal_interface]["address"] = address
	_save_device_config(_terminal_device)


func _clear_interface_address() -> void:
	_device_configs[_terminal_device]["interfaces"][_terminal_interface]["address"] = ""
	_save_device_config(_terminal_device)


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
	_device_configs[_terminal_device]["interfaces"][_terminal_interface]["shutdown"] = value
	_save_device_config(_terminal_device)


func _set_interface_description(command: String) -> void:
	var first_space := command.find(" ")
	var value := command.substr(first_space + 1).strip_edges() if first_space >= 0 else ""
	_device_configs[_terminal_device]["interfaces"][_terminal_interface]["description"] = value
	_save_device_config(_terminal_device)


func _add_static_route(words: PackedStringArray) -> void:
	if words.size() < 4: _append_terminal("% Expected: ip route NETWORK/PREFIX NEXT-HOP\n"); return
	var network := words[2]
	var next_hop := words[3]
	if not "/" in network:
		if words.size() < 5: _append_terminal("% Subnet mask and next-hop required\n"); return
		var prefix := _mask_to_prefix(words[3])
		if prefix < 0: _append_terminal("% Invalid subnet mask\n"); return
		network += "/%d" % prefix
		next_hop = words[4]
	_device_configs[_terminal_device]["routes"].append({"network": network, "next_hop": next_hop})
	_save_device_config(_terminal_device)


func _show_running_config() -> void:
	var config: Dictionary = _device_configs[_terminal_device]
	_append_terminal("Building configuration...\n\nhostname %s\n!\n" % config["hostname"])
	for iface in config["interfaces"]:
		var state: Dictionary = config["interfaces"][iface]
		_append_terminal("interface %s\n" % iface)
		if not str(state["description"]).is_empty(): _append_terminal(" description %s\n" % state["description"])
		if not str(state["address"]).is_empty(): _append_terminal(" ip address %s\n" % state["address"])
		_append_terminal(" %s\n!\n" % ("shutdown" if state["shutdown"] else "no shutdown"))
	for route in config["routes"]: _append_terminal("ip route %s %s\n" % [route["network"], route["next_hop"]])
	_append_terminal("end\n")


func _show_ip_interfaces() -> void:
	_append_terminal("Interface        IP-Address          Status\n")
	var interfaces: Dictionary = _device_configs[_terminal_device]["interfaces"]
	for iface in interfaces:
		var state: Dictionary = interfaces[iface]
		var address := str(state["address"]) if not str(state["address"]).is_empty() else "unassigned"
		var status := "administratively down" if state["shutdown"] else "up"
		_append_terminal("%-16s %-19s %s\n" % [iface, address, status])


func _show_ip_routes() -> void:
	_append_terminal("Codes: C - connected, S - static\n")
	var config: Dictionary = _device_configs[_terminal_device]
	for iface in config["interfaces"]:
		var state: Dictionary = config["interfaces"][iface]
		if not str(state["address"]).is_empty() and not state["shutdown"]:
			_append_terminal("C  %s is directly connected, %s\n" % [state["address"], iface])
	for route in config["routes"]: _append_terminal("S  %s via %s\n" % [route["network"], route["next_hop"]])


func _run_ping_command(words: PackedStringArray) -> void:
	if words.size() < 2: _append_terminal("% Destination required\n"); return
	var destination := words[1]
	_append_terminal("Resolving path through ns-3...\n")
	Bridge.ping(_terminal_device, destination, _build_topology_payload(), func(status, data):
		if status == "ok" and typeof(data) == TYPE_DICTIONARY: _append_terminal(str(data.get("output", "")) + "\n")
		else: _append_terminal("Error: %s\n" % str(data))
		_focus_terminal_input()
	)


func _build_topology_payload() -> Dictionary:
	var devices: Array = []
	for device_name in _device_configs:
		var config: Dictionary = _device_configs[device_name]
		devices.append({
			"name": device_name,
			"category": config.get("category", "router"),
			"interfaces": config.get("interfaces", {}).duplicate(true),
			"routes": config.get("routes", []).duplicate(true),
		})
	var links: Array = []
	for event in GameState.events:
		if event.get("type", "") == "add_link":
			links.append({
				"dev1": event.get("dev1", ""), "iface1": event.get("iface1", ""),
				"dev2": event.get("dev2", ""), "iface2": event.get("iface2", ""),
			})
	return {"devices": devices, "links": links}


func _append_terminal(text: String) -> void:
	_terminal_output.text += text
	_terminal_output.scroll_to_line(_terminal_output.get_line_count())


func _update_terminal_prompt() -> void:
	var config: Dictionary = _device_configs.get(_terminal_device, {})
	var hostname := str(config.get("hostname", _terminal_device))
	match _terminal_mode:
		"config": _terminal_prompt.text = "%s(config)# " % hostname
		"interface": _terminal_prompt.text = "%s(config-if)# " % hostname
		_: _terminal_prompt.text = "%s# " % hostname


func _on_terminal_text_changed(text: String) -> void:
	if _terminal_completing:
		return
	if text.ends_with("?"):
		var prefix := text.trim_suffix("?").strip_edges()
		_terminal_input.text = prefix
		_terminal_input.caret_column = prefix.length()
		_show_terminal_help(prefix)
		return
	_terminal_completion_seed = ""
	_terminal_completion_matches = _matching_terminal_commands(text)
	_update_terminal_suggestions()


func _matching_terminal_commands(prefix: String) -> Array[String]:
	var matches: Array[String] = []
	var normalized := prefix.strip_edges().to_lower()
	for command in TERMINAL_COMMANDS:
		if normalized.is_empty() or _is_command_prefix(normalized, command):
			matches.append(command)
	return matches


func _is_command_prefix(input: String, canonical: String) -> bool:
	var input_words := input.split(" ", false)
	var canonical_words := canonical.split(" ", false)
	if input_words.size() > canonical_words.size():
		return false
	for index in input_words.size():
		if not canonical_words[index].begins_with(input_words[index]):
			return false
	return true


func _update_terminal_suggestions() -> void:
	if _terminal_completion_matches.is_empty() or _terminal_input.text.is_empty():
		_terminal_suggestions.text = ""
		return
	_terminal_suggestions.text = "  ".join(_terminal_completion_matches.slice(0, 5))


func _show_terminal_help(prefix: String) -> void:
	var matches := _matching_terminal_commands(prefix)
	_append_terminal("Available commands%s:\n" % (" for '%s'" % prefix if not prefix.is_empty() else ""))
	for command in matches:
		_append_terminal("  %-38s\n" % command)


func _on_terminal_input_event(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_TAB:
			_complete_terminal_input()
			_terminal_input.accept_event()
		KEY_UP:
			_navigate_terminal_history(-1)
			_terminal_input.accept_event()
		KEY_DOWN:
			_navigate_terminal_history(1)
			_terminal_input.accept_event()


func _complete_terminal_input() -> void:
	var current := _terminal_input.text.strip_edges().to_lower()
	if _terminal_completion_seed.is_empty():
		_terminal_completion_seed = current
		_terminal_completion_matches = _matching_terminal_commands(current)
		_terminal_completion_index = 0
	elif not _terminal_completion_matches.is_empty():
		_terminal_completion_index = (_terminal_completion_index + 1) % _terminal_completion_matches.size()
	if _terminal_completion_matches.is_empty():
		return
	_terminal_completing = true
	_terminal_input.text = _terminal_completion_matches[_terminal_completion_index]
	_terminal_input.caret_column = _terminal_input.text.length()
	_terminal_completing = false
	_update_terminal_suggestions()


func _navigate_terminal_history(direction: int) -> void:
	if _terminal_history.is_empty():
		return
	_terminal_history_index = clampi(_terminal_history_index + direction, 0, _terminal_history.size())
	_terminal_input.text = "" if _terminal_history_index == _terminal_history.size() else _terminal_history[_terminal_history_index]
	_terminal_input.caret_column = _terminal_input.text.length()


func _refresh_terminal() -> void:
	pass


func _place_device() -> void:
	if _catalog.is_empty():
		return
	var entry := _catalog[_selected_index]
	var category: String = entry["id"]
	var count: int = _type_counters.get(category, 0) + 1
	var dev_name := "%s%d" % [_name_prefix(category), count]

	var forward := -_player.global_transform.basis.z
	var pos := _player.global_position + forward * 2.5
	match category:
		"pc", "nas", "server": pos.y = 0.41
		_: pos.y = 0.825
	var toward_player := _player.global_position - pos
	var world_yaw := atan2(toward_player.x, toward_player.z)

	var event := {
		"type": "place_device",
		"name": dev_name,
		"model": entry["model"],
		"category": category,
		"world_pos": [pos.x, pos.y, pos.z],
		"world_yaw": world_yaw,
	}
	_apply_event_visual(event)
	GameState.record(event)
	print("[game] pose %s (%s)" % [dev_name, entry["label"]])


func _name_prefix(category: String) -> String:
	match category:
		"router": return "GameR"
		"switch": return "GameSW"
		"switch_l3": return "GameMLS"
		"wireless_router": return "GameWR"
		"firewall": return "GameFW"
		"access_point": return "GameAP"
		"nas": return "GameNAS"
		"server": return "GameSRV"
		"pc": return "GamePC"
		_: return "GameDev"


## Viser un equipement + clic = debut du cable ; viser un 2e + clic = fin du cable.
func _handle_cable_click() -> void:
	var hit := _raycast_target()
	var target: String = hit.get("device", "")
	var iface: String = hit.get("interface", "")
	if target.is_empty():
		return
	if iface.is_empty():
		_flash_feedback("Vise directement un port ethX pour brancher le cable")
		return
	if iface in _used_interfaces.get(target, []):
		_flash_feedback("%s %s est deja utilise" % [target, iface])
		return

	if _cable_start.is_empty():
		_cable_start = target
		_cable_start_interface = iface
		_flash_feedback("Cable : %s %s selectionne, vise un autre port" % [target, iface])
		return

	if target == _cable_start and iface == _cable_start_interface:
		_flash_feedback("Choisis un autre port pour l'autre bout du cable")
		return

	_create_link(_cable_start, target, _cable_start_interface, iface)
	_cable_start = ""
	_cable_start_interface = ""


func _create_link(dev1: String, dev2: String, selected_iface1 := "", selected_iface2 := "") -> void:
	var cat1: String = _device_categories.get(dev1, "router")
	var cat2: String = _device_categories.get(dev2, "router")
	var iface1: String = selected_iface1 if not selected_iface1.is_empty() else DeviceInterfaces.next_free(cat1, _used_interfaces.get(dev1, []))
	var iface2: String = selected_iface2 if not selected_iface2.is_empty() else DeviceInterfaces.next_free(cat2, _used_interfaces.get(dev2, []))

	if iface1.is_empty() or iface2.is_empty():
		_flash_feedback("Plus d'interface libre sur %s" % (dev1 if iface1.is_empty() else dev2))
		return

	var event := {
		"type": "add_link",
		"dev1": dev1, "iface1": iface1,
		"dev2": dev2, "iface2": iface2,
		"cable": _selected_cable_type,
	}
	_apply_event_visual(event)
	GameState.record(event)
	_flash_feedback("Cable : %s (%s) <-> %s (%s)" % [dev1, iface1, dev2, iface2])
	print("[game] cable %s(%s) <-> %s(%s)" % [dev1, iface1, dev2, iface2])


func _raycast_device_name() -> String:
	return str(_raycast_target().get("device", ""))


func _raycast_target() -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var cam := _player.get_node("Camera3D") as Camera3D
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * CABLE_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider = hit.get("collider")
	if collider and collider.has_meta("device_name"):
		return {
			"device": str(collider.get_meta("device_name")),
			"interface": str(collider.get_meta("interface_name", "")),
			"technician_laptop": bool(collider.get_meta("technician_laptop", false)),
		}
	return {}


func _update_inspection_panel() -> void:
	var hit := _raycast_target()
	var device_name: String = hit.get("device", "")
	if device_name.is_empty():
		_inspection_label.visible = false
		return
	_inspection_label.visible = true
	if hit.get("technician_laptop", false):
		_inspection_label.text = "POSTE TECHNICIEN\n[T] Ouvrir le hub\nMails • Jobs • Boutique • Paramètres"
		return
	var category: String = _device_categories.get(device_name, "device")
	var targeted: String = hit.get("interface", "")
	var lines := ["%s  |  %s" % [device_name, category.to_upper()]]
	var interfaces: Array = DeviceInterfaces.BY_CATEGORY.get(category, [])
	for iface in interfaces:
		var used: bool = iface in _used_interfaces.get(device_name, [])
		var marker: String = ">" if iface == targeted else " "
		var link_state: String = "CABLE" if used else "LIBRE"
		var admin_state: String = ""
		if _device_configs.has(device_name):
			var state: Dictionary = _device_configs[device_name]["interfaces"].get(iface, {})
			admin_state = "DOWN" if state.get("shutdown", true) else "UP"
		lines.append("%s %-5s  %-5s  %s" % [marker, iface, link_state, admin_state])
	_inspection_label.text = "\n".join(lines)


# --- Callbacks UI -------------------------------------------------------------

func _on_bridge_status_changed(state: String, message: String) -> void:
	_status_label.text = "[Pont] %s" % message
	match state:
		"connected":
			_status_label.modulate = Color(0.4, 0.9, 0.4)
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
