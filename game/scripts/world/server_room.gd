extends Node3D
## Salle 3D + boucle d'interaction. Construit la salle par code (aucune manip
## souris necessaire). Chaque pose d'equipement / cablage est un EVENEMENT :
## applique visuellement et enregistre dans GameState.
## pour la sauvegarde par rejeu. Au chargement d'une partie, les evenements
## sont rejoues.

const MENU_SCENE := "res://scenes/ui/menu.tscn"
const CABLE_MAX_DISTANCE := 8.0
const TERMINAL_COMMANDS := [
	"enable", "disable", "configure terminal", "end", "exit",
	"show running-config", "show interfaces",
	"show ip interface brief", "show ip route", "show vlan brief",
	"ping", "traceroute", "hostname", "interface", "description",
	"ip address", "ip address dhcp", "ip route", "ip default-gateway",
	"ip dhcp pool", "ip nat inside", "ip nat outside", "ip nat overload", "no ip nat overload", "no ip nat inside", "no ip nat outside",
	"no shutdown", "shutdown", "no ip address", "no ip route", "no vlan",
	"vlan", "name",
	"switchport mode access", "switchport mode trunk",
	"switchport access vlan", "switchport trunk allowed vlan",
]

## Etat initial d'une nouvelle partie : deux baies contre le mur nord de la
## salle serveur, un switch deja racke, et un poste bureautique dans l'open
## space. Simple liste d'evenements du journal, remplacable par un scenario.
const STARTER_EVENTS := [
	{"type": "place_device", "name": "BAIE-A", "model": "rack", "category": "rack",
		"world_pos": [-6.0, 0.95, -8.6], "world_yaw": 0.0},
	{"type": "place_device", "name": "BAIE-B", "model": "rack", "category": "rack",
		"world_pos": [-4.2, 0.95, -8.6], "world_yaw": 0.0},
	{"type": "place_device", "name": "SW-CORE", "model": "switch_l2", "category": "switch",
		"world_pos": [-6.0, 0.2, -8.6], "world_yaw": 0.0},
	{"type": "place_device", "name": "PC-BUREAU1", "model": "desktop", "category": "pc",
		"world_pos": [-8.55, 0.41, 16.2], "world_yaw": 1.5708},
]

var _paused := false
var _interior_test: RefCounted
var _equipment_art: RefCounted
var _soundscape: Node
var _hud: CanvasLayer
var _port_focus: Node3D

var _player: CharacterBody3D
var _status_label: Label
var _feedback_label: Label
var _help_label: Label
var _inspection_label: Label
var _context_label: Label
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
var _device_yaws: Dictionary = {}         # device_name -> float (radians)
var _racks: Dictionary = {}               # rack_name -> {position, yaw, count} pour le rackage
var _interface_positions: Dictionary = {} # "device|interface" -> Vector3
var _used_interfaces: Dictionary = {}     # device_name -> Array[String]
var _cable_start: String = ""
var _cable_start_interface: String = ""
var _cable_nodes: Dictionary = {}         # cle de lien -> Node3D du cable (pour debrancher)
var _device_bodies: Dictionary = {}       # device_name -> StaticBody3D (pour retirer l'equipement)
var _port_leds: Dictionary = {}           # "device|iface" -> MeshInstance3D de la LED d'etat
var _device_configs: Dictionary = {}      # device_name -> configuration CLI
var _held_root: Node3D                     # objet tenu en main (viewmodel), enfant de la camera

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


var _desktop_mat: StandardMaterial3D
var _ui_builder: RefCounted
var _building: RefCounted
var _network_cli: RefCounted
var _pc_os: CanvasLayer
var _host_service: RefCounted
var _office_hosts: Array[Dictionary] = []
var _fixed_network: RefCounted

func _ready() -> void:
	_player = $Player
	get_viewport().use_occlusion_culling = true
	_catalog = EquipmentCatalog.load_all()
	_equipment_art = preload("res://scripts/world/equipment_art.gd").new(self)
	_building = preload("res://scripts/world/building.gd").new(self)
	_build_environment()
	_fixed_network = preload("res://scripts/world/infrastructure/fixed_network.gd").new(self)
	_build_room()
	_build_technician_station()
	_art.optimize_static()
	_ui_builder = preload("res://scripts/ui/level_ui.gd").new(self)
	_build_ui()
	_build_palette()
	_network_cli = preload("res://scripts/ui/terminal/network_cli.gd").new(self)
	_build_terminal()
	_host_service = preload("res://scripts/network/host_service.gd").new(_device_configs, _save_device_config, NetSim)
	_host_service.ping_succeeded.connect(_record_host_ping_success)
	_pc_os = preload("res://scripts/ui/pc_os/desktop.gd").new()
	_pc_os.service = _host_service
	add_child(_pc_os)
	_pc_os.closed.connect(_close_terminal)
	_build_technician_hub()
	_build_objectives_panel()
	_build_pause_menu()
	_build_held_item()
	_port_focus = Node3D.new()
	add_child(_port_focus)
	var focus_mat := _material(Color("8bc6b5"),0.8).duplicate()
	focus_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.012,0.012]: _add_local_box(_port_focus,Vector3(x,0,0),Vector3(0.001,0.025,0.001),focus_mat)
	for y in [-0.012,0.012]: _add_local_box(_port_focus,Vector3(0,y,0),Vector3(0.025,0.001,0.001),focus_mat)
	_port_focus.visible = false
	preload("res://scripts/ui/design_system.gd").apply(self)

	Bridge.status_changed.connect(_on_bridge_status_changed)
	Bridge.ensure_running()

	Objectives.objective_completed.connect(_on_objective_completed)
	Objectives.objectives_changed.connect(_refresh_objectives_panel)

	GameState.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()

	# Nouvelle partie : on seede une petite infrastructure de depart via des
	# evenements normaux du journal. C'est exactement le mecanisme qu'un futur
	# systeme de scenarios utilisera pour definir l'etat initial d'une mission.
	if GameState.events.is_empty():
		for event in STARTER_EVENTS:
			GameState.events.append(event.duplicate(true))

	_ensure_office_hosts()
	# Reconstruit immediatement les visuels 3D depuis la sauvegarde (journal existant).
	_rebuild_visuals_from_save()
	# Le modele reseau logique suit chaque evenement enregistre.
	GameState.event_recorded.connect(func(_event): _sync_netsim())
	_sync_netsim()
	# Rattrape les objectifs eventuellement ajoutes au catalogue depuis la sauvegarde.
	Objectives.evaluate()
	_refresh_objectives_panel()

	_soundscape = preload("res://scripts/world/soundscape.gd").new()
	add_child(_soundscape)
	_soundscape.setup(self)

	# Outil de dev : capture d'ecran automatique pour verification visuelle hors-jeu.
	# N'a aucun effet sauf si la variable d'environnement BACKBONE_SCREENSHOT est
	# definie (chemin de sortie). Ne s'active jamais pendant une partie normale.
	var screenshot_path := OS.get_environment("BACKBONE_SCREENSHOT")
	if not screenshot_path.is_empty():
		_run_dev_screenshot(screenshot_path)

	# Autotest de bout en bout (dev uniquement, BACKBONE_SELFTEST=1) : execute
	# le vrai parcours joueur (pose, cablage, commandes terminal, ping) dans le
	# runtime complet et quitte avec un code d'erreur si un comportement casse.
	if OS.get_environment("BACKBONE_SELFTEST") == "1":
		_interior_test = preload("res://tests/test_runtime.gd").new()
		_interior_test.run.call_deferred(self)
	if OS.get_environment("BACKBONE_INTERIOR_TEST") == "1":
		_interior_test = preload("res://tests/test_interior.gd").new()
		_interior_test.run.call_deferred(self)
	if OS.get_environment("BACKBONE_WAN_TEST") == "1":
		_interior_test = preload("res://tests/test_wan_runtime.gd").new()
		_interior_test.run.call_deferred(self)
	var icons_path := OS.get_environment("BACKBONE_CATALOG_ICONS")
	if not icons_path.is_empty():
		_interior_test = preload("res://tests/catalog_thumbnails.gd").new()
		_interior_test.run.call_deferred(self, icons_path)
	var tour_path := OS.get_environment("BACKBONE_VISUAL_TOUR")
	if not tour_path.is_empty():
		_interior_test = preload("res://tests/visual_tour.gd").new()
		_interior_test.run.call_deferred(self, tour_path)


