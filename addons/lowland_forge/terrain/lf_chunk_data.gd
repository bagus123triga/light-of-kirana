class_name LFChunkData
extends RefCounted
## One 32 m chunk as plain data, safe on any thread: its heights and flat-shaded terrain triangles, and its
## props (placement, MultiMesh buffers, foliage and tree records, forage, the river overlay). The map baker
## builds its blocks from it.

const RIVER_OVERLAY_Y := 0.02


## Heightfield + flat-shaded triangle arrays of one chunk.
## Returns { heights, faces, normals, colors }, and on a map with water up in the hills
## (LFTerrainGenerator.has_raised_water) also `levels` (the water level at each height point) and `water`
## (that raised water's triangles, chunk-local; empty where there is none).
static func compute_terrain(gen: LFTerrainGenerator, coord: Vector2i) -> Dictionary:
	var V := LFTerrainGenerator.VERTS
	var S := LFTerrainGenerator.STEP
	var ox := coord.x * LFTerrainGenerator.CHUNK_SIZE
	var oz := coord.y * LFTerrainGenerator.CHUNK_SIZE
	var heights := PackedFloat32Array()
	heights.resize(V * V)
	var raised := gen.has_raised_water()
	var levels := PackedFloat32Array()   # as water_levels gives them, each asked right after its height (one river scan)
	if raised:
		levels.resize(V * V)
	for j in V:
		for i in V:
			heights[j * V + i] = gen.get_height(ox + i * S, oz + j * S)
			if raised:
				levels[j * V + i] = gen.water_level_at(ox + i * S, oz + j * S)

	var rng := RandomNumberGenerator.new()
	rng.seed = gen.chunk_seed(coord, 7)
	var cells := LFTerrainGenerator.CELLS
	var faces := PackedVector3Array()
	faces.resize(cells * cells * 6)
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	normals.resize(cells * cells * 6)
	colors.resize(cells * cells * 6)
	var w := 0
	for j in cells:
		for i in cells:
			var x0 := i * S
			var x1 := x0 + S
			var z0 := j * S
			var z1 := z0 + S
			var p00 := Vector3(x0, heights[j * V + i], z0)
			var p10 := Vector3(x1, heights[j * V + i + 1], z0)
			var p01 := Vector3(x0, heights[(j + 1) * V + i], z1)
			var p11 := Vector3(x1, heights[(j + 1) * V + i + 1], z1)
			var base := gen.biome_color(gen.biome_weights(ox + x0 + S * 0.5, oz + z0 + S * 0.5))
			var lv := PackedFloat32Array()   # the water level at p00, p10, p01, p11
			if raised:
				lv = PackedFloat32Array([levels[j * V + i], levels[j * V + i + 1], levels[(j + 1) * V + i],
						levels[(j + 1) * V + i + 1]])
			# the extra jitter of a steep face, one per quad: per triangle, its tall thin pairs read as teeth
			var block := rng.randf_range(-1.0, 1.0)
			# Two triangles per quad, listed clockwise seen from above (= front-facing in Godot).
			var tris := [[p00, p10, p01], [p10, p11, p01]]
			var ns: Array[Vector3] = []
			var info: Array[Vector3] = []   # per triangle: mean height, normal y, water level
			for t in 2:
				var a: Vector3 = tris[t][0]
				var b: Vector3 = tris[t][1]
				var c: Vector3 = tris[t][2]
				# Flat shading: one normal per triangle, vertices are NOT shared between triangles.
				var n := (c - a).cross(b - a).normalized()
				var wl := LFTerrainGenerator.WATER_LEVEL
				if raised:
					wl = (lv[0] + lv[1] + lv[2]) / 3.0 if t == 0 else (lv[1] + lv[3] + lv[2]) / 3.0
				ns.append(n)
				info.append(Vector3((a.y + b.y + c.y) / 3.0, n.y, wl))
			var cols := gen.quad_shade(base, Vector2(ox + x0 + S * 0.5, oz + z0 + S * 0.5), info[0], info[1])
			var jit := rng.randf_range(-0.07, 0.07)
			var jit1 := rng.randf_range(-0.07, 0.07)
			for t in 2:
				var a: Vector3 = tris[t][0]
				var b: Vector3 = tris[t][1]
				var c: Vector3 = tris[t][2]
				var n := ns[t]
				# facet jitter, stronger on steep faces so a cliff breaks up into blocks of rock; one per quad where
				# the quad has one colour
				var steep := 0.07 * gen.cliff_jitter() * smoothstep(0.8, 0.4, minf(info[0].y, info[1].y))
				var col := cols[0] if cols.size() == 1 else cols[t]
				col = LFMeshBuilder.tint(col, 1.0 + (jit if cols.size() == 1 or t == 0 else jit1) + block * steep)
				faces[w] = a
				faces[w + 1] = b
				faces[w + 2] = c
				for k in 3:
					normals[w + k] = n
					colors[w + k] = col
				w += 3
	var out := {"heights": heights, "faces": faces, "normals": normals, "colors": colors}
	if raised:
		out["levels"] = levels
		out["water"] = raised_water(heights, levels)
	return out


