@tool
class_name LFHeightLayer
extends Resource
## A landform (cliffs, gorges, valleys, dunes...): reshapes the land height where its mask allows.
## LFMapParams.landforms is an ordered list of them, applied after the hills and before the rivers and the
## coast (so rivers still cut through and the coast still caps the land). Subclass it: override `shape` (and
## `_make_noises` for your own noise, made with `noise()`). The generator works on its own copy of each layer
## (thread safe), so a layer may keep state made in `_make_noises`.

## Off: skipped, as if it were not in the list.
@export var enabled := true
## Seeds this layer's noise. Give each layer its own; changing it moves the features.
@export var id := "landform"

@export_group("Mask")
## Size of the patches where this landform appears: lower = bigger. 0 = everywhere.
@export var mask_freq := 0.0015
## Higher = fewer, smaller patches. Ignored when Mask Freq is 0.
@export var mask_from := 0.1
## Mask noise value where the landform is at full strength (see Mask From). Keep it above Mask From. Ignored
## when Mask Freq is 0.
@export var mask_to := 0.35
## Only in these biomes (by name). Empty = any biome.
@export var biomes: PackedStringArray = []

var _seed := 0
var _mask: FastNoiseLite


## Makes the noises for one world. The generator calls it on its own copy before any height is read.
func prepare(world_seed: int) -> void:
	_seed = world_seed
	_mask = noise("mask", mask_freq, 1) if mask_freq > 0.0 else null
	_make_noises()


## Override to make this layer's noises with noise().
func _make_noises() -> void:
	pass


## The new height at (x, z) where this landform is at full strength; `h` is the height so far. Override it.
func shape(_x: float, _z: float, h: float) -> float:
	return h


## How strongly the landform applies at (x, z) by its noise mask alone (0..1).
func mask_at(x: float, z: float) -> float:
	if _mask == null:
		return 1.0
	return smoothstep(mask_from, mask_to, _mask.get_noise_2d(x, z))


## A noise seeded from the world seed, this layer's id and `key`.
func noise(key: String, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = hash("%d/%s/%s" % [_seed, id, key])
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n