func _run_dev_screenshot(path: String) -> void:
	_player.set_active(false)
	var setup_script := OS.get_environment("BACKBONE_SCREENSHOT_SETUP")
	if not setup_script.is_empty() and has_method(setup_script):
		call(setup_script)
	# Position/cible de camera optionnelles : BACKBONE_SHOT_POS="x,y,z"
	# et BACKBONE_SHOT_LOOK="x,y,z" pour cadrer sans fonction dediee.
	var pos_env := OS.get_environment("BACKBONE_SHOT_POS")
	var look_env := OS.get_environment("BACKBONE_SHOT_LOOK")
	if not pos_env.is_empty():
		var p := pos_env.split_floats(",")
		if p.size() == 3:
			_player.global_position = Vector3(p[0], p[1], p[2])
		if not look_env.is_empty():
			var l := look_env.split_floats(",")
			if l.size() == 3:
				_player.look_at(Vector3(l[0], l[1], l[2]), Vector3.UP)
				var camera: Camera3D = _player.get_node("Camera3D")
				camera.look_at(Vector3(l[0], l[1], l[2]), Vector3.UP)
	if OS.get_environment("BACKBONE_HIDE_HUD") == "1":
		for child in get_children():
			if child is CanvasLayer: child.visible = false
		_held_root.visible = false
	await get_tree().create_timer(1.2).timeout
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	get_tree().quit()


# --- Construction de la scene -------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c3d1d5")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssao_radius = 0.65
	env.ssao_intensity = 1.3
	env.fog_enabled = false
	env.fog_light_color = Color(0.13, 0.18, 0.2)
	env.fog_density = 0.003
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.25
	light.shadow_enabled = false
	add_child(light)


var _art: RefCounted

func _build_room() -> void:
	_art = preload("res://scripts/world/interior_art.gd").new(self)
	_art.build()


const KENNEY_ASSETS := "res://assets/kenney/"

## Instancie un modele Kenney (CC0, kenney.nl) enfant de la salle, a la position
## donnee. sub_path est relatif a assets/kenney/ (ex: "furniture/table.glb").
## Retourne null si le fichier est absent (pas d'assets telecharges) pour que
## les appelants puissent se rabattre sur une geometrie codee en secours.
func _desktop_material() -> StandardMaterial3D:
	if _desktop_mat == null:
		_desktop_mat = StandardMaterial3D.new()
		_desktop_mat.albedo_texture = load("res://assets/art/desktop.svg")
		_desktop_mat.emission_enabled = true
		_desktop_mat.emission_texture = _desktop_mat.albedo_texture
		_desktop_mat.emission = Color.WHITE
		_desktop_mat.emission_energy_multiplier = 0.35
		_desktop_mat.roughness = 0.65
		_desktop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _desktop_mat


func _add_display(parent: Node3D, pos: Vector3, size: Vector2) -> void:
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = _desktop_material()
	var screen := MeshInstance3D.new()
	screen.mesh = mesh
	parent.add_child(screen)
	screen.position = pos


var _material_cache: Dictionary = {}  # cle -> StandardMaterial3D, evite de regenerer les textures de bruit

## Materiau de base. Avec detailed=true, ajoute une legere variation de surface
## (bruit procedural sur la rugosite) et un liseret de contour (rim light) pour
## que les equipements se detachent mieux du sol sombre - sans dependre d'assets
## externes. emission_color (alpha > 0) rend le materiau lumineux (LED, ecran,
## luminaire) sans avoir a le modifier apres coup - important car les materiaux
## sont mis en cache par signature et partages entre plusieurs objets.
func _material(color: Color, roughness := 0.7, metallic := 0.0, detailed := false, emission_color := Color(0, 0, 0, 0), emission_strength := 1.0) -> StandardMaterial3D:
	var key := "%s|%.3f|%.3f|%s|%s|%.2f" % [color.to_html(), roughness, metallic, str(detailed), emission_color.to_html(), emission_strength]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission_color.a > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(emission_color.r, emission_color.g, emission_color.b)
		mat.emission_energy_multiplier = emission_strength
	if detailed:
		# Liseret de contour tres discret pour detacher la silhouette du fond
		# sombre, sans creer de reflet parasite sous les luminaires.
		mat.rim_enabled = true
		mat.rim = 0.06
		mat.rim_tint = 0.25
	_material_cache[key] = mat
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
	laptop.position = Vector3(0, 0.855, -7.15)
	laptop.scale = Vector3.ONE * 0.5
	laptop.set_meta("technician_laptop", true)
	laptop.set_meta("device_name", "TECH-LAPTOP")
	add_child(laptop)
	var laptop_mat := _material(Color("2c363d"), 0.3, 0.7)
	_add_local_box(laptop, Vector3(0, 0, 0.18), Vector3(0.78, 0.055, 0.52), laptop_mat)
	_add_local_box(laptop, Vector3(0, 0.31, -0.05), Vector3(0.78, 0.58, 0.055), laptop_mat)
	_add_display(laptop, Vector3(0, 0.31, -0.015), Vector2(0.69, 0.48))
	var laptop_col := CollisionShape3D.new()
	var laptop_shape := BoxShape3D.new()
	laptop_shape.size = Vector3(0.9, 0.72, 0.65)
	laptop_col.shape = laptop_shape
	laptop_col.position = Vector3(0, 0.22, 0.05)
	laptop.add_child(laptop_col)
	_spawn_kenney_prop_local(laptop, "furniture/computerKeyboard.glb", Vector3(0, 0.032, 0.18), 0, 0.9)



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
	if size.y >= 2.9:
		var occluder := OccluderInstance3D.new()
		var box_occluder := BoxOccluder3D.new()
		box_occluder.size = size
		occluder.occluder = box_occluder
		body.add_child(occluder)


func _on_settings_changed() -> void:
	GameState.apply_render_scale(get_viewport())
	if _help_label != null:
		_help_label.visible = bool(GameState.settings.get("show_help_overlay", true))


func _update_help_text() -> void:
	var selected := "?"
	if not _catalog.is_empty():
		selected = _catalog[_selected_index]["label"]
	_help_label.visible = bool(GameState.settings.get("show_help_overlay", true))
	_help_label.text = "BACKBONE  /  NETOPS
TAB  Équipement    ·    E  Poser %s" % selected



## --- Objet tenu en main (viewmodel) ------------------------------------------
## Affiche une maquette de l'equipement selectionne dans le coin bas-droit de la
## vue, comme si le technicien le portait. Reconstruit a chaque changement de
## selection. N'a aucun collider et n'affecte ni le monde ni les sauvegardes.

func _build_held_item() -> void:
	var cam := _player.get_node("Camera3D") as Camera3D
	if cam == null:
		return
	_held_root = Node3D.new()
	_held_root.name = "HeldItem"
	cam.add_child(_held_root)
	_held_root.position = Vector3(0.42, -0.34, -0.85)
	_held_root.rotation_degrees = Vector3(7, -24, 4)
	_held_root.scale = Vector3.ONE * 0.55
	_update_held_item()


