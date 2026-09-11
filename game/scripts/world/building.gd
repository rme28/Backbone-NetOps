extends RefCounted
## Existing room layout, furniture placement and imported prop normalization.
var room: Node3D

func _init(host: Node3D) -> void:
	room = host

func _spawn_kenney_prop(sub_path: String, pos: Vector3, yaw := 0.0, scale_mult := 1.0) -> Node3D:
	var instance := _load_kenney_prop(sub_path, scale_mult)
	if instance == null:
		return null
	room.add_child(instance)
	instance.position = pos
	instance.rotation.y = yaw
	if sub_path.get_file().get_basename() in ["chairDesk", "loungeDesignSofa", "tableCoffee", "kitchenCabinetDrawer", "kitchenFridgeSmall", "bookcaseOpen"]:
		var bounds := _prop_bounds(instance, instance.transform.affine_inverse())
		var body := StaticBody3D.new()
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = bounds.get_center()
		body.add_child(collider)
		instance.add_child(body)
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
	var path: String = room.KENNEY_ASSETS + sub_path
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var instance := scene.instantiate()
	var heights := {"table": 0.74, "chair": 0.9, "bookcaseOpen": 1.65, "plantSmall1": 0.55, "pottedPlant": 0.9, "kitchenCabinetDrawer": 0.60, "kitchenFridgeSmall": 0.72, "kitchenCoffeeMachine": 0.35, "books": 0.22, "cardboardBoxClosed": 0.55, "cardboardBoxOpen": 0.55, "tableCoffee": 0.43, "loungeDesignSofa": 0.60}
	var asset_name := sub_path.get_file().get_basename()
	var bounds := _prop_bounds(instance)
	var model_scale := float(heights.get(asset_name, bounds.size.y)) / maxf(bounds.size.y, 0.001)
	_harmonize_prop(instance)
	var wrapper := Node3D.new()
	wrapper.name = asset_name
	wrapper.add_child(instance)
	instance.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	wrapper.scale = Vector3.ONE * scale_mult * model_scale
	return wrapper



func _prop_bounds(root: Node3D, parent_transform := Transform3D.IDENTITY) -> AABB:
	var transform := parent_transform * root.transform
	var result := AABB()
	if root is MeshInstance3D:
		result = transform * root.get_aabb()
	for child in root.get_children():
		if child is Node3D:
			var bounds := _prop_bounds(child, transform)
			if bounds.size != Vector3.ZERO:
				result = bounds if result.size == Vector3.ZERO else result.merge(bounds)
	return result


func _harmonize_prop(root: Node) -> void:
	if root is MeshInstance3D:
		for i in root.mesh.get_surface_count():
			var original: Material = root.mesh.surface_get_material(i)
			if original == null: continue
			var key := original.resource_name.to_lower()
			var palette := {"carpet": "344e59", "carpetblue": "344e59", "plant": "467459", "wood": "ad8966", "wooddark": "725c47", "metalmedium": "343f44"}
			if palette.has(key):
				root.set_surface_override_material(i, room._material(Color(palette[key]), 0.85, 0.0))
	for child in root.get_children(): _harmonize_prop(child)


