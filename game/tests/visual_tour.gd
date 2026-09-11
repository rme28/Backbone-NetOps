extends RefCounted
## Deterministic real-renderer QA, no user save writes. Output directory must exist.
func run(room: Node3D, directory: String) -> void:
	room._player.set_active(false)
	var camera: Camera3D = room._player.get_node("Camera3D")
	var shots := [
		["01-concourse", Vector3(0, 1, 4), Vector3(0, 1.6, -7)],
		["02-network", Vector3(-4.9, 1, -5.5), Vector3(-5.6, 1.05, -8.6)],
		["03-offices", Vector3(-2.8, 1, 17.4), Vector3(-7, 1.0, 19.6)],
		["04-reception", Vector3(9, 1, 15), Vector3(5.5, 1.1, 19.3)],
		["05-breakroom", Vector3(11.2, 1, 2.8), Vector3(14.3, 1.1, -2)],
		["06-meeting", Vector3(4.4, 1, 2.7), Vector3(7, 1.0, 6)],
		["07-technician", Vector3(0.6, 1, -5.4), Vector3(0, 1.2, -7.2)],
	]
	for shot in shots:
		room._player.global_position = shot[1]
		camera.look_at(shot[2], Vector3.UP)
		await room.get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		room.get_viewport().get_texture().get_image().save_png(directory.path_join(shot[0] + ".png"))
		print("VISUAL %s: FPS=%d draws=%d objects=%d" % [shot[0], Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	room._open_terminal("SW-CORE")
	room._execute_terminal_command("show interfaces")
	await capture(room, directory, "08-terminal")
	room._close_terminal()
	room._toggle_palette()
	await capture(room, directory, "09-inventory")
	room._close_palette()
	room._toggle_pause()
	await capture(room, directory, "10-pause")
	room._open_game_settings()
	await capture(room, directory, "11-settings")
	room._close_game_settings()
	room._toggle_pause()
	room._open_technician_hub()
	await capture(room, directory, "12-hub")
	room.get_tree().quit()

func capture(room: Node3D, directory: String, label: String) -> void:
	await room.get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	room.get_viewport().get_texture().get_image().save_png(directory.path_join(label+".png"))