## The water level at each height point of the chunk at `pos` (its corner), or empty on a map whose water
## all lies at WATER_LEVEL (LFTerrainGenerator.has_raised_water).
static func water_levels(gen: LFTerrainGenerator, pos: Vector3) -> PackedFloat32Array:
	var levels := PackedFloat32Array()
	if not gen.has_raised_water():
		return levels
	var V := LFTerrainGenerator.VERTS
	var S := LFTerrainGenerator.STEP
	levels.resize(V * V)
	for j in V:
		for i in V:
			levels[j * V + i] = gen.water_level_at(pos.x + i * S, pos.z + j * S)
	return levels


## The triangles of the water above WATER_LEVEL over one chunk's grid (heights and water levels at its
## points), chunk-local: each cell where the ground dips below that water, its corners at the water's own
## level (a river's surface falls along it). A corner out at the sea's level takes the cell's lowest raised
## level where its ground is above that, so the edge of a highland lake or river ends under its bank instead
## of falling to the sea; one down below a fall or cliff keeps its own (lifted, the water would hang there).
static func raised_water(heights: PackedFloat32Array, levels: PackedFloat32Array) -> PackedVector3Array:
	var V := LFTerrainGenerator.VERTS
	var S := LFTerrainGenerator.STEP
	var cells := V - 1
	var out := PackedVector3Array()
	var low := LFTerrainGenerator.WATER_LEVEL + 0.05
	for j in cells:
		for i in cells:
			var ks := PackedInt32Array([j * V + i, j * V + i + 1, (j + 1) * V + i, (j + 1) * V + i + 1])
			var top := INF   # the lowest raised level of the cell
			for k in ks:
				if levels[k] > low:
					top = minf(top, levels[k])
			if top == INF:
				continue
			var y := PackedFloat32Array()
			var wet := false
			for k in ks:
				var l := levels[k] if levels[k] > low or heights[k] < top - 0.05 else top
				y.append(l)
				wet = wet or heights[k] < l
			if not wet:
				continue
			var p00 := Vector3(i * S, y[0], j * S)
			var p10 := Vector3((i + 1) * S, y[1], j * S)
			var p01 := Vector3(i * S, y[2], (j + 1) * S)
			var p11 := Vector3((i + 1) * S, y[3], (j + 1) * S)
			out.append_array(PackedVector3Array([p00, p10, p01, p10, p11, p01]))   # as the terrain's triangles
	return out


