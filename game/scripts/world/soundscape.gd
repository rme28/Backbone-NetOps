extends Node
## Subtle local ambience and foley; obeys the existing Effects/Master volume buses.
var room: Node3D
var effects: AudioStreamPlayer
var steps: AudioStreamPlayer
var cooldown := 0.0
var step_index := 0
var streams: Dictionary = {}

func setup(host: Node3D) -> void:
	if DisplayServer.get_name() == "headless": return
	room = host
	for key in ["step", "plug", "ui", "fan"]:
		streams[key] = load("res://assets/audio/" + key + ".wav")
	effects = AudioStreamPlayer.new()
	effects.bus = "Effects"
	effects.volume_db = -20
	add_child(effects)
	steps = AudioStreamPlayer.new()
	steps.bus = "Effects"
	steps.volume_db = -23
	steps.stream = streams["step"]
	add_child(steps)
	var fan := AudioStreamPlayer3D.new()
	var loop: AudioStreamWAV = streams["fan"].duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = loop.data.size() / 2
	fan.stream = loop
	fan.bus = "Effects"
	fan.volume_db = -15
	fan.unit_size = 2.0
	fan.max_distance = 9.0
	room.add_child(fan)
	fan.position = Vector3(-5.2, 1.1, -8.5)
	fan.play()

func play(key: String) -> void:
	if effects == null: return
	effects.stream = streams[key]
	effects.play()

func _process(delta: float) -> void:
	if room == null: return
	cooldown -= delta
	var player: CharacterBody3D = room._player
	if not player.is_physics_processing() or not player.is_on_floor(): return
	if Vector2(player.velocity.x, player.velocity.z).length() < 0.3:
		cooldown = 0.0
		return
	if cooldown <= 0:
		step_index += 1
		steps.pitch_scale = 0.95 if step_index % 2 == 0 else 1.05
		steps.volume_db = -28 if player.global_position.z > 13.6 else -23
		steps.play()
		cooldown = 0.42
