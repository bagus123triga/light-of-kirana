@tool
class_name LFValleyLayer
extends LFHeightLayer
## Valleys: broad, deep cuts hundreds of metres wide that wander across the land along a noise line (the wide
## cousin of LFGorgeLayer). The floor is flat-ish and dry (rivers and roads can use it), the sides rise
## gently or steeply as `side_curve` says. The floor lies `depth` m under the land it cuts through (never
## below `floor_min`), so it follows the land down toward the sea. Cost: four noise reads per sample.

## How deep the valley cuts (m).
@export_range(10.0, 400.0, 1.0, "or_greater", "suffix:m") var depth := 80.0
## Half width of the flat floor (m). Keep it below Top Half.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:m") var floor_half := 60.0
## Half the width of the valley at the top of its sides (m).
@export_range(20.0, 2000.0, 1.0, "or_greater", "suffix:m") var top_half := 260.0
## Shape of the sides: 1 = an even S curve, below 1 = steep near the floor and easing out at the top (a canyon),
## above 1 = gentle near the floor and steepening toward the rim (a bowl).
@export_range(0.3, 3.0, 0.05) var side_curve := 1.0
## Lower = valleys further apart. Not a count.
@export var freq := 0.0006
## How far the valley line wanders sideways (m): 0 = it follows the noise line smoothly.
@export_range(0.0, 600.0, 1.0, "or_greater", "suffix:m") var wander := 140.0
## Lowest the floor may go (m; above 0 it stays dry for rivers and roads).
@export var floor_min := 2.0

var _line: FastNoiseLite
var _warp: FastNoiseLite
var _reach := 0.0   # |noise| beyond which no valley can be (a generous bound on top_half x gradient)


func _init() -> void:
	id = "valleys"
	mask_freq = 0.0   # valleys run all over the land unless a mask is asked for


func _make_noises() -> void:
	_line = noise("line", freq, 1)
	_warp = noise("warp", freq * 3.0, 2)
	_reach = minf(top_half * freq * 6.0, 1.0)


func shape(x: float, z: float, h: float) -> float:
	var wx := x + _warp.get_noise_2d(x, z) * wander
	var n := _line.get_noise_2d(wx, z)
	if absf(n) > _reach:
		return h
	var step := 4.0
	var gx := _line.get_noise_2d(wx + step, z) - n
	var gz := _line.get_noise_2d(wx, z + step) - n
	var g := maxf(sqrt(gx * gx + gz * gz) / step, freq * 0.5)   # distance ~ |n| / |grad n|; the floor on the gradient keeps it continuous where the noise is flat
	var d := absf(n) / g
	if d >= top_half:
		return h
	var bottom := minf(maxf(h - depth, floor_min), h)
	var t := clampf((d - floor_half) / maxf(top_half - floor_half, 1.0), 0.0, 1.0)
	return lerpf(bottom, h, smoothstep(0.0, 1.0, pow(t, side_curve)))