## Everything the props of one chunk need, as plain data: placement, MultiMesh buffers, foliage
## and tree records, forage bookkeeping and (if `with_river`) the river overlay arrays. `levels`: the chunk's
## water levels if the caller has them (compute_terrain), else worked out here.
## `lib` is only read (variant counts, collider radii, perch point keys).
static func compute_props(gen: LFTerrainGenerator, lib: LFPropMeshes, coord: Vector2i,
		heights: PackedFloat32Array, with_river: bool, levels := PackedFloat32Array()) -> Dictionary:
	var pos := Vector3(coord.x, 0, coord.y) * LFTerrainGenerator.CHUNK_SIZE
	var out := {}
	if levels.is_empty():
		levels = water_levels(gen, pos)   # (compute_terrain's `levels`, when the caller has them)
	out["river"] = _compute_river(gen, pos, heights, levels) if with_river else {}
	var result := LFPropPlacer.place(gen, lib, coord, heights, levels)
	out["colliders"] = result["colliders"]
	out["log_colliders"] = result["log_colliders"]
	out["cliff_colliders"] = result["cliff_colliders"]
	var forage: Array = result["forage"]
	var berries := 0
	var by_id := {}
	for i in forage.size():
		var e: Dictionary = forage[i]
		e["hidden"] = false
		e["plain"] = -1
		if e["kind"] == &"berries":
			e["plain"] = berries
			berries += 1
		by_id[e["id"]] = i
	out["forage"] = forage
	out["forage_by_id"] = by_id
	out["berries"] = berries
	var foliage := PackedFloat32Array()
	var trees := PackedFloat32Array()
	var mms: Array = []  # [{ key, count, buf }] in batch order
	var batches: Dictionary = result["batches"]
	for key: Vector2i in batches:
		var xforms: Array = batches[key]
		if LFPropMeshes.FOLIAGE_SHAPE.has(key.x):
			var shape: Array = LFPropMeshes.FOLIAGE_SHAPE[key.x]
			for xf: Transform3D in xforms:
				var sc := xf.basis.get_scale()
				var wp := pos + xf.origin
				foliage.append_array(PackedFloat32Array([wp.x, wp.y, wp.z,
					shape[0] * sc.y, shape[1] * sc.y, shape[2] * sc.x, shape[3], shape[4], shape[5], shape[6]]))
		if lib.perch_points.has(key):
			for xf: Transform3D in xforms:
				var wp := pos + xf.origin
				var bs := xf.basis
				trees.append_array(PackedFloat32Array([wp.x, wp.y, wp.z, bs.x.x, bs.x.y, bs.x.z,
						bs.y.x, bs.y.y, bs.y.z, bs.z.x, bs.z.y, bs.z.z, key.x, key.y]))
		var buf := PackedFloat32Array()
		buf.resize(xforms.size() * 12)
		var o := 0
		for xf: Transform3D in xforms:
			# MultiMesh buffer layout: 3 rows of (basis row xyz, origin component)
			var b := xf.basis
			var p := xf.origin
			buf[o] = b.x.x
			buf[o + 1] = b.y.x
			buf[o + 2] = b.z.x
			buf[o + 3] = p.x
			buf[o + 4] = b.x.y
			buf[o + 5] = b.y.y
			buf[o + 6] = b.z.y
			buf[o + 7] = p.y
			buf[o + 8] = b.x.z
			buf[o + 9] = b.y.z
			buf[o + 10] = b.z.z
			buf[o + 11] = p.z
			o += 12
		mms.append({"key": key, "count": xforms.size(), "buf": buf})
	out["foliage"] = foliage
	out["trees"] = trees
	out["mms"] = mms
	return out


