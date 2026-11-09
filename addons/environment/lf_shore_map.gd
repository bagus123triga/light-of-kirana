class_name LFShoreMap
extends RefCounted
## The ground height round the focus as a small float texture, so water.gdshader knows how deep the water is
## under each vertex and where the shore lies: waves grow and break in the shallows and wash up the beach.
## Copied from the loaded chunks' height grids (no height sampling), 7 x 7 chunks at the 2 m vertex step.
## LFWorld owns one and calls update() every frame; it rebuilds only when the window moves or a chunk in it
## loads or unloads. Without it (a baked map) the shader keeps its open-water waves and the plain shore foam.

## Chunks per side of the window (odd: the focus's chunk in the middle).
const CHUNKS := 7
## Height written where no chunk is loaded yet: deep water, so nothing breaks there.
const UNKNOWN := -20.0

var texture: ImageTexture
var _origin := Vector2i(1 << 30, 0)   # chunk coord of the window's corner
var _mask := PackedByteArray()        # which chunks were loaded at the last build
var _px := PackedFloat32Array()


## A chunk's ground heights (any object with a `heights` PackedFloat32Array, e.g. LFTerrainChunk; read by name so
## the baker edition, which has no streaming, can ship this file), or empty.
static func _heights(chunk: Object) -> PackedFloat32Array:
	if chunk == null:
		return PackedFloat32Array()
	var h: Variant = chunk.get("heights")
	return h if h is PackedFloat32Array else PackedFloat32Array()


## Rebuilds the texture if the window round `center` (a chunk coord) moved or its loaded chunks changed, and
## points `material`'s shore_tex / shore_rect at it.
func update(center: Vector2i, chunks: Dictionary, material: ShaderMaterial) -> void:
	var o := center - Vector2i(CHUNKS / 2, CHUNKS / 2)
	var mask := PackedByteArray()
	mask.resize(CHUNKS * CHUNKS)
	for cj in CHUNKS:
		for ci in CHUNKS:
			mask[cj * CHUNKS + ci] = 0 if _heights(chunks.get(o + Vector2i(ci, cj))).is_empty() else 1
	if o == _origin and mask == _mask:
		return
	_origin = o
	_mask = mask
	_build(chunks)
	var cs := LFTerrainGenerator.CHUNK_SIZE
	var st := LFTerrainGenerator.STEP
	# texel k's centre lies on grid point origin + k * STEP (linear filtering then matches the mesh's grid)
	material.set_shader_parameter(&"shore_tex", texture)
	material.set_shader_parameter(&"shore_rect", Vector4(o.x * cs - st * 0.5, o.y * cs - st * 0.5,
			CHUNKS * LFTerrainGenerator.CELLS * st, 1.0))


func _build(chunks: Dictionary) -> void:
	var C := LFTerrainGenerator.CELLS
	var V := LFTerrainGenerator.VERTS
	var w := CHUNKS * C
	if _px.size() != w * w:
		_px.resize(w * w)
	for cj in CHUNKS:
		for ci in CHUNKS:
			var base := cj * C * w + ci * C
			if _mask[cj * CHUNKS + ci] == 0:
				for j in C:
					for i in C:
						_px[base + j * w + i] = UNKNOWN
				continue
			var h := _heights(chunks[_origin + Vector2i(ci, cj)])
			for j in C:
				var row := base + j * w
				var src := j * V
				for i in C:
					_px[row + i] = h[src + i]
	var img := Image.create_from_data(w, w, false, Image.FORMAT_RF, _px.to_byte_array())
	if texture == null:
		texture = ImageTexture.create_from_image(img)
	else:
		texture.update(img)
