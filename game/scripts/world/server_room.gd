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
	"ip dhcp pool",
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
	_build_held_item()

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

	# Reconstruit immediatement les visuels 3D depuis la sauvegarde (sans PT).
	_rebuild_visuals_from_save()
	# Le modele reseau logique suit chaque evenement enregistre.
	GameState.event_recorded.connect(func(_event): _sync_netsim())
	_sync_netsim()
	# Rattrape les objectifs eventuellement ajoutes au catalogue depuis la sauvegarde.
	Objectives.evaluate()
	_refresh_objectives_panel()

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
		_run_selftest.call_deferred()


func _run_selftest() -> void:
	var failures: Array[String] = []
	var check := func(name: String, condition: bool) -> void:
		print(("  ok   " if condition else "  FAIL ") + name)
		if not condition: failures.append(name)

	# Deux PC cables sur le switch de depart SW-CORE.
	for setup in [["PC-A", 4.0], ["PC-B", 5.2]]:
		_apply_event_visual({"type": "place_device", "name": setup[0], "model": "desktop",
			"category": "pc", "world_pos": [setup[1], 0.41, -2.0], "world_yaw": 0.0})
	GameState.record({"type": "add_link", "dev1": "PC-A", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth0", "cable": "rj45"})
	GameState.record({"type": "add_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1", "cable": "rj45"})
	_sync_netsim()
	check.call("liens proto up (defauts switch/pc)", NetSim.link_protocol_up("PC-A", "eth0") and NetSim.link_protocol_up("PC-B", "eth0"))

	# Configuration IP des PC via la vraie couche terminal.
	for setup in [["PC-A", "10.0.0.1"], ["PC-B", "10.0.0.2"]]:
		_open_terminal(setup[0])
		for cmd in ["configure terminal", "interface eth0", "ip address %s 255.255.255.0" % setup[1], "no shutdown", "end"]:
			_execute_terminal_command(cmd)
		_close_terminal()
	check.call("ip configuree via terminal", NetSim.ip_configured("PC-A", "eth0"))
	check.call("ping PC-A -> PC-B", NetSim.can_reach("PC-A", "10.0.0.2"))

	# Isolation VLAN via le terminal du switch.
	_open_terminal("SW-CORE")
	for cmd in ["configure terminal", "vlan 10", "exit", "interface eth0", "switchport access vlan 10", "end"]:
		_execute_terminal_command(cmd)
	_close_terminal()
	check.call("vlan 10 existe", NetSim.vlan_exists("SW-CORE", 10))
	check.call("vlan isole le ping", not NetSim.can_reach("PC-A", "10.0.0.2"))

	# Retour au meme VLAN puis debranchement physique.
	_open_terminal("SW-CORE")
	for cmd in ["configure terminal", "interface eth1", "switchport access vlan 10", "end"]:
		_execute_terminal_command(cmd)
	_close_terminal()
	check.call("meme vlan retablit le ping", NetSim.can_reach("PC-A", "10.0.0.2"))
	_disconnect_link("PC-B", "eth0")
	check.call("debranchement coupe le ping", not NetSim.can_reach("PC-A", "10.0.0.2"))
	check.call("port libere apres debranchement", not ("eth0" in _used_interfaces.get("PC-B", [])))

	# Ping via la commande terminal (journalise ping_ok pour les objectifs).
	GameState.record({"type": "add_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1", "cable": "rj45"})
	_sync_netsim()
	_open_terminal("PC-A")
	_execute_terminal_command("ping 10.0.0.2")
	_close_terminal()
	var has_ping_event := false
	for event in GameState.events:
		if event.get("type", "") == "ping_ok": has_ping_event = true
	check.call("ping_ok journalise", has_ping_event)
	check.call("objectif premier ping accompli", Objectives.is_completed("first_ping"))

	# Retrait d'equipement : liens debranches, config purgee, replay coherent.
	var pcb_body: Node3D = _device_bodies.get("PC-B")
	_apply_event_visual({"type": "remove_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1"})
	GameState.record({"type": "remove_link", "dev1": "PC-B", "iface1": "eth0", "dev2": "SW-CORE", "iface2": "eth1"})
	_apply_event_visual({"type": "remove_device", "name": "PC-B"})
	GameState.record({"type": "remove_device", "name": "PC-B"})
	check.call("equipement retire du modele", not NetSim.device_exists("PC-B"))
	check.call("corps 3d supprime", pcb_body == null or pcb_body.is_queued_for_deletion())
	check.call("port du switch libere", not ("eth1" in _used_interfaces.get("SW-CORE", [])))

	print("SELFTEST %s (%d checks)" % ["PASSED" if failures.is_empty() else "FAILED", 13])
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_dev_screenshot(path: String) -> void:
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
	# Mur sud perce d'une porte vers le couloir de l'aile bureaux.
	_add_box(Vector3(-5.6, 1.5, 10), Vector3(8.8, 3, 0.2), wall_mat)
	_add_box(Vector3(5.6, 1.5, 10), Vector3(8.8, 3, 0.2), wall_mat)
	_add_signage(Vector3(0, 2.55, 10.15), "SALLE SERVEUR", Color("7dd8ff"))
	# Mur est perce d'une porte (2 segments) vers l'annexe pause/bureau.
	_add_box(Vector3(10, 1.5, -5.75), Vector3(0.2, 3, 8.5), wall_mat)
	_add_box(Vector3(10, 1.5, 5.75), Vector3(0.2, 3, 8.5), wall_mat)
	_add_box(Vector3(-10, 1.5, 0), Vector3(0.2, 3, 20), wall_mat)   # mur ouest
	_add_visual_box(Vector3(0, 3.05, 0), Vector3(20, 0.1, 20), ceiling_mat)

	_build_annex_room(wall_mat, ceiling_mat)
	_build_south_wing(wall_mat, ceiling_mat)

	# Dalles et joints du faux plancher.
	var grid_mat := _material(Color("3a464b"), 0.75, 0.25)
	for x in range(-10, 11, 2):
		_add_visual_box(Vector3(x, 0.012, 0), Vector3(0.025, 0.015, 20), grid_mat)
	for z in range(-10, 11, 2):
		_add_visual_box(Vector3(0, 0.013, z), Vector3(20, 0.015, 0.025), grid_mat)

	# Luminaires industriels au plafond.
	for x in [-6.0, 0.0, 6.0]:
		for z in [-6.0, 0.0, 6.0]:
			var lamp_mat := _material(Color("d8f5ff"), 0.2, 0.0, false, Color("b8ecff"), 3.0)
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


const KENNEY_ASSETS := "res://assets/kenney/"

## Instancie un modele Kenney (CC0, kenney.nl) enfant de la salle, a la position
## donnee. sub_path est relatif a assets/kenney/ (ex: "furniture/table.glb").
## Retourne null si le fichier est absent (pas d'assets telecharges) pour que
## les appelants puissent se rabattre sur une geometrie codee en secours.
func _spawn_kenney_prop(sub_path: String, pos: Vector3, yaw := 0.0, scale_mult := 1.0) -> Node3D:
	var instance := _load_kenney_prop(sub_path, scale_mult)
	if instance == null:
		return null
	add_child(instance)
	instance.position = pos
	instance.rotation.y = yaw
	return instance


## Comme _spawn_kenney_prop mais l'instance est enfant de parent (ex: le corps
## d'un equipement), pour qu'elle suive sa position/rotation/selection.
func _spawn_kenney_prop_local(parent: Node3D, sub_path: String, pos: Vector3, yaw := 0.0, scale_mult := 1.0) -> Node3D:
	var instance := _load_kenney_prop(sub_path, scale_mult)
	if instance == null:
		return null
	parent.add_child(instance)
	instance.position = pos
	instance.rotation.y = yaw
	return instance


func _load_kenney_prop(sub_path: String, scale_mult: float) -> Node3D:
	var path := KENNEY_ASSETS + sub_path
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var instance := scene.instantiate()
	instance.scale = Vector3.ONE * scale_mult
	return instance


## Petite annexe pause/bureau a l'est de la salle serveur, reliee par la porte
## percee dans le mur est. Casse la sensation de "salle carree unique". Le
## mobilier utilise les modeles Kenney (CC0, kenney.nl/assets/furniture-kit)
## quand disponibles dans assets/kenney/furniture/, sinon des boites codees.
func _build_annex_room(wall_mat: Material, ceiling_mat: Material) -> void:
	var floor_mat := _material(Color("2a2420"), 0.85, 0.05)
	var annex_wall := _material(Color("3d362d"), 0.85, 0.05)
	_add_box(Vector3(14, -0.1, 0), Vector3(8, 0.2, 9), floor_mat)
	_add_box(Vector3(14, 1.5, -4.5), Vector3(8, 3, 0.2), annex_wall)
	_add_box(Vector3(14, 1.5, 4.5), Vector3(8, 3, 0.2), annex_wall)
	_add_box(Vector3(18, 1.5, 0), Vector3(0.2, 3, 9), annex_wall)
	_add_visual_box(Vector3(14, 3.05, 0), Vector3(8, 0.1, 9), ceiling_mat)

	var lamp_mat := _material(Color("ffe3b8"), 0.3, 0.0, false, Color("ffd9a0"), 2.2)
	_add_visual_box(Vector3(14, 2.96, 0), Vector3(1.8, 0.04, 0.4), lamp_mat)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(14, 2.7, 0)
	lamp.light_color = Color("ffe6c2")
	lamp.light_energy = 1.1
	lamp.omni_range = 7.0
	add_child(lamp)

	# Table + chaises + bibliotheque, coin pause. Modeles Kenney si disponibles.
	if _spawn_kenney_prop("furniture/table.glb", Vector3(14, 0, 0)) == null:
		var table_mat := _material(Color("5a4632"), 0.6, 0.1, true)
		_add_box(Vector3(14, 0.38, 0), Vector3(1.1, 0.06, 1.1), table_mat)
		for i in 4:
			var angle := i * PI / 2.0
			var leg_pos := Vector3(14 + cos(angle) * 0.42, 0.19, sin(angle) * 0.42)
			_add_box(leg_pos, Vector3(0.06, 0.38, 0.06), table_mat)
	var chair_a := _spawn_kenney_prop("furniture/chair.glb", Vector3(12.9, 0, 0), PI * 1.5)
	var chair_b := _spawn_kenney_prop("furniture/chair.glb", Vector3(15.1, 0, 0), PI * 0.5)
	if chair_a == null or chair_b == null:
		var seat_mat := _material(Color("4a4038"), 0.7, 0.05)
		if chair_a == null: _add_box(Vector3(12.8, 0.22, 0), Vector3(0.5, 0.44, 1.6), seat_mat)
		if chair_b == null: _add_box(Vector3(15.2, 0.22, 0), Vector3(0.5, 0.44, 1.6), seat_mat)
	if _spawn_kenney_prop("furniture/bookcaseOpen.glb", Vector3(17.7, 0, -3.8), PI) == null:
		var shelf_mat := _material(Color("4a4038"), 0.6, 0.1)
		_add_box(Vector3(17.7, 0.9, -3.8), Vector3(0.4, 1.8, 0.9), shelf_mat)

	var label := Label3D.new()
	label.text = "ESPACE PAUSE"
	label.position = Vector3(14, 2.4, -4.3)
	label.font_size = 30
	label.pixel_size = 0.0035
	label.modulate = Color("f0dfc4")
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


## Aile sud du batiment : couloir, open-space bureaux, accueil et local
## technique operateur (arrivee WAN). Chaque zone est construite par une
## fonction dediee avec des coordonnees regroupees, pour rester facilement
## deplacable / modifiable par un futur developpeur de scenarios.
func _build_south_wing(wall_mat: Material, ceiling_mat: Material) -> void:
	var corridor_floor := _material(Color("262c31"), 0.8, 0.1)
	var office_floor := _material(Color("3f4440"), 0.9, 0.0)
	var closet_floor := _material(Color("2b2926"), 0.9, 0.0)

	# --- Couloir (x -10..10, z 10..13.6) ---
	_add_box(Vector3(0, -0.1, 11.8), Vector3(20, 0.2, 3.6), corridor_floor)
	_add_visual_box(Vector3(0, 3.05, 11.8), Vector3(20, 0.1, 3.6), ceiling_mat)
	# Mur sud du couloir : ouvertures vers bureaux (x -5.2..-2.8) et accueil (x 3..8).
	_add_box(Vector3(-7.6, 1.5, 13.6), Vector3(4.8, 3, 0.2), wall_mat)
	_add_box(Vector3(0.1, 1.5, 13.6), Vector3(5.8, 3, 0.2), wall_mat)
	_add_box(Vector3(9.0, 1.5, 13.6), Vector3(2.0, 3, 0.2), wall_mat)
	_add_zone_light(Vector3(-5, 2.75, 11.8), Color("fff1dc"), 1.8, 8.0)
	_add_zone_light(Vector3(5, 2.75, 11.8), Color("fff1dc"), 1.8, 8.0)
	_add_zone_light(Vector3(0, 2.75, 11.8), Color("fff1dc"), 1.6, 7.0)
	_add_signage(Vector3(-4, 2.5, 13.45), "BUREAUX", Color("e8e2d0"), PI)
	_add_signage(Vector3(5.5, 2.5, 13.45), "ACCUEIL", Color("e8e2d0"), PI)

	# --- Open-space bureaux (x -10..3, z 13.6..21.2) ---
	_add_box(Vector3(-3.5, -0.1, 17.4), Vector3(13, 0.2, 7.6), office_floor)
	_add_visual_box(Vector3(-3.5, 3.05, 17.4), Vector3(13, 0.1, 7.6), ceiling_mat)
	_add_box(Vector3(3, 1.5, 17.4), Vector3(0.2, 3, 7.6), wall_mat)  # cloison accueil
	_add_zone_light(Vector3(-6, 2.75, 17.4), Color("f4f8ff"), 1.8, 8.0)
	_add_zone_light(Vector3(-1, 2.75, 17.4), Color("f4f8ff"), 1.8, 8.0)
	for desk_x in [-7.5, -4.5]:
		_build_office_desk(Vector3(desk_x, 0, 16.2), 0.0)
		_build_office_desk(Vector3(desk_x, 0, 19.2), PI)
	for outlet_x in [-8.0, -6.0, -3.0, 0.0]:
		_add_wall_outlet(Vector3(outlet_x, 0.35, 13.72))
	_add_plant(Vector3(1.8, 0, 20.2))
	_build_printer_corner(Vector3(-9.2, 0, 20.3))

	# --- Accueil (x 3..10, z 13.6..21.2) ---
	_add_box(Vector3(6.5, -0.1, 17.4), Vector3(7, 0.2, 7.6), office_floor)
	_add_visual_box(Vector3(6.5, 3.05, 17.4), Vector3(7, 0.1, 7.6), ceiling_mat)
	_add_zone_light(Vector3(6.5, 2.75, 17.4), Color("ffedd6"), 1.8, 8.0)
	_build_reception_desk(Vector3(5.6, 0, 16.6))
	_add_plant(Vector3(9.2, 0, 14.6))
	_add_signage(Vector3(6.5, 2.3, 20.9), "BACKBONE CORP", Color("7dd8ff"), PI)
	# Porte d'entree (decor) sur le mur sud.
	var door_mat := _material(Color("1b2226"), 0.4, 0.4)
	_add_visual_box(Vector3(7.5, 1.25, 21.08), Vector3(2.2, 2.5, 0.08), door_mat)
	_add_signage(Vector3(7.5, 2.62, 21.0), "ENTREE", Color("9adf9a"), PI)

	# --- Murs exterieurs de l'aile ---
	_add_box(Vector3(0, 1.5, 21.2), Vector3(20, 3, 0.2), wall_mat)              # sud
	_add_box(Vector3(10, 1.5, 15.6), Vector3(0.2, 3, 11.2), wall_mat)           # est
	_add_box(Vector3(-10, 1.5, 10.5), Vector3(0.2, 3, 1.0), wall_mat)           # ouest (haut)
	_add_box(Vector3(-10, 1.5, 17.3), Vector3(0.2, 3, 7.8), wall_mat)           # ouest (bas)

	# --- Local technique / arrivee WAN (x -14.4..-10, z 10..14) ---
	_add_box(Vector3(-12.2, -0.1, 12), Vector3(4.4, 0.2, 4), closet_floor)
	_add_visual_box(Vector3(-12.2, 3.05, 12), Vector3(4.4, 0.1, 4), ceiling_mat)
	_add_box(Vector3(-14.4, 1.5, 12), Vector3(0.2, 3, 4), wall_mat)
	_add_box(Vector3(-12.2, 1.5, 10), Vector3(4.4, 3, 0.2), wall_mat)
	_add_box(Vector3(-12.2, 1.5, 14), Vector3(4.4, 3, 0.2), wall_mat)
	_add_zone_light(Vector3(-12.2, 2.7, 12), Color("dceaf2"), 1.5, 6.0)
	_add_signage(Vector3(-9.85, 2.5, 12), "LOCAL TECHNIQUE", Color("ffd166"), PI / 2.0)
	# Boitier operateur + conduits (decor : le point d'entree WAN du batiment).
	var box_mat := _material(Color("4a5258"), 0.5, 0.3, true)
	_add_visual_box(Vector3(-14.2, 1.4, 12), Vector3(0.3, 0.9, 0.7), box_mat)
	_add_signage(Vector3(-14.0, 2.05, 12), "ARRIVEE OPERATEUR (WAN)", Color("9adf9a"), PI / 2.0)
	var conduit := _material(Color("35434a"), 0.35, 0.65)
	_add_visual_box(Vector3(-14.25, 2.5, 12), Vector3(0.12, 1.3, 0.12), conduit)
	_add_visual_box(Vector3(-12.2, 2.88, 12), Vector3(4.2, 0.1, 0.14), conduit)


## Panneau de signalisation mural (texte fixe oriente, pas de billboard).
func _add_signage(pos: Vector3, text: String, color: Color, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.rotation.y = yaw
	label.font_size = 40
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 4
	label.double_sided = false
	add_child(label)


func _add_zone_light(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var lamp_mat := _material(Color("f5efe2"), 0.3, 0.0, false, color, 2.0)
	_add_visual_box(Vector3(pos.x, 2.96, pos.z), Vector3(1.6, 0.04, 0.4), lamp_mat)
	var lamp := OmniLight3D.new()
	lamp.position = pos
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = range_m
	add_child(lamp)


## Bureau d'open-space (decor) : plateau, pietement, ecran et chaise Kenney.
func _build_office_desk(pos: Vector3, yaw: float) -> void:
	var desk := StaticBody3D.new()
	desk.position = pos
	desk.rotation.y = yaw
	add_child(desk)
	var top_mat := _material(Color("6a6156"), 0.6, 0.1, true)
	var leg_mat := _material(Color("2c3134"), 0.4, 0.5)
	_add_local_box(desk, Vector3(0, 0.74, 0), Vector3(1.6, 0.06, 0.8), top_mat)
	for x in [-0.72, 0.72]:
		_add_local_box(desk, Vector3(x, 0.37, 0), Vector3(0.06, 0.74, 0.7), leg_mat)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 0.8, 0.8)
	col.shape = shape
	col.position = Vector3(0, 0.4, 0)
	desk.add_child(col)
	# Moniteur + clavier (decor).
	var screen_mat := _material(Color("10222c"), 0.3, 0.0, false, Color("1a5a7a"), 1.2)
	_add_local_box(desk, Vector3(0, 1.02, -0.2), Vector3(0.55, 0.34, 0.03), _material(Color("14181b"), 0.4, 0.4))
	_add_local_box(desk, Vector3(0, 1.02, -0.185), Vector3(0.5, 0.29, 0.012), screen_mat)
	_add_local_box(desk, Vector3(0, 0.79, -0.2), Vector3(0.06, 0.04, 0.06), leg_mat)
	_add_local_box(desk, Vector3(0, 0.78, 0.1), Vector3(0.42, 0.02, 0.14), leg_mat)
	if _spawn_kenney_prop("furniture/chair.glb", pos + Vector3(0, 0, 0.7).rotated(Vector3.UP, yaw), yaw + PI) == null:
		pass


func _build_reception_desk(pos: Vector3) -> void:
	var counter := _material(Color("4d5a63"), 0.5, 0.2, true)
	var front := _material(Color("22303a"), 0.6, 0.1)
	_add_box(pos + Vector3(0, 0.55, 0), Vector3(2.4, 1.1, 0.5), front)
	_add_visual_box(pos + Vector3(0, 1.12, 0), Vector3(2.6, 0.05, 0.7), counter)
	_add_box(pos + Vector3(1.45, 0.55, 0.85), Vector3(0.5, 1.1, 1.6), front)
	_add_visual_box(pos + Vector3(1.45, 1.12, 0.85), Vector3(0.7, 0.05, 1.8), counter)


## Coin reprographie (decor) : meuble bas + imprimante multifonction.
func _build_printer_corner(pos: Vector3) -> void:
	var cabinet := _material(Color("50565a"), 0.6, 0.15, true)
	_add_box(pos + Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.6), cabinet)
	var shell := _material(Color("d8dce0"), 0.5, 0.05, true)
	var dark := _material(Color("2a2f33"), 0.5, 0.2)
	_add_visual_box(pos + Vector3(0, 0.86, 0), Vector3(0.62, 0.32, 0.5), shell)
	_add_visual_box(pos + Vector3(0, 1.045, 0), Vector3(0.5, 0.05, 0.42), dark)
	_add_visual_box(pos + Vector3(0, 0.78, 0.26), Vector3(0.4, 0.06, 0.1), dark)
	var led := _material(Color("113322"), 0.4, 0.0, false, Color("2fdd7a"), 1.4)
	_add_visual_box(pos + Vector3(0.22, 0.95, 0.251), Vector3(0.02, 0.02, 0.01), led)
	_add_signage(pos + Vector3(0, 1.35, 0.1), "IMPRIMANTE", Color("9aabba"), PI)


func _add_wall_outlet(pos: Vector3) -> void:
	var plate := _material(Color("d8dde0"), 0.5, 0.05)
	_add_visual_box(pos, Vector3(0.16, 0.1, 0.03), plate)
	var hole := _material(Color("1a1e21"), 0.5)
	_add_visual_box(pos + Vector3(-0.035, 0, 0.014), Vector3(0.045, 0.04, 0.01), hole)
	_add_visual_box(pos + Vector3(0.035, 0, 0.014), Vector3(0.045, 0.04, 0.01), hole)


func _add_plant(pos: Vector3) -> void:
	var pot := MeshInstance3D.new()
	var pot_mesh := CylinderMesh.new()
	pot_mesh.height = 0.35
	pot_mesh.top_radius = 0.22
	pot_mesh.bottom_radius = 0.17
	pot_mesh.material = _material(Color("5a4a3a"), 0.7)
	pot.mesh = pot_mesh
	pot.position = pos + Vector3(0, 0.175, 0)
	add_child(pot)
	var leaves := MeshInstance3D.new()
	var leaves_mesh := SphereMesh.new()
	leaves_mesh.radius = 0.38
	leaves_mesh.height = 0.85
	leaves_mesh.material = _material(Color("3f6f3f"), 0.85)
	leaves.mesh = leaves_mesh
	leaves.position = pos + Vector3(0, 0.75, 0)
	add_child(leaves)


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
	laptop.position = Vector3(0, 0.9, -7.15)
	laptop.set_meta("technician_laptop", true)
	laptop.set_meta("device_name", "TECH-LAPTOP")
	add_child(laptop)
	var laptop_mat := _material(Color("2c363d"), 0.3, 0.7)
	_add_local_box(laptop, Vector3(0, 0, 0.18), Vector3(0.78, 0.055, 0.52), laptop_mat)
	_add_local_box(laptop, Vector3(0, 0.31, -0.05), Vector3(0.78, 0.58, 0.055), laptop_mat)
	var screen_mat := _material(Color("102b3a"), 0.25, 0.0, false, Color("17638a"), 1.8)
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

	# Indication contextuelle discrete, centree au-dessus du reticule.
	_context_label = Label.new()
	_context_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_context_label.position = Vector2(-260, -140)
	_context_label.custom_minimum_size = Vector2(520, 0)
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_label.add_theme_font_size_override("font_size", 15)
	_context_label.add_theme_color_override("font_color", Color("cfeaff"))
	_context_label.add_theme_constant_override("outline_size", 4)
	_context_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_context_label.visible = false
	layer.add_child(_context_label)

	add_child(layer)
	_update_help_text()


## Applique les reglages qui concernent la scene 3D : echelle de rendu du
## viewport et visibilite de l'aide a l'ecran (parametre "show_help_overlay").
func _on_settings_changed() -> void:
	GameState.apply_render_scale(get_viewport())
	if _help_label != null:
		_help_label.visible = bool(GameState.settings.get("show_help_overlay", true))


func _update_help_text() -> void:
	var selected := "?"
	if not _catalog.is_empty():
		selected = _catalog[_selected_index]["label"]
	_help_label.visible = bool(GameState.settings.get("show_help_overlay", true))
	_help_label.text = (
		"ZQSD deplacer   |   Souris regarder   |   Tab materiel (%s)   |   E poser\n"
		+ "Clic sur port cabler / debrancher   |   T console   |   X retirer   |   Echap pause"
	) % selected


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


func _update_held_item() -> void:
	if _held_root == null:
		return
	for child in _held_root.get_children():
		child.queue_free()
	if _catalog.is_empty():
		return
	var category: String = _catalog[_selected_index].get("id", "router")
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 0.3
	_held_root.add_child(holder)
	_build_held_model(holder, category)


## Maquette simplifiee (sans ports ni etiquette) qui evoque le modele reel.
func _build_held_model(holder: Node3D, category: String) -> void:
	match category:
		"switch", "switch_l3":
			_add_local_box(holder, Vector3.ZERO, Vector3(1.7, 0.15, 0.56), _material(Color("32393d"), 0.55, 0.15))
			_add_local_box(holder, Vector3(0, -0.015, 0.285), Vector3(1.6, 0.09, 0.05), _material(Color("111417"), 0.5, 0.2))
		"pc":
			_add_local_box(holder, Vector3.ZERO, Vector3(0.46, 0.82, 0.52), _material(Color("414b53"), 0.55, 0.15))
			_add_local_box(holder, Vector3(0, 0, 0.266), Vector3(0.38, 0.72, 0.025), _material(Color("161d21"), 0.55, 0.35))
		"nas", "server":
			_add_local_box(holder, Vector3.ZERO, Vector3(0.52, 0.82, 0.62), _material(Color("38464e"), 0.5, 0.18))
			for y in [-0.23, -0.08, 0.07, 0.22]:
				_add_local_box(holder, Vector3(0, y, 0.316), Vector3(0.34, 0.09, 0.018), _material(Color("38464e"), 0.5, 0.18))
		"access_point":
			var puck := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.height = 0.12
			cyl.top_radius = 0.36
			cyl.bottom_radius = 0.38
			cyl.material = _material(Color("d7e1e5"), 0.55, 0.08)
			puck.mesh = cyl
			holder.add_child(puck)
		"client_laptop":
			_add_local_box(holder, Vector3(0, -0.16, 0.05), Vector3(0.42, 0.03, 0.3), _material(Color("3a444b"), 0.5, 0.2))
			var screen := _add_local_box(holder, Vector3(0, 0.06, -0.1), Vector3(0.42, 0.28, 0.02), _material(Color("3a444b"), 0.5, 0.2))
			screen.rotation.x = deg_to_rad(-12)
		"rack":
			for x in [-0.28, 0.28]:
				for z in [-0.31, 0.31]:
					_add_local_box(holder, Vector3(x, 0, z), Vector3(0.045, 1.9, 0.045), _material(Color("2b3438"), 0.6, 0.3))
		"table":
			_add_local_box(holder, Vector3(0, 0.75, 0), Vector3(1.6, 0.06, 0.9), _material(Color("56636a"), 0.55, 0.32))
		"firewall":
			_add_local_box(holder, Vector3.ZERO, Vector3(0.85, 0.32, 0.56), _material(Color("2a5fa5"), 0.45, 0.1))
			_add_local_box(holder, Vector3(0.15, -0.02, 0.285), Vector3(0.5, 0.16, 0.02), _material(Color("13223a"), 0.4, 0.15))
		_:
			# routeur / wireless_router
			_add_local_box(holder, Vector3.ZERO, Vector3(1.4, 0.16, 0.62), _material(Color("5b6a73"), 0.5, 0.15))
			_add_local_box(holder, Vector3(0, -0.025, 0.325), Vector3(1.3, 0.09, 0.05), _material(Color("1c252b"), 0.55, 0.1))
			for x in [-0.5, 0.5]:
				var antenna := MeshInstance3D.new()
				var rod := CylinderMesh.new()
				rod.height = 0.42
				rod.top_radius = 0.013
				rod.bottom_radius = 0.02
				rod.material = _material(Color("1c252b"), 0.55, 0.1)
				antenna.mesh = rod
				antenna.position = Vector3(x, 0.29, -0.2)
				antenna.rotation.x = deg_to_rad(-18)
				holder.add_child(antenna)


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
			_update_held_item()
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
			_hub_content.text = "[font_size=26]MESSAGERIE[/font_size]\n\n[color=#8fd8ff]NOC Central[/color]  •  Nouveau job disponible\nConfigure le réseau du nouveau site avant 18h.\n\n[color=#8fd8ff]Logistique[/color]  •  Inventaire initial\nTout le matériel est débloqué pendant l'alpha.\n\n[color=#8fd8ff]Sécurité[/color]  •  Rappel\nPense à fermer les ports inutilisés."
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
			_hub_content.text = ("[font_size=28]BONSOIR, TECHNICIEN[/font_size]\n\n"
				+ "[color=#7fdbff]Equipements deployes[/color]   %d\n" % device_count
				+ "[color=#7fdbff]Cables poses[/color]           %d\n" % links.size()
				+ "[color=#7fdbff]Liens actifs[/color]           %d\n" % links_up
				+ "[color=#7fdbff]Machines adressees[/color]     %d\n" % configured
				+ "[color=#7fdbff]Objectifs[/color]              %d / %d\n" % [done_count, total_count]
				+ "[color=#7fdbff]Score[/color]                  %d\n" % GameState.score
				+ "[color=#7fdbff]Solde[/color]                  ◈ %d B-Coins\n" % GameState.bcoins
				+ "\n[font_size=20]RAPPEL[/font_size]\nUn lien n'est actif que si le cable est branche et les deux interfaces sont up (no shutdown).")


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
			var yaw := float(event.get("world_yaw", 0.0))
			var containing_rack := "" if category == "rack" else _find_containing_rack(pos)
			_spawn_device_mesh(pos, device_name, category, yaw, not containing_rack.is_empty())
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
func _spawn_device_mesh(pos: Vector3, device_name: String, category: String, yaw := 0.0, compact := false) -> void:
	var body := StaticBody3D.new()
	body.name = device_name if not device_name.is_empty() else "Device"
	body.set_meta("device_name", device_name)
	body.set_meta("category", category)
	add_child(body)
	body.global_position = pos
	body.rotation.y = yaw
	_device_bodies[device_name] = body

	var size := Vector3(1.4, 0.16, 0.62)
	var collision_offset := Vector3.ZERO
	match category:
		"switch", "switch_l3": size = Vector3(1.7, 0.15, 0.56)
		"firewall": size = Vector3(0.85, 0.32, 0.56)
		"pc", "nas", "server": size = Vector3(0.46, 0.82, 0.52)
		"client_laptop": size = Vector3(0.5, 0.45, 0.4)
		"wireless_router": size = Vector3(1.0, 0.8, 0.6)
		"access_point": size = Vector3(0.75, 0.6, 0.75)
		"rack": size = Vector3(0.62, 1.9, 0.68)
		"table":
			size = Vector3(1.6, 0.8, 0.9)
			collision_offset = Vector3(0, 0.4, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = collision_offset
	body.add_child(col)

	match category:
		"switch", "switch_l3": _build_switch_model(body, device_name, compact)
		"firewall": _build_firewall_model(body, device_name, compact)
		"pc": _build_pc_model(body, device_name)
		"client_laptop": _build_client_laptop_model(body, device_name)
		"nas", "server": _build_server_model(body, device_name, category)
		"wireless_router": _build_wireless_router_model(body, device_name, compact)
		"access_point": _build_access_point_model(body, device_name, compact)
		"rack": _build_rack_model(body, device_name)
		"table": _build_table_model(body, device_name)
		_: _build_router_model(body, device_name, compact)
	if category not in ["pc", "nas", "server", "client_laptop", "rack", "table"] and not compact:
		_build_equipment_cart(body)
	_add_device_ports(body, device_name, category, compact)


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
	label.position = pos
	label.font_size = 14 if compact else 36
	label.pixel_size = 0.0014 if compact else 0.0042
	label.modulate = Color("e8f7ff")
	label.outline_size = 3
	label.no_depth_test = not compact
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


## Rangee de LEDs d'etat clignotantes (visuel), signature classique du materiel
## reseau reel. n LEDs espacees le long de x, sur la face avant en z.
func _add_led_strip(body: Node3D, n: int, center_x: float, spread: float, y: float, z: float) -> void:
	var colors := [Color("3ddc6a"), Color("3ddc6a"), Color("ffcf4a"), Color("3ddc6a")]
	for i in n:
		var x := center_x + (i - (n - 1) / 2.0) * (spread / maxf(n - 1, 1))
		var led := _material(Color("111"), 0.3, 0.0, false, colors[i % colors.size()], 1.6)
		_add_local_box(body, Vector3(x, y, z), Vector3(0.02, 0.02, 0.008), led)


## Oreilles de montage rack 19", pour l'air "materiel 1U" meme pose au sol.
func _add_rack_ears(body: Node3D, half_width: float, mat: Material) -> void:
	for x in [-half_width - 0.03, half_width + 0.03]:
		_add_local_box(body, Vector3(x, 0, 0.24), Vector3(0.05, 0.22, 0.03), mat)


## Boitier plat type Cisco 88x : coque fine + panneau de ports en legere
## saillie sur le bas de la face avant (comme un routeur d'entree de gamme
## reel). Proportions et disposition inspirees de photos de reference.
func _build_router_model(body: Node3D, device_name: String, compact := false) -> void:
	var shell := _material(Color("5b6a73"), 0.5, 0.15, true)
	var panel := _material(Color("1c252b"), 0.55, 0.1)
	_add_local_box(body, Vector3.ZERO, Vector3(1.4, 0.16, 0.62), shell)
	# Panneau de ports : bande plus etroite, en leger surplomb sur le bas de la face avant.
	_add_local_box(body, Vector3(0, -0.025, 0.325), Vector3(1.3, 0.09, 0.05), panel)
	if not compact:
		_add_rack_ears(body, 0.7, shell)
	_add_led_strip(body, 4, -0.5, 0.24, 0.045, 0.316)
	if not compact:
		for x in [-0.5, 0.5]:
			var antenna := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.height = 0.42
			cylinder.top_radius = 0.013
			cylinder.bottom_radius = 0.02
			cylinder.material = panel
			antenna.mesh = cylinder
			antenna.position = Vector3(x, 0.29, -0.2)
			antenna.rotation.x = deg_to_rad(-18)
			body.add_child(antenna)
	_add_device_label(body, device_name, Vector3(0, 0.16, 0.02), compact)


## Switch rackable type Cisco/Netgear 24 ports : coque noire large et plate,
## grille de ventilation laterale, 2 rangees de ports.
func _build_switch_model(body: Node3D, device_name: String, compact := false) -> void:
	var shell := _material(Color("32393d"), 0.55, 0.15, true)
	var panel := _material(Color("111417"), 0.5, 0.2)
	_add_local_box(body, Vector3.ZERO, Vector3(1.7, 0.15, 0.56), shell)
	_add_local_box(body, Vector3(0, -0.015, 0.285), Vector3(1.6, 0.09, 0.05), panel)
	# Grille de ventilation sur le cote gauche (fines lamelles horizontales).
	var vent_mat := _material(Color("0c0f11"), 0.6, 0.1)
	for i in 5:
		_add_local_box(body, Vector3(-0.79, -0.03 + i * 0.022, 0.1), Vector3(0.03, 0.012, 0.42), vent_mat)
	if not compact:
		_add_rack_ears(body, 0.85, shell)
	_add_led_strip(body, 6, 0.35, 0.9, 0.045, 0.278)
	_add_device_label(body, device_name, Vector3(0, 0.15, 0.02), compact)


## Boitier compact type UTM/firewall bureau : plus cube que les autres
## equipements reseau, couleur d'accent bleue, ports groupes d'un cote.
func _build_firewall_model(body: Node3D, device_name: String, compact := false) -> void:
	var shell := _material(Color("2a5fa5"), 0.45, 0.1, true)
	var panel := _material(Color("13223a"), 0.4, 0.15)
	_add_local_box(body, Vector3.ZERO, Vector3(0.85, 0.32, 0.56), shell)
	_add_local_box(body, Vector3(0.15, -0.02, 0.285), Vector3(0.5, 0.16, 0.02), panel)
	var vent_mat := _material(Color("173259"), 0.5, 0.2)
	for i in 6:
		_add_local_box(body, Vector3(0.34, -0.1 + i * 0.035, 0.0), Vector3(0.14, 0.015, 0.4), vent_mat)
	_add_led_strip(body, 2, -0.15, 0.1, 0.03, 0.297)
	_add_device_label(body, device_name, Vector3(0, 0.3, 0.02), compact)


func _build_pc_model(body: Node3D, device_name: String) -> void:
	var shell := _material(Color("414b53"), 0.55, 0.15, true)
	var front := _material(Color("161d21"), 0.55, 0.35)
	_add_local_box(body, Vector3.ZERO, Vector3(0.46, 0.82, 0.52), shell)
	_add_local_box(body, Vector3(0, 0, 0.266), Vector3(0.38, 0.72, 0.025), front)
	var power := _material(Color("4ddf88"), 0.3, 0.0, false, Color("22aa55"))
	_add_local_box(body, Vector3(0.14, 0.28, 0.282), Vector3(0.035, 0.035, 0.012), power)
	_add_device_label(body, device_name, Vector3(0, 0.50, 0.0))


func _build_server_model(body: Node3D, device_name: String, category: String) -> void:
	var shell := _material(Color("38464e"), 0.5, 0.18, true)
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


## Point d'acces : utilise le modele Kenney (CC0) machine_wireless si present,
## sinon le puck procedural en secours.
func _build_access_point_model(body: Node3D, device_name: String, compact := false) -> void:
	var prop := _spawn_kenney_prop_local(body, "space/machine_wireless.glb", Vector3(0, 0, 0), 0.0, 0.55)
	if prop == null:
		var shell := _material(Color("d7e1e5"), 0.55, 0.08, true)
		var puck := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = 0.12
		cylinder.top_radius = 0.36
		cylinder.bottom_radius = 0.38
		cylinder.material = shell
		puck.mesh = cylinder
		body.add_child(puck)
		var led := _material(Color("55dd99"), 0.2, 0.0, false, Color("33cc77"))
		_add_local_box(body, Vector3(0, 0.07, 0.18), Vector3(0.05, 0.02, 0.025), led)
	_add_device_label(body, device_name, Vector3(0, 0.32, 0.0), compact)


## Routeur Wi-Fi : utilise le modele Kenney (CC0) machine_wirelessCable si
## present, sinon le routeur a antennes procedural en secours.
func _build_wireless_router_model(body: Node3D, device_name: String, compact := false) -> void:
	var prop := _spawn_kenney_prop_local(body, "space/machine_wirelessCable.glb", Vector3(0, 0, 0), 0.0, 1.05)
	if prop == null:
		_build_router_model(body, device_name, compact)
		return
	_add_device_label(body, device_name, Vector3(0, 0.5, 0.0), compact)


## Baie de brassage 19" : cadre ouvert avec montants et traverses. Sert de
## support de rackage - voir _next_rack_slot() / _register_if_racked().
func _build_rack_model(body: Node3D, device_name: String) -> void:
	var frame := _material(Color("2b3438"), 0.6, 0.3, true)
	var rail := _material(Color("15191b"), 0.5, 0.4)
	for x in [-0.28, 0.28]:
		for z in [-0.31, 0.31]:
			_add_local_box(body, Vector3(x, 0, z), Vector3(0.045, 1.9, 0.045), frame)
	for y in [-0.93, -0.47, 0.0, 0.47, 0.93]:
		_add_local_box(body, Vector3(0, y, -0.31), Vector3(0.6, 0.03, 0.03), rail)
	_add_local_box(body, Vector3(0, 0, -0.33), Vector3(0.58, 1.86, 0.02), rail)
	# Panneau de brassage (decor) monte dans le haut de la baie : rangee de
	# connecteurs sous collerette claire, comme un vrai panneau 24 ports.
	var panel := _material(Color("14181b"), 0.5, 0.3)
	_add_local_box(body, Vector3(0, 0.72, 0.28), Vector3(0.56, 0.09, 0.03), panel)
	var jack_frame := _material(Color("9aa4aa"), 0.35, 0.6)
	var jack_hole := _material(Color("05070a"), 0.5)
	for i in 8:
		var x := -0.235 + i * 0.067
		_add_local_box(body, Vector3(x, 0.72, 0.296), Vector3(0.042, 0.05, 0.008), jack_frame)
		_add_local_box(body, Vector3(x, 0.717, 0.301), Vector3(0.028, 0.032, 0.006), jack_hole)
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
func _build_client_laptop_model(body: Node3D, device_name: String) -> void:
	var shell := _material(Color("3a444b"), 0.5, 0.2, true)
	var screen_mat := _material(Color("0f2530"), 0.3, 0.05, false, Color("1c6f96"), 1.4)
	_add_local_box(body, Vector3(0, -0.16, 0.05), Vector3(0.42, 0.03, 0.3), shell)
	var screen := _add_local_box(body, Vector3(0, 0.06, -0.1), Vector3(0.42, 0.28, 0.02), shell)
	screen.rotation.x = deg_to_rad(-12)
	var display := _add_local_box(body, Vector3(0, 0.06, -0.092), Vector3(0.36, 0.22, 0.01), screen_mat)
	display.rotation.x = deg_to_rad(-12)
	_add_device_label(body, device_name, Vector3(0, 0.28, 0.0))


func _build_equipment_cart(body: Node3D) -> void:
	var frame := _material(Color("3b4449"), 0.35, 0.65)
	var shelf := _material(Color("69767c"), 0.5, 0.4, true)
	_add_local_box(body, Vector3(0, -0.17, 0), Vector3(1.8, 0.07, 0.75), shelf)
	for x in [-0.78, 0.78]:
		for z in [-0.27, 0.27]:
			_add_local_box(body, Vector3(x, -0.50, z), Vector3(0.055, 0.65, 0.055), frame)


func _add_device_ports(body: Node3D, device_name: String, category: String, compact := false) -> void:
	var interfaces: Array = DeviceInterfaces.BY_CATEGORY.get(category, [])
	for index in interfaces.size():
		var iface: String = interfaces[index]
		var local_pos := Vector3.ZERO
		match category:
			"switch", "switch_l3":
				var half := ceili(interfaces.size() / 2.0)
				var row := index / half
				var col := index % half
				local_pos = Vector3((col - (half - 1) / 2.0) * 0.16, 0.028 if row == 0 else -0.028, 0.312)
			"firewall": local_pos = Vector3(0.15 + (index - (interfaces.size() - 1) / 2.0) * 0.1, -0.02, 0.297)
			"pc", "nas", "server": local_pos = Vector3(-0.12 + index * 0.16, -0.20, 0.355)
			"access_point": local_pos = Vector3(-0.10 + index * 0.20, -0.02, 0.40)
			_: local_pos = Vector3((index - (interfaces.size() - 1) / 2.0) * 0.26, -0.025, 0.352)
		var port := StaticBody3D.new()
		port.name = "%s_%s" % [device_name, iface]
		port.position = local_pos
		port.set_meta("device_name", device_name)
		port.set_meta("interface_name", iface)
		# Connecteur : collerette metallique claire + cavite sombre, comme un
		# RJ45 reel sur panneau fonce (sinon les ports noirs sont invisibles).
		# Plus petit sur les switches dont le chassis 1U est bas.
		var jack_size := Vector3(0.10, 0.068, 0.05) if category in ["switch", "switch_l3"] else Vector3(0.13, 0.09, 0.055)
		var port_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = jack_size
		box.material = _material(Color("aeb8be"), 0.35, 0.55)
		port_mesh.mesh = box
		port.add_child(port_mesh)
		var cavity := MeshInstance3D.new()
		var cavity_box := BoxMesh.new()
		cavity_box.size = Vector3(jack_size.x * 0.72, jack_size.y * 0.66, 0.02)
		cavity_box.material = _material(Color("05070a"), 0.5)
		cavity.mesh = cavity_box
		cavity.position = Vector3(0, 0, jack_size.z / 2.0 - 0.004)
		port.add_child(cavity)
		# LED d'etat du port (au-dessus du connecteur), pilotee par NetSim :
		# eteinte = libre, verte = lien actif, orange = cable mais down.
		var led := MeshInstance3D.new()
		var led_box := BoxMesh.new()
		led_box.size = Vector3(0.03, 0.018, 0.012)
		led_box.material = _material(Color("101314"), 0.5)
		led.mesh = led_box
		led.position = Vector3(0, 0.056, 0.026)
		port.add_child(led)
		_port_leds["%s|%s" % [device_name, iface]] = led
		var port_col := CollisionShape3D.new()
		var port_shape := BoxShape3D.new()
		port_shape.size = Vector3(0.21, 0.17, 0.15)
		port_col.shape = port_shape
		port.add_child(port_col)
		body.add_child(port)
		if not compact:
			var port_label := Label3D.new()
			port_label.text = iface
			port_label.position = local_pos + Vector3(0, -0.075, 0.04)
			port_label.font_size = 20
			port_label.pixel_size = 0.0022
			port_label.no_depth_test = true
			port_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			body.add_child(port_label)
		_interface_positions["%s|%s" % [device_name, iface]] = body.to_global(local_pos)


## Construit le visuel d'un cable (plugs + segments) dans un noeud conteneur,
## pour pouvoir le supprimer d'un bloc au debranchement.
func _draw_cable(a: Vector3, b: Vector3, cable_type := "rj45") -> Node3D:
	var cable := Node3D.new()
	add_child(cable)
	var floor_a := Vector3(a.x, 0.12, a.z)
	var floor_b := Vector3(b.x, 0.12, b.z)
	var corner := Vector3(floor_b.x, 0.12, floor_a.z)
	_add_cable_plug(cable, a, cable_type)
	_add_cable_plug(cable, b, cable_type)
	_draw_cable_segment(cable, a, floor_a, cable_type)
	_draw_cable_segment(cable, floor_a, corner, cable_type)
	_draw_cable_segment(cable, corner, floor_b, cable_type)
	_draw_cable_segment(cable, floor_b, b, cable_type)
	return cable


func _add_cable_plug(parent: Node3D, pos: Vector3, cable_type: String) -> void:
	var plug := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.11, 0.08, 0.14)
	mesh.material = _material(Color("e1b84b") if cable_type == "fiber" else Color("42a5d9"), 0.32, 0.2)
	plug.mesh = mesh
	parent.add_child(plug)
	plug.global_position = pos


func _draw_cable_segment(parent: Node3D, a: Vector3, b: Vector3, cable_type: String) -> void:
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
	parent.add_child(mesh_inst)

	mesh_inst.global_position = (a + b) / 2.0
	var dir := (b - a).normalized()
	if abs(dir.dot(Vector3.UP)) < 0.999:
		mesh_inst.look_at(b, Vector3.UP)
		mesh_inst.rotate_object_local(Vector3.RIGHT, PI / 2.0)


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
	_paused = not _paused
	_pause_menu.visible = _paused
	_player.set_active(not _paused)
	_update_held_item_visibility()


## Fondu discret a l'ouverture d'un panneau plein ecran (CanvasLayer).
func _animate_open(layer: CanvasLayer) -> void:
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
	if _terminal_open:
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
	NetSim.rebuild(_device_configs, NetSim.links_from_events(GameState.events))
	_refresh_port_leds()
	# Certains objectifs dependent de l'etat reseau (liens actifs), pas
	# seulement du journal : reevaluation a chaque changement de config.
	Objectives.evaluate()


func _is_switch_device() -> bool:
	return str(_device_configs[_terminal_device].get("category", "")) in ["switch", "switch_l3"]


func _is_host_device() -> bool:
	return str(_device_configs[_terminal_device].get("category", "")) in ["pc", "client_laptop", "server", "nas"]


func _execute_terminal_command(command: String) -> void:
	var words := command.to_lower().split(" ", false)
	if command == "?": _show_terminal_help(""); return
	if _command_matches(words, ["clear"]): _terminal_output.text = ""; return
	if _command_matches(words, ["end"]):
		_terminal_mode = "exec"; _terminal_interface = ""; _update_terminal_prompt(); return
	if _command_matches(words, ["exit"]):
		if _terminal_mode in ["interface", "vlan"]:
			_terminal_mode = "config"; _terminal_interface = ""; _update_terminal_prompt()
		elif _terminal_mode == "config":
			_terminal_mode = "exec"; _update_terminal_prompt()
		else: _close_terminal()
		return
	if _command_matches(words, ["show", "running-config"]): _show_running_config(); return
	if _command_matches(words, ["show", "ip", "route"]): _show_ip_routes(); return
	if _command_matches(words, ["show", "ip", "interface", "brief"]): _show_ip_interfaces(); return
	if _command_matches(words, ["show", "interfaces"]): _show_interfaces_detail(); return
	if _command_matches(words, ["show", "vlan"]) or _command_matches(words, ["show", "vlan", "brief"]):
		_show_vlans(); return
	if _command_starts(words, ["ping"]): _run_ping_command(words); return
	if _command_starts(words, ["traceroute"]): _run_traceroute_command(words); return

	if _terminal_mode == "exec":
		if _command_matches(words, ["configure", "terminal"]):
			_terminal_mode = "config"; _update_terminal_prompt()
			_append_terminal("Enter configuration commands, one per line.\n")
		else: _append_terminal("% Invalid command in EXEC mode\n")
	elif _terminal_mode == "config":
		if _command_starts(words, ["hostname"]): _set_hostname(command)
		elif _command_starts(words, ["interface"]): _enter_interface(words)
		elif _command_starts(words, ["no", "ip", "route"]): _remove_static_route(words)
		elif _command_starts(words, ["ip", "route"]):
			if _device_configs[_terminal_device]["category"] == "switch": _append_terminal("% IP routing is not available on a Layer 2 switch\n")
			else: _add_static_route(words)
		elif _command_starts(words, ["ip", "default-gateway"]): _set_default_gateway(words)
		elif _command_starts(words, ["no", "ip", "dhcp", "pool"]): _remove_dhcp_pool(words)
		elif _command_starts(words, ["ip", "dhcp", "pool"]): _add_dhcp_pool(words)
		elif _command_starts(words, ["no", "vlan"]): _remove_vlan(words)
		elif _command_starts(words, ["vlan"]): _enter_vlan(words)
		else: _append_terminal("% Invalid configuration command\n")
	elif _terminal_mode == "vlan":
		if _command_starts(words, ["name"]): _set_vlan_name(command)
		else: _append_terminal("% Invalid VLAN configuration command\n")
	elif _terminal_mode == "interface":
		if _command_matches(words, ["no", "ip", "address"]): _clear_interface_address()
		elif _command_matches(words, ["ip", "address", "dhcp"]):
			if _device_configs[_terminal_device]["category"] == "switch": _append_terminal("% Layer 3 addressing is not available on this switch port\n")
			else:
				_device_configs[_terminal_device]["interfaces"][_terminal_interface]["address"] = "dhcp"
				_save_device_config(_terminal_device)
		elif _command_starts(words, ["ip", "address"]):
			if _device_configs[_terminal_device]["category"] == "switch": _append_terminal("% Layer 3 addressing is not available on this switch port\n")
			else: _set_interface_address(words)
		elif _command_matches(words, ["no", "shutdown"]): _set_interface_shutdown(false)
		elif _command_matches(words, ["shutdown"]): _set_interface_shutdown(true)
		elif _command_starts(words, ["description"]): _set_interface_description(command)
		elif _command_starts(words, ["switchport"]): _handle_switchport(words)
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


func _remove_static_route(words: PackedStringArray) -> void:
	if words.size() < 4: _append_terminal("% Expected: no ip route NETWORK/PREFIX NEXT-HOP\n"); return
	var network := words[3]
	var next_hop := words[4] if words.size() > 4 else ""
	var routes: Array = _device_configs[_terminal_device]["routes"]
	for i in routes.size():
		var route: Dictionary = routes[i]
		if str(route["network"]) == network and (next_hop.is_empty() or str(route["next_hop"]) == next_hop):
			routes.remove_at(i)
			_save_device_config(_terminal_device)
			return
	_append_terminal("% No matching route\n")


func _set_default_gateway(words: PackedStringArray) -> void:
	if words.size() < 3: _append_terminal("% Expected: ip default-gateway A.B.C.D\n"); return
	_device_configs[_terminal_device]["default_gateway"] = words[2]
	_save_device_config(_terminal_device)


## Pool DHCP simplifie en une ligne : ip dhcp pool NETWORK/PREFIX gateway A.B.C.D
## Le serveur doit posseder une adresse dans le reseau du pool pour repondre.
func _add_dhcp_pool(words: PackedStringArray) -> void:
	if _device_configs[_terminal_device]["category"] == "switch":
		_append_terminal("% DHCP server is not available on a Layer 2 switch\n"); return
	if words.size() < 6 or words[4] != "gateway" or not "/" in words[3]:
		_append_terminal("% Expected: ip dhcp pool NETWORK/PREFIX gateway A.B.C.D\n"); return
	var pools: Array = _device_configs[_terminal_device].get("dhcp_pools", [])
	pools.append({"network": words[3], "gateway": words[5]})
	_device_configs[_terminal_device]["dhcp_pools"] = pools
	_save_device_config(_terminal_device)


func _remove_dhcp_pool(words: PackedStringArray) -> void:
	if words.size() < 5: _append_terminal("% Expected: no ip dhcp pool NETWORK/PREFIX\n"); return
	var pools: Array = _device_configs[_terminal_device].get("dhcp_pools", [])
	for i in pools.size():
		if str(pools[i].get("network", "")) == words[4]:
			pools.remove_at(i)
			_save_device_config(_terminal_device)
			return
	_append_terminal("% No matching pool\n")


# --- VLANs / switchport ---------------------------------------------------------

func _enter_vlan(words: PackedStringArray) -> void:
	if not _is_switch_device():
		_append_terminal("% VLAN configuration is only available on switches\n"); return
	if words.size() < 2 or not words[1].is_valid_int():
		_append_terminal("% Expected: vlan <1-4094>\n"); return
	var vlan_id := int(words[1])
	if vlan_id < 1 or vlan_id > 4094:
		_append_terminal("% VLAN id out of range\n"); return
	var vlans: Dictionary = _device_configs[_terminal_device]["vlans"]
	if not vlans.has(str(vlan_id)):
		vlans[str(vlan_id)] = "VLAN%04d" % vlan_id
		_save_device_config(_terminal_device)
	_terminal_interface = str(vlan_id)
	_terminal_mode = "vlan"
	_update_terminal_prompt()


func _remove_vlan(words: PackedStringArray) -> void:
	if not _is_switch_device():
		_append_terminal("% VLAN configuration is only available on switches\n"); return
	if words.size() < 3 or not words[2].is_valid_int():
		_append_terminal("% Expected: no vlan <id>\n"); return
	if words[2] == "1":
		_append_terminal("% Default VLAN 1 cannot be deleted\n"); return
	_device_configs[_terminal_device]["vlans"].erase(words[2])
	_save_device_config(_terminal_device)


func _set_vlan_name(command: String) -> void:
	var value := command.get_slice(" ", 1).strip_edges()
	if value.is_empty(): _append_terminal("% Name required\n"); return
	_device_configs[_terminal_device]["vlans"][_terminal_interface] = value
	_save_device_config(_terminal_device)


func _handle_switchport(words: PackedStringArray) -> void:
	if not _is_switch_device():
		_append_terminal("% switchport is only available on switch ports\n"); return
	var state: Dictionary = _device_configs[_terminal_device]["interfaces"][_terminal_interface]
	if _command_matches(words, ["switchport", "mode", "access"]):
		state["mode"] = "access"
	elif _command_matches(words, ["switchport", "mode", "trunk"]):
		state["mode"] = "trunk"
	elif _command_starts(words, ["switchport", "access", "vlan"]):
		if words.size() < 4 or not words[3].is_valid_int():
			_append_terminal("% Expected: switchport access vlan <id>\n"); return
		if not _device_configs[_terminal_device]["vlans"].has(words[3]):
			_append_terminal("%% VLAN %s does not exist (create it with: vlan %s)\n" % [words[3], words[3]]); return
		state["vlan"] = int(words[3])
	elif _command_starts(words, ["switchport", "trunk", "allowed", "vlan"]):
		if words.size() < 5:
			_append_terminal("% Expected: switchport trunk allowed vlan <list|all>\n"); return
		state["trunk_allowed"] = words[4]
	else:
		_append_terminal("% Invalid switchport command\n"); return
	_save_device_config(_terminal_device)


# --- Show commands ---------------------------------------------------------------

func _show_running_config() -> void:
	var config: Dictionary = _device_configs[_terminal_device]
	_append_terminal("Building configuration...\n\nhostname %s\n!\n" % config["hostname"])
	if _is_switch_device():
		for vlan_id in config.get("vlans", {}):
			if str(vlan_id) != "1":
				_append_terminal("vlan %s\n name %s\n!\n" % [vlan_id, config["vlans"][vlan_id]])
	for iface in config["interfaces"]:
		var state: Dictionary = config["interfaces"][iface]
		_append_terminal("interface %s\n" % iface)
		if not str(state["description"]).is_empty(): _append_terminal(" description %s\n" % state["description"])
		if not str(state["address"]).is_empty(): _append_terminal(" ip address %s\n" % state["address"])
		if _is_switch_device():
			if str(state.get("mode", "access")) == "trunk":
				_append_terminal(" switchport mode trunk\n")
				if str(state.get("trunk_allowed", "all")) != "all":
					_append_terminal(" switchport trunk allowed vlan %s\n" % state["trunk_allowed"])
			elif int(state.get("vlan", 1)) != 1:
				_append_terminal(" switchport access vlan %d\n" % int(state["vlan"]))
		_append_terminal(" %s\n!\n" % ("shutdown" if state["shutdown"] else "no shutdown"))
	for route in config["routes"]: _append_terminal("ip route %s %s\n" % [route["network"], route["next_hop"]])
	for pool in config.get("dhcp_pools", []):
		_append_terminal("ip dhcp pool %s gateway %s\n" % [pool["network"], pool["gateway"]])
	if not str(config.get("default_gateway", "")).is_empty():
		_append_terminal("ip default-gateway %s\n" % config["default_gateway"])
	_append_terminal("end\n")


func _show_ip_interfaces() -> void:
	_append_terminal("Interface        IP-Address          Status                 Protocol\n")
	var interfaces: Dictionary = _device_configs[_terminal_device]["interfaces"]
	for iface in interfaces:
		var state: Dictionary = interfaces[iface]
		var address := str(state["address"]) if not str(state["address"]).is_empty() else "unassigned"
		if address == "dhcp":
			var lease := str(NetSim.effective_address(_terminal_device, iface))
			address = "%s (dhcp)" % (lease if not lease.is_empty() else "unassigned")
		var status := "administratively down" if state["shutdown"] else "up"
		var protocol := "up" if NetSim.link_protocol_up(_terminal_device, iface) else "down"
		_append_terminal("%-16s %-19s %-22s %s\n" % [iface, address, status, protocol])


func _show_interfaces_detail() -> void:
	var interfaces: Dictionary = _device_configs[_terminal_device]["interfaces"]
	for iface in interfaces:
		var state: Dictionary = interfaces[iface]
		var admin := "administratively down" if state["shutdown"] else "up"
		var protocol := "up" if NetSim.link_protocol_up(_terminal_device, iface) else "down"
		_append_terminal("%s is %s, line protocol is %s\n" % [iface, admin, protocol])
		if not str(state["description"]).is_empty():
			_append_terminal("  Description: %s\n" % state["description"])
		var shown_address := str(state["address"])
		if shown_address == "dhcp":
			var lease := str(NetSim.effective_address(_terminal_device, iface))
			shown_address = "%s (dhcp)" % lease if not lease.is_empty() else "dhcp (no lease)"
		if not shown_address.is_empty():
			_append_terminal("  Internet address is %s\n" % shown_address)
		if _is_switch_device():
			if str(state.get("mode", "access")) == "trunk":
				_append_terminal("  Switchport: trunk, allowed VLANs %s\n" % str(state.get("trunk_allowed", "all")))
			else:
				_append_terminal("  Switchport: access, VLAN %d\n" % int(state.get("vlan", 1)))
		_append_terminal("  Link: %s\n" % ("connected" if NetSim.cable_connected(_terminal_device, iface) else "not connected"))


func _show_ip_routes() -> void:
	_append_terminal("Codes: C - connected, S - static\n")
	var config: Dictionary = _device_configs[_terminal_device]
	for iface in config["interfaces"]:
		var state: Dictionary = config["interfaces"][iface]
		if not str(state["address"]).is_empty() and not state["shutdown"]:
			_append_terminal("C  %s is directly connected, %s\n" % [state["address"], iface])
	for route in config["routes"]: _append_terminal("S  %s via %s\n" % [route["network"], route["next_hop"]])
	var gateway := str(config.get("default_gateway", ""))
	if not gateway.is_empty():
		_append_terminal("S* 0.0.0.0/0 via %s (default gateway)\n" % gateway)


func _show_vlans() -> void:
	if not _is_switch_device():
		_append_terminal("% This device does not support VLANs\n"); return
	var config: Dictionary = _device_configs[_terminal_device]
	_append_terminal("VLAN  Name                 Ports\n")
	var vlan_ids: Array = config.get("vlans", {}).keys()
	vlan_ids.sort_custom(func(a, b): return int(a) < int(b))
	for vlan_id in vlan_ids:
		var ports: Array = []
		for iface in config["interfaces"]:
			var state: Dictionary = config["interfaces"][iface]
			if str(state.get("mode", "access")) == "access" and int(state.get("vlan", 1)) == int(vlan_id):
				ports.append(iface)
		_append_terminal("%-5s %-20s %s\n" % [vlan_id, config["vlans"][vlan_id], ", ".join(ports)])
	var trunks: Array = []
	for iface in config["interfaces"]:
		if str(config["interfaces"][iface].get("mode", "access")) == "trunk":
			trunks.append("%s (allowed: %s)" % [iface, str(config["interfaces"][iface].get("trunk_allowed", "all"))])
	if not trunks.is_empty():
		_append_terminal("Trunk ports: %s\n" % ", ".join(trunks))


# --- Ping / traceroute ------------------------------------------------------------

func _run_ping_command(words: PackedStringArray) -> void:
	if words.size() < 2: _append_terminal("% Destination required\n"); return
	var destination := words[1]
	var result: Dictionary = NetSim.ping(_terminal_device, destination)
	_append_terminal("Sending 5 ICMP echos to %s:\n" % destination)
	if result["success"]:
		_append_terminal("!!!!!\nSuccess rate is 100 percent (5/5)\n")
		var path: Array = result.get("path", [])
		if path.size() > 2:
			_append_terminal("Path: %s\n" % " -> ".join(path))
		_record_ping_success(destination, path.size())
	else:
		_append_terminal(".....\nSuccess rate is 0 percent (0/5)\n")
		_append_terminal(NetSim.reason_text(str(result["reason"])) + "\n")


## Journalise un ping reussi (pour les objectifs), sans dupliquer les entrees
## identiques pour ne pas gonfler la sauvegarde.
func _record_ping_success(destination: String, hops: int) -> void:
	for event in GameState.events:
		if event.get("type", "") == "ping_ok" and event.get("src", "") == _terminal_device \
				and event.get("dst", "") == destination:
			return
	GameState.record({"type": "ping_ok", "src": _terminal_device, "dst": destination, "hops": hops})


func _run_traceroute_command(words: PackedStringArray) -> void:
	if words.size() < 2: _append_terminal("% Destination required\n"); return
	var destination := words[1]
	var result: Dictionary = NetSim.traceroute(_terminal_device, destination)
	_append_terminal("Tracing the route to %s:\n" % destination)
	var path: Array = result.get("path", [])
	var hop := 1
	for i in range(1, path.size()):
		_append_terminal("  %d  %s\n" % [hop, path[i]])
		hop += 1
	if result["success"]:
		_append_terminal("Trace complete.\n")
	else:
		_append_terminal("  %d  * * *\n%s\n" % [hop, NetSim.reason_text(str(result["reason"]))])


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
			"pc", "nas", "server", "client_laptop": pos.y = 0.41
			"table": pos.y = 0.0
			"rack": pos.y = 0.95
			_: pos.y = 0.825
		var toward_player := _player.global_position - pos
		world_yaw = atan2(toward_player.x, toward_player.z)

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
	var local_y := -0.75 + count * 0.22
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
	elif not device_name.is_empty():
		var category: String = _device_categories.get(device_name, "")
		if category == "rack" and not _catalog.is_empty() \
				and str(_catalog[_selected_index].get("id", "")) in RACKABLE_CATEGORIES:
			text = "[E] Racker %s ici   [T] Console" % str(_catalog[_selected_index].get("label", ""))
		elif category in ["rack", "table"]:
			text = "%s   [X] Retirer" % device_name
		else:
			text = "[T] Console de %s   [X] Retirer" % device_name
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