## Cache l'objet tenu en main pendant les interfaces plein ecran (inventaire,
## terminal, hub, pause) ou l'on ne veut pas qu'il empiete sur l'UI.
func _update_held_item_visibility() -> void:
	if _held_root == null:
		return
	_held_root.visible = not (_palette_open or _terminal_open or _technician_hub_open or _paused)
	_hud.visible = _held_root.visible
	if _port_focus != null: _port_focus.visible = false


func _update_held_item() -> void:
	if _held_root == null:
		return
	for child in _held_root.get_children():
		child.queue_free()
	if _catalog.is_empty():
		return
	var category: String = _catalog[_selected_index].get("id", "router")
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * (0.3 if category in ["rack", "table"] else 1.0)
	_held_root.add_child(holder)
	_build_held_model(holder, category)
	_equipment_art.batch(holder)


## Maquette simplifiee (sans ports ni etiquette) qui evoque le modele reel.
func _build_held_model(holder: Node3D, category: String) -> void:
	if category == "rack": _build_rack_model(holder, "")
	elif category == "table": _build_table_model(holder, "")
	else:
		_equipment_art.build(holder, category, false)
		var interfaces: Array = DeviceInterfaces.BY_CATEGORY.get(category, [])
		for i in interfaces.size(): _equipment_art.jack(holder, _equipment_art.port_position(category, i, interfaces.size(), false))