## Petite annexe pause/bureau a l'est de la salle serveur, reliee par la porte
## percee dans le mur est. Casse la sensation de "salle carree unique". Le
## mobilier utilise les modeles Kenney (CC0, kenney.nl/assets/furniture-kit)
## quand disponibles dans assets/kenney/furniture/, sinon des boites codees.
func _build_annex_room(wall_mat: Material, ceiling_mat: Material) -> void:
	var floor_mat: Material = room._material(Color("8c7962"), 0.85, 0.05)
	var annex_wall: Material = room._material(Color("c8c4b7"), 0.85, 0.05)
	room._add_box(Vector3(14, -0.1, 0), Vector3(8, 0.2, 9), floor_mat)
	room._add_box(Vector3(14, 1.5, -4.5), Vector3(8, 3, 0.2), annex_wall)
	room._add_box(Vector3(14, 1.5, 4.5), Vector3(8, 3, 0.2), annex_wall)
	room._add_box(Vector3(18, 1.5, 0), Vector3(0.2, 3, 9), annex_wall)
	room._add_visual_box(Vector3(14, 3.05, 0), Vector3(8, 0.1, 9), ceiling_mat)

	_add_zone_light(Vector3(14, 2.7, 0), Color("ffead1"), 1.1, 7.0)

	# Table + chaises + bibliotheque, coin pause. Modeles Kenney si disponibles.
	if _spawn_kenney_prop("furniture/table.glb", Vector3(14, 0, 0)) == null:
		var table_mat: Material = room._material(Color("5a4632"), 0.6, 0.1, true)
		room._add_box(Vector3(14, 0.38, 0), Vector3(1.1, 0.06, 1.1), table_mat)
		for i in 4:
			var angle := i * PI / 2.0
			var leg_pos := Vector3(14 + cos(angle) * 0.42, 0.19, sin(angle) * 0.42)
			room._add_box(leg_pos, Vector3(0.06, 0.38, 0.06), table_mat)
	var chair_a := _spawn_kenney_prop("furniture/chair.glb", Vector3(12.9, 0, 0), PI * 1.5)
	var chair_b := _spawn_kenney_prop("furniture/chair.glb", Vector3(15.1, 0, 0), PI * 0.5)
	if chair_a == null or chair_b == null:
		var seat_mat: Material = room._material(Color("4a4038"), 0.7, 0.05)
		if chair_a == null: room._add_box(Vector3(12.8, 0.22, 0), Vector3(0.5, 0.44, 1.6), seat_mat)
		if chair_b == null: room._add_box(Vector3(15.2, 0.22, 0), Vector3(0.5, 0.44, 1.6), seat_mat)
	if _spawn_kenney_prop("furniture/bookcaseOpen.glb", Vector3(17.7, 0, -3.8), -PI/2) == null:
		var shelf_mat: Material = room._material(Color("4a4038"), 0.6, 0.1)
		room._add_box(Vector3(17.7, 0.9, -3.8), Vector3(0.4, 1.8, 0.9), shelf_mat)

	_add_signage(Vector3(14, 2.4, -4.385), "ESPACE PAUSE", Color("f0dfc4"))


