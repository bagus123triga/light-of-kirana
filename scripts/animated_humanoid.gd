extends CharacterBody3D

## Animated humanoid controller for Light of Kirana.
## Character and motion clips are sourced from Quaternius / KinemIQ (CC0 1.0).
## Locomotion is in-place; CharacterBody3D owns world movement and collision.

const WALK_SPEED := 2.0
const RUN_SPEED := 5.5
const GRAVITY := 20.0
const JUMP_VELOCITY := 6.5
const ACCELERATION := 12.0
const BRAKING := 16.0

const IDLE := &"Idle_relaxed"
const WALK := &"Walk_forwards"
const JOG := &"Run_jog_forwards"
const SPRINT := &"Run_sprint"
const JUMP_TAKEOFF := &"Jump_take_off"
const JUMP_AIR := &"Jump_in_the_air"
const JUMP_LAND := &"Jump_landing"

enum JumpState { NONE, TAKEOFF, AIRBORNE, LANDING }

## Inputs set by main.gd (keyboard or virtual joystick).
var move_input := Vector2.ZERO
var wish_dir := Vector3.ZERO
var is_running := false
var want_jump := false

var jump_state: JumpState = JumpState.NONE
var _facing_yaw := 0.0
var _visual: Node3D
var _animation_player: AnimationPlayer


func _ready() -> void:
	floor_snap_length = 0.32
	floor_max_angle = deg_to_rad(45.0)
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

	var collision := CollisionShape3D.new()
	collision.name = "BodyCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.8
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.9, 0.0)
	add_child(collision)

	_visual = Node3D.new()
	_visual.name = "CharacterVisual"
	add_child(_visual)

	var character_scene: PackedScene = load("res://assets/characters/light_of_kirana_animated.glb")
	if character_scene == null:
		push_error("Missing animated character GLB at res://assets/characters/light_of_kirana_animated.glb.")
		return
	var character_instance := character_scene.instantiate()
	_visual.add_child(character_instance)

	var players := character_instance.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("Imported GLB has no AnimationPlayer.")
		return
	_animation_player = players[0] as AnimationPlayer
	_animation_player.animation_finished.connect(_on_animation_finished)

	for animation_name in [IDLE, WALK, JOG, SPRINT, JUMP_AIR]:
		if _animation_player.has_animation(animation_name):
			var animation: Animation = _animation_player.get_animation(animation_name)
			animation.loop_mode = Animation.LOOP_LINEAR

	_play_animation(IDLE, 1.0, 0.0)


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	var desired_speed := RUN_SPEED if is_running else WALK_SPEED
	var desired_horizontal := wish_dir * desired_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCELERATION if desired_horizontal.length() > horizontal.length() else BRAKING
	horizontal = horizontal.move_toward(desired_horizontal, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if not was_on_floor:
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var jump_requested := want_jump
	want_jump = false
	if jump_requested and was_on_floor and jump_state == JumpState.NONE:
		velocity.y = JUMP_VELOCITY
		jump_state = JumpState.TAKEOFF
		_play_animation(JUMP_TAKEOFF, 2.2, 0.08)

	if wish_dir.length() > 0.05:
		var target_yaw := atan2(wish_dir.x, wish_dir.z) + PI
		_facing_yaw = rotate_toward(_facing_yaw, target_yaw, 8.0 * delta)
	rotation.y = _facing_yaw

	move_and_slide()

	var on_floor_now := is_on_floor()
	if was_on_floor and not on_floor_now and jump_state == JumpState.NONE:
		jump_state = JumpState.AIRBORNE
		_play_animation(JUMP_AIR, 1.0, 0.12)
	elif not was_on_floor and on_floor_now and jump_state != JumpState.NONE:
		jump_state = JumpState.LANDING
		_play_animation(JUMP_LAND, 2.0, 0.08)

	if jump_state == JumpState.NONE:
		_update_locomotion_animation(horizontal.length())


func _update_locomotion_animation(horizontal_speed: float) -> void:
	if horizontal_speed < 0.12:
		_play_animation(IDLE, 1.0)
	elif is_running and horizontal_speed >= 4.3:
		_play_animation(SPRINT, clampf(horizontal_speed / 9.0, 0.5, 1.0))
	elif is_running:
		_play_animation(JOG, clampf(horizontal_speed / 6.0, 0.55, 1.15))
	else:
		_play_animation(WALK, clampf(horizontal_speed / 1.08, 0.65, 2.2))


func _play_animation(animation_name: StringName, playback_rate: float = 1.0, blend: float = 0.18) -> void:
	if _animation_player == null or not _animation_player.has_animation(animation_name):
		return
	if _animation_player.current_animation == animation_name and _animation_player.is_playing():
		_animation_player.speed_scale = playback_rate
		return
	_animation_player.speed_scale = playback_rate
	_animation_player.play(animation_name, blend)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == JUMP_TAKEOFF and jump_state == JumpState.TAKEOFF:
		if is_on_floor():
			jump_state = JumpState.LANDING
			_play_animation(JUMP_LAND, 2.0, 0.08)
		else:
			jump_state = JumpState.AIRBORNE
			_play_animation(JUMP_AIR, 1.0, 0.12)
	elif animation_name == JUMP_LAND and jump_state == JumpState.LANDING:
		jump_state = JumpState.NONE
		_update_locomotion_animation(Vector2(velocity.x, velocity.z).length())