func _show_palette_section(section: String) -> void:
	var titles := {"network":"Équipements réseau", "systems":"Systèmes", "accessories":"Accessoires", "tools":"Outils"}
	_palette_section_title.text = titles.get(section, section)
	for child in _palette_content.get_children(): child.queue_free()
	for index in _catalog.size():
		var entry: Dictionary = _catalog[index]
		if entry.get("section", "") != section: continue
		var button := Button.new()
		var suffix := ""
		if entry.get("kind", "") == "tool": suffix = "   •   À VENIR"
		elif entry.get("kind", "") == "special": suffix = "   •   INSTALLÉ SUR SITE"
		button.text = "%s%s\n%s" % [entry.get("label", "?"), suffix, entry.get("description", "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 82)
		button.disabled = entry.get("kind", "") in ["tool", "special"]
		var icon_path := "res://assets/equipment_thumbnails/%s.png" % entry.get("id", "")
		if ResourceLoader.exists(icon_path):
			button.icon = load(icon_path)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 100)
			button.add_theme_constant_override("h_separation", 18)
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
			_update_held_item()
			_close_palette()
		"cable":
			_selected_cable_type = entry.get("id", "rj45")
			_flash_feedback("Câble sélectionné : %s" % entry.get("label", ""))
			_close_palette()
		_:
			_flash_feedback("Cet objet sera disponible dans une prochaine mise à jour")


## Hub du poste technicien.
func _terminal_font() -> Font:
	var font := SystemFont.new()
	font.font_names = ["JetBrains Mono", "Fira Code", "DejaVu Sans Mono", "monospace"]
	return font


func _open_technician_hub() -> void:
	_technician_hub_open = true
	_technician_hub.visible = true
	_animate_open(_technician_hub)
	_hub_bcoins.text = "◈ %d B-COINS" % GameState.bcoins
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player.set_active(false)
	_show_hub_tab("dashboard")
	_update_held_item_visibility()


func _close_technician_hub() -> void:
	_technician_hub_open = false
	_technician_hub.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.set_active(true)
	_update_held_item_visibility()


func _show_hub_tab(tab: String) -> void:
	match tab:
		"mail":
			_hub_content.text = "[font_size=26]MESSAGERIE[/font_size]\n\nAucun message."

		"jobs":
			var jobs := "[font_size=26]OBJECTIFS EN COURS[/font_size]\n\n"
			for objective in Objectives.get_display_list():
				var done: bool = objective["done"]
				var mark := "[color=#7ddf9a]TERMINE[/color]" if done else "[color=#ffd166]◈ %d[/color]" % objective["bcoins"]
				jobs += "%s  %s\n" % [mark, objective["title"]]
			jobs += "\n[color=#9aabba]Les recompenses tombent automatiquement des que la condition est remplie sur le reseau reel.[/color]"
			_hub_content.text = jobs
		"shop":
			_hub_content.text = "[font_size=26]BOUTIQUE MATÉRIEL[/font_size]\n\nTous les articles sont actuellement débloqués pour les tests.\n\nRéseau : switches, routeurs, firewall, Wi-Fi\nSystèmes : PC, serveurs, NAS\nAccessoires : cuivre, fibre, console\n\n[color=#ffd166]Solde : ◈ %d B-Coins[/color]" % GameState.bcoins
		"settings":
			_hub_content.text = "[font_size=26]PARAMÈTRES RAPIDES[/font_size]\n\nAudio, vidéo, commandes et interface sont accessibles depuis le menu Pause.\n\nÉchap → Paramètres"
		_:
			# Tableau de bord : etat reel du reseau via NetSim et le journal.
			var device_count := 0
			for name in _device_categories:
				if _device_categories[name] not in ["rack", "table"]:
					device_count += 1
			var links := NetSim.links_from_events(GameState.events)
			var links_up := 0
			for link in links:
				if NetSim.link_protocol_up(link["dev1"], link["iface1"]):
					links_up += 1
			var configured := 0
			for name in _device_configs:
				for iface in _device_configs[name].get("interfaces", {}):
					if NetSim.ip_configured(name, iface):
						configured += 1
						break
			var done_count := 0
			var total_count := 0
			for objective in Objectives.get_display_list():
				total_count += 1
				if objective["done"]: done_count += 1
			_hub_content.text = ("[font_size=28]VOTRE INFRASTRUCTURE[/font_size]\n\n"
				+ "[color=#8bc6b5]Equipements deployes[/color]   %d\n" % device_count
				+ "[color=#8bc6b5]Cables poses[/color]           %d\n" % links.size()
				+ "[color=#8bc6b5]Liens actifs[/color]           %d\n" % links_up
				+ "[color=#8bc6b5]Machines adressees[/color]     %d\n" % configured
				+ "[color=#8bc6b5]Objectifs[/color]              %d / %d\n" % [done_count, total_count]
				+ "[color=#8bc6b5]Score[/color]                  %d\n" % GameState.score
				+ "[color=#8bc6b5]Solde[/color]                  ◈ %d B-Coins\n" % GameState.bcoins
				+ "\n[font_size=20]RAPPEL[/font_size]\nUn lien n'est actif que si le cable est branche et les deux interfaces sont up (no shutdown).")


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


func _open_game_settings() -> void:
	_settings_overlay.visible = true


func _close_game_settings() -> void:
	_settings_overlay.visible = false


# --- Sauvegarde / rejeu -------------------------------------------------------

## Reconstruit les équipements et câbles depuis le journal.
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
			var yaw := float(event.get("world_yaw", 0.0))
			var containing_rack := "" if category == "rack" else _find_containing_rack(pos)
			_spawn_device_mesh(pos, device_name, category, yaw, not containing_rack.is_empty(), bool(event.get("supported", false)))
			_device_categories[device_name] = category
			_device_positions[device_name] = pos
			_device_yaws[device_name] = yaw
			_ensure_device_config(device_name, category)
			var count: int = _type_counters.get(category, 0) + 1
			_type_counters[category] = count
			if category == "rack":
				_racks[device_name] = {"position": pos, "yaw": yaw, "count": 0}
			elif not containing_rack.is_empty():
				var rack: Dictionary = _racks[containing_rack]
				rack["count"] = int(rack.get("count", 0)) + 1
				_racks[containing_rack] = rack
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
				var cable := _draw_cable(_interface_positions[key1], _interface_positions[key2], event.get("cable", "rj45"))
				_cable_nodes[_link_key(dev1, iface1, dev2, iface2)] = cable
		"remove_link":
			var dev1: String = event.get("dev1", "")
			var dev2: String = event.get("dev2", "")
			var iface1: String = event.get("iface1", "")
			var iface2: String = event.get("iface2", "")
			_mark_interface_free(dev1, iface1)
			_mark_interface_free(dev2, iface2)
			var key := _link_key(dev1, iface1, dev2, iface2)
			if _cable_nodes.has(key):
				_cable_nodes[key].queue_free()
				_cable_nodes.erase(key)
		"remove_device":
			var device_name: String = event.get("name", "")
			if _device_bodies.has(device_name):
				_device_bodies[device_name].queue_free()
				_device_bodies.erase(device_name)
			# Libere l'emplacement de baie si l'equipement etait racke.
			var pos: Vector3 = _device_positions.get(device_name, Vector3.INF)
			if pos != Vector3.INF:
				var rack_name := _find_containing_rack(pos)
				if not rack_name.is_empty() and _racks.has(rack_name):
					_racks[rack_name]["count"] = maxi(0, int(_racks[rack_name].get("count", 0)) - 1)
			_device_categories.erase(device_name)
			_device_positions.erase(device_name)
			_device_yaws.erase(device_name)
			_used_interfaces.erase(device_name)
			_device_configs.erase(device_name)
			GameState.device_configs.erase(device_name)
			_racks.erase(device_name)
			for led_key in _port_leds.keys():
				if str(led_key).begins_with(device_name + "|"):
					_port_leds.erase(led_key)
			for iface_key in _interface_positions.keys():
				if str(iface_key).begins_with(device_name + "|"):
					_interface_positions.erase(iface_key)


## Cle canonique d'un lien, independante de l'ordre des extremites.
func _link_key(dev1: String, iface1: String, dev2: String, iface2: String) -> String:
	var a := "%s|%s" % [dev1, iface1]
	var b := "%s|%s" % [dev2, iface2]
	return "%s__%s" % [a, b] if a < b else "%s__%s" % [b, a]


func _mark_interface_used(device_name: String, iface: String) -> void:
	if iface.is_empty():
		return
	var used: Array = _used_interfaces.get(device_name, [])
	if not (iface in used):
		used.append(iface)
	_used_interfaces[device_name] = used


func _mark_interface_free(device_name: String, iface: String) -> void:
	var used: Array = _used_interfaces.get(device_name, [])
	used.erase(iface)
	_used_interfaces[device_name] = used


## compact=true est utilise pour les equipements rackes (etiquettes reduites,
## pas de labels de port flottants) afin d'eviter le fouillis visuel quand
## plusieurs unites sont empilees a quelques centimetres les unes des autres.
func _spawn_device_mesh(pos: Vector3, device_name: String, category: String, yaw := 0.0, compact := false, supported := false) -> void:
	var body := StaticBody3D.new()
	body.name = device_name if not device_name.is_empty() else "Device"
	body.set_meta("device_name", device_name)
	body.set_meta("category", category)
	add_child(body)
	body.global_position = pos
	body.rotation.y = yaw
	_device_bodies[device_name] = body

	var size: Vector3 = _equipment_art.dimensions(category)
	var collision_offset: Vector3 = _equipment_art.offset(category, compact)
	if category == "rack":
		size = Vector3(0.62, 1.9, 0.025)
		collision_offset = Vector3(0, 0, -0.33)
	elif category == "table":
		size = Vector3(1.6, 0.78, 0.9)
		collision_offset = Vector3(0, 0.39, 0)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = collision_offset
	body.add_child(col)

	if category == "rack": _build_rack_model(body, device_name)
	elif category == "table": _build_table_model(body, device_name)
	else: _equipment_art.build(body, category, compact)

	if category not in ["pc", "nas", "server", "client_laptop", "rack", "table"] and not compact and not supported:
		_build_equipment_cart(body)
	_add_device_ports(body, device_name, category, compact)
	_equipment_art.batch(body)


func _add_local_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
	return instance


func _add_device_label(parent: Node3D, device_name: String, pos: Vector3, compact := false) -> void:
	var label := Label3D.new()
	label.text = device_name
	label.position = Vector3(pos.x, minf(pos.y, 0.86), 0.345 if parent.get_meta("category", "") == "rack" else 0.285)
	label.font_size = 24
	label.pixel_size = 0.00075 if compact else 0.0012
	label.modulate = Color("c6d6d5")
	label.outline_size = 0
	parent.add_child(label)


## Rangee de LEDs d'etat clignotantes (visuel), signature classique du materiel
## reseau reel. n LEDs espacees le long de x, sur la face avant en z.
func _build_rack_model(body: Node3D, device_name: String) -> void:
	if body is StaticBody3D:
		for x in [-0.30, 0.30]:
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.03, 1.9, 0.68)
			collider.shape = shape
			collider.position.x = x
			body.add_child(collider)
	var frame := _material(Color("2b3438"), 0.6, 0.3, true)
	var rail := _material(Color("15191b"), 0.5, 0.4)
	for x in [-0.28, 0.28]:
		for z in [-0.31, 0.31]:
			_add_local_box(body, Vector3(x, 0, z), Vector3(0.045, 1.9, 0.045), frame)
	for y in [-0.93, -0.47, 0.0, 0.47, 0.93]:
		_add_local_box(body, Vector3(0, y, -0.31), Vector3(0.6, 0.03, 0.03), rail)
	_add_local_box(body, Vector3(0, 0, -0.33), Vector3(0.58, 1.86, 0.02), rail)
	for x in [-0.30, 0.30]:
		_add_local_box(body, Vector3(x, 0, 0), Vector3(0.018, 1.88, 0.66), frame)
		for i in 40:
			_add_local_box(body, Vector3(x * 0.9, -0.89 + i * 0.04445, 0.337), Vector3(0.012, 0.016, 0.004), rail)
	for y in [-0.94, 0.94]:
		_add_local_box(body, Vector3(0, y, 0), Vector3(0.64, 0.055, 0.72), frame)
	for x in [-0.23, 0.23]:
		_add_local_box(body, Vector3(x, -0.965, 0.22), Vector3(0.075, 0.06, 0.075), rail)
	# Panneau de brassage (decor) monte dans le haut de la baie : rangee de
	# connecteurs sous collerette claire, comme un vrai panneau 24 ports.
	var panel := _material(Color("14181b"), 0.5, 0.3)
	_add_local_box(body, Vector3(0, 0.72, 0.28), Vector3(0.56, 0.09, 0.03), panel)
	for i in 12:
		var x := -0.21 + i * 0.038
		_equipment_art.jack(body, Vector3(x, 0.72, 0.305))
		_equipment_art.text(body, str(i + 1), Vector3(x, 0.743, 0.314), 0.00022)

	_add_device_label(body, device_name, Vector3(0, 1.02, 0.0))


## Table de travail posable depuis l'inventaire, pour poser du materiel dessus.
func _build_table_model(body: Node3D, device_name: String) -> void:
	var top := _material(Color("56636a"), 0.55, 0.32, true)
	var leg := _material(Color("262f34"), 0.4, 0.6)
	_add_local_box(body, Vector3(0, 0.75, 0), Vector3(1.6, 0.06, 0.9), top)
	for x in [-0.7, 0.7]:
		for z in [-0.38, 0.38]:
			_add_local_box(body, Vector3(x, 0.375, z), Vector3(0.06, 0.75, 0.06), leg)
	_add_device_label(body, device_name, Vector3(0, 0.95, 0.0))