## Aile sud du batiment : couloir, open-space bureaux, accueil et local
## technique operateur (arrivee WAN). Chaque zone est construite par une
## fonction dediee avec des coordonnees regroupees, pour rester facilement
## deplacable / modifiable par un futur developpeur de scenarios.
func _build_south_wing(wall_mat: Material, ceiling_mat: Material) -> void:
	var corridor_floor: Material = room._material(Color("262c31"), 0.8, 0.1)
	var office_floor: Material = room._art.mats["carpet"]
	var closet_floor: Material = room._material(Color("2b2926"), 0.9, 0.0)

	# --- Couloir (x -10..10, z 10..13.6) ---
	room._add_box(Vector3(0, -0.1, 11.8), Vector3(20, 0.2, 3.6), corridor_floor)
	room._add_visual_box(Vector3(0, 3.05, 11.8), Vector3(20, 0.1, 3.6), ceiling_mat)
	# Mur sud du couloir : ouvertures vers bureaux (x -5.2..-2.8) et accueil (x 3..8).
	room._add_box(Vector3(-7.6, 1.5, 13.6), Vector3(4.8, 3, 0.2), wall_mat)
	room._add_box(Vector3(0.1, 1.5, 13.6), Vector3(5.8, 3, 0.2), wall_mat)
	room._add_box(Vector3(9.0, 1.5, 13.6), Vector3(2.0, 3, 0.2), wall_mat)
	_add_zone_light(Vector3(-5, 2.75, 11.8), Color("fff1dc"), 1.8, 8.0)
	_add_zone_light(Vector3(5, 2.75, 11.8), Color("fff1dc"), 1.8, 8.0)
	_add_zone_light(Vector3(0, 2.75, 11.8), Color("fff1dc"), 1.6, 7.0)
	_add_signage(Vector3(-4, 2.7, 13.485), "BUREAUX", Color("e8e2d0"), PI)
	_add_signage(Vector3(5.5, 2.7, 13.485), "ACCUEIL", Color("e8e2d0"), PI)

	for opening in [[-4.0, 2.4], [5.5, 5.0]]:
		room._add_box(Vector3(opening[0],2.75,13.6),Vector3(opening[1],0.5,0.2),wall_mat)
	room._add_box(Vector3(-10,2.75,12.2),Vector3(0.2,0.5,2.4),wall_mat)

	# --- Open-space bureaux (x -10..3, z 13.6..21.2) ---
	room._add_box(Vector3(-3.5, -0.1, 17.4), Vector3(13, 0.2, 7.6), office_floor)
	room._add_visual_box(Vector3(-3.5, 3.05, 17.4), Vector3(13, 0.1, 7.6), ceiling_mat)
	room._add_box(Vector3(3, 1.5, 17.4), Vector3(0.2, 3, 7.6), wall_mat)  # cloison accueil
	_add_zone_light(Vector3(-6, 2.75, 17.4), Color("f4f8ff"), 1.8, 8.0)
	_add_zone_light(Vector3(-1, 2.75, 17.4), Color("f4f8ff"), 1.8, 8.0)
	for desk_x in [-7.5, -4.5]:
		_build_office_desk(Vector3(desk_x, 0, 16.2), 0.0)
		_build_office_desk(Vector3(desk_x, 0, 19.2), PI)
	for outlet_x in [-8.0, -6.0, -2.5, 0.0]:
		_add_wall_outlet(Vector3(outlet_x, 0.35, 13.705))
	_add_plant(Vector3(1.8, 0, 20.2))
	_build_printer_corner(Vector3(-9.2, 0, 20.3))

	# --- Accueil (x 3..10, z 13.6..21.2) ---
	room._add_box(Vector3(6.5, -0.1, 17.4), Vector3(7, 0.2, 7.6), office_floor)
	room._add_visual_box(Vector3(6.5, 3.05, 17.4), Vector3(7, 0.1, 7.6), ceiling_mat)
	_add_zone_light(Vector3(6.5, 2.75, 17.4), Color("ffedd6"), 1.8, 8.0)
	_build_reception_desk(Vector3(5.6, 0, 16.6))
	_add_plant(Vector3(9.2, 0, 14.6))
	_add_signage(Vector3(4.7, 2.3, 21.085), "BACKBONE CORP", Color("8bc6b5"), PI)
	# Porte d'entree (decor) sur le mur sud.
	var door_mat: Material = room._material(Color("1b2226"), 0.4, 0.4)
	room._add_visual_box(Vector3(7.5, 1.25, 21.08), Vector3(2.2, 2.5, 0.08), door_mat)
	_add_signage(Vector3(7.5, 2.62, 21.0), "ENTREE", Color("9adf9a"), PI)

	# --- Murs exterieurs de l'aile ---
	room._add_box(Vector3(0, 1.5, 21.2), Vector3(20, 3, 0.2), wall_mat)              # sud
	room._add_box(Vector3(10, 1.5, 15.6), Vector3(0.2, 3, 11.2), wall_mat)           # est
	room._add_box(Vector3(-10, 1.5, 10.5), Vector3(0.2, 3, 1.0), wall_mat)           # ouest (haut)
	room._add_box(Vector3(-10, 1.5, 17.3), Vector3(0.2, 3, 7.8), wall_mat)           # ouest (bas)

	# --- Local technique / arrivee WAN (x -14.4..-10, z 10..14) ---
	room._add_box(Vector3(-12.2, -0.1, 12), Vector3(4.4, 0.2, 4), closet_floor)
	room._add_visual_box(Vector3(-12.2, 3.05, 12), Vector3(4.4, 0.1, 4), ceiling_mat)
	room._add_box(Vector3(-14.4, 1.5, 12), Vector3(0.2, 3, 4), wall_mat)
	room._add_box(Vector3(-12.2, 1.5, 10), Vector3(4.4, 3, 0.2), wall_mat)
	room._add_box(Vector3(-12.2, 1.5, 14), Vector3(4.4, 3, 0.2), wall_mat)
	_add_zone_light(Vector3(-12.2, 2.7, 12), Color("dceaf2"), 1.5, 6.0)
	_add_signage(Vector3(-9.885, 2.7, 12), "LOCAL TECHNIQUE", Color("ffd166"), PI / 2.0)
	room._fixed_network.wan()
	_add_signage(Vector3(-14.285,2.05,12),"ARRIVÉE OPÉRATEUR",Color("9adf9a"),PI/2)
	var fiber: Material = room._material(Color("c3aa55"))
	room._add_visual_box(Vector3(-14.245,1.35,12.4),Vector3(0.008,0.008,0.8),fiber)
	room._add_visual_box(Vector3(-14.245,1.55,12.8),Vector3(0.008,0.4,0.008),fiber)
	var conduit: Material = room._material(Color("35434a"), 0.35, 0.65)
	room._add_visual_box(Vector3(-14.25, 2.35, 12.8), Vector3(0.08, 1.2, 0.08), conduit)
	room._add_visual_box(Vector3(-12.2, 2.88, 12.8), Vector3(4.2, 0.1, 0.14), conduit)


