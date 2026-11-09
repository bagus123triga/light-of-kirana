extends Control
class_name KiranaTouchButton

## Round touch button that handles InputEventScreenTouch directly
## (emulate_mouse_from_touch is OFF, see project.godot, so Button alone
## would miss multi-touch). Works with mouse too, for desktop testing.

signal pressed_down
signal released_up

var label_text := "BTN"
var _touch_index := -1
var _held := false


func _ready() -> void:
	custom_minimum_size = Vector2(96, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var col := Color(0.35, 0.35, 0.35, 0.75) if not _held else Color(0.55, 0.55, 0.55, 0.85)
	draw_circle(c, r, col)
	draw_arc(c, r, 0, TAU, 48, Color(0.85, 0.85, 0.85, 0.9), 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-28, 6), label_text, HORIZONTAL_ALIGNMENT_CENTER, 56, 20, Color(0.95, 0.95, 0.95))


func _set_held(value: bool) -> void:
	if _held == value:
		return
	_held = value
	queue_redraw()
	if _held:
		pressed_down.emit()
	else:
		released_up.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_held(event.pressed)
	elif event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_set_held(true)
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_set_held(false)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		_touch_index = -1
		_set_held(false)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _touch_index == -1:
			_set_held(false)