## Ordinateur portable client (place-able, distinct de l'unique portable du
## technicien qui est integre a la salle et non deplacable).
func _build_equipment_cart(body: Node3D) -> void:
	var metal := _material(Color("485b62"), 0.55, 0.55)
	_add_local_box(body, Vector3(0, -0.04, 0), Vector3(0.7, 0.025, 0.48), metal)
	_add_local_box(body, Vector3(0, -0.59, 0), Vector3(0.65, 0.018, 0.45), metal)
	for x in [-0.3, 0.3]:
		for z in [-0.19, 0.19]:
			_add_local_box(body, Vector3(x,-0.43,z), Vector3(0.025,0.78,0.025),metal)



func _add_device_ports(body: Node3D, device_name: String, category: String, compact := false) -> void:
	var interfaces: Array = DeviceInterfaces.BY_CATEGORY.get(category, [])
	for index in interfaces.size():
		var iface: String = interfaces[index]
		var local_pos: Vector3 = _equipment_art.port_position(category, index, interfaces.size(), compact)
		var port := StaticBody3D.new()
		port.name = "%s_%s" % [device_name, iface]
		port.position = local_pos
		port.set_meta("device_name", device_name)
		port.set_meta("interface_name", iface)
		_equipment_art.jack(port)
		var led := _add_local_box(port, Vector3(0.006, 0.007, 0.0075), Vector3(0.002, 0.0015, 0.001), _material(Color("101314")))
		led.name = "PortLED"
		_port_leds["%s|%s" % [device_name, iface]] = led
		_equipment_art.text(port, str(index + 1), Vector3(0, 0.013, 0.007), 0.00022)

		var port_col := CollisionShape3D.new()
		var port_shape := BoxShape3D.new()
		port_shape.size = Vector3(0.024, 0.026, 0.025)
		port_col.shape = port_shape
		port.add_child(port_col)
		body.add_child(port)

		_interface_positions["%s|%s" % [device_name, iface]] = body.to_global(local_pos)


## Construit le visuel d'un cable (plugs + segments) dans un noeud conteneur,
## pour pouvoir le supprimer d'un bloc au debranchement.
func _port_direction(pos: Vector3) -> Vector3:
	for key in _interface_positions:
		if _interface_positions[key].distance_to(pos) < 0.001:
			if _fixed_network.directions.has(key): return _fixed_network.directions[key]
			var dev: String = key.get_slice("|", 0)
			if _device_bodies.has(dev): return _device_bodies[dev].global_basis.z.normalized()
	return Vector3.BACK


func _draw_cable(a: Vector3, b: Vector3, cable_type := "rj45") -> Node3D:
	var cable := Node3D.new()
	add_child(cable)
	var da := _port_direction(a)
	var db := _port_direction(b)
	_add_cable_plug(cable, a, cable_type, da)
	_add_cable_plug(cable, b, cable_type, db)
	var points: Array[Vector3] = [a + da * 0.025, a + da * 0.09]
	if a.distance_to(b) < 1.3:
		points.append(Vector3((a.x+b.x)/2, maxf(0.025,minf(a.y,b.y)-0.14), (a.z+b.z)/2) + (da+db)*0.10)
	else:
		var fa := a + da * 0.22
		var fb := b + db * 0.22
		fa.y = 0.018
		fb.y = 0.018
		points.append(fa)
		points.append(fb)
	points.append(b + db * 0.09)
	points.append(b + db * 0.025)
	var curve := Curve3D.new()
	curve.bake_interval = 0.035
	for i in points.size():
		var previous: Vector3 = points[maxi(0,i-1)]
		var next: Vector3 = points[mini(points.size()-1,i+1)]
		var tangent := (next-previous)*0.13
		if points[i].y < 0.03: tangent.y = 0
		curve.add_point(points[i], -tangent, tangent)
	var samples := curve.get_baked_points()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 0.003 if cable_type == "fiber" else 0.004
	for i in samples.size():
		var direction := (samples[mini(i+1,samples.size()-1)]-samples[maxi(0,i-1)]).normalized()
		var side := direction.cross(Vector3.UP)
		if side.length_squared() < 0.001: side = direction.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(direction).normalized()
		for j in 8:
			var normal := side*cos(j*TAU/8)+up*sin(j*TAU/8)
			st.set_normal(normal)
			st.add_vertex(samples[i]+normal*radius)
	for i in samples.size()-1:
		for j in 8:
			var n := (j+1)%8
			for index in [i*8+j,(i+1)*8+j,(i+1)*8+n,i*8+j,(i+1)*8+n,i*8+n]: st.add_index(index)
	st.set_material(_material(Color("c9964d") if cable_type == "fiber" else Color("38899d"),0.8))
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	cable.add_child(mesh)
	return cable


func _add_cable_plug(parent: Node3D, pos: Vector3, cable_type: String, direction: Vector3) -> void:
	var plug := Node3D.new()
	parent.add_child(plug)
	plug.global_position = pos + direction*0.012
	plug.look_at(plug.global_position+direction, Vector3.UP)
	_add_local_box(plug, Vector3.ZERO, Vector3(0.012,0.01,0.026), _material(Color("b9c4c0"),0.3,0.15))
	var boot := _material(Color("c9964d") if cable_type == "fiber" else Color("38899d"),0.85)
	_add_local_box(plug, Vector3(0,0,-0.015), Vector3(0.013,0.012,0.014),boot)
	_add_local_box(plug, Vector3(0,0.006,0.003), Vector3(0.005,0.002,0.013),boot)


## Met a jour la couleur des LEDs de tous les ports selon l'etat NetSim.
func _refresh_port_leds() -> void:
	var led_off := _material(Color("101314"), 0.5)
	var led_up := _material(Color("113322"), 0.4, 0.0, false, Color("2fdd7a"), 1.8)
	var led_down := _material(Color("332211"), 0.4, 0.0, false, Color("ddaa22"), 1.4)
	for key in _port_leds:
		var led: MeshInstance3D = _port_leds[key]
		if not is_instance_valid(led):
			continue
		var dev := str(key).get_slice("|", 0)
		var iface := str(key).get_slice("|", 1)
		var mat: Material = led_off
		if NetSim.cable_connected(dev, iface):
			mat = led_up if NetSim.link_protocol_up(dev, iface) else led_down
		(led.mesh as BoxMesh).material = mat


# --- Entrees ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		var camera: Camera3D = _player.get_node("Camera3D")
		camera.fov = 42.0 if event.pressed and not (_paused or _terminal_open or _palette_open or _technician_hub_open) else 75.0
		return

	if event.is_action_pressed("ui_cancel"):
		if _paused and _settings_overlay.visible:
			_close_game_settings()
		elif _technician_hub_open:
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
		if event.keycode == KEY_X:
			_remove_targeted_device()
			return
	if _palette_open:
		return

	if event.is_action_pressed("interact"):
		_place_device()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_cable_click()


func _process(_delta: float) -> void:
	if not _terminal_open:
		_update_inspection_panel()
		return
	_inspection_label.visible = false


func _toggle_pause() -> void:
	_player.get_node("Camera3D").fov = 75.0
	_paused = not _paused
	_pause_menu.visible = _paused
	_player.set_active(not _paused)
	_update_held_item_visibility()


