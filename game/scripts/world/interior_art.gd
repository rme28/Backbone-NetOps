extends RefCounted
## Architectural dressing only. Equipment, ports and event replay belong to server_room.
var room: Node3D
var mats: Dictionary = {}

func _init(host: Node3D) -> void:
	room = host
	mats["wall"] = surface("d3d5ce", 0.9, 0.0, 70.0)
	mats["floor"] = surface("899b9c", 0.8, 0.12, 95.0)
	mats["wood"] = surface("af855b", 0.75, 0.0, 5.0, Vector3(0.2, 6, 6))
	mats["carpet"] = surface("4d6266", 1.0, 0.0, 140.0)
	mats["metal"] = room._material(Color("273b43"), 0.45, 0.6)
	mats["trim"] = room._material(Color("52666d"), 0.6, 0.35)
	mats["ceiling"] = surface("b4bdb9", 0.95, 0.0, 100.0)
	var glass: StandardMaterial3D = room._material(Color(0.42, 0.65, 0.69, 0.16), 0.2, 0.1).duplicate()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["glass"] = glass

func surface(hex: String, rough: float, metal: float, frequency: float, stretch := Vector3.ONE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(hex)
	mat.roughness = rough
	mat.metallic = metal
	var noise := FastNoiseLite.new()
	noise.seed = 481
	noise.frequency = frequency / 512.0
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	texture.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.93, 0.92))
	ramp.set_color(1, Color(1, 1, 1))
	texture.color_ramp = ramp
	mat.albedo_texture = texture
	mat.uv1_triplanar = true
	mat.uv1_scale = stretch
	return mat

func box(pos: Vector3, size: Vector3, material: String, solid := false) -> void:
	if solid: room._add_box(pos, size, mats[material])
	else: room._add_visual_box(pos, size, mats[material])

func prop(asset: String, pos: Vector3, yaw := 0.0, scale_factor := 1.0) -> Node3D:
	return room._spawn_kenney_prop("furniture/" + asset + ".glb", pos, yaw, scale_factor)

