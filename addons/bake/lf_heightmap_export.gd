class_name LFHeightmapExport
extends RefCounted
## Writes a square of the land as heightmap files for other terrain tools (Terrain3D, HTerrain, World Machine,
## Blender, Unity...): `<base>_height.exr` (32-bit float, heights in metres), `<base>_height.r16` (16-bit
## unsigned, little endian, min..max height spread over 0..65535), `<base>_color.png` (the ground colours,
## no alpha: Terrain3D reads alpha as roughness) and `<base>_heightmap.json` (size, metres per pixel, world
## origin, height range, and the Terrain3D import settings). On a map with water up in the hills (lakes and
## rivers above the sea) also `<base>_water.exr`: the water level at each pixel (water wherever it is above
## the height). Pixel (0, 0) is the north-west corner (-X, -Z);
## +x is east, +y south. Editor and headless only: Image.save_exr is not in exported games.
##
##   LFHeightmapExport.export(gen, gen.region_center, 1024.0, 1.0, "res://maps/map")
##
## Terrain3D: open its importer scene, pick the .exr as height and the .png as colour, import_scale 1,
## height_offset 0, and set the Terrain3D node's vertex_spacing to `metres_per_pixel`.


## Largest image side written (pixels). A finer step on a bigger map is coarsened to fit, with a warning:
## 16385 x 16385 floats is already a 1 GB .exr in memory while it is written.
static var max_px := 16385


## Rows per task when the sampling is spread over the worker threads (smaller = finer progress and cancel).
static var band_rows := 8


## Samples `size` x `size` metres centred on `center` every `step` metres and writes the files. Returns the
## info written to the .json (its `metres_per_pixel` is the step used), plus "error" (an Error, OK when every
## file was written). A step that would make an image wider than max_px is raised (in 0.5 m steps) to fit.
## The sampling runs on the worker threads; `prog` ([done_rows, total_rows, cancelled], optional) is updated as
## it goes, and setting prog[2] to true stops it early: nothing is written and "error" is ERR_SKIP.
static func export(gen: LFTerrainGenerator, center: Vector2, size: float, step: float, base: String,
		prog: Array = []) -> Dictionary:
	var n := int(roundf(size / step)) + 1
	if n > max_px:
		var fit := ceilf(size / (max_px - 1) * 2.0) / 2.0
		push_warning("LFHeightmapExport: %d px at %.1f m would be too big: exporting at %.1f m per pixel (%d px)." \
				% [n, step, fit, int(roundf(size / fit)) + 1])
		step = fit
		n = int(roundf(size / step)) + 1
	var origin := center - Vector2(size, size) * 0.5
	var raised := gen.has_raised_water()
	if prog.size() < 3:
		prog.assign([0, 0, false])
	prog[0] = 0
	prog[1] = n * (3 if raised else 2)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var bands := (n + band_rows - 1) / band_rows
	var los := PackedFloat64Array()
	var his := PackedFloat64Array()
	los.resize(bands)
	his.resize(bands)
	run_rows(gen, n, prog, func(g: LFTerrainGenerator, j0: int, j1: int) -> void:
		var lo_b := INF
		var hi_b := -INF
		for j in range(j0, j1):
			for i in n:
				var h := g.get_height(origin.x + i * step, origin.y + j * step)
				heights[j * n + i] = h
				lo_b = minf(lo_b, h)
				hi_b = maxf(hi_b, h)
		los[j0 / band_rows] = lo_b
		his[j0 / band_rows] = hi_b)
	if prog[2]:
		return {"error": ERR_SKIP}
	var lo := INF
	var hi := -INF
	for k in bands:
		lo = minf(lo, los[k])
		hi = maxf(hi, his[k])
	var colors := PackedByteArray()
	colors.resize(n * n * 3)
	run_rows(gen, n, prog, func(g: LFTerrainGenerator, j0: int, j1: int) -> void:
		_colors(g, heights, n, origin, step, j0, j1, colors))
	var levels := PackedFloat32Array()
	if raised and not prog[2]:
		levels.resize(n * n)
		run_rows(gen, n, prog, func(g: LFTerrainGenerator, j0: int, j1: int) -> void:
			for j in range(j0, j1):
				for i in n:
					levels[j * n + i] = g.water_level_at(origin.x + i * step, origin.y + j * step))
	if prog[2]:
		return {"error": ERR_SKIP}
	var err := OK
	var dir := base.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		err = DirAccess.make_dir_recursive_absolute(dir)
	if err == OK:
		err = _save_exr(heights, n, base + "_height.exr")
	if err == OK:
		err = _save_r16(heights, lo, hi, base + "_height.r16")
	if err == OK:
		err = Image.create_from_data(n, n, false, Image.FORMAT_RGB8, colors).save_png(base + "_color.png")
	if err == OK and raised:
		err = _save_exr(levels, n, base + "_water.exr")
	var info := {
		"size_px": n, "metres_per_pixel": step, "size_m": (n - 1) * step,
		"origin_x": origin.x, "origin_z": origin.y, "min_height": lo, "max_height": hi,
		"water_level": LFTerrainGenerator.WATER_LEVEL, "seed": gen.world_seed,
		"water_map": base.get_file() + "_water.exr" if raised else "",
		"r16": "little endian, 0 = min_height, 65535 = max_height",
		"terrain3d": {"height": base.get_file() + "_height.exr", "color": base.get_file() + "_color.png",
				"import_scale": 1.0, "height_offset": 0.0, "vertex_spacing": step},
	}
	if err == OK:
		var f := FileAccess.open(base + "_heightmap.json", FileAccess.WRITE)
		if f == null:
			err = FileAccess.get_open_error()
		else:
			f.store_string(JSON.stringify(info, "\t"))
	info["error"] = err
	return info


