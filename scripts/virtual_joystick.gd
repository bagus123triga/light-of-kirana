extends Control
class_name KiranaVirtualJoystick

## Analog virtual kiri: seret knob, output -1..1 (y ke bawah = +).
## Menangani InputEventScreenTouch langsung (emulate_mouse_from_touch MATI,
## lihat project.godot) supaya multi-touch dengan tombol + kamera tidak mati.

const RADIUS := 90.0
const KNOB_RADIUS := 42.0
const MAX_OFFSET := 60.0

var output := Vector2.ZERO

var _active := false
var _touch_index := -1


func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(event.position)
		elif _touch_index == -1:
			_end()
	elif event is InputEventMouseMotion and _active and _touch_index == -1:
		_move(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_begin(event.position)
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_end()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_move(event.position)


func _input(event: InputEvent) -> void:
	# Lepas di luar area joystick tetap harus mengakhiri drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _active and _touch_index == -1:
			_end()
	elif event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		_touch_index = -1
		_end()


func _begin(pos: Vector2) -> void:
	_active = true
	_move(pos)


func _move(pos: Vector2) -> void:
	var d := pos - size * 0.5
	if d.length() > MAX_OFFSET:
		d = d.normalized() * MAX_OFFSET
	output = d / MAX_OFFSET
	queue_redraw()


func _end() -> void:
	_active = false
	output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(c, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	var knob := c + output * MAX_OFFSET
	draw_circle(knob, KNOB_RADIUS, Color(1, 1, 1, 0.35))
	draw_arc(knob, KNOB_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)
