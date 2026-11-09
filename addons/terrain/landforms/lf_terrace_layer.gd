@tool
class_name LFTerraceLayer
extends LFHeightLayer
## Cliffs and mesas: the land rises in flat steps with steep faces between them. The ground shading turns
## the faces to rock by slope. The heightmap is a 2 m grid, so a face is a steep slope, never an overhang.

## Height of one step (m). Taller steps make fewer, higher cliffs. At least 0.5 m (smaller is read as 0.5).
@export_range(0.5, 50.0, 0.5, "or_greater", "suffix:m") var step_height := 8.0
## Share of each step that is the face: 0.02 = sheer cliffs, 1 = gentle terraces (no flat tops left).
@export_range(0.02, 1.0, 0.01) var face := 0.2
## Land at or below this height (m) is left alone (keeps beaches and river banks). Steps start here.
@export var above := 3.0
## Noise that wobbles the step heights so the cliff lines wander (m). 0 = cliff lines follow the hills' contours.
@export var wobble := 2.0

var _wobble: FastNoiseLite


func _init() -> void:
	id = "terraces"


func _make_noises() -> void:
	_wobble = noise("wobble", 0.02, 2)


func shape(x: float, z: float, h: float) -> float:
	if h <= above:
		return h
	var step := maxf(step_height, 0.5)   # 0 from code would divide by zero
	var t := (h - above + _wobble.get_noise_2d(x, z) * wobble) / step
	var f := floorf(t)
	return above + (f + smoothstep(1.0 - face, 1.0, t - f)) * step