## Fondu discret a l'ouverture d'un panneau plein ecran (CanvasLayer).
func _animate_open(layer: CanvasLayer) -> void:
	_player.get_node("Camera3D").fov = 75.0
	if _soundscape != null: _soundscape.play("ui")
	for child in layer.get_children():
		if child is CanvasItem:
			var item := child as CanvasItem
			item.modulate.a = 0.0
			var tween := create_tween()
			tween.tween_property(item, "modulate:a", 1.0, 0.14).set_ease(Tween.EASE_OUT)


func _toggle_palette() -> void:
	_palette_open = not _palette_open
	_palette_layer.visible = _palette_open
	if _palette_open:
		_animate_open(_palette_layer)
		_palette_bcoins.text = "◈ %d B-COINS" % GameState.bcoins
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_player.set_active(false)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_player.set_active(true)
	_update_held_item_visibility()


func _close_palette() -> void:
	_palette_open = false
	_palette_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.set_active(true)
	_update_held_item_visibility()


func _open_terminal(device_name: String) -> void:
	if not _device_configs.has(device_name): return
	if _device_categories.get(device_name, "") in ["pc", "client_laptop"]:
		_terminal_open = true
		_pc_os.open_device(device_name)
		_player.set_active(false)
		_update_held_item_visibility()
		return
	if _fixed_network.fixed.has(device_name):
		if device_name == "WAN-ONT":
			_flash_feedback("Remise opérateur : DHCP ou 203.0.113.x/24, passerelle 203.0.113.1. Test : 198.51.100.10")
			return
		_flash_feedback("Brassage passif : relier la prise au port de panneau portant le même numéro.")
		return
	_terminal_device = device_name
	_terminal_open = true
	_terminal_layer.visible = true
	_animate_open(_terminal_layer)
	_terminal_title.text = "%s - Terminal" % device_name
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
	_update_held_item_visibility()


func _close_terminal() -> void:
	_pc_os.visible = false
	_terminal_open = false
	_terminal_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.set_active(true)
	_update_held_item_visibility()


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
	if _terminal_open and _terminal_layer.visible:
		_terminal_input.call_deferred("grab_focus")


func _keep_terminal_focus() -> void:
	if _terminal_open:
		_focus_terminal_input()


## Categories dont les interfaces sont actives des la sortie de boite (comme
## dans la realite : un switch ou un PC a ses ports up par defaut, un routeur
## Cisco demarre tout en shutdown).
const DEFAULT_UP_CATEGORIES := ["switch", "switch_l3", "access_point", "pc", "client_laptop", "server", "nas"]


func _ensure_device_config(device_name: String, category: String) -> void:
	if _device_configs.has(device_name):
		return
	if GameState.device_configs.has(device_name):
		_device_configs[device_name] = GameState.device_configs[device_name].duplicate(true)
		_normalize_config(device_name)
		return
	var default_up := category in DEFAULT_UP_CATEGORIES
	var interfaces := {}
	for iface in DeviceInterfaces.BY_CATEGORY.get(category, []):
		interfaces[iface] = {
			"address": "", "shutdown": not default_up, "description": "",
			"mode": "access", "vlan": 1, "trunk_allowed": "all",
		}
	_device_configs[device_name] = {
		"hostname": device_name, "category": category,
		"interfaces": interfaces, "routes": [],
		"default_gateway": "",
		"vlans": {"1": "default"},
	}
	_save_device_config(device_name)


## Complete les champs manquants d'une config chargee depuis une ancienne
## sauvegarde (VLANs, passerelle...), sans toucher aux valeurs existantes.
func _normalize_config(device_name: String) -> void:
	var config: Dictionary = _device_configs[device_name]
	if not config.has("default_gateway"): config["default_gateway"] = ""
	if not config.has("vlans"): config["vlans"] = {"1": "default"}
	if not config.has("routes"): config["routes"] = []
	if not config.has("dhcp_pools"): config["dhcp_pools"] = []
	for iface in config.get("interfaces", {}):
		var state: Dictionary = config["interfaces"][iface]
		if not state.has("mode"): state["mode"] = "access"
		if not state.has("vlan"): state["vlan"] = 1
		if not state.has("trunk_allowed"): state["trunk_allowed"] = "all"


func _save_device_config(device_name: String) -> void:
	GameState.device_configs[device_name] = _device_configs[device_name].duplicate(true)
	_sync_netsim()


## Pousse l'etat courant (configs + liens du journal) dans le modele reseau
## logique, puis rafraichit les indicateurs visuels qui en dependent.
func _sync_netsim() -> void:
	var configs := _device_configs.duplicate(true)
	configs.merge(preload("res://scripts/network/operator_network.gd").configs())
	var links := NetSim.links_from_events(GameState.events)
	links.append_array(preload("res://scripts/network/operator_network.gd").links())
	NetSim.rebuild(configs, links)
	_refresh_port_leds()
	# Certains objectifs dependent de l'etat reseau (liens actifs), pas
	# seulement du journal : reevaluation a chaque changement de config.
	Objectives.evaluate()


func _append_terminal(text: String) -> void:
	_terminal_output.text += text
	_terminal_output.scroll_to_line(_terminal_output.get_line_count())


func _update_terminal_prompt() -> void:
	var config: Dictionary = _device_configs.get(_terminal_device, {})
	var hostname := str(config.get("hostname", _terminal_device))
	match _terminal_mode:
		"config": _terminal_prompt.text = "%s(config)# " % hostname
		"interface": _terminal_prompt.text = "%s(config-if)# " % hostname
		"vlan": _terminal_prompt.text = "%s(config-vlan)# " % hostname
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


## Categories d'equipement assez compactes/plates pour etre rackees proprement.
## Serveurs, NAS, PC etc sont trop hauts et donnent un rendu illisible une fois
## empiles a quelques centimetres d'ecart - ils se posent au sol comme d'habitude.
const RACKABLE_CATEGORIES := ["router", "switch", "switch_l3", "wireless_router", "firewall", "access_point"]


func _place_device() -> void:
	if _catalog.is_empty():
		return
	var entry := _catalog[_selected_index]
	var category: String = entry["id"]
	var count: int = _type_counters.get(category, 0) + 1
	var dev_name := "%s%d" % [_name_prefix(category), count]

	var pos: Vector3
	var world_yaw: float
	var supported := false
	var rack_name := "" if category == "rack" else _raycast_rack_target()
	if not rack_name.is_empty() and category not in RACKABLE_CATEGORIES:
		_flash_feedback("Seul le matériel réseau compact se racke (routeur, switch, AP, firewall...)")
		return
	if not rack_name.is_empty():
		var slot = _next_rack_slot(rack_name)
		if slot == null:
			_flash_feedback("Baie pleine : vise une autre baie ou pose au sol")
			return
		pos = slot["position"]
		world_yaw = slot["yaw"]
	else:
		var forward := -_player.global_transform.basis.z
		pos = _player.global_position + forward * 2.5
		match category:
			"pc", "nas", "server": pos.y = 0.41
			"client_laptop": pos.y = 0.12
			"table": pos.y = 0.0
			"rack": pos.y = 0.95
			_: pos.y = 0.825
		# Use the actual hit surface for tabletop placement; keep the journal replayable.
		if category not in ["rack", "table"]:
			var camera: Camera3D = _player.get_node("Camera3D")
			var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position-camera.global_basis.z*4.0)
			query.exclude = [_player.get_rid()]
			var surface := get_world_3d().direct_space_state.intersect_ray(query)
			if not surface.is_empty() and surface.normal.y > 0.8 and surface.position.y > 0.3:
				var surface_category: String = surface.collider.get_meta("category", "")
				if not surface.collider.has_meta("device_name") or surface_category == "table":
					var dims: Vector3 = _equipment_art.dimensions(category)
					var origin: Vector3 = _equipment_art.offset(category, false)
					pos = surface.position + Vector3(0, dims.y/2-origin.y+0.003, 0)
					supported = true

		var toward_player := _player.global_position - pos
		world_yaw = atan2(toward_player.x, toward_player.z)

	var event := {
		"type": "place_device",
		"name": dev_name,
		"model": entry["model"],
		"category": category,
		"world_pos": [pos.x, pos.y, pos.z],
		"world_yaw": world_yaw,
		"supported": supported,
	}
	_apply_event_visual(event)
	GameState.record(event)
	if not rack_name.is_empty():
		_flash_feedback("%s racke dans %s" % [dev_name, rack_name])
	print("[game] pose %s (%s)" % [dev_name, entry["label"]])


