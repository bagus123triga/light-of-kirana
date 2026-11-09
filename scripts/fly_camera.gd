extends Camera3D

## LIGHT OF KIRANA — kamera terbang v5 (REBUILD DARI 0).
## Mode kamera saja (tanpa pemain, minta Bagus 2026-11-09).
## Gerak: joystick kiri (layar sentuh) / WASD, 10 m/s (25 m/s kalau CEPAT/Shift).
## Naik/turun: tombol NAIK/TURUN (sentuh) / Space naik / C turun.
## Lihat: drag setengah kanan layar (sentuh) / drag mouse.
## Tanpa gravitasi/kolisi.

const MOVE_SPEED := 10.0
const FAST_SPEED := 25.0
const LOOK_SENS := 0.005

var _yaw := 0.0
var _pitch := -0.15
var _dragging := false
var _drag_id := -1
var _joystick: Control
var _btn_fast: Button
var _btn_up: Button
var _btn_down: Button
var _fast_held := false
var _up_held := false
var _down_held := false


func _ready() -> void:
	add_to_group("fly_camera")
	position = Vector3(0.0, 9.0, 20.0)
	far = 600.0
	_build_touch_ui()


func _build_touch_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TouchUI"
	add_child(layer)
	# Joystick kiri.
	var joy_script := load("res://scripts/virtual_joystick.gd")
	_joystick = Control.new()
	_joystick.set_script(joy_script)
	_joystick.name = "Joystick"
	_joystick.position = Vector2(40, 400)
	_joystick.size = Vector2(220, 220)
	layer.add_child(_joystick)
	# Tombol kanan: LARI (cepat), NAIK, TURUN.
	_btn_fast = _make_button(layer, "CEPAT", Vector2(1080, 620), Vector2(150, 70))
	_btn_up = _make_button(layer, "NAIK", Vector2(1080, 500), Vector2(150, 70))
	_btn_down = _make_button(layer, "TURUN", Vector2(1080, 740), Vector2(150, 70))
	_btn_fast.button_down.connect(func() -> void: _fast_held = true)
	_btn_fast.button_up.connect(func() -> void: _fast_held = false)
	_btn_up.button_down.connect(func() -> void: _up_held = true)
	_btn_up.button_up.connect(func() -> void: _up_held = false)
	_btn_down.button_down.connect(func() -> void: _down_held = true)
	_btn_down.button_up.connect(func() -> void: _down_held = false)


func _make_button(parent: Node, text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	parent.add_child(b)
	return b


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * LOOK_SENS
		_pitch = clampf(_pitch - mm.relative.y * LOOK_SENS, -1.5, 1.5)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var vp := get_viewport().get_visible_rect().size
		if st.position.x > vp.x * 0.5:
			if st.pressed:
				_drag_id = st.index
			elif st.index == _drag_id:
				_drag_id = -1
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _drag_id:
			_yaw -= sd.relative.x * LOOK_SENS
			_pitch = clampf(_pitch - sd.relative.y * LOOK_SENS, -1.5, 1.5)


func _process(delta: float) -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
	var input_dir := Vector2.ZERO
	if _joystick:
		input_dir = _joystick.output
	else:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var speed := FAST_SPEED if (_fast_held or Input.is_key_pressed(KEY_SHIFT)) else MOVE_SPEED
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var move := (right * input_dir.x) + (forward * -input_dir.y)
	var up := 0.0
	if _up_held or Input.is_key_pressed(KEY_SPACE):
		up += 1.0
	if _down_held or Input.is_key_pressed(KEY_C):
		up -= 1.0
	move.y += up
	if move.length() > 0.01:
		position += move.normalized() * speed * delta
