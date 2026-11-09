@tool
class_name LFGorgeLayer
extends LFHeightLayer
## Gorges: deep, steep-walled cuts that wind across the land along a noise line (like the rivers, but
## narrow and deep). A floor below the water level fills with water. Narrower than ~6 m reads as a V ditch
## on the 2 m grid.

## How deep the gorge cuts (m).
@export var depth := 14.0
## Half width of the flat floor (m). Keep it below Top Half.
@export var floor_half := 4.0
## Half the width at the top of the walls (m).
@export var top_half := 12.0
## Lower = gorges further apart (and more widely wound). Not a count.
@export var freq := 0.0009
## Lowest the floor may go (m; below 0 it holds water, 0 or more it stays dry).
@export var floor_min := -1.5

var _line: FastNoiseLite
var _warp: FastNoiseLite


func _init() -> void:
	id = "gorges"


func _make_noises() -> void:
	_line = noise("line", freq, 1)
	_warp = noise("warp", freq * 4.0, 2)


func shape(x: float, z: float, h: float) -> float:
	var wx := x + _warp.get_noise_2d(x, z) * 60.0
	var n := _line.get_noise_2d(wx, z)
	if absf(n) > 0.2:
		return h
	var gx := _line.get_noise_2d(wx + 2.0, z) - n
	var gz := _line.get_noise_2d(wx, z + 2.0) - n
	var g := maxf(sqrt(gx * gx + gz * gz) / 2.0, 0.0002)   # distance ~ |n| / |grad n|
	var d := absf(n) / g
	if d >= top_half:
		return h
	var bottom := maxf(h - depth, floor_min)
	return lerpf(bottom, h, smoothstep(floor_half, top_half, d))