func build() -> void:
	box(Vector3(0, -0.1, 0), Vector3(20, 0.2, 20), "floor", true)
	box(Vector3(0, 1.5, -10), Vector3(20, 3, 0.2), "wall", true)
	box(Vector3(-10, 1.5, 0), Vector3(0.2, 3, 20), "wall", true)
	for x in [-5.6, 5.6]: box(Vector3(x, 1.5, 10), Vector3(8.8, 3, 0.2), "wall", true)
	for z in [-5.75, 5.75]: box(Vector3(10, 1.5, z), Vector3(0.2, 3, 8.5), "wall", true)
	box(Vector3(0, 3.05, 0), Vector3(20, 0.1, 20), "ceiling")
	# Small raised-floor tiles, fine joints; repeated meshes share their material.
	for x in range(-10, 11): box(Vector3(x, 0.005, 0), Vector3(0.008, 0.008, 20), "trim")
	for z in range(-10, 11): box(Vector3(0, 0.006, z), Vector3(20, 0.008, 0.008), "trim")
	ceiling_grid(Vector3.ZERO, Vector2(20, 20))
	for x in [-6.0, 0.0, 6.0]:
		for z in [-7.0, 0.0, 7.0]: room._add_zone_light(Vector3(x, 2.76, z), Color("e3f0f1"), 0.8, 6.0)
	# Northern rooms: accessible rack room and operations workshop, visible from the concourse.
	partition(Vector3(-6, 0, -3.5), 8.0, 0.0, true)
	partition(Vector3(4, 0, -3.5), 12.0, 0.0, true)
	partition(Vector3(-2, 0, -6.75), 6.5, PI / 2, false)
	room._add_signage(Vector3(-6, 2.88, -3.425), "01  /  NETWORK", Color("bfe4df"))
	room._add_signage(Vector3(4, 2.88, -3.425), "02  /  OPERATIONS", Color("bfe4df"))
	# Existing starter equipment stays in place, with working clearance around every face.
	for x in [-8.2, -2.8]: cooling(Vector3(x, 0, -9.55))
	cable_tray(Vector3(-6, 2.55, -8.6), 7.0)
	for x in [-6.0, -4.2]:
		box(Vector3(x, 0.014, -8.1), Vector3(1.0, 0.018, 2.3), "carpet")
	# Workbench and spares fill the workshop's side wall, leaving the technician console accessible.
	workbench(Vector3(6.5, 0, -8.6))
	for x in [4.5, 6.0, 7.5]:
		prop("cardboardBoxClosed", Vector3(x, 0, -9.3), 0.12, 0.8)
	room._build_office_desk(Vector3(6.8, 0, -5.1), PI)
	# South-east meeting area, clear main north/south circulation through x=0.
	partition(Vector3(3.3, 0, 5.0), 7.0, PI / 2, true)
	box(Vector3(6.6, 0.013, 5.3), Vector3(6.4, 0.015, 7.5), "carpet")
	meeting(Vector3(6.8, 0, 5.5))
	# Assembly island, anchored to the west wall; center aisle remains free.
	room._build_office_desk(Vector3(-6.7, 0, 0.5), 0)
	room._build_office_desk(Vector3(-4.5, 0, 0.5), 0)
	box(Vector3(-5.6, 0.012, 0.7), Vector3(5.5, 0.014, 3.0), "carpet")
	prop("coatRackStanding", Vector3(-9.2, 0, 2.8), 0, 1.7)
	# South-west staging area for future deployments.
	workbench(Vector3(-7.5, 0, 7.9))
	prop("bookcaseOpen", Vector3(-9.3, 0, 5.7), PI / 2, 1.8)
	for z in [5.3, 6.2, 7.2]: prop("cardboardBoxClosed", Vector3(-8.7, 0, z), z, 0.7)
	room._add_plant(Vector3(-3.0, 0, 8.7))
	room._add_signage(Vector3(-6.5, 2.1, 9.82), "STAGING / DEPLOYMENT", Color("bfe4df"), PI)
	# Baseboards and pilasters break long flat walls.
	for x in [-9.85, 9.85]:
		box(Vector3(x, 0.09, -5.8), Vector3(0.08, 0.18, 8.2), "trim")
		box(Vector3(x, 0.09, 5.8), Vector3(0.08, 0.18, 8.2), "trim")
		for z in [-9.7, -3.5, 3.5, 9.7]: box(Vector3(x, 1.5, z), Vector3(0.15, 3.0, 0.2), "trim")
	box(Vector3(0, 0.09, -9.85), Vector3(20, 0.18, 0.08), "trim")
	room._build_annex_room(mats["wall"], mats["ceiling"])
	room._build_south_wing(mats["wall"], mats["ceiling"])
	south_details()

func ceiling_grid(center: Vector3, size: Vector2) -> void:
	for x in range(int(-size.x / 2), int(size.x / 2) + 1, 2):
		box(center + Vector3(x, 2.985, 0), Vector3(0.025, 0.025, size.y), "trim")
	for z in range(int(-size.y / 2), int(size.y / 2) + 1, 2):
		box(center + Vector3(0, 2.985, z), Vector3(size.x, 0.025, 0.025), "trim")

func partition(pos: Vector3, width: float, yaw: float, doorway: bool) -> void:
	var root := Node3D.new()
	room.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var count := int(ceil(width / 1.3))
	var step := width / count
	for i in count:
		var x := -width / 2 + step * (i + 0.5)
		if doorway and absf(x) < 1.05: continue
		room._add_local_box(root, Vector3(x, 1.45, 0), Vector3(step - 0.045, 2.45, 0.02), mats["glass"])
		for y in [0.12, 1.05, 2.72]: room._add_local_box(root, Vector3(x, y, 0), Vector3(step, 0.055, 0.07), mats["metal"])
		room._add_local_box(root, Vector3(x - step / 2, 1.4, 0), Vector3(0.04, 2.7, 0.08), mats["metal"])
		# Frosted band doubles as a collision visibility cue.
		room._add_local_box(root, Vector3(x, 1.1, 0.017), Vector3(step - 0.05, 0.14, 0.007), mats["trim"])
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(step, 2.7, 0.08)
		col.shape = shape
		body.add_child(col)
		root.add_child(body)
		body.position = Vector3(x, 1.35, 0)
	room._add_local_box(root, Vector3(0, 2.88, 0), Vector3(width, 0.24, 0.12), mats["metal"])

