class_name LFWaterfall
extends RefCounted
## Builds a waterfall from one of LFTerrainGenerator.waterfalls(): a curtain of falling water arcing out from
## the lip down to the river below, and foam on the pool at its foot, both drawn by waterfall.gdshader (its
## streaks run down the curtain; no script, so baked scenes keep them). The node is in the `waterfall` group
## with metas `top`, `bottom` and `width`, for a game's sound or spray.

const GROUP := &"waterfall"
const ROWS := 8   # rows down the curtain
const COLS := 6   # columns across it
const REACH := 1.6   # m out from the lip per sqrt(m fallen): the water arcs clear of the rock face
const POOL_SEGS := 14


## The curtain's and the pool foam's materials (waterfall.gdshader). Share one pair between waterfalls.
static func make_materials() -> Array[ShaderMaterial]:
	var shader := load("res://addons/lowland_forge/shaders/waterfall.gdshader") as Shader
	var curtain := ShaderMaterial.new()
	curtain.shader = shader
	curtain.render_priority = 1   # after the water (-1) and the river overlay (0)
	var pool := ShaderMaterial.new()
	pool.shader = shader
	pool.render_priority = 1
	pool.set_shader_parameter("pool", true)
	return [curtain, pool]


## A MeshInstance3D named "Waterfall" for `fall`, placed relative to `origin` (world x, y, z of the parent's
## origin), with the curtain and the pool foam as its two surfaces.
static func build(fall: Dictionary, materials: Array[ShaderMaterial], origin := Vector3.ZERO) -> MeshInstance3D:
	var lip: Vector3 = fall["position"]
	var top := lip.y
	var bottom: float = fall["bottom"]
	var drop := top - bottom
	var d: Vector2 = fall["direction"]
	var side := d.orthogonal()
	var half: float = fall["width"] * 0.5
	var fwd := Vector3(d.x, 0.0, d.y)
	var across := Vector3(side.x, 0.0, side.y)
	var mesh := ArrayMesh.new()

	# The curtain: rows down, each REACH * sqrt(fallen) m out from the lip (a falling arc), widening a little.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for r in ROWS + 1:
		var t := float(r) / ROWS
		var fallen := drop * t
		var out := 0.3 + REACH * sqrt(fallen + 0.05)
		var spread := half * (0.85 + 0.15 * t)
		var y := top + 0.04 - fallen - (0.25 if r == ROWS else 0.0)   # its foot under the pool's surface
		var slope := (REACH * 0.5 / sqrt(fallen + 0.05))   # d(out)/d(fallen): the face's lean
		var n := (fwd + Vector3.UP * slope).normalized()
		for c in COLS + 1:
			var u := float(c) / COLS * 2.0 - 1.0
			verts.append(fwd * out + across * u * spread + Vector3(0.0, y, 0.0))
			normals.append(n)
			uvs.append(Vector2(u * spread, fallen))
			var edge := 1.0 - smoothstep(0.65, 1.0, absf(u))
			cols.append(Color(1.0, 1.0, 1.0, edge * smoothstep(0.0, 0.12, t + 0.04)))
	var idx := PackedInt32Array()
	for r in ROWS:
		for c in COLS:
			var a := r * (COLS + 1) + c
			idx.append_array(PackedInt32Array([a, a + 1, a + COLS + 1, a + 1, a + COLS + 2, a + COLS + 1]))
	_add_surface(mesh, verts, normals, uvs, cols, idx, materials[0])

	# The pool foam: a disc on the water at the curtain's foot, thick in the middle, fading out.
	var foot := fwd * (0.3 + REACH * sqrt(drop + 0.05))
	var rad := maxf(half * 1.2, 2.5)
	var centre := foot + fwd * rad * 0.35 + Vector3(0.0, bottom + 0.06, 0.0)
	verts = PackedVector3Array([centre])
	normals = PackedVector3Array([Vector3.UP])
	uvs = PackedVector2Array([Vector2(centre.x + lip.x, centre.z + lip.z)])
	cols = PackedColorArray([Color(1, 1, 1, 1)])
	idx = PackedInt32Array()
	for ring in 2:
		var rr := rad * (0.55 if ring == 0 else 1.0)
		for s in POOL_SEGS:
			var a := TAU * s / POOL_SEGS
			var p := centre + (fwd * cos(a) * 1.15 + across * sin(a)) * rr
			verts.append(p)
			normals.append(Vector3.UP)
			uvs.append(Vector2(p.x + lip.x, p.z + lip.z))
			cols.append(Color(1, 1, 1, 0.75 if ring == 0 else 0.0))
	for s in POOL_SEGS:
		var s1 := (s + 1) % POOL_SEGS
		idx.append_array(PackedInt32Array([0, 1 + s, 1 + s1]))
		var i0 := 1 + s
		var i1 := 1 + s1
		var o0 := 1 + POOL_SEGS + s
		var o1 := 1 + POOL_SEGS + s1
		idx.append_array(PackedInt32Array([i0, o0, i1, i1, o0, o1]))
	_add_surface(mesh, verts, normals, uvs, cols, idx, materials[1])

	var mi := MeshInstance3D.new()
	mi.name = "Waterfall"
	mi.mesh = mesh
	mi.position = Vector3(lip.x, 0.0, lip.z) - Vector3(origin.x, 0.0, origin.z) + Vector3(0.0, -origin.y, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group(GROUP, true)
	mi.set_meta("top", top)
	mi.set_meta("bottom", bottom)
	mi.set_meta("width", half * 2.0)
	return mi


static func _add_surface(mesh: ArrayMesh, verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, mat: Material) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
