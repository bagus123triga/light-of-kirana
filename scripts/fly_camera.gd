extends Camera3D

## LIGHT OF KIRANA — kamera saja (tanpa pemain, minta Bagus 2026-11-09:
## "aku cuma pengen pake kamera dulu aja").
## Mode cek dunia: kamera bebas terbang tanpa tabrakan. Joystick kiri +
## WASD gerak, Space/NAIK naik, C/TURUN turun, Shift/CEPAT cepat (25 m/s),
## drag kanan (atau mouse) lihat-lihat. Rumput gameidea didorong oleh
## posisi kamera (player_position shader).

const VirtualJoystickScript := preload("res://scripts/virtual_joystick.gd")

const FLY_SPEED := 10.0
const FLY_FAST := 25.0

var world: Node3D

var _yaw := 0.0
var _pitch := 18.0
var _joystick: VirtualJoystick
var _up_held := false
var _down_held := false
var _fast_toggle := false
var _mouse_look := false
var _look_touch_id := -1


func _ready() -> void:
	add_to_group("fly_camera")
	position = Vector3(0.0, 9.0, 20.0)
	_update_camera()
	_create_touch_controls()


func _process(delta: float) -> void:
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
	var fast := Input.is_key_pressed(KEY_SHIFT) or _fast_toggle
	var speed := FLY_FAST if fast else FLY_SPEED
	var basis := global_transform.basis
	var forward := -basis.z
	var right := basis.x
	var move := right * input_dir.x - forward * input_dir.y
	if _up_held or Input.is_key_pressed(KEY_SPACE):
		move.y += 1.0
	if _down_held or Input.is_key_pressed(KEY_C):
		move.y -= 1.0
	if move.length() > 1.0:
		move = move.normalized()
	global_position += move * speed * delta
	if world and world.has_method("set_interaction_position"):
		world.set_interaction_position(global_position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_look = event.pressed
	if event is InputEventMouseMotion and _mouse_look:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch - event.relative.y * 0.3, -80.0, 80.0)
		_update_camera()
	if event is InputEventScreenTouch:
		var viewport := get_viewport().get_visible_rect().size
		if event.pressed:
			if event.position.x >= viewport.x * 0.5 and _look_touch_id == -1:
				_look_touch_id = event.index
		else:
			if event.index == _look_touch_id:
				_look_touch_id = -1
	if event is InputEventScreenDrag and event.index == _look_touch_id:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch - event.relative.y * 0.3, -80.0, 80.0)
		_update_camera()


func _update_camera() -> void:
	rotation = Vector3(deg_to_rad(-_pitch), _yaw, 0.0)


func _create_touch_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_joystick = VirtualJoystick.new()
	layer.add_child(_joystick)
	var fast_btn := _make_button("CEPAT", Vector2(-292, -272))
	fast_btn.toggle_mode = true
	fast_btn.toggled.connect(func(on: bool) -> void: _fast_toggle = on)
	layer.add_child(fast_btn)
	var up_btn := _make_button("NAIK", Vector2(-172, -272))
	up_btn.button_down.connect(func() -> void: _up_held = true)
	up_btn.button_up.connect(func() -> void: _up_held = false)
	layer.add_child(up_btn)
	var down_btn := _make_button("TURUN", Vector2(-172, -152))
	down_btn.button_down.connect(func() -> void: _down_held = true)
	down_btn.button_up.connect(func() -> void: _down_held = false)
	layer.add_child(down_btn)


func _make_button(text: String, offset: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 96)
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = offset
	return b
