extends RefCounted
## All dimensions in metres. Shared geometry for world equipment and inventory viewmodels.
var room: Node3D
var shell: Material
var dark: Material
var steel: Material
var ivory: Material
var meshes: Dictionary = {}

func _init(host: Node3D) -> void:
	room = host
	shell = room._material(Color("46565c"), 0.58, 0.45)
	dark = room._material(Color("111d23"), 0.8, 0.1)
	steel = room._material(Color("9da9a9"), 0.36, 0.7)
	ivory = room._material(Color("c7ceca"), 0.7, 0.05)

func dimensions(category: String) -> Vector3:
	match category:
		"switch", "switch_l3": return Vector3(0.44, 0.044, 0.28)
		"router": return Vector3(0.43, 0.044, 0.26)
		"firewall": return Vector3(0.3, 0.044, 0.22)
		"wireless_router": return Vector3(0.24, 0.045, 0.16)
		"access_point": return Vector3(0.20, 0.038, 0.20)
		"pc": return Vector3(0.21, 0.42, 0.38)
		"server": return Vector3(0.24, 0.70, 0.55)
		"nas": return Vector3(0.22, 0.24, 0.25)
		"client_laptop": return Vector3(0.34, 0.24, 0.24)
	return Vector3(0.4, 0.1, 0.3)

func offset(category: String, compact: bool) -> Vector3:
	var size := dimensions(category)
	if category in ["pc", "server", "nas"]: return Vector3(0, size.y / 2 - 0.41, 0)
	if compact: return Vector3(0, 0, 0.32 - size.z / 2)
	return Vector3.ZERO

func port_position(category: String, index: int, count: int, compact: bool) -> Vector3:
	var size := dimensions(category)
	var pos := Vector3((index - (count - 1) / 2.0) * 0.035, 0, size.z / 2 + 0.004)
	if category in ["switch", "switch_l3", "router"]: pos.x += 0.085
	if category in ["pc", "server", "nas"]:
		pos.y = -size.y / 2 + 0.09
		pos.x = -size.x / 2 + 0.035 + index * 0.025
	if category == "client_laptop": pos = Vector3(-0.14 + index * 0.025, -0.105, 0.125)
	return pos + offset(category, compact)

func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	room._add_local_box(parent, pos, size, mat)

func text(parent: Node3D, value: String, pos: Vector3, scale_px := 0.00035) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = pos
	label.font_size = 24
	label.pixel_size = scale_px
	label.outline_size = 0
	label.modulate = Color("bccbc9")
	parent.add_child(label)

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	parent.add_child(node)
	return node

## Chamfered metal/plastic shell, cached per size/material.
func chassis(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, bevel := 0.003) -> void:
	var key := "%s/%s" % [size, mat.get_instance_id()]
	if not meshes.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rings: Array = []
		for layer in 4:
			var inset := bevel if layer in [0, 3] else 0.0
			var x := size.x / 2 - inset
			var z := size.z / 2 - inset
			var y: float = [-size.y / 2, -size.y / 2 + bevel, size.y / 2 - bevel, size.y / 2][layer]
			var ring: Array[Vector3] = []
			for v in [Vector2(x-bevel,z),Vector2(x,z-bevel),Vector2(x,-z+bevel),Vector2(x-bevel,-z),Vector2(-x+bevel,-z),Vector2(-x,-z+bevel),Vector2(-x,z-bevel),Vector2(-x+bevel,z)]:
				ring.append(Vector3(v.x, y, v.y))
			rings.append(ring)
		for j in 3:
			for i in 8:
				var n := (i + 1) % 8
				for v in [rings[j][i], rings[j+1][i], rings[j+1][n], rings[j][i], rings[j+1][n], rings[j][n]]: st.add_vertex(v)
		for i in range(1,7):
			for v in [rings[0][0], rings[0][i], rings[0][i+1], rings[3][0], rings[3][i+1], rings[3][i]]: st.add_vertex(v)
		st.generate_normals()
		st.set_material(mat)
		meshes[key] = st.commit()
	var node := MeshInstance3D.new()
	node.mesh = meshes[key]
	node.position = pos
	parent.add_child(node)

func jack(parent: Node3D, pos := Vector3.ZERO) -> void:
	# 18 mm shield, recessed 8P8C cavity and keyway, gold contacts.
	box(parent, pos, Vector3(0.018, 0.016, 0.012), steel)
	box(parent, pos + Vector3(0, 0.001, 0.0065), Vector3(0.014, 0.009, 0.001), dark)
	box(parent, pos + Vector3(0, -0.005, 0.0065), Vector3(0.007, 0.004, 0.001), dark)
	var gold: Material = room._material(Color("b39b58"), 0.45, 0.65)
	for i in 8:
		box(parent, pos + Vector3(-0.005 + i * 0.0014, 0.003, 0.0072), Vector3(0.0006, 0.003, 0.0005), gold)