## Panneau de signalisation mural (texte fixe oriente, pas de billboard).
func _add_signage(pos: Vector3, text: String, color: Color, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.rotation.y = yaw
	label.font_size = 32
	label.pixel_size = 0.0024
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	var plate: MeshInstance3D = room._add_visual_box(pos - Vector3(0, 0, 0.015).rotated(Vector3.UP, yaw), Vector3(maxf(0.7, text.length() * 0.048), 0.25, 0.025), room._material(Color("263c43")))
	plate.rotation.y = yaw
	room.add_child(label)


func _add_zone_light(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var lamp_mat: Material = room._material(Color("a3b4b1"), 0.9).duplicate()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	room._add_visual_box(Vector3(pos.x, 2.985, pos.z), Vector3(1.7, 0.045, 0.5), room._material(Color("34474b")))
	room._add_visual_box(Vector3(pos.x, 2.96, pos.z), Vector3(1.6, 0.04, 0.4), lamp_mat)
	var lamp := OmniLight3D.new()
	lamp.position = pos
	lamp.light_color = color
	lamp.light_energy = energy * 0.65
	lamp.shadow_enabled = false
	if pos.distance_to(Vector3(-6, 2.76, -7)) < 0.1 or pos.distance_to(Vector3(-6, 2.75, 17.4)) < 0.1:
		var key_light := SpotLight3D.new()
		key_light.position = pos
		key_light.rotation.x = -PI / 2
		key_light.light_color = color
		key_light.light_energy = 0.7
		key_light.spot_range = 7.0
		key_light.spot_angle = 75.0
		key_light.shadow_enabled = true
		room.add_child(key_light)
	lamp.omni_range = range_m
	room.add_child(lamp)


## Bureau d'open-space (decor) : plateau, pietement, ecran et chaise Kenney.
func _build_office_desk(pos: Vector3, yaw: float) -> void:
	var desk := StaticBody3D.new()
	desk.position = pos
	desk.rotation.y = yaw
	room.add_child(desk)
	var top_mat: Material = room._art.mats["wood"]
	var leg_mat: Material = room._material(Color("2c3134"), 0.4, 0.5)
	room._add_local_box(desk, Vector3(0, 0.74, 0), Vector3(1.6, 0.06, 0.8), top_mat)
	for x in [-0.72, 0.72]:
		for z in [-0.3, 0.3]:
			room._add_local_box(desk, Vector3(x, 0.37, z), Vector3(0.045, 0.74, 0.045), leg_mat)
		room._add_local_box(desk, Vector3(x, 0.09, 0), Vector3(0.045, 0.04, 0.65), leg_mat)
	room._add_local_box(desk, Vector3(0, 0.67, -0.31), Vector3(1.45, 0.08, 0.04), leg_mat)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 0.06, 0.8)
	col.shape = shape
	col.position = Vector3(0, 0.74, 0)
	desk.add_child(col)
	for x in [-0.72, 0.72]:
		for z in [-0.3, 0.3]:
			var leg_col := CollisionShape3D.new()
			var leg_shape := BoxShape3D.new()
			leg_shape.size = Vector3(0.045,0.74,0.045)
			leg_col.shape = leg_shape
			leg_col.position = Vector3(x,0.37,z)
			desk.add_child(leg_col)
	var host_name := "POSTE-%02d" % (room._office_hosts.size()+1)
	var host_pos := pos + Vector3(-1.05,0.41,0).rotated(Vector3.UP,yaw)
	if pos.is_equal_approx(Vector3(-7.5,0,16.2)):
		host_name = "PC-BUREAU1"
		host_pos = Vector3(-8.55,0.41,16.2)
	room._office_hosts.append({"type":"place_device","name":host_name,"category":"pc","model":"desktop","world_pos":[host_pos.x,host_pos.y,host_pos.z],"world_yaw":yaw+PI/2})
	var monitor := StaticBody3D.new()
	desk.add_child(monitor)
	monitor.position = Vector3(0,1.02,-0.2)
	monitor.set_meta("device_name",host_name)
	var monitor_col := CollisionShape3D.new()
	var monitor_shape := BoxShape3D.new()
	monitor_shape.size = Vector3(0.55,0.34,0.035)
	monitor_col.shape = monitor_shape
	monitor.add_child(monitor_col)
	# Monitor and peripherals share the corresponding host's interaction.

	room._add_local_box(desk, Vector3(0, 1.02, -0.2), Vector3(0.55, 0.34, 0.03), room._material(Color("14181b"), 0.4, 0.4))
	room._add_display(desk, Vector3(0, 1.02, -0.177), Vector2(0.5, 0.29))
	room._add_local_box(desk, Vector3(0, 0.79, -0.2), Vector3(0.06, 0.04, 0.06), leg_mat)
	room._add_local_box(desk, Vector3(0, 0.78, 0.1), Vector3(0.42, 0.02, 0.14), leg_mat)
	_spawn_kenney_prop("furniture/chairDesk.glb", pos + Vector3(0.15, 0, 0.82).rotated(Vector3.UP, yaw), yaw + PI, 1.25)
	_spawn_kenney_prop_local(desk, "furniture/computerKeyboard.glb", Vector3(0, 0.79, 0.13), 0, 0.7)
	_spawn_kenney_prop_local(desk, "furniture/computerMouse.glb", Vector3(0.4, 0.79, 0.14), 0, 0.65)
	_spawn_kenney_prop_local(desk, "furniture/plantSmall1.glb", Vector3(-0.6, 0.78, -0.18), 0, 0.4)
	room._add_local_box(desk, Vector3(0.52, 0.79, -0.1), Vector3(0.22, 0.025, 0.3), room._material(Color("d1d7c9")))
	room._add_local_box(desk, Vector3(0, 0.86, -0.22), Vector3(0.05, 0.18, 0.05), leg_mat)
	room._add_local_box(desk, Vector3(0, 0.782, -0.22), Vector3(0.28, 0.014, 0.18), leg_mat)



func _build_reception_desk(pos: Vector3) -> void:
	var counter: Material = room._material(Color("4d5a63"), 0.5, 0.2, true)
	var front: Material = room._material(Color("22303a"), 0.6, 0.1)
	room._add_box(pos + Vector3(0, 0.55, 0), Vector3(2.4, 1.1, 0.5), front)
	room._add_visual_box(pos + Vector3(0, 1.12, 0), Vector3(2.6, 0.05, 0.7), counter)
	room._add_box(pos + Vector3(1.45, 0.55, 0.85), Vector3(0.5, 1.1, 1.6), front)
	room._add_visual_box(pos + Vector3(1.45, 1.12, 0.85), Vector3(0.7, 0.05, 1.8), counter)


## Coin reprographie (decor) : meuble bas + imprimante multifonction.
func _build_printer_corner(pos: Vector3) -> void:
	var cabinet: Material = room._material(Color("627577"),0.8)
	room._add_box(pos+Vector3(0,0.35,0),Vector3(0.9,0.7,0.6),cabinet)
	var printer := Node3D.new()
	room.add_child(printer)
	printer.position = pos+Vector3(0,0.7,0)
	var shell: Material = room._material(Color("c7ceca"),0.75)
	var dark: Material = room._material(Color("273b43"),0.6)
	room._equipment_art.chassis(printer,Vector3(0,0.16,0),Vector3(0.56,0.32,0.46),shell,0.009)
	room._equipment_art.chassis(printer,Vector3(0,0.337,0),Vector3(0.58,0.028,0.48),dark,0.005)
	room._equipment_art.chassis(printer,Vector3(0,0.36,-0.025),Vector3(0.46,0.027,0.38),shell,0.005)
	room._add_local_box(printer,Vector3(0,0.20,0.236),Vector3(0.38,0.045,0.018),dark)
	room._add_local_box(printer,Vector3(0,0.183,0.29),Vector3(0.35,0.01,0.15),shell)
	room._add_local_box(printer,Vector3(0,0.195,0.29),Vector3(0.21,0.006,0.12),room._material(Color("edf0e5")))
	for y in [0.045,0.10]:
		room._add_local_box(printer,Vector3(0,y,0.232),Vector3(0.47,0.003,0.004),dark)
		room._add_local_box(printer,Vector3(0,y+0.02,0.237),Vector3(0.08,0.014,0.008),dark)
	room._add_local_box(printer,Vector3(0.19,0.28,0.234),Vector3(0.095,0.055,0.01),dark)
	room._add_display(printer,Vector3(0.19,0.28,0.241),Vector2(0.085,0.045))


func _add_wall_outlet(pos: Vector3, yaw := 0.0) -> void:
	room._fixed_network.outlet(pos, yaw)


func _add_plant(pos: Vector3) -> void:
	_spawn_kenney_prop("furniture/pottedPlant.glb", pos, pos.x, 1.6)