func cooling(pos: Vector3) -> void:
	box(pos + Vector3(0, 1.05, 0), Vector3(0.7, 2.1, 0.42), "wall", true)
	for i in 22: box(pos + Vector3(0, 0.4 + i * 0.063, 0.22), Vector3(0.56, 0.021, 0.03), "metal")
	room._add_signage(pos + Vector3(0, 1.9, 0.225), "AIR / 22°C", Color("bad8d8"))

func cable_tray(pos: Vector3, length: float) -> void:
	for z in [-0.18, 0.18]: box(pos + Vector3(0, 0, z), Vector3(length, 0.1, 0.025), "metal")
	for i in int(length * 4): box(pos + Vector3(-length / 2 + i * 0.25, -0.035, 0), Vector3(0.025, 0.025, 0.36), "trim")
	for x in [-length / 2 + 0.3, length / 2 - 0.3]: box(pos + Vector3(x, 0.22, 0), Vector3(0.02, 0.45, 0.02), "trim")
	for z in [-0.10, 0.0, 0.1]:
		room._add_visual_box(pos + Vector3(0, 0.01, z), Vector3(length, 0.022, 0.025), room._material(Color("477f91"), 0.75))

func workbench(pos: Vector3) -> void:
	box(pos + Vector3(0, 0.85, 0), Vector3(3.2, 0.07, 0.85), "wood", true)
	for x in [-1.4, 1.4]: box(pos + Vector3(x, 0.41, 0), Vector3(0.1, 0.82, 0.7), "metal", true)
	box(pos + Vector3(0, 0.25, 0), Vector3(2.8, 0.04, 0.7), "trim")
	for x in [-0.9, 0.2, 1.0]: prop("cardboardBoxOpen", pos + Vector3(x, 0.3, 0), 0, 0.5)
	prop("books", pos + Vector3(-1, 0.89, 0), 0, 0.8)
	room._add_wall_outlet(Vector3(pos.x, 1.08, -9.895 if pos.z < 0 else 9.895), 0.0 if pos.z < 0 else PI)

func meeting(pos: Vector3) -> void:
	box(pos + Vector3(0, 0.76, 0), Vector3(2.0, 0.08, 3.0), "wood", true)
	for z in [-1.1, 1.1]: box(pos + Vector3(0, 0.37, z), Vector3(1.3, 0.74, 0.08), "metal", true)
	for z in [-0.9, 0.9]:
		prop("chairDesk", pos + Vector3(-1.45, 0, z), PI / 2, 1.25)
		prop("chairDesk", pos + Vector3(1.45, 0, z), -PI / 2, 1.25)
	prop("plantSmall1", pos + Vector3(0, 0.8, 0), 0, 0.55)
	box(Vector3(9.82, 1.65, 5.5), Vector3(0.08, 1.1, 2.1), "metal")
	var screen := Node3D.new()
	room.add_child(screen)
	screen.position = Vector3(9.775,1.65,5.5)
	screen.rotation.y = -PI / 2
	room._add_display(screen, Vector3.ZERO, Vector2(1.96,0.96))