func build(body: Node3D, category: String, compact: bool) -> void:
	var size := dimensions(category)
	var o := offset(category, compact)
	if category == "access_point":
		cylinder(body, o, 0.1, 0.026, ivory)
		cylinder(body, o + Vector3(0, 0.014, 0), 0.09, 0.006, ivory)
		cylinder(body, o + Vector3(0, 0.018, 0), 0.018, 0.001, room._material(Color("4f9695"),0.6))
	elif category == "client_laptop":
		chassis(body, Vector3(0,-0.105,0.025), Vector3(0.34,0.015,0.24), shell)
		chassis(body, Vector3(0,0.01,-0.09), Vector3(0.34,0.22,0.012), dark)
		room._add_display(body, Vector3(0,0.01,-0.082), Vector2(0.31,0.19))
		for x in 10:
			for y in 4: box(body,Vector3(-0.13+x*0.027,-0.096,-0.04+y*0.022),Vector3(0.021,0.002,0.016),dark)
		box(body,Vector3(0,-0.096,0.098),Vector3(0.09,0.001,0.045),dark)
	else:
		chassis(body, o, size, shell)
		chassis(body, o + Vector3(0,0,size.z/2), Vector3(size.x-0.008,size.y-0.008,0.006), dark, 0.001)
		if category in ["pc", "server", "nas"]:
			var front_z := size.z/2 + 0.005
			# Drive caddies and inset latch, vents, power control, feet.
			var drives := 4 if category == "server" else (2 if category == "nas" else 1)
			for i in drives:
				var y := size.y/2 - 0.05 - i*0.055
				box(body,o+Vector3(0,y,front_z),Vector3(size.x-0.045,0.04,0.008),shell)
				box(body,o+Vector3(size.x/2-0.04,y,front_z+0.005),Vector3(0.013,0.022,0.002),steel)
			for i in 12:
				box(body,o+Vector3(0,-size.y/2+0.13+i*0.006,front_z),Vector3(size.x-0.05,0.002,0.001),steel)
			var power := cylinder(body,o+Vector3(size.x/2-0.03,size.y/2-0.025,front_z+0.002),0.005,0.002,steel)
			power.rotation.x = PI/2
			for x in [-size.x/2+0.025,size.x/2-0.025]:
				box(body,o+Vector3(x,-size.y/2,0),Vector3(0.025,0.009,size.z-0.04),dark)
		else:
			# Front branding and rear ventilation slots, real single-unit silhouette.
			text(body, "BACKBONE", o+Vector3(-size.x/2+0.053,0,size.z/2+0.004),0.00022)
			for i in 14:
				box(body,o+Vector3(-size.x/2+0.03+i*0.013,size.y/2+0.0005,-size.z/2+0.05),Vector3(0.004,0.001,0.06),dark)
			for x in [-size.x/2+0.008,size.x/2-0.008]:
				text(body,"+",o+Vector3(x,0,size.z/2+0.004),0.0003)
			if category == "wireless_router":
				for x in [-0.09,0.09]:
					var antenna := cylinder(body,o+Vector3(x,0.09,-0.06),0.004,0.18,dark)
					antenna.rotation.z = -0.13 if x < 0 else 0.13
			if compact:
				for x in [-0.235,0.235]:
					box(body,Vector3(x,0,0.32),Vector3(0.02,0.044,0.006),steel)
					text(body,"+",Vector3(x,0,0.324),0.0003)

func batch(body: Node3D) -> void:
	var groups: Dictionary = {}
	_collect(body, groups)
	for key in groups:
		var items: Array = groups[key]
		if items.size() < 3: continue
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		cube.material = items[0].mesh.material
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = cube
		multi.instance_count = items.size()
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		body.add_child(node)
		for i in items.size():
			var item: MeshInstance3D = items[i]
			multi.set_instance_transform(i, (body.global_transform.affine_inverse()*item.global_transform).scaled_local(item.mesh.size))
			item.queue_free()

func _collect(root: Node, groups: Dictionary) -> void:
	if root is MeshInstance3D and root.mesh is BoxMesh and root.name != "PortLED":
		var mat: Material = root.mesh.material
		var key := mat.get_instance_id()
		if not groups.has(key): groups[key] = []
		groups[key].append(root)
	for child in root.get_children(): _collect(child, groups)