## Retourne le nom de la baie visee (dans la portee du cablage), ou "".
func _raycast_rack_target() -> String:
	var hit := _raycast_target()
	var target: String = hit.get("device", "")
	if target.is_empty() or _device_categories.get(target, "") != "rack":
		return ""
	return target


## Prochain emplacement libre dans une baie (6 U), ou null si pleine.
func _next_rack_slot(rack_name: String):
	if not _racks.has(rack_name):
		return null
	var rack: Dictionary = _racks[rack_name]
	var count: int = int(rack.get("count", 0))
	if count >= 6:
		return null
	var local_y := -0.75 + count * (5.0 * 0.04445)
	var rack_pos: Vector3 = rack["position"]
	return {"position": rack_pos + Vector3(0, local_y, 0), "yaw": rack["yaw"]}


## Retourne le nom de la baie dans le volume de laquelle se trouve pos, ou "".
## Pure (aucune mutation) - utilise a la fois pour decider si un equipement
## doit s'afficher en mode compact et pour incrementer l'occupation de la baie.
func _find_containing_rack(pos: Vector3) -> String:
	for rack_name in _racks:
		var rack: Dictionary = _racks[rack_name]
		var rack_pos: Vector3 = rack["position"]
		if absf(pos.x - rack_pos.x) < 0.15 and absf(pos.z - rack_pos.z) < 0.15 \
				and pos.y > rack_pos.y - 1.0 and pos.y < rack_pos.y + 1.0:
			return rack_name
	return ""


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
		"client_laptop": return "GameLap"
		"rack": return "GameRack"
		"table": return "GameTable"
		_: return "GameDev"


## Viser un port + clic = debut du cable ; viser un 2e port + clic = branchement.
## Cliquer sur un port deja occupe (sans cable en cours) = debranchement.
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
		if _cable_start.is_empty():
			_disconnect_link(target, iface)
		else:
			_flash_feedback("%s %s est deja utilise" % [target, iface])
		return

	if _cable_start.is_empty():
		_cable_start = target
		_cable_start_interface = iface
		if _soundscape != null: _soundscape.play("plug")
		_flash_feedback("Cable : %s %s selectionne, vise un autre port" % [target, iface])
		return

	if target == _cable_start and iface == _cable_start_interface:
		_cable_start = ""
		_cable_start_interface = ""
		_flash_feedback("Branchement annule")
		return

	_create_link(_cable_start, target, _cable_start_interface, iface)
	_cable_start = ""
	_cable_start_interface = ""


## Retire l'equipement vise (touche X) : debranche d'abord tous ses cables,
## puis journalise un remove_device. Les meubles integres au batiment et le
## poste technicien ne sont pas retirables.
func _remove_targeted_device() -> void:
	var hit := _raycast_target()
	var target: String = hit.get("device", "")
	if target.is_empty() or hit.get("technician_laptop", false):
		_flash_feedback("Vise un equipement a retirer")
		return
	if _fixed_network.fixed.has(target):
		_flash_feedback("Équipement fixé au bâtiment : seuls les cordons se retirent.")
		return
	if not _device_categories.has(target):
		return
	if _device_categories.get(target, "") == "rack" and int(_racks.get(target, {}).get("count", 0)) > 0:
		_flash_feedback("Vide d'abord la baie avant de la retirer")
		return
	for link in NetSim.links_from_events(GameState.events):
		if link["dev1"] == target or link["dev2"] == target:
			var unlink := {"type": "remove_link", "dev1": link["dev1"], "iface1": link["iface1"],
				"dev2": link["dev2"], "iface2": link["iface2"]}
			_apply_event_visual(unlink)
			GameState.record(unlink)
	var event := {"type": "remove_device", "name": target}
	_apply_event_visual(event)
	GameState.record(event)
	_flash_feedback("%s retire" % target)


## Debranche le cable relie a (dev, iface) : evenement remove_link journalise.
func _disconnect_link(dev: String, iface: String) -> void:
	for link in NetSim.links_from_events(GameState.events):
		var matches_1: bool = link["dev1"] == dev and link["iface1"] == iface
		var matches_2: bool = link["dev2"] == dev and link["iface2"] == iface
		if matches_1 or matches_2:
			var event := {
				"type": "remove_link",
				"dev1": link["dev1"], "iface1": link["iface1"],
				"dev2": link["dev2"], "iface2": link["iface2"],
			}
			_apply_event_visual(event)
			GameState.record(event)
			_sync_netsim()
			if _soundscape != null: _soundscape.play("plug")
			_flash_feedback("Cable debranche : %s (%s) <-> %s (%s)" % [link["dev1"], link["iface1"], link["dev2"], link["iface2"]])
			return
	_flash_feedback("Aucun cable trouve sur %s %s" % [dev, iface])


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
	if _soundscape != null: _soundscape.play("plug")
	_flash_feedback("Cable : %s (%s) <-> %s (%s)" % [dev1, iface1, dev2, iface2])
	print("[game] cable %s(%s) <-> %s(%s)" % [dev1, iface1, dev2, iface2])


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
		if not collider.get_meta("technician_laptop",false) and not _device_configs.has(str(collider.get_meta("device_name"))): return {}
		return {
			"device": str(collider.get_meta("device_name")),
			"interface": str(collider.get_meta("interface_name", "")),
			"technician_laptop": bool(collider.get_meta("technician_laptop", false)),
		}
	return {}


func _update_inspection_panel() -> void:
	var hit := _raycast_target()
	if _port_focus != null:
		var key: String = str(hit.get("device",""))+"|"+str(hit.get("interface",""))
		_port_focus.visible = _interface_positions.has(key) and not (_paused or _palette_open or _technician_hub_open)
		if _port_focus.visible:
			var pos: Vector3 = _interface_positions[key]
			var direction := _port_direction(pos)
			_port_focus.global_position = pos+direction*0.009
			_port_focus.look_at(_port_focus.global_position+direction, Vector3.UP)
	var device_name: String = hit.get("device", "")
	_update_context_prompt(hit)
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
		if iface != targeted: continue
		var used: bool = iface in _used_interfaces.get(device_name, [])
		var marker: String = ">" if iface == targeted else " "
		var link_state: String = "LIEN" if NetSim.link_protocol_up(device_name, iface) \
			else ("CABLE" if used else "LIBRE")
		var admin_state: String = ""
		if _device_configs.has(device_name):
			var state: Dictionary = _device_configs[device_name]["interfaces"].get(iface, {})
			admin_state = "DOWN" if state.get("shutdown", true) else "UP"
		lines.append("%s %-5s  %-5s  %s" % [marker, iface, link_state, admin_state])
	_inspection_label.text = "\n".join(lines)