func south_details() -> void:
	ceiling_grid(Vector3(0, 0, 17.4), Vector2(20, 7))
	# Window bays: inset glazing, mullions, sill and venetian blinds.
	for x in [-7.5, -3.8, 0.0]: window_bay(Vector3(x, 1.8, 21.04), PI)
	for z in [-2.5, 2.5]: window_bay(Vector3(17.84, 1.8, z), -PI / 2)
	for x in [-8.5, -1.0]:
		prop("pottedPlant", Vector3(x, 0, 14.5), 0, 1.6)
	for z in [15.4, 18.2]:
		box(Vector3(-1.8, 0.425, z), Vector3(0.12, 0.85, 1.9), "trim", true)
		box(Vector3(-1.8, 0.9, z), Vector3(0.28, 0.045, 1.95), "wood")
		for dz in [-0.5, 0.5]: prop("plantSmall1", Vector3(-1.8, 0.93, z + dz), 0, 0.65)
	box(Vector3(5.3, 0.013, 19.1), Vector3(3.7, 0.015, 2.7), "carpet")
	prop("loungeDesignSofa", Vector3(4.4, 0, 19.6), PI / 2, 1.4)
	prop("tableCoffee", Vector3(5.8, 0, 19.6), 0, 1.15)
	prop("plantSmall1", Vector3(5.8, 0.5, 19.6), 0, 0.6)
	window_bay(Vector3(9.84, 1.8, 18.7), -PI / 2)
	box(Vector3(3.13, 1.5, 17.8), Vector3(0.05, 2.6, 3.6), "metal")
	room._add_signage(Vector3(3.18, 1.9, 17.8), "BACKBONE  /  CONNECTED WORKPLACES", Color("e0d3b8"), PI / 2)
	prop("plantSmall1", Vector3(6.9, 1.15, 17.1), 0, 0.6)
	box(Vector3(5.5, 1.38, 16.8), Vector3(0.55, 0.34, 0.035), "metal")
	box(Vector3(5.5, 1.21, 16.8), Vector3(0.06, 0.2, 0.08), "metal")
	room._add_display(room, Vector3(5.5, 1.38, 16.823), Vector2(0.51, 0.3))
	# Entry door mullions and pull handles, fixed architectural entrance.
	for x in [6.45, 7.5, 8.55]: box(Vector3(x, 1.25, 20.99), Vector3(0.06, 2.5, 0.04), "trim")
	for x in [7.36, 7.64]: box(Vector3(x, 1.1, 20.94), Vector3(0.025, 0.42, 0.045), "wall")
	# Warm timber reception fascia.
	for i in 27: box(Vector3(4.44 + i * 0.09, 0.57, 16.325), Vector3(0.035, 1.0, 0.04), "wood")
	for x in [11.8, 12.8, 13.8]: prop("kitchenCabinetDrawer", Vector3(x, 0, -4.0), 0, 1.25)
	prop("kitchenCoffeeMachine", Vector3(12.8, 0.78, -3.9), 0, 0.8)
	prop("kitchenFridgeSmall", Vector3(15.7, 0, -3.9), 0, 1.5)
	prop("trashcan", Vector3(16.7, 0, -3.7), 0, 1.2)
	for z in [14.5, 17.5, 20.3]: box(Vector3(-9.84, 0.1, z), Vector3(0.08, 0.2, 2.6), "trim")

func window_bay(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	room.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var daylight: StandardMaterial3D = room._material(Color("a5c5cb"), 0.7, 0.0, false, Color("73949c"), 0.35)
	room._add_local_box(root, Vector3.ZERO, Vector3(2.8, 1.6, 0.025), daylight)
	for x in [-1.44, 0.0, 1.44]: room._add_local_box(root, Vector3(x, 0, 0.045), Vector3(0.065, 1.7, 0.09), mats["metal"])
	for y in [-0.85, 0.85]: room._add_local_box(root, Vector3(0, y, 0.08), Vector3(2.95, 0.075, 0.2), mats["wall"])
	for i in 12: room._add_local_box(root, Vector3(0, 0.74 - i * 0.13, 0.07), Vector3(2.8, 0.025, 0.095), mats["ceiling"])

## Batch static box dressing into spatial MultiMeshes; collisions stay in place.
## Cell-local batches keep frustum culling useful. Glass is left separately sorted.
func optimize_static() -> void:
	var groups: Dictionary = {}
	_collect_boxes(room, groups)
	for key in groups:
		var entries: Array = groups[key]
		if entries.size() < 3: continue
		var source: MeshInstance3D = entries[0]
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = source.mesh.material
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = entries.size()
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = multi
		batch.name = "StaticBatch"
		room.add_child(batch)
		for i in entries.size():
			var item: MeshInstance3D = entries[i]
			multi.set_instance_transform(i, item.global_transform.scaled_local(item.mesh.size))
			item.queue_free()

func _collect_boxes(root: Node, groups: Dictionary) -> void:
	if root.has_meta("device_name") or root is CharacterBody3D: return
	if root is MeshInstance3D and root.mesh is BoxMesh:
		var mat: Material = root.mesh.material
		if mat is StandardMaterial3D and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			var pos: Vector3 = root.global_position
			var key := "%s/%d/%d" % [mat.get_instance_id(), floori(pos.x / 5), floori(pos.z / 5)]
			if not groups.has(key): groups[key] = []
			groups[key].append(root)
	for child in root.get_children(): _collect_boxes(child, groups)
