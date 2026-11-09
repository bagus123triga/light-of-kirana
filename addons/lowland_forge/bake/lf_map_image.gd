class_name LFMapImage
extends RefCounted
## A top-down picture of the land from a generator: the ground colours as the terrain is shaded (biome, sand,
## rock, snow), lit from the north-west, water tinted by its depth, rivers, and marks for the planned roads,
## sites and the spawn. North (-Z) is up, east (+X) right. For a minimap in your game, a map screen, or to
## check a seed at a glance. An overlay swaps the ground colours for one thing to check:
##
##   var img := LFMapImage.render(gen, gen.region_center, 2048.0, 1024)
##   img.save_png("res://map.png")
##   LFMapImage.render(gen, c, 2048.0, 512, LFMapImage.Overlay.BIOME)   # each biome in its own flat colour

## What colours the land: the shaded ground (NONE), each biome's own colour (BIOME, the dominant one), the
## slope (SLOPE: green flat, yellow steep, red cliff) or the height (HEIGHT: low blue to high white).
enum Overlay { NONE, BIOME, SLOPE, HEIGHT }

const WATER := Color(0.20, 0.42, 0.66)
const DEEP := Color(0.08, 0.18, 0.36)
const RIVER := Color(0.25, 0.55, 0.85)
const ROAD := Color(0.55, 0.42, 0.28)
const SITE := Color(0.85, 0.15, 0.12)
const SPAWN := Color(1.0, 1.0, 1.0)
## Flat colours for the BIOME overlay, by biome index (cycled past the end).
const BIOME_COLORS: Array[Color] = [Color(0.55, 0.80, 0.30), Color(0.10, 0.40, 0.20), Color(0.85, 0.85, 0.45),
		Color(0.25, 0.25, 0.10), Color(0.95, 0.75, 0.35), Color(0.30, 0.85, 0.75), Color(0.92, 0.95, 1.0),
		Color(0.45, 0.42, 0.40), Color(0.40, 0.50, 0.35), Color(0.70, 0.35, 0.75)]


## A `px` x `px` image of the `size` x `size` metres centred on `center` (world x, z). `marks`: draw the
## generator's roads, sites (a ring the size of each) and spawn (a dot) over it. The rows are sampled on the
## worker threads; `prog` ([done_rows, total_rows, cancelled], optional) is updated as it goes, and setting
## prog[2] to true stops it: render() then returns null.
static func render(gen: LFTerrainGenerator, center: Vector2, size: float, px: int,
		overlay := Overlay.NONE, marks := true, prog: Array = []) -> Image:
	var step := size / px
	var origin := center - Vector2(size, size) * 0.5 + Vector2(step, step) * 0.5   # pixel centres
	var n := px + 1   # one extra row and column for the slope of the last pixels
	if prog.size() < 3:
		prog.assign([0, 0, false])
	prog[0] = 0
	prog[1] = n + px
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	LFHeightmapExport.run_rows(gen, n, prog, func(g: LFTerrainGenerator, j0: int, j1: int) -> void:
		for j in range(j0, j1):
			for i in n:
				hs[j * n + i] = g.get_height(origin.x + i * step, origin.y + j * step))
	var bytes := PackedByteArray()
	bytes.resize(px * px * 3)
	var light := Vector3(-1.0, 1.4, -1.0).normalized()   # from the north-west, as maps are drawn
	var top := 60.0   # the height overlay's white: 60 m, or the highest point of a taller map
	if overlay == Overlay.HEIGHT:
		for v in hs:
			top = maxf(top, v)
	LFHeightmapExport.run_rows(gen, px, prog, func(g: LFTerrainGenerator, j0: int, j1: int) -> void:
		for j in range(j0, j1):
			for i in px:
				var h := hs[j * n + i]
				var dx := hs[j * n + i + 1] - h
				var dz := hs[(j + 1) * n + i] - h
				var nrm := Vector3(-dx, step, -dz).normalized()
				var x := origin.x + i * step
				var z := origin.y + j * step
				var c := _land_color(g, overlay, x, z, h, nrm.y, top)
				if overlay != Overlay.SLOPE and overlay != Overlay.HEIGHT:
					c = c * clampf(0.55 + 0.6 * nrm.dot(light), 0.35, 1.25)   # hillshade
				var wl := g.water_level_at(x, z)
				if h < wl:
					var wc := RIVER if g.river_factor(x, z) > 0.5 else WATER.lerp(DEEP, clampf((wl - h) / 15.0, 0.0, 1.0))
					c = c.lerp(wc, 0.85)
				var o := (j * px + i) * 3
				bytes[o] = int(clampf(c.r * 255.0, 0.0, 255.0))
				bytes[o + 1] = int(clampf(c.g * 255.0, 0.0, 255.0))
				bytes[o + 2] = int(clampf(c.b * 255.0, 0.0, 255.0)))
	if prog[2]:
		return null
	var img := Image.create_from_data(px, px, false, Image.FORMAT_RGB8, bytes)
	if marks:
		_marks(gen, img, origin, step)
	return img


