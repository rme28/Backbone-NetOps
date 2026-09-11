extends CharacterBody3D
## Controleur FPS : deplacement ZQSD (physique, independant du clavier) + vue souris.
## L'etat actif (souris capturee + entrees) est pilote par le niveau via set_active()
## pour le menu pause.

const SPEED := 5.0
const STANDING_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.0
const CROUCH_SPEED := 2.4
var crouched := false
@onready var collider: CollisionShape3D = $CollisionShape3D
var standing_shape := CapsuleShape3D.new()

@onready var camera: Camera3D = $Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	collider.shape = collider.shape.duplicate()
	standing_shape.radius = collider.shape.radius
	standing_shape.height = STANDING_HEIGHT - 0.03


## Active/desactive le joueur (mouvement, vue souris, capture du curseur).
func set_active(active: bool) -> void:
	set_physics_process(active)
	set_process_unhandled_input(active)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := 0.00005 * float(GameState.settings.get("mouse_sensitivity", 50.0))
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -1.4, 1.4)


func _physics_process(delta: float) -> void:
	update_stance(Input.is_action_pressed("crouch"), delta)
	var speed := CROUCH_SPEED if crouched else SPEED
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


func can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = global_transform
	query.transform.origin.y += 0.02
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func update_stance(request_crouch: bool, delta: float) -> void:
	crouched = request_crouch or not can_stand()
	var height := CROUCH_HEIGHT if crouched else STANDING_HEIGHT
	# Keep the capsule's feet fixed so lowering it never lifts the body.
	collider.shape.height = height
	collider.position.y = (height - STANDING_HEIGHT) * 0.5
	var eye := 0.6 - (STANDING_HEIGHT - height)
	camera.position.y = move_toward(camera.position.y, eye, delta * 4.5)