## The flow overlay's vertex colour at world (x, z), `depth` = ground - water there (negative under water),
## `level` its water level (see river_flow.gdshader): rg flow vector, b opacity (0 off the river, out at
## the coast, and where the water is open on both sides: a lake or the sea it runs into), a bank closeness.
static func flow_color(gen: LFTerrainGenerator, x: float, z: float, depth: float, level: float) -> Color:
	var still := Color(0.5, 0.5, 0.0, 0.0)
	if depth > -0.05:
		return still
	var rf := gen.river_factor(x, z)
	if rf <= 0.5:
		return still
	var fd := gen.river_flow_dir(x, z)
	var speed := lerpf(0.35, 1.0, smoothstep(-0.2, -1.8, depth))  # faster over deep water
	var alpha := smoothstep(0.5, 0.85, rf) * smoothstep(-0.05, -0.45, depth)
	alpha *= 1.0 - smoothstep(-40.0, 0.0, gen.coast_offset(x, z))   # the river ends at the coast
	if alpha > 0.0 and fd != Vector2.ZERO:   # open water on both sides (a lake): no current
		var edge := gen.params.river_water_edge if gen.params != null else LFTerrainGenerator.RIVER_WATER_EDGE
		var side := fd.orthogonal()
		var wet := 0
		for f: float in [1.8, 2.8, -1.8, -2.8]:
			var q := Vector2(x, z) + side * edge * f
			wet += 1 if gen.get_height(q.x, q.y) < level - 0.3 else 0
		alpha *= 1.0 - smoothstep(2.0, 4.0, float(wet))
	var bank := smoothstep(-1.4, -0.1, depth)   # 1 by the shore (shallow), 0 in the deep middle
	return Color(0.5 + 0.5 * fd.x * speed, 0.5 + 0.5 * fd.y * speed, alpha, bank)


## Flow overlay for rivers: a flat grid just above the water (y = RIVER_OVERLAY_Y) covering the
## river cells of this chunk. Per-vertex COLOR (see river_flow.gdshader): rg = flow vector,
## b = opacity, a = bank closeness. Flow direction is LFTerrainGenerator.river_flow_dir: downstream
## along the river's points (spring to the sea, its water falling), a pure function of world position,
## so neighbouring chunks agree on shared edges. Chunks without river water cost one cheap height scan.
## Returns the mesh arrays ({ verts, uvs, normals, cols, idx }) or {} if there is no river water.
static func _compute_river(gen: LFTerrainGenerator, pos: Vector3, heights: PackedFloat32Array,
		raised_levels: PackedFloat32Array) -> Dictionary:
	var V := LFTerrainGenerator.VERTS
	var S := LFTerrainGenerator.STEP
	var levels := raised_levels   # the water level at each point (the sea's, unless some lies higher)
	if levels.is_empty():
		levels = PackedFloat32Array()
		levels.resize(V * V)
		levels.fill(LFTerrainGenerator.WATER_LEVEL)
	var any := false
	for k in V * V:
		if heights[k] - levels[k] < -0.1:
			any = true
			break
	if not any:
		return {}
	var cols := PackedColorArray()
	cols.resize(V * V)
	var live := PackedByteArray()
	live.resize(V * V)
	var n_live := 0
	for j in V:
		for i in V:
			var k := j * V + i
			var h := heights[k] - levels[k]   # depth below the water there
			if h > -0.05:
				cols[k] = Color(0.5, 0.5, 0.0, 0.0)
				continue
			cols[k] = flow_color(gen, pos.x + i * S, pos.z + j * S, h, levels[k])
			if cols[k].b > 0.0:
				live[k] = 1
				n_live += 1
	if n_live == 0:
		return {}
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	verts.resize(V * V)
	uvs.resize(V * V)
	normals.resize(V * V)
	for j in V:
		for i in V:
			var k := j * V + i
			verts[k] = Vector3(i * S, levels[j * V + i] + RIVER_OVERLAY_Y, j * S)
			uvs[k] = Vector2(pos.x + i * S, pos.z + j * S)
			normals[k] = Vector3.UP
	var idx := PackedInt32Array()
	for j in V - 1:
		for i in V - 1:
			var a := j * V + i
			if live[a] + live[a + 1] + live[a + V] + live[a + V + 1] == 0:
				continue
			idx.append_array(PackedInt32Array([a, a + 1, a + V, a + 1, a + V + 1, a + V]))
	if idx.is_empty():
		return {}
	return {"verts": verts, "uvs": uvs, "normals": normals, "cols": cols, "idx": idx}
