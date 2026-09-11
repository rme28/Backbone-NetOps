extends SceneTree

var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
	print("PLAYER ", label, ": ", value)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player = load("res://scenes/player/player.tscn").instantiate()
	world.add_child(player)
	player.position = Vector3(0, 0.91, 0)
	player.set_active(false)
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(10, 0.2, 10)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	world.add_child(floor_body)
	floor_body.position.y = -0.1
	await physics_frame
	await physics_frame
	player.update_stance(true, 0.02)
	check(player.crouched and player.camera.position.y > -0.2, "smooth camera descent")
	for i in 20: player.update_stance(true, 0.02)
	check(is_equal_approx(player.collider.position.y - player.collider.shape.height / 2, -0.9), "feet unchanged")
	var ceiling := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 0.2, 3)
	col.shape = shape
	ceiling.add_child(col)
	world.add_child(ceiling)
	ceiling.position.y = 1.3
	await physics_frame
	await physics_frame
	player.update_stance(false, 0.2)
	check(player.crouched, "cannot stand under obstacle")
	ceiling.position.x = 8
	await physics_frame
	await physics_frame
	player.update_stance(false, 0.2)
	check(not player.crouched and is_equal_approx(player.camera.position.y, 0.6), "stand after clearing obstacle")
	check(InputMap.has_action("crouch"), "input action registered")
	world.queue_free()
	await process_frame
	print("PLAYER failures=", failures)
	quit(0 if failures.is_empty() else 1)
