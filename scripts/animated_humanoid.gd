extends CharacterBody3D

## Animated humanoid controller for Light of Kirana.
## Character and motion clips are sourced from Quaternius / KinemIQ (CC0 1.0).
## Locomotion is in-place; CharacterBody3D owns world movement and collision.

const WALK_SPEED := 2.0
const RUN_SPEED := 5.5
const GRAVITY := 22.0
const JUMP_VELOCITY := 7.0

# Ground movement has deliberate acceleration, strong stopping friction,
# and a quicker response when the player reverses direction.
const GROUND_ACCELERATION := 14.0
const GROUND_FRICTION := 26.0
const DIRECTION_CHANGE_ACCELERATION := 24.0

# In the air, preserve momentum and allow only limited steering.
const AIR_ACCELERATION := 3.5
const AIR_DRAG := 0.7

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

# Locomotion clips swap only at cycle boundaries to avoid cutting steps short.
var _pending_locomotion_animation: StringName = &""
var _target_animation_rate := 1.0
var _locomotion_stop_time := 0.0


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
	var has_move_input := wish_dir.length_squared() > 0.0025

	if was_on_floor:
		if has_move_input:
			var reversing := horizontal.length_squared() > 0.04 and horizontal.normalized().dot(desired_horizontal.normalized()) < -0.15
			var acceleration := DIRECTION_CHANGE_ACCELERATION if reversing else GROUND_ACCELERATION
			horizontal = horizontal.move_toward(desired_horizontal, acceleration * delta)
		else:
			# Strong ground friction prevents skating after releasing the stick.
			horizontal = horizontal.move_toward(Vector3.ZERO, GROUND_FRICTION * delta)
	else:
		if has_move_input:
			horizontal = horizontal.move_toward(desired_horizontal, AIR_ACCELERATION * delta)
		else:
			# Keep most horizontal momentum while airborne.
			horizontal = horizontal.move_toward(Vector3.ZERO, AIR_DRAG * delta)

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
		var target_yaw := atan2(wish_dir.x, wish_dir.z)
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
		_update_locomotion_animation(horizontal.length(), delta)
		_advance_locomotion_animation(delta)


func _update_locomotion_animation(horizontal_speed: float, delta: float = 0.016) -> void:
	var has_input := wish_dir.length_squared() > 0.0025
	var desired_animation: StringName = IDLE
	var desired_rate := 1.0

	if has_input:
		_locomotion_stop_time = 0.0
		if is_running:
			# Hysteresis prevents rapid jog/sprint switching near the threshold.
			if _animation_player.current_animation == SPRINT:
				desired_animation = SPRINT if horizontal_speed > 3.9 else JOG
			else:
				desired_animation = SPRINT if horizontal_speed >= 4.8 else JOG
			desired_rate = clampf(horizontal_speed / (RUN_SPEED if desired_animation == SPRINT else 3.8), 0.85, 1.15)
		else:
			desired_animation = WALK
			desired_rate = clampf(horizontal_speed / WALK_SPEED, 0.85, 1.15)
	else:
		# Continue the current step cycle while braking; idle starts only
		# after the body has stopped for a brief stable interval.
		if horizontal_speed > 0.10:
			_locomotion_stop_time = 0.0
			desired_animation = _animation_player.current_animation
			if desired_animation == &"" or desired_animation == IDLE:
				desired_animation = WALK
		else:
			_locomotion_stop_time += delta
			desired_animation = IDLE if _locomotion_stop_time >= 0.12 else _animation_player.current_animation
			if desired_animation == &"":
				desired_animation = IDLE

	_target_animation_rate = desired_rate
	if desired_animation != _animation_player.current_animation:
		_pending_locomotion_animation = desired_animation
	elif _pending_locomotion_animation != &"":
		_pending_locomotion_animation = &""


func _advance_locomotion_animation(delta: float) -> void:
	if _animation_player == null:
		return

	# Smooth playback-rate changes instead of changing speed_scale abruptly.
	_animation_player.speed_scale = move_toward(_animation_player.speed_scale, _target_animation_rate, 2.5 * delta)
	if _pending_locomotion_animation == &"":
		return

	var current_name := _animation_player.current_animation
	if current_name == &"" or not _animation_player.is_playing():
		var next_name := _pending_locomotion_animation
		_pending_locomotion_animation = &""
		_play_animation(next_name, _target_animation_rate, 0.16)
		return

	var current_clip: Animation = _animation_player.get_animation(current_name)
	if current_clip == null or current_clip.length <= 0.0:
		return
	var remaining := current_clip.length - _animation_player.current_animation_position
	if remaining <= maxf(delta * _animation_player.speed_scale, 0.035):
		var next_name := _pending_locomotion_animation
		_pending_locomotion_animation = &""
		_play_animation(next_name, _target_animation_rate, 0.16)


func _play_animation(animation_name: StringName, playback_rate: float = 1.0, blend: float = 0.18) -> void:
	if _animation_player == null or not _animation_player.has_animation(animation_name):
		return
	_pending_locomotion_animation = &""
	_target_animation_rate = playback_rate
	_animation_player.speed_scale = playback_rate
	if _animation_player.current_animation == animation_name and _animation_player.is_playing():
		return
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
		_locomotion_stop_time = 0.0
		_update_locomotion_animation(Vector2(velocity.x, velocity.z).length(), 0.016)
		_advance_locomotion_animation(0.016)