## Writes render() to `path` (.png). Returns the error (ERR_SKIP if `prog` was cancelled; nothing is written).
static func save(gen: LFTerrainGenerator, center: Vector2, size: float, px: int, path: String,
		overlay := Overlay.NONE, marks := true, prog: Array = []) -> Error:
	var img := render(gen, center, size, px, overlay, marks, prog)
	if img == null:
		return ERR_SKIP
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return img.save_png(path)


static func _land_color(gen: LFTerrainGenerator, overlay: Overlay, x: float, z: float, h: float, ny: float, top := 60.0) -> Color:
	match overlay:
		Overlay.BIOME:
			return BIOME_COLORS[LFTerrainGenerator.dominant_biome(gen.biome_weights(x, z)) % BIOME_COLORS.size()]
		Overlay.SLOPE:
			var deg := rad_to_deg(acos(clampf(ny, -1.0, 1.0)))
			if deg < 15.0:
				return Color(0.35, 0.75, 0.30).lerp(Color(0.95, 0.85, 0.25), deg / 15.0)
			return Color(0.95, 0.85, 0.25).lerp(Color(0.85, 0.15, 0.10), clampf((deg - 15.0) / 25.0, 0.0, 1.0))
		Overlay.HEIGHT:
			var t := clampf(h / top, 0.0, 1.0)   # top: 60 m, or the highest point of a taller map
			return Color(0.15, 0.35, 0.25).lerp(Color(0.75, 0.62, 0.40), minf(t * 2.0, 1.0)).lerp(Color.WHITE, maxf(t * 2.0 - 1.0, 0.0))
	return gen.ground_shade(gen.biome_color(gen.biome_weights(x, z)), h, ny, LFTerrainGenerator.WATER_LEVEL, Vector2(x, z))


## Roads (pixels within a road's half width), site rings and the spawn dot.
static func _marks(gen: LFTerrainGenerator, img: Image, origin: Vector2, step: float) -> void:
	var px := img.get_width()
	if not gen.roads.is_empty():
		var half := maxf(LFTerrainRoads.HALF_WIDTH, step * 0.6)
		for j in px:
			for i in px:
				if gen.roads.distance_to(origin.x + i * step, origin.y + j * step) < half:
					img.set_pixel(i, j, img.get_pixel(i, j).lerp(ROAD, 0.85))
	for site: Dictionary in gen.sites:
		var c: Vector3 = (site["spot"] as Array)[0]
		_ring(img, (Vector2(c.x, c.z) - origin) / step, maxf(float(site.get("radius", 30.0)) / step, 3.0), SITE)
	var s := (gen.spawn_xz - origin) / step
	for dj in range(-2, 3):
		for di in range(-2, 3):
			if di * di + dj * dj <= 5:
				_dot(img, Vector2i(roundi(s.x) + di, roundi(s.y) + dj), SPAWN)


static func _ring(img: Image, c: Vector2, r: float, col: Color) -> void:
	var count := maxi(int(TAU * r * 1.5), 12)
	for k in count:
		var p := c + Vector2.from_angle(TAU * k / count) * r
		_dot(img, Vector2i(roundi(p.x), roundi(p.y)), col)


static func _dot(img: Image, p: Vector2i, col: Color) -> void:
	if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
		img.set_pixel(p.x, p.y, col)
