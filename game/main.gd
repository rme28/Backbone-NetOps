extends Node3D
## Construit la salle 3D par code (aucune manip souris necessaire) et gere
## l'interaction : appuyer sur E pose un routeur - un cube apparait dans le jeu
## ET l'equipement apparait dans Packet Tracer via le pont Python.

var device_count := 0
var _status_label: Label


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_ui()
	Bridge.status_changed.connect(_on_bridge_status_changed)
	Bridge.ensure_running()


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
	help.text = "ZQSD : se deplacer    Souris : regarder    E : poser un routeur    Echap : liberer la souris"
	help.position = Vector2(16, 12)
	layer.add_child(help)

	_status_label = Label.new()
	_status_label.position = Vector2(16, 40)
	layer.add_child(_status_label)

	add_child(layer)


func _on_bridge_status_changed(state: String, message: String) -> void:
	_status_label.text = "[Pont] %s" % message
	match state:
		"connected":
			_status_label.modulate = Color(0.4, 0.9, 0.4)
		"error":
			_status_label.modulate = Color(0.95, 0.3, 0.3)
		_:
			_status_label.modulate = Color(0.9, 0.8, 0.3)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_place_device()


func _place_device() -> void:
	device_count += 1
	var dev_name := "GameR%d" % device_count

	var player := $Player as CharacterBody3D
	var forward := -player.global_transform.basis.z
	var pos := player.global_position + forward * 2.5
	pos.y = 0.5

	# Cube visuel dans le jeu.
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 0.6, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.9)
	mesh.material = mat
	box.mesh = mesh
	add_child(box)
	box.global_position = pos

	# Envoi au pont -> l'equipement apparait dans Packet Tracer.
	Bridge.add_device(dev_name, "2911", 100 + device_count * 60, 100)
	print("Pose %s a %s" % [dev_name, pos])