## Runs `body(gen, row_from, row_to)` over the rows 0..rows-1 in bands of band_rows, on the worker threads
## (high priority), each band with its own `gen.clone_for_worker()` (a generator keeps scratch state while it
## samples). Bodies must write only their own rows. Waits for all of it. Adds each band to prog[0] and skips
## the bands left once prog[2] (cancelled) is true. Shared by LFMapImage.
static func run_rows(gen: LFTerrainGenerator, rows: int, prog: Array, body: Callable) -> void:
	if prog[2] or rows <= 0:
		return
	var bands := (rows + band_rows - 1) / band_rows
	var mutex := Mutex.new()
	var work := func(k: int) -> void:
		if prog[2]:
			return
		var j0 := k * band_rows
		var j1 := mini(j0 + band_rows, rows)
		body.call(gen.clone_for_worker(), j0, j1)
		mutex.lock()
		prog[0] += j1 - j0
		mutex.unlock()
	var id := WorkerThreadPool.add_group_task(work, bands, -1, true, "LF export rows")
	WorkerThreadPool.wait_for_group_task_completion(id)


static func _save_exr(heights: PackedFloat32Array, n: int, path: String) -> Error:
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
	return img.save_exr(path, true)


static func _save_r16(heights: PackedFloat32Array, lo: float, hi: float, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var span := maxf(hi - lo, 0.001)
	var data := PackedByteArray()
	data.resize(heights.size() * 2)
	for k in heights.size():
		data.encode_u16(k * 2, clampi(roundi((heights[k] - lo) / span * 65535.0), 0, 65535))
	f.store_buffer(data)
	return OK


## The ground colour per pixel for rows j0..j1-1 into `out` (RGB8 bytes), shaded like the terrain chunks
## (biome colour, sand / rock / snow by height and slope); the slope comes from the neighbouring samples.
static func _colors(gen: LFTerrainGenerator, heights: PackedFloat32Array, n: int, origin: Vector2, step: float,
		j0: int, j1: int, out: PackedByteArray) -> void:
	for j in range(j0, j1):
		for i in n:
			var h := heights[j * n + i]
			var dx := heights[j * n + mini(i + 1, n - 1)] - heights[j * n + maxi(i - 1, 0)]
			var dz := heights[mini(j + 1, n - 1) * n + i] - heights[maxi(j - 1, 0) * n + i]
			var ny := Vector3(-dx, 2.0 * step, -dz).normalized().y
			var x := origin.x + i * step
			var z := origin.y + j * step
			var c := gen.ground_shade(gen.biome_color(gen.biome_weights(x, z)), h, ny, gen.water_level_at(x, z), Vector2(x, z))
			var o := (j * n + i) * 3
			out[o] = int(clampf(c.r * 255.0, 0.0, 255.0))
			out[o + 1] = int(clampf(c.g * 255.0, 0.0, 255.0))
			out[o + 2] = int(clampf(c.b * 255.0, 0.0, 255.0))
