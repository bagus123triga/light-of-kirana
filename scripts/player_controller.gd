extends CharacterBody3D

## Pemain kapsul sementara (model Kirana menyusul).
## WASD/panah + joystick kiri gerak, Shift / tombol LARI = lari,
## Space / LOMPAT = lompat, F / TEBAS = tebas pohon di depan.
## Kamera: drag kanan (sentuh/mouse). Langkah kaki bunyi per permukaan.

const WorldScript := preload("res://scripts/world.gd")

const WALK_SPEED := 4.0
const RUN_SPEED := 7.0
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8
const CAMERA_DISTANCE := 6.0
const ATTACK_RANGE := 2.6
const ATTACK_COOLDOWN := 0.45
const STEP_DISTANCE := 2.4

var world: Node3D
var ambience: Node

var _yaw := 0.0
var _pitch := 18.0
var _pivot: Node3D
var _camera: Camera3D
var _joystick: VirtualJoystick
var _run_toggle := false
var _attack_cooldown := 0.0
var _step_accum := 0.0
var _in_water := false
var _look_touch_id := -1
var _look_last := Vector2.ZERO
var _mouse_look := false


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.3
	# Visual kapsul + tabrakan.
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.7
	visual.mesh = mesh
	visual.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.35)
	visual.material_override = mat
	add_child(visual)
	# Kamera orbit.
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position.y = 1.4
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.0, CAMERA_DISTANCE)
	_pivot.add_child(_camera)
	_update_camera()
	_create_touch_controls()


func _create_touch_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_joystick = VirtualJoystick.new()
	_joystick.position = Vector2(72, -272)
	_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	layer.add_child(_joystick)
	var run_btn := _make_button("LARI", Vector2(-292, -272))
	run_btn.toggle_mode = true
	run_btn.toggled.connect(func(on: bool) -> void: _run_toggle = on)
	layer.add_child(run_btn)
	var jump_btn := _make_button("LOMPAT", Vector2(-172, -272))
	jump_btn.pressed.connect(_try_jump)
	jump_btn.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			_try_jump()
	)
	layer.add_child(jump_btn)
	var attack_btn := _make_button("TEBAS", Vector2(-172, -152))
	attack_btn.pressed.connect(try_attack)
	attack_btn.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			try_attack()
	)
	layer.add_child(attack_btn)


func _make_button(text: String, offset: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(104, 64)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = offset
	return btn


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_look = event.pressed
	if event is InputEventMouseMotion and _mouse_look:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.3, -10.0, 55.0)
		_update_camera()
	if event is InputEventScreenTouch:
		var viewport := get_viewport().get_visible_rect().size
		if event.pressed:
			if event.position.x >= viewport.x * 0.5 and _look_touch_id == -1:
				_look_touch_id = event.index
				_look_last = event.position
		else:
			if event.index == _look_touch_id:
				_look_touch_id = -1
	if event is InputEventScreenDrag and event.index == _look_touch_id:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch - event.relative.y * 0.3, -10.0, 55.0)
		_update_camera()


func _update_camera() -> void:
	_pivot.rotation.y = _yaw
	_pivot.rotation.x = deg_to_rad(-_pitch)


func _try_jump() -> void:
	if is_on_floor():
		velocity.y = JUMP_VELOCITY


func try_attack() -> void:
	if _attack_cooldown > 0.0 or world == null:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	var best: Node3D = null
	var best_d := ATTACK_RANGE
	var facing := -global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	for tree in world.trees:
		if tree.fallen:
			continue
		var to: Vector3 = tree.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > ATTACK_RANGE or d < 0.01:
			continue
		if facing.dot(to.normalized()) < 0.5:
			continue
		if d < best_d:
			best_d = d
			best = tree
	if best:
		best.chop(global_position)


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	if _joystick:
		input_dir += _joystick.output
	input_dir = input_dir.limit_length(1.0)
	var running := Input.is_key_pressed(KEY_SHIFT) or _run_toggle
	var speed := RUN_SPEED if running else WALK_SPEED
	# Berendam di danau: gerak melambat.
	var in_water_now := false
	if world:
		in_water_now = global_position.y < WorldScript.WATER_LEVEL + 0.05 and world.get_height(global_position.x, global_position.z) < WorldScript.WATER_LEVEL + 0.1
	if in_water_now and not _in_water and ambience and ambience.has_method("play_splash"):
		ambience.play_splash()
	_in_water = in_water_now
	if in_water_now:
		speed *= 0.55
	var forward := -_pivot.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := _pivot.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := Vector3.ZERO
	if input_dir.length() > 0.01:
		direction = (right * input_dir.x - forward * input_dir.y).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY
	if Input.is_key_pressed(KEY_F):
		try_attack()
	if direction.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 0.2)
		# Langkah kaki tiap jarak tempuh tertentu, bunyi ikut permukaan.
		_step_accum += direction.length() * speed * delta
		if _step_accum >= STEP_DISTANCE:
			_step_accum = 0.0
			if world and ambience and ambience.has_method("play_footstep"):
				ambience.play_footstep(world.get_ground_type(global_position.x, global_position.z))
	move_and_slide()