## Indication d'action centree en bas d'ecran, selon ce que vise le joueur.
func _update_context_prompt(hit: Dictionary) -> void:
	var device_name: String = hit.get("device", "")
	var iface: String = hit.get("interface", "")
	var text := ""
	if hit.get("technician_laptop", false):
		text = "[T] Poste technicien"
	elif not iface.is_empty():
		var used: bool = iface in _used_interfaces.get(device_name, [])
		if not _cable_start.is_empty():
			if used:
				text = "Port %s occupe" % iface
			elif device_name == _cable_start and iface == _cable_start_interface:
				text = "[Clic] Annuler le branchement"
			else:
				text = "[Clic] Brancher sur %s %s" % [device_name, iface]
		elif used:
			text = "[Clic] Debrancher %s" % iface
		else:
			text = "[Clic] Prendre un cable (%s %s)" % [device_name, iface]
	elif _fixed_network.fixed.has(device_name):
		text = "[T] Informations de raccordement"
	elif not device_name.is_empty():
		var category: String = _device_categories.get(device_name, "")
		if category == "rack" and not _catalog.is_empty() \
				and str(_catalog[_selected_index].get("id", "")) in RACKABLE_CATEGORIES:
			text = "[E] Racker %s ici   [T] Console" % str(_catalog[_selected_index].get("label", ""))
		elif category in ["rack", "table"]:
			text = "%s   [X] Retirer" % device_name
		else:
			text = ("[T] Bureau de %s   [X] Retirer" if category in ["pc","client_laptop"] else "[T] Console de %s   [Clic droit] Vue précise   [X] Retirer") % device_name
	elif not _cable_start.is_empty():
		text = "Cable en main depuis %s %s : vise un port libre" % [_cable_start, _cable_start_interface]
	_context_label.text = text
	_context_label.visible = not text.is_empty()


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
	# Sauvegarde automatique avant de quitter, pour ne jamais perdre la partie.
	if not GameState.save_name.strip_edges().is_empty():
		GameState.save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # souris libre pour le menu
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Outils de dev (capture d'ecran) -------------------------------------------
## Fonctions de mise en scene optionnelles, appelees par nom via la variable
## d'environnement BACKBONE_SCREENSHOT_SETUP avant la capture. Aucun effet en
## jeu normal.

func _dev_rack_demo() -> void:
	var rack_pos := Vector3(0, 0.95, 0)
	_apply_event_visual({
		"type": "place_device", "name": "Rack1", "model": "rack", "category": "rack",
		"world_pos": [rack_pos.x, rack_pos.y, rack_pos.z], "world_yaw": 0.0,
	})
	for category in ["switch", "router", "access_point"]:
		var slot = _next_rack_slot("Rack1")
		var pos: Vector3 = slot["position"]
		_apply_event_visual({
			"type": "place_device", "name": "%s_r" % category, "model": category, "category": category,
			"world_pos": [pos.x, pos.y, pos.z], "world_yaw": 0.0,
		})
	_apply_event_visual({
		"type": "place_device", "name": "Table1", "model": "table", "category": "table",
		"world_pos": [1.8, 0.0, 0.0], "world_yaw": 0.0,
	})
	_apply_event_visual({
		"type": "place_device", "name": "Lap1", "model": "client_laptop", "category": "client_laptop",
		"world_pos": [1.8, 0.75, 0.0], "world_yaw": 0.0,
	})
	_player.global_position = Vector3(0.6, 1.5, 3.2)
	_player.look_at(Vector3(0.6, 1.0, 0.0), Vector3.UP)


func _dev_closeup_equipment() -> void:
	var base := Vector3(0, 0, 0)
	var count := 0
	var first_pos := base
	for entry in _catalog:
		if entry.get("kind", "") != "device" or not entry.get("placeable", true):
			continue
		var category: String = entry["id"]
		var pos := base + Vector3(count * 2.4, 0, 0)
		match category:
			"pc", "nas", "server": pos.y = 0.41
			_: pos.y = 0.825
		if count == 0:
			first_pos = pos
		_apply_event_visual({
			"type": "place_device", "name": "%s_dev" % category,
			"model": entry["model"], "category": category,
			"world_pos": [pos.x, pos.y, pos.z], "world_yaw": 0.0,
		})
		count += 1
	_player.global_position = first_pos + Vector3(0, 0.35, 1.7)
	_player.look_at(first_pos + Vector3(0, 0.15, 0), Vector3.UP)


func _flash_feedback(text: String) -> void:
	_feedback_label.text = text
	var timer := get_tree().create_timer(2.5)
	timer.timeout.connect(func(): _feedback_label.text = "")


func _dev_equipment_review() -> void:
	for entry in [["QA-SW","switch",6.0],["QA-R","router",6.65],["QA-FW","firewall",7.3]]:
		_apply_event_visual({"type":"place_device","name":entry[0],"category":entry[1],"world_pos":[entry[2],1.01 if entry[1] == "client_laptop" else 0.91,-8.5],"world_yaw":0.0,"supported":true})
	for entry in [["QA-PC","pc",4.8],["QA-SRV","server",5.4],["QA-NAS","nas",6.0]]:
		_apply_event_visual({"type":"place_device","name":entry[0],"category":entry[1],"world_pos":[entry[2],0.41,-7.7],"world_yaw":0.0})
	_create_link("QA-SW","QA-R","eth0","eth0")


func _ensure_office_hosts() -> void:
	for event in GameState.events:
		if event.get("type","") == "office_hosts_v1": return
	var known := {}
	for event in GameState.events:
		if event.get("type","") == "place_device": known[event.get("name","")] = true
	for event in _office_hosts:
		if not known.has(event.name): GameState.events.append(event.duplicate(true))
	GameState.events.append({"type":"office_hosts_v1"})



func _execute_terminal_command(command: String) -> void:
	_network_cli._execute_terminal_command(command)

func _record_host_ping_success(source: String, destination: String, hops: int) -> void:
	_network_cli._record_host_ping_success(source,destination,hops)

func _spawn_kenney_prop(sub_path: String, pos: Vector3, yaw := 0.0, scale_mult := 1.0) -> Node3D:
	return _building._spawn_kenney_prop(sub_path, pos, yaw, scale_mult)

func _spawn_kenney_prop_local(parent: Node3D, sub_path: String, pos: Vector3, yaw := 0.0, scale_mult := 1.0) -> Node3D:
	return _building._spawn_kenney_prop_local(parent, sub_path, pos, yaw, scale_mult)

func _build_annex_room(wall_mat: Material, ceiling_mat: Material) -> void:
	_building._build_annex_room(wall_mat, ceiling_mat)

func _build_south_wing(wall_mat: Material, ceiling_mat: Material) -> void:
	_building._build_south_wing(wall_mat, ceiling_mat)

func _add_signage(pos: Vector3, text: String, color: Color, yaw := 0.0) -> void:
	_building._add_signage(pos, text, color, yaw)

func _add_zone_light(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	_building._add_zone_light(pos, color, energy, range_m)

func _build_office_desk(pos: Vector3, yaw: float) -> void:
	_building._build_office_desk(pos, yaw)

func _build_reception_desk(pos: Vector3) -> void:
	_building._build_reception_desk(pos)

func _build_printer_corner(pos: Vector3) -> void:
	_building._build_printer_corner(pos)

func _add_wall_outlet(pos: Vector3, yaw := 0.0) -> void:
	_building._add_wall_outlet(pos, yaw)

func _add_plant(pos: Vector3) -> void:
	_building._add_plant(pos)

func _build_ui() -> void:
	_ui_builder._build_ui()

func _build_palette() -> void:
	_ui_builder._build_palette()

func _build_terminal() -> void:
	_ui_builder._build_terminal()

func _build_technician_hub() -> void:
	_ui_builder._build_technician_hub()

func _build_objectives_panel() -> void:
	_ui_builder._build_objectives_panel()

func _build_pause_menu() -> void:
	_ui_builder._build_pause_menu()
