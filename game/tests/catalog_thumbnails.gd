extends RefCounted
## Render inventory icons from the exact same meshes as the interactive equipment.
func run(room: Node3D, directory: String) -> void:
	var categories := ["switch","switch_l3","router","firewall","wireless_router","access_point","pc","server","nas","client_laptop","rack","table"]
	for category in categories:
		var view := SubViewport.new()
		view.size = Vector2i(192,128)
		view.own_world_3d = true
		view.transparent_bg = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		room.add_child(view)
		var root := Node3D.new()
		view.add_child(root)
		room._build_held_model(root, category)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35,-25,0)
		light.light_energy = 1.2
		root.add_child(light)
		var env := Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("c3d1d5")
		env.ambient_light_energy = 0.7
		var world := WorldEnvironment.new()
		world.environment = env
		root.add_child(world)
		var size: Vector3 = room._equipment_art.dimensions(category)
		var center: Vector3 = room._equipment_art.offset(category,false)
		if category == "rack": size = Vector3(0.64,1.9,0.72); center = Vector3.ZERO
		if category == "table": size = Vector3(1.6,0.8,0.9); center = Vector3(0,0.4,0)
		var distance := maxf(size.x, maxf(size.y, size.z)) * 2.2
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = center+Vector3(distance*0.5,distance*0.45,distance)
		camera.fov = 40
		camera.look_at(center,Vector3.UP)
		camera.make_current()
		await room.get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png(directory.path_join(category+".png"))
		view.queue_free()
	room.get_tree().quit()
