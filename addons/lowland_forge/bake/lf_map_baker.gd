@tool
@icon("res://addons/lowland_forge/icons/lf_map_baker.svg")
class_name LFMapBaker
extends Node3D
## The map baker: add it to a scene, set the map in the Inspector, watch the preview, press Bake. Writes
## plain scenes (LFTileBaker) you then edit by hand: delete trees, move rocks, add your own things.
## The preview is a low-detail mesh of the whole map with its trees, rocks and logs (ground cover is left
## out), built on a worker thread shortly after any setting changes; it is not saved with the scene. Bake
## writes `output_dir/map.tscn`, one `tile_<x>_<z>.tscn` per tile and `tiles.json`, a block at a time so the
## editor stays usable (the plugin shows a progress bar). Export heightmap writes `output_dir/heightmap_*` for
## Terrain3D and other terrain tools. On a big map, *Work on one tile* previews and bakes a single tile.
## *Grow Map* adds tiles round a map already baked without changing its land or its tiles.

## The baker baking in the editor right now (the plugin draws its progress bar), or null.
static var baking: LFMapBaker
## The baker whose preview is being built right now (the plugin draws its progress bar), or null.
static var loading: LFMapBaker
## The baker whose heightmap or map image export is running in the background (start_export_heightmap), if any.
static var exporting: LFMapBaker

## Same seed and settings give the same map.
@export var map_seed := 42:
	set(v):
		map_seed = v
		_queue_preview()
@export_tool_button("New seed", "RandomNumberGenerator") var _new_seed_button := new_seed
## All the land settings: height, mountains, lakes, rivers, biomes, colours. Save it as a .tres to reuse.
@export var params: LFMapParams:
	set(v):
		params = v
		if Engine.is_editor_hint():
			_add_missing_presets()
		_queue_preview()
		notify_property_list_changed()
## A ready-made map. Pick one and press Apply preset (Ctrl+Z undoes it).
@export_enum("Classic Island", "Highland Island", "Mountain Valley", "Rolling Plains", "Deep Forest",
		"Badlands", "Frozen Isle", "Great Mountains", "Deep Valleys") var preset := 0
@export_tool_button("Apply preset", "Load") var _apply_preset_button := apply_preset

@export_group("Map")
## Size of one tile scene (m). A 1024 m tile with every prop is about 25 MB on disk.
@export_range(128, 4096, 128, "suffix:m") var tile_size := 1024:
	set(v):
		tile_size = v
		_queue_preview()
## Tiles across, west to east (at most 16).
@export_range(1, 16) var tiles_x := 1:
	set(v):
		tiles_x = v
		_queue_preview()
## Tiles down, north to south (at most 16).
@export_range(1, 16) var tiles_z := 1:
	set(v):
		tiles_z = v
		_queue_preview()
## Open: land runs off every edge. Island: sea all round. Mountains: a valley ringed by mountains.
@export_custom(PROPERTY_HINT_ENUM, "Open,Island,Mountains", PROPERTY_USAGE_EDITOR) var boundary: int:
	get:
		return params.boundary if params != null else LFMapParams.Boundary.ISLAND
	set(v):
		_set_param(&"boundary", v)
## How high the mountain rim stands (m). Mountains boundary only.
@export_custom(PROPERTY_HINT_RANGE, "20,300,1,or_greater,suffix:m", PROPERTY_USAGE_EDITOR) var rim_height: float:
	get:
		return params.rim_height if params != null else 0.0
	set(v):
		_set_param(&"rim_height", v)
## Rivers leave the valley through a pass they cut in the rim (off: they end in a lake). Mountains boundary only.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR) var rim_pass: bool:
	get:
		return params.rim_pass if params != null else false
	set(v):
		_set_param(&"rim_pass", v)
## How high mountains rise (m). 0 = no mountains; try 60 to 120.
@export_custom(PROPERTY_HINT_RANGE, "0,200,1,or_greater,suffix:m", PROPERTY_USAGE_EDITOR) var mountain_height: float:
	get:
		return params.mountain_height if params != null else 0.0
	set(v):
		_set_param(&"mountain_height", v)
## 0: mountain ranges. 1 or more: that many separate peaks. Needs Mountain Height above 0.
@export_custom(PROPERTY_HINT_RANGE, "0,32,1,or_greater", PROPERTY_USAGE_EDITOR) var mountain_count: int:
	get:
		return params.mountain_count if params != null else 0
	set(v):
		_set_param(&"mountain_count", v)
## How many lakes. Lakes need room, so a small map may get fewer.
@export_custom(PROPERTY_HINT_RANGE, "0,32,1,or_greater", PROPERTY_USAGE_EDITOR) var lake_count: int:
	get:
		return params.lake_count if params != null else 1
	set(v):
		_set_param(&"lake_count", v)
## Also put lakes wherever the land dips below sea level.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR) var natural_lakes: bool:
	get:
		return params.natural_lakes if params != null else false
	set(v):
		_set_param(&"natural_lakes", v)
## How many rivers. Each flows from high ground through the lakes in its path to the sea.
@export_custom(PROPERTY_HINT_RANGE, "0,16,1,or_greater", PROPERTY_USAGE_EDITOR) var river_count: int:
	get:
		return params.river_count if params != null else 1
	set(v):
		_set_param(&"river_count", v)
## The biomes the map may use. Tick one for a single-biome map.
@export_custom(PROPERTY_HINT_FLAGS, "", PROPERTY_USAGE_EDITOR) var biomes_on: int:
	get:
		var bits := 0
		if params != null:
			for i in mini(params.biomes.size(), 32):
				if params.biomes[i] != null and params.biomes[i].enabled:
					bits |= 1 << i
		return bits
	set(v):
		if params == null:
			return
		for i in mini(params.biomes.size(), 32):
			if params.biomes[i] != null:
				params.biomes[i].enabled = (int(v) >> i) & 1 == 1
		_queue_preview()
## Where snow starts: 0 = the lowlands, 1 = only the highest peak.
@export_custom(PROPERTY_HINT_RANGE, "0,1,0.05", PROPERTY_USAGE_EDITOR) var snow_line: float:
	get:
		return params.snow_line if params != null else 0.5
	set(v):
		_set_param(&"snow_line", v)
## Fit the island to the map. Code only.
@export_storage var fit_island := true:
	set(v):
		fit_island = v
		_queue_preview()

@export_group("Grow Map")
## Tiles to add west of a baked map. Tick New Tiles Only to keep your edits in the old tiles.
@export_range(0, 16) var add_west := 0:
	set(v):
		add_west = v
		_queue_preview()
## Tiles to add east of a baked map.
@export_range(0, 16) var add_east := 0:
	set(v):
		add_east = v
		_queue_preview()
## Tiles to add north of a baked map.
@export_range(0, 16) var add_north := 0:
	set(v):
		add_north = v
		_queue_preview()
## Tiles to add south of a baked map.
@export_range(0, 16) var add_south := 0:
	set(v):
		add_south = v
		_queue_preview()
## Bake only the tiles the folder doesn't have yet; keep the rest as they are.
@export var new_tiles_only := false:
	set(v):
		new_tiles_only = v
		_queue_preview()

@export_group("Work on One Tile")
## Preview and bake just one tile (Work Tile). Quick on big maps.
@export var one_tile := false:
	set(v):
		one_tile = v
		_queue_preview()
## Which tile: x = column, y = row, from 0 at the north-west corner (as in tile_x_z.tscn).
@export var work_tile := Vector2i.ZERO:
	set(v):
		work_tile = v
		_queue_preview()

@export_group("Props")
## What to place: every prop, only trees / rocks / logs, or none.
@export var props := LFTileBaker.Props.ALL:
	set(v):
		props = v
		_queue_preview()
## How many props: 0 = none, 1 = normal, 2 = about twice as many.
@export_custom(PROPERTY_HINT_RANGE, "0,3,0.05", PROPERTY_USAGE_EDITOR) var prop_density: float:
	get:
		return params.prop_density if params != null else 1.0
	set(v):
		_set_param(&"prop_density", v)
## Trees, rocks and logs stop drawing past this distance (m). 0 = always drawn.
@export_range(0.0, 4000.0, 50.0, "or_greater", "suffix:m") var prop_draw_distance := 800.0
## Props are drawn and collide in batches this big: bigger = fewer draw calls (256 m: a quarter of 128 m's).
## 128 m bakes them inside each block, as Map Baker 2.0 did.
@export_enum("128 m (as 2.0):128", "256 m:256", "512 m:512") var prop_batch_size := 256

@export_group("Preview")
## Redraw the preview after every change.
@export var auto_preview := true
## Preview detail (m between samples; 0 = automatic). The bake is always full detail.
@export_range(0.0, 64.0, 1.0, "suffix:m") var preview_step := 0.0
## Show trees, rocks and logs in the preview.
@export var preview_props := true:
	set(v):
		preview_props = v
		_queue_preview()
## Hide props in the preview of maps bigger than this (km²). 0 = always show them.
@export_range(0.0, 64.0, 0.5, "or_greater", "suffix:km²") var preview_props_limit := 0.0:
	set(v):
		preview_props_limit = v
		_queue_preview()
@export_tool_button("Refresh preview", "Reload") var _refresh_button := refresh_preview
@export_tool_button("Cancel preview", "Stop") var _cancel_preview_button := cancel_preview

@export_group("Collision")
## Collision for the land, trees, rocks and logs (groups terrain, tree, rock, log).
@export var collision := true
## Invisible walls so the player can't leave the map. Open and Mountains maps only.
@export var edge_walls := true
## Physics layers of the land.
@export_flags_3d_physics var terrain_layers := 1
## Physics layers of the trees, rocks and logs.
@export_flags_3d_physics var prop_layers := 1
## Physics layers of the edge walls.
@export_flags_3d_physics var wall_layers := 1
## An Area3D in all water (group water) to detect swimming. Its water_level meta is the surface height.
@export var water_areas := true
## Physics layers of the water areas.
@export_flags_3d_physics var water_layers := 1
## What the water areas detect (your player's layers, boats...). The land and props are on layer 1 too, so
## they are reported once as a tile loads: skip StaticBody3D in body_entered (see the guide).
@export_flags_3d_physics var water_mask := 1

@export_group("Bake")
## Folder the bake writes to. Baking again overwrites the tiles there (it asks first).
@export_dir var output_dir := "res://maps/map"
## Experimental: moving streaks on the rivers (in the preview too). Off: still water. See the guide to use your own.
@export var flowing_rivers := false:
	set(v):
		flowing_rivers = v
		_queue_preview()
## Threads building the map while it bakes (0 = every CPU core but one).
@export_range(0, 64) var bake_threads := 0
@export_tool_button("Bake", "PackedScene") var _bake_button := start_bake
@export_tool_button("Cancel bake", "Stop") var _cancel_button := cancel_bake

@export_group("Heightmap Export")
## Metres per pixel of the exported heightmap.
@export_range(0.5, 8.0, 0.5, "suffix:m") var heightmap_step := 1.0
@export_tool_button("Export heightmap", "Image") var _heightmap_button := start_export_heightmap

@export_group("Map Image")
## Width of the map picture in pixels (square, north up).
@export_range(128, 8192, 64, "suffix:px") var map_image_px := 1024
## Draw the map as baked, or show biomes, slope or height.
@export var map_image_overlay := LFMapImage.Overlay.NONE
@export_tool_button("Export map image", "ImageTexture") var _map_image_button := start_export_map_image

var _preview: Node3D
var _dirty := false
var _dirty_at := 0
var _params_sig := ""
var _lib: LFPropMeshes   # prop meshes for the preview, built for _lib_seed
var _lib_seed := -1
var _lib_swaps := ""   # _signature of the prop_swaps _lib was built with
var _land_task := -1   # WorkerThreadPool task building the preview land
var _land_out: Dictionary = {}   # its result (_build_land)
var _props_task := -1   # then the one placing the preview props
var _props_out: Dictionary = {}   # its result: Vector2i(kind, variant) -> Array[Transform3D]
var _prog: Array = [0, 0, false]   # the running preview task's [done, total, cancelled] (it writes the steps)
var _with_props := false   # this preview places props after the land
var _preview_t0 := 0
var _refresh_wanted := false   # a refresh asked for while those ran: done when they end
var _exp_task := -1   # WorkerThreadPool task running an export (start_export_*)
var _exp_prog: Array = [0, 0, false]   # its [done_rows, total_rows, cancelled]
var _exp_heightmap := true   # that export is the heightmap (else the map image)
var _exp_out: Dictionary = {}   # its result: "error" and the export's info
var _job: LFTileBaker.Job   # the bake running in steps (start_bake)
var _job_next := 0   # the block count at which it prints its progress next
var _job_frame := -1   # the frame drive_bake last ran in
var _ground_gen: LFTerrainGenerator   # for ground_at, made again when a setting changes
var _ground_key := ""
var _baked_tiles: Array = []   # baked_rect(): [tile, scene] of tiles.json, read for _baked_stamp
var _baked_stamp := ""

## How deep land_key reads params: params > biomes > a biome > its tree rules > a rule > its values.
const SIGNATURE_DEPTH := 12


func _init() -> void:
	if params == null:
		params = LFMapParams.new()
		params.natural_lakes = false   # a new map: one lake, one river from the high ground through it
		params.lake_count = 1
		_add_missing_presets()


## Lists every preset biome (LFBiomePresets) the params lack, unticked: in Biomes On, out of the map until
## ticked, so the map stays the same. Params saved before a preset existed get it too. A params saved in its
## own .tres file (a preset other scenes may share) is left as it is.
func _add_missing_presets() -> void:
	if params == null or params.resource_path.is_absolute_path() and not params.resource_path.contains("::"):
		return
	var have := {}
	for b in params.biomes:
		if b != null:
			have[b.name] = true
	for b in LFBiomePresets.all():
		if not have.has(b.name):
			b.enabled = false
			params.biomes.append(b)


func _ready() -> void:
	if Engine.is_editor_hint():
		LFEnvironment.register_globals()
		_queue_preview()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# Edits inside params (a biome, a landform) don't pass through our setters: watch a signature of it.
	if Engine.get_process_frames() % 30 == 0:
		var sig := _signature(params, 0)
		if sig != _params_sig:
			if _params_sig != "":
				_queue_preview()
			_params_sig = sig
	if _exp_task >= 0 and WorkerThreadPool.is_task_completed(_exp_task):
		_finish_export()
	if _job != null:
		drive_bake()
		return
	if _dirty and auto_preview and Time.get_ticks_msec() - _dirty_at > 400:
		refresh_preview()
	if _land_task >= 0 and WorkerThreadPool.is_task_completed(_land_task):
		_finish_land()
	if _props_task >= 0 and WorkerThreadPool.is_task_completed(_props_task):
		_finish_props()
	if _refresh_wanted and _land_task < 0 and _props_task < 0:
		refresh_preview()


# A bake goes on while the scene is out of the tree (another scene tab open: the plugin drives it); it stops
# only when the baker is freed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _job != null:
			cancel_bake()
		if _exp_task >= 0:
			_exp_prog[2] = true
			WorkerThreadPool.wait_for_task_completion(_exp_task)
			_exp_task = -1
			if exporting == self:
				exporting = null


func _exit_tree() -> void:
	cancel_preview()
	if _exp_task >= 0:
		_exp_prog[2] = true
		_finish_export()
	for t in [_land_task, _props_task]:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)
	_land_task = -1
	_props_task = -1


# --- the Map and Props shortcuts (boundary ... snow_line, prop_density): params' settings shown here, so they are
# at hand; never saved with the scene (params holds them) ------------------------------------------------------

func _set_param(property: StringName, value: Variant) -> void:
	if params == null:
		return
	params.set(property, value)
	if property == &"boundary":
		notify_property_list_changed()   # Rim Height and Rim Pass show with the mountains
	_queue_preview()


func _validate_property(property: Dictionary) -> void:
	var shortcut: bool = property.name in ["boundary", "rim_height", "rim_pass", "mountain_height", "mountain_count",
			"lake_count", "natural_lakes", "river_count", "biomes_on", "snow_line", "prop_density"]
	if not shortcut:
		return
	if params == null or (property.name in ["rim_height", "rim_pass"] and params.boundary != LFMapParams.Boundary.MOUNTAINS) \
			or (property.name == "biomes_on" and params.biomes.is_empty()):
		property.usage = PROPERTY_USAGE_NONE
		return
	if property.name == "biomes_on":
		var names := PackedStringArray()
		for b in params.biomes:
			names.append(b.name if b != null else "?")
		property.hint_string = ",".join(names)


# --- the map -----------------------------------------------------------------------------------------------

## The generator for the current settings (params copied, with the island fitted to the map if asked).
func make_generator() -> LFTerrainGenerator:
	return _generator(_map_params(), map_seed)


static func _generator(p: LFMapParams, seed: int) -> LFTerrainGenerator:
	var g := LFTerrainGenerator.new()
	g.params = p
	g.setup(seed)
	return g


## A copy of params as the map uses them (island fitted, mountain rim at the map edge, mountains kept inside).
func _map_params() -> LFMapParams:
	var p: LFMapParams = params.duplicate(true) if params != null else LFMapParams.new()
	if fit_island:
		var half := minf(tiles_x, tiles_z) * tile_size * 0.5
		var r := half * 0.7   # lobes (up to +20 %) and ragged coast stay inside the map
		p.island_radius = r
		p.coast_noise = r * 0.05
		p.coast_band = minf(p.coast_band, r * 0.07)
		p.coast_shelf = minf(p.coast_shelf, r * 0.1)
		p.start_radius = minf(p.start_radius, r * 0.5)
	# the mountain rim stands at the map's edge, and leaves at least 40 % of the map open in the middle
	p.boundary_size = Vector2(tiles_x, tiles_z) * tile_size
	p.rim_width = minf(p.rim_width, minf(p.boundary_size.x, p.boundary_size.y) * 0.3)
	# counted mountains go inside the map (its centre is the region centre), half a mountain's width off the
	# edge, and at least in the middle 60 % of it, so several find room on a small map
	var half_map := minf(tiles_x, tiles_z) * tile_size * 0.5
	p.mountain_area = maxf(half_map - p.mountain_size * 0.5, half_map * 0.6)
	return p


## The ground under `p` (a point in this node's space) as the bake will have it: the 2 m terrain grid,
## split into triangles as the baked mesh is, so things placed on the preview sit on the baked land.
## Returns (normal.x, normal.y, normal.z, height), in this node's space.
func ground_at(p: Vector3) -> Vector4:
	var key := land_key()
	if _ground_gen == null or key != _ground_key:
		_ground_gen = make_generator()
		_ground_key = key
	var w := Vector2(p.x, p.z) + map_origin(_ground_gen) + Vector2(tiles_x, tiles_z) * tile_size * 0.5
	var s := LFTerrainGenerator.STEP
	var c := (w / s).floor() * s
	# sample_grid reads a chunk's grid: fill just the one cell (corners 0, 1, VERTS, VERTS + 1) round w.
	var hs := PackedFloat32Array()
	hs.resize(LFTerrainGenerator.VERTS * 2)
	for k in 4:
		var i := k % 2
		var j := k / 2
		hs[j * LFTerrainGenerator.VERTS + i] = _ground_gen.get_height(c.x + i * s, c.y + j * s)
	return LFTerrainGenerator.sample_grid(hs, w.x - c.x, w.y - c.y)


## The water's surface over `p` (in this node's space, like ground_at): 0 for the sea, or a lake's or river's
## own level up in the hills. The spot is under water where ground_at(p).w is below it.
func water_level_at(p: Vector3) -> float:
	ground_at(p)   # makes the generator for the current settings
	var w := Vector2(p.x, p.z) + map_origin(_ground_gen) + Vector2(tiles_x, tiles_z) * tile_size * 0.5
	return _ground_gen.water_level_at(w.x, w.y)


## Names the land this baker makes (seed, every setting in params, map size, the generator's LAND_VERSION):
## written to tiles.json by a bake.
func land_key() -> String:
	return ("%d/%d/%d/%d/%s/%d/%s" % [map_seed, tile_size, tiles_x, tiles_z, fit_island,
			LFTerrainGenerator.LAND_VERSION, _signature(params, 0, SIGNATURE_DEPTH)]).md5_text()


## The land key Map Baker 1.1 to 2.0 wrote (no generator version; params read 4 levels deep).
func _legacy_land_key() -> String:
	return ("%d/%d/%d/%d/%s/%s" % [map_seed, tile_size, tiles_x, tiles_z, fit_island, _signature(params, 0)]).md5_text()


## Every tile of the map: the Tiles X x Tiles Z grid, the tiles Grow Map adds round it, and the tiles of
## this map already baked in output_dir round that (a grown map stays grown when Add West ... are set back).
func tile_rect() -> Rect2i:
	var r := Rect2i(-add_west, -add_north, tiles_x + add_west + add_east, tiles_z + add_north + add_south)
	var d := baked_rect()
	return r.merge(d) if d.has_area() else r


## The tiles of this map (the same land: land_key) that output_dir holds, as the rect round them; empty when
## it holds none, or another map. Read from its tiles.json (the tile scenes it lists that are still there).
func baked_rect() -> Rect2i:
	var json := output_dir + "/tiles.json"
	if not FileAccess.file_exists(json):
		return Rect2i()
	var stamp := "%s/%d/%s" % [json, FileAccess.get_modified_time(json), land_key()]
	if stamp != _baked_stamp:   # tiles.json read again only when it (or the land) changed
		_baked_stamp = stamp
		_baked_tiles = []
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(json))
		if old is Dictionary and old.has("land") and _same_land(old, null):
			for t: Variant in old.get("tiles", []):
				if t is Dictionary:
					_baked_tiles.append([Vector2i(int(t.get("x", 0)), int(t.get("z", 0))), String(t.get("scene", ""))])
	var out := Rect2i()
	for t: Array in _baked_tiles:   # the scenes still there (one deleted by hand leaves the map)
		if FileAccess.file_exists(output_dir + "/" + String(t[1])):
			out = Rect2i(t[0], Vector2i.ONE) if not out.has_area() else out.merge(Rect2i(t[0], Vector2i.ONE))
	return out


## True if `p` (in this node's space) is over the map.
func covers(p: Vector3) -> bool:
	var r := tile_rect()
	var a := Vector2(r.position) * tile_size - Vector2(tiles_x, tiles_z) * tile_size * 0.5
	var e := a + Vector2(r.size) * tile_size
	return p.x >= a.x and p.x <= e.x and p.z >= a.y and p.z <= e.y


## World-space corner (x, z) where the first tile starts: the map is centred on the island.
func map_origin(g: LFTerrainGenerator) -> Vector2:
	var size := Vector2(tiles_x, tiles_z) * tile_size
	return ((g.region_center - size * 0.5) / LFTileBaker.BLOCK).floor() * LFTileBaker.BLOCK


## The tile Work on One Tile picks, kept inside the map.
func current_tile() -> Vector2i:
	var r := tile_rect()
	return work_tile.clamp(r.position, r.end - Vector2i.ONE)


## A fresh map scene: a root "Map" with an LFMapBaker baking to `output`, a sun with shadows and a sky (so the
## preview is lit as the baked map will be). Every node is owned by the root, ready to pack and save. The
## Tools menu's "New Lowland Forge map" saves one and opens it.
static func new_map_scene(output := "res://maps/map") -> Node3D:
	var root := Node3D.new()
	root.name = "Map"
	var baker := LFMapBaker.new()
	baker.name = "LFMapBaker"
	baker.output_dir = output
	root.add_child(baker)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	for n in [baker, sun, env]:
		n.owner = root
	return root


## Replaces params with a fresh copy of the picked preset (LFMapPresets), as an undoable action in the editor.
func apply_preset() -> void:
	var p := LFMapPresets.make(LFMapPresets.NAMES[clampi(preset, 0, LFMapPresets.NAMES.size() - 1)])
	var ei: Object = Engine.get_singleton(&"EditorInterface") \
			if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	if ei == null:
		params = p
		return
	var ur: Object = ei.get_editor_undo_redo()
	ur.create_action("Apply map preset " + LFMapPresets.NAMES[preset])
	ur.add_do_property(self, &"params", p)
	ur.add_undo_property(self, &"params", params)
	ur.commit_action()


func new_seed() -> void:
	map_seed = randi() % 1000000


## Bakes the map (or the work tile) to output_dir in one go. Returns LFTileBaker.bake's result.
func bake() -> Dictionary:
	var job := _start_job()
	while not job.step():
		pass
	return _bake_done(job)


## Bakes in the editor a block per frame or so, the editor staying usable, with a progress bar (the plugin)
## and Cancel bake. Outside the editor it is bake(). In the editor, baking over a map already in output_dir
## asks first (rebake_warning): the tiles there, and any hand edits in them, are overwritten.
func start_bake() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		bake()
		return
	var warn := rebake_warning()
	if warn != "" and Engine.has_singleton(&"EditorInterface"):
		var dlg := ConfirmationDialog.new()
		dlg.title = "Lowland Forge: bake over a map?"
		dlg.dialog_text = warn
		dlg.ok_button_text = "Bake over it"
		dlg.confirmed.connect(_begin_bake)
		dlg.visibility_changed.connect(func() -> void:
			if not dlg.visible:
				dlg.queue_free())
		Engine.get_singleton(&"EditorInterface").get_base_control().add_child(dlg)
		dlg.popup_centered()
		return
	_begin_bake()


## What a bake now would overwrite in output_dir, as a question for the user, or "" when nothing is lost:
## no map there yet, or New Tiles Only (it writes only tiles not on disk). Names the tiles saved after the
## last bake (edited by hand, most likely).
func rebake_warning() -> String:
	var json := output_dir + "/tiles.json"
	if new_tiles_only or not FileAccess.file_exists(json):
		return ""
	var baked_at := FileAccess.get_modified_time(json)
	var edited := PackedStringArray()
	var mine := current_tile()
	var dir := DirAccess.open(output_dir)
	if dir != null:
		for f in dir.get_files():
			if not (f.begins_with("tile_") and f.ends_with(".tscn")):
				continue
			if one_tile and f != "tile_%d_%d.tscn" % [mine.x, mine.y]:
				continue
			if FileAccess.get_modified_time(output_dir + "/" + f) > baked_at + 2:
				edited.append(f)
	var what := "tile %d, %d" % [mine.x, mine.y] if one_tile else "every tile"
	var text := "%s already holds a baked map. Baking again rewrites %s there, and hand edits in them are lost." \
			% [output_dir, what]
	var off := tiles_off_map()
	if not one_tile and not off.is_empty():
		var some := off.slice(0, 6)
		text += "\n\nIt holds another map (other seed, settings or size): %d tile scenes off this map are deleted: %s%s." \
				% [off.size(), ", ".join(some), " ..." if off.size() > some.size() else ""]
	if not edited.is_empty():
		var shown := edited.slice(0, 6)
		text += "\n\nSaved since the last bake (edited by hand?): %s%s." % [", ".join(shown),
				" and %d more" % (edited.size() - shown.size()) if edited.size() > shown.size() else ""]
	return text + "\n\nTo keep them, set Output Dir to a new folder (or tick New Tiles Only to add tiles)."


## The tile scenes in output_dir that a full bake now deletes: those outside tile_rect() (left by another map:
## this map's own grown tiles are in tile_rect()).
func tiles_off_map() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(output_dir):
		return out
	var r := tile_rect()
	for f in DirAccess.get_files_at(output_dir):
		if f.begins_with("tile_") and f.ends_with(".tscn"):
			var xz := f.trim_prefix("tile_").get_slice(".", 0).split("_")
			if xz.size() == 2 and not r.has_point(Vector2i(int(xz[0]), int(xz[1]))):
				out.append(f)
	return out


func _begin_bake() -> void:
	if _job != null:
		push_warning("LFMapBaker: already baking (Cancel bake to stop).")
		return
	if baking != null and is_instance_valid(baking) and baking != self:
		push_warning("LFMapBaker: another baker is baking.")
		return
	_job = _start_job()
	_job_next = 0
	baking = self


## Stops a bake started with Bake (tiles already written stay).
func cancel_bake() -> void:
	if _job == null:
		return
	_job.cancel()
	_bake_done(_job)


## True while the preview is shown.
func has_preview() -> bool:
	return _preview != null and is_instance_valid(_preview)


## How far the preview is built: 0..1 (land, then props), or -1 when it isn't being built.
func preview_progress() -> float:
	if _land_task < 0 and _props_task < 0:
		return -1.0
	var f := float(_prog[0]) / maxf(_prog[1], 1.0)
	if not _with_props:
		return f
	return 0.15 * f if _land_task >= 0 else 0.15 + 0.85 * f


## Seconds since the preview being built was started.
func preview_seconds() -> float:
	return (Time.get_ticks_msec() - _preview_t0) / 1000.0


## How far the bake is: 0..1, or -1 when not baking (for progress bars).
func bake_progress() -> float:
	if _job == null:
		return -1.0
	return float(_job.done) / maxf(_job.total, 1.0)


func _start_job() -> LFTileBaker.Job:
	var bad := settings_error()
	if bad != "":
		push_error("LFMapBaker: " + bad)
		return _ended(ERR_INVALID_PARAMETER)
	var g := make_generator()
	var rect := tile_rect()
	var only: Array[Vector2i] = []
	if one_tile:
		only.append(current_tile())
	var what := "tile %d, %d of %d x %d" % [only[0].x, only[0].y, rect.size.x, rect.size.y] if one_tile \
			else "%d x %d tiles" % [rect.size.x, rect.size.y]
	if new_tiles_only:
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(output_dir + "/tiles.json")) \
				if FileAccess.file_exists(output_dir + "/tiles.json") else null
		if old is Dictionary and not _same_land(old, g):
			push_error("LFMapBaker: %s holds another map (baked with another seed, params or Tiles X / Z): set them back to add tiles to it, or untick New Tiles Only to bake it all again." % output_dir)
			return _ended(ERR_INVALID_DATA)
		var todo: Array[Vector2i] = only.duplicate()
		if not one_tile:
			for tz in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					todo.append(Vector2i(tx, tz))
		only.clear()
		for t in todo:
			if not FileAccess.file_exists("%s/tile_%d_%d.tscn" % [output_dir, t.x, t.y]):
				only.append(t)
		if only.is_empty():
			print("LFMapBaker: every tile is in %s already (New Tiles Only): nothing to bake." % output_dir)
			return _ended(OK)
		what = "%d new tiles of %d x %d" % [only.size(), rect.size.x, rect.size.y]
	print("LFMapBaker: baking %s of %d m (seed %d) to %s ..." % [what, tile_size, map_seed, output_dir])
	if g.lake_count_placed() < g.params.lake_count:
		push_warning("LFMapBaker: only %d of %d lakes found room: a bigger map, a smaller Lake Size or fewer lakes." \
				% [g.lake_count_placed(), g.params.lake_count])
	if g.peak_count() < g.params.mountain_count and g.params.mountain_height > 0.0:
		push_warning("LFMapBaker: only %d of %d mountains found room: a bigger map, a smaller Mountain Size or fewer mountains." \
				% [g.peak_count(), g.params.mountain_count])
	var job := LFTileBaker.start(g, map_origin(g), tile_size, tiles_x, tiles_z, output_dir, collision, props,
			flowing_rivers, only, rect)
	job.land_key = land_key()
	job.edge_walls = edge_walls and collision and g.params.boundary != LFMapParams.Boundary.ISLAND
	job.prop_range = prop_draw_distance
	job.terrain_layers = terrain_layers
	job.prop_layers = prop_layers
	job.wall_layers = wall_layers
	job.water_areas = water_areas
	job.water_layers = water_layers
	job.water_mask = water_mask
	job.prop_batch = prop_batch_size
	job.threads = bake_threads
	var sp := spawn_point(g)
	var c := map_origin(g) + Vector2(tiles_x, tiles_z) * tile_size * 0.5
	job.has_spawn = true
	job.spawn = sp + Vector3(c.x, 0, c.y)
	return job


## Why the settings can't be baked ("" when they can): Tile Size a multiple of 128 m (at least 128), at least
## one tile each way, an Output Dir. The Inspector keeps to these; code setting them is checked here.
func settings_error() -> String:
	if tile_size < LFTileBaker.BLOCK or tile_size % int(LFTileBaker.BLOCK) != 0:
		return "Tile Size must be a multiple of %d m (it is %d)." % [LFTileBaker.BLOCK, tile_size]
	if tiles_x < 1 or tiles_z < 1:
		return "Tiles X and Tiles Z must be at least 1 (they are %d x %d)." % [tiles_x, tiles_z]
	if output_dir.strip_edges() == "":
		return "Output Dir is empty."
	if params == null:
		return "Params is empty."
	return ""


## Where a player starts, in this node's space (the map's centre at the origin), on the baked ground: the
## generator's spawn (dry, gentle ground near the middle of the land) if it is on the map, else the dry,
## gentle ground nearest the map's centre (or the centre itself). A bake marks it with a Marker3D "Spawn".
func spawn_point(g: LFTerrainGenerator = null) -> Vector3:
	if g == null:
		g = make_generator()
	var c := map_origin(g) + Vector2(tiles_x, tiles_z) * tile_size * 0.5
	var half := Vector2(tiles_x, tiles_z) * tile_size * 0.5 - Vector2(16, 16)   # off the very edge
	var p := g.spawn_xz - c
	# off the map, or (a tiny map) under a lake that found no room clear of it: the nearest dry, gentle ground
	if absf(p.x) > half.x or absf(p.y) > half.y \
			or g.get_height(g.spawn_xz.x, g.spawn_xz.y) < g.water_level_at(g.spawn_xz.x, g.spawn_xz.y) + 0.5:
		p = Vector2.ZERO
		var found := false
		var ring := 1
		while not found and ring <= 80 and ring * 6.0 <= maxf(half.x, half.y):   # out to 480 m
			var count := ring * 6
			for k in count:
				var q := Vector2.from_angle(TAU * k / count) * ring * 6.0
				if absf(q.x) > half.x or absf(q.y) > half.y:
					continue
				var h := g.get_height(q.x + c.x, q.y + c.y)
				if h < g.water_level_at(q.x + c.x, q.y + c.y) + 1.0:
					continue
				var dx := g.get_height(q.x + c.x + 3.0, q.y + c.y) - g.get_height(q.x + c.x - 3.0, q.y + c.y)
				var dz := g.get_height(q.x + c.x, q.y + c.y + 3.0) - g.get_height(q.x + c.x, q.y + c.y - 3.0)
				if absf(dx) < 2.0 and absf(dz) < 2.0:
					p = q
					found = true
					break
			ring += 1
	return Vector3(p.x, ground_at(Vector3(p.x, 0, p.y)).w, p.y)


## True if tiles.json (`old`) is this baker's land. A bake from Map Baker 1.1 to 2.0 has the older land key
## (no generator version: its land can't be told from this version's, a warning says so). One from before 1.1
## has none: its seed, tile size and centre must match (`g`: the generator), and the params can't be checked.
func _same_land(old: Dictionary, g: LFTerrainGenerator) -> bool:
	if old.has("land_version"):
		return String(old.get("land", "")) == land_key()
	if old.has("land"):
		if String(old["land"]) != _legacy_land_key():
			return false
		if g != null:
			push_warning("LFMapBaker: %s was baked before Map Baker 2.1: its land can't be checked against this version's. If new tiles don't join it, bake it all again." % output_dir)
		return true
	if g == null:
		return false
	var c: Array = old.get("world_center", [])
	var center := map_origin(g) + Vector2(tiles_x, tiles_z) * tile_size * 0.5
	if int(old.get("seed", -1)) != map_seed or float(old.get("tile_size", 0)) != tile_size or c.size() != 2 \
			or not Vector2(c[0], c[1]).is_equal_approx(center):
		return false
	push_warning("LFMapBaker: %s was baked before Map Baker 1.1: the seed and size match, but check its params are these too." % output_dir)
	return true


## A job that is already over (nothing baked), with `err`.
static func _ended(err: Error) -> LFTileBaker.Job:
	var job := LFTileBaker.Job.new()
	job.result = {"error": err, "tiles": [], "ms": 0, "props": 0}
	return job


## Moves a bake started with Bake on: saves the blocks the worker threads have built, for up to 30 ms (once a
## frame; the baker's own _process and, while its scene is in another tab, the plugin call it).
func drive_bake() -> void:
	if _job == null or Engine.get_process_frames() == _job_frame:
		return
	_job_frame = Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30:
		var was := _job.done
		if _job.step(false):
			_bake_done(_job)
			return
		if _job.done == was:
			break   # the next block is still being built
	if _job.done >= _job_next:
		print("  %d / %d blocks" % [_job.done, _job.total])
		_job_next = _job.done + maxi(_job.total / 10, 16)


func _bake_done(job: LFTileBaker.Job) -> Dictionary:
	var info := job.result
	_job = null
	if baking == self:
		baking = null
	var dir := ProjectSettings.globalize_path(output_dir) if output_dir.begins_with("res://") else output_dir
	if info["error"] == ERR_SKIP:
		print("LFMapBaker: bake cancelled after %d / %d blocks" % [job.done, job.total])
	elif info["error"] != OK:
		push_error("LFMapBaker: bake failed (%s) in %s" % [error_string(info["error"]), dir])
	else:
		print("LFMapBaker: %d tiles, %d props in %.1f s -> %s/map.tscn" % [info["tiles"].size(), info["props"],
				info["ms"] / 1000.0, output_dir])
	_rescan()
	return info


## Writes the whole map as heightmap files (LFHeightmapExport) to output_dir/heightmap_*. Returns when done
## (the Inspector button uses start_export_heightmap, which does not block the editor).
func export_heightmap() -> Dictionary:
	var info := _heightmap_job(make_generator(), _exp_prog_new())
	_report_heightmap(info)
	_rescan()
	return info


## Writes a top-down picture of the whole map (LFMapImage: the land lit from the north-west, water, rivers,
## the spawn) to output_dir/map_image.png. Its pixel (0, 0) is the map's north-west corner. Returns the error
## once it is written (the Inspector button uses start_export_map_image, which does not block the editor).
func export_map_image() -> Error:
	var err := _map_image_job(make_generator(), _exp_prog_new())
	_report_map_image(err)
	_rescan()
	return err


## export_heightmap() on a worker thread, for the editor: returns at once, and _process finishes it (prints,
## rescans) when the files are written. Watch export_progress(), stop it with cancel_export(). Outside the editor
## (or the tree) it just runs export_heightmap().
func start_export_heightmap() -> void:
	_start_export(true)


## export_map_image() on a worker thread, like start_export_heightmap().
func start_export_map_image() -> void:
	_start_export(false)


## How far the running export is: 0..1, or -1 when none runs (for progress bars).
func export_progress() -> float:
	if _exp_task < 0:
		return -1.0
	return float(_exp_prog[0]) / maxf(_exp_prog[1], 1.0)


## Stops the running export (start_export_*): its files are not written.
func cancel_export() -> void:
	_exp_prog[2] = true


func _exp_prog_new() -> Array:
	_exp_prog = [0, 0, false]
	return _exp_prog


func _start_export(heightmap: bool) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		if heightmap:
			export_heightmap()
		else:
			export_map_image()
		return
	if _exp_task >= 0 or (exporting != null and is_instance_valid(exporting)):
		push_warning("LFMapBaker: an export is already running.")
		return
	_exp_heightmap = heightmap
	_exp_out = {}
	var g := make_generator()
	var prog := _exp_prog_new()
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	var job := func() -> void:
		if heightmap:
			_exp_out = _heightmap_job(g, prog)
		else:
			_exp_out = {"error": _map_image_job(g, prog)}
	exporting = self
	_exp_task = WorkerThreadPool.add_task(job, true, "LFMapBaker export")


func _finish_export() -> void:
	WorkerThreadPool.wait_for_task_completion(_exp_task)
	_exp_task = -1
	if exporting == self:
		exporting = null
	if _exp_heightmap:
		_report_heightmap(_exp_out)
	else:
		_report_map_image(_exp_out["error"])
	_rescan()


# The map's square, as export_heightmap and export_map_image both need it: [center, size].
func _export_square(g: LFTerrainGenerator) -> Array:
	var r := tile_rect()
	var size := maxf(r.size.x, r.size.y) * tile_size
	var o := map_origin(g) + Vector2(r.position) * tile_size
	return [o + Vector2(r.size) * tile_size * 0.5, size]


func _heightmap_job(g: LFTerrainGenerator, prog: Array) -> Dictionary:
	var sq := _export_square(g)
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	return LFHeightmapExport.export(g, sq[0], sq[1], heightmap_step, output_dir + "/heightmap", prog)


func _map_image_job(g: LFTerrainGenerator, prog: Array) -> Error:
	var sq := _export_square(g)
	return LFMapImage.save(g, sq[0], sq[1], map_image_px, output_dir + "/map_image.png", map_image_overlay, true, prog)


func _report_heightmap(info: Dictionary) -> void:
	if info["error"] == ERR_SKIP:
		print("LFMapBaker: heightmap export cancelled")
	elif info["error"] != OK:
		push_error("LFMapBaker: heightmap export failed (%s)" % error_string(info["error"]))
	else:
		print("LFMapBaker: heightmap %d px -> %s/heightmap_height.exr" % [info["size_px"], output_dir])


func _report_map_image(err: Error) -> void:
	if err == ERR_SKIP:
		print("LFMapBaker: map image export cancelled")
	elif err != OK:
		push_error("LFMapBaker: map image failed (%s)" % error_string(err))
	else:
		print("LFMapBaker: map image %d px (%.1f m per pixel) -> %s/map_image.png" % [map_image_px,
				maxf(tile_rect().size.x, tile_rect().size.y) * tile_size / map_image_px, output_dir])


func _rescan() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		# Looked up by name: EditorInterface does not exist in exported games, where this script still loads.
		Engine.get_singleton(&"EditorInterface").get_resource_filesystem().scan()


# --- preview -----------------------------------------------------------------------------------------------

func _queue_preview() -> void:
	_dirty = true
	_dirty_at = Time.get_ticks_msec()


## Rebuilds the preview, on worker threads: the map as one coloured mesh (centred like the bake) and a
## water plane, then its trees, rocks and logs. With Work on One Tile: that tile in detail, the rest of the map
## coarse round it. Every tile is labelled with its column, row when the map has more than one.
func refresh_preview() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	if _land_task >= 0 or _props_task >= 0:
		_refresh_wanted = true   # after the running one
		return
	_refresh_wanted = false
	var size := Vector2(tiles_x, tiles_z) * tile_size
	var full := tile_rect()
	var tile := Rect2i(current_tile(), Vector2i.ONE) if one_tile and full.get_area() > 1 else full
	var rs := Vector2(tile.size) * tile_size
	_with_props = preview_props and props != LFTileBaker.Props.NONE \
			and (preview_props_limit <= 0.0 or rs.x * rs.y <= preview_props_limit * 1e6)
	_preview_t0 = Time.get_ticks_msec()
	_prog = [0, 0, false]
	loading = self
	_land_out = {}
	_land_task = WorkerThreadPool.add_task(_build_land.bind(_map_params(), map_seed, size, float(tile_size), tile,
			full, preview_step, flowing_rivers), false, "LFMapBaker preview land")


## The preview land (worker thread): `tile` = the tiles shown in detail, the rest of the map (`full`) coarse.
## `size`: the Tiles X x Tiles Z grid, which places the map.
func _build_land(p: LFMapParams, seed: int, size: Vector2, ts: float, tile: Rect2i, full: Rect2i,
		step: float, flow := false) -> void:
	var t0 := Time.get_ticks_msec()
	var g := _generator(p, seed)
	var o := ((g.region_center - size * 0.5) / LFTileBaker.BLOCK).floor() * LFTileBaker.BLOCK   # map_origin
	var shift := o + size * 0.5   # world -> the preview's centred frame
	var r0 := o + Vector2(tile.position) * ts
	var rs := Vector2(tile.size) * ts
	if step <= 0.0:
		step = maxf(4.0, maxf(rs.x, rs.y) / 256.0)
	var fo := o + Vector2(full.position) * ts
	var fs := Vector2(full.size) * ts
	var out := {"g": g, "o": o, "r0": r0, "rs": rs, "step": step, "size": size, "fo": fo, "fs": fs,
			"land": _land_arrays(g, r0, rs, step, shift, Rect2(), _prog)}
	if tile != full:
		var k := maxi(1, 64 / maxi(full.size.x, full.size.y))   # ~64 samples across the map, each tile whole
		out["rest"] = _land_arrays(g, fo, fs, ts / k, shift, Rect2(r0, rs), _prog)
	if flow and p.river_count > 0 and not _prog[2]:
		out["flow"] = _flow_arrays(g, r0, rs, step, shift)
	out["ms"] = Time.get_ticks_msec() - t0
	_land_out = {} if _prog[2] else out


## The preview's river flow overlay (Flowing Rivers) over `size` metres from world `o`, `step` apart, in the
## frame `shift` centres: [vertices, uvs, colours (LFChunkData.flow_color), indices], empty without rivers.
static func _flow_arrays(g: LFTerrainGenerator, o: Vector2, size: Vector2, step: float, shift: Vector2) -> Array:
	var nx := int(size.x / step) + 1
	var nz := int(size.y / step) + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	uvs.resize(nx * nz)
	cols.resize(nx * nz)
	var live := PackedByteArray()
	live.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var x := o.x + i * step
			var z := o.y + j * step
			var lv := g.water_level_at(x, z)
			cols[k] = Color(0.5, 0.5, 0.0, 0.0)
			if g.river_factor(x, z) > 0.5:
				cols[k] = LFChunkData.flow_color(g, x, z, g.get_height(x, z) - lv, lv)
				live[k] = 1 if cols[k].b > 0.0 else 0
			verts[k] = Vector3(x - shift.x, lv + LFChunkData.RIVER_OVERLAY_Y, z - shift.y)
			uvs[k] = Vector2(x, z)
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			if live[a] + live[a + 1] + live[a + nx] + live[a + nx + 1] > 0:
				idx.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	return [] if idx.is_empty() else [verts, uvs, cols, idx]


## A flat-shaded patch of land `size` metres from world `o`, `step` apart, in the frame `shift` centres;
## cells inside `skip` left out. [vertices, normals, colours, water vertices: the water up in the hills (lakes
## and rivers above the sea; the sea is the flat plane), empty without]. Counts its rows into `prog` ([done,
## total, cancelled]) and stops early, empty, once cancelled is set.
static func _land_arrays(g: LFTerrainGenerator, o: Vector2, size: Vector2, step: float, shift: Vector2,
		skip: Rect2, prog: Array = [0, 0]) -> Array:
	var nx := int(roundf(size.x / step)) + 1
	var nz := int(roundf(size.y / step)) + 1
	prog[1] += nz
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	cols.resize(nx * nz)
	var raised := g.has_raised_water()
	var levels := PackedFloat32Array()
	levels.resize(nx * nz if raised else 0)
	for j in nz:
		if prog.size() > 2 and prog[2]:
			return [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector3Array()]
		for i in nx:
			var x := o.x + i * step
			var z := o.y + j * step
			verts[j * nx + i] = Vector3(x - shift.x, g.get_height(x, z), z - shift.y)
			cols[j * nx + i] = g.biome_color(g.biome_weights(x, z))
			if raised:
				levels[j * nx + i] = g.water_level_at(x, z)
		prog[0] += 1
	# Flat shading and the slope / height colours need per-triangle data: unshared vertices.
	var fv := PackedVector3Array()
	var fc := PackedColorArray()
	var fn := PackedVector3Array()
	var fw := PackedVector3Array()
	var low := LFTerrainGenerator.WATER_LEVEL + 0.05
	for j in nz - 1:
		for i in nx - 1:
			if skip.has_point(o + Vector2(i + 0.5, j + 0.5) * step):
				continue
			var a := j * nx + i
			var tris := [[a, a + 1, a + nx], [a + 1, a + nx + 1, a + nx]]
			var ns: Array[Vector3] = []
			var info: Array[Vector3] = []   # per triangle: mean height, normal y, water level (as LFChunkData)
			for tri: Array in tris:
				var va := verts[tri[0]]
				var vb := verts[tri[1]]
				var vc := verts[tri[2]]
				var n := (vc - va).cross(vb - va).normalized()
				var wl := LFTerrainGenerator.WATER_LEVEL
				if raised:
					wl = (levels[tri[0]] + levels[tri[1]] + levels[tri[2]]) / 3.0
				ns.append(n)
				info.append(Vector3((va.y + vb.y + vc.y) / 3.0, n.y, wl))
			var qc := g.quad_shade(cols[a], o + Vector2(i + 0.5, j + 0.5) * step, info[0], info[1])
			for t in 2:
				var col := qc[0] if qc.size() == 1 else qc[t]
				var n := ns[t]
				fv.append_array(PackedVector3Array([verts[tris[t][0]], verts[tris[t][1]], verts[tris[t][2]]]))
				fc.append_array(PackedColorArray([col, col, col]))
				fn.append_array(PackedVector3Array([n, n, n]))
			if raised:   # the water above the sea over this cell (as LFChunkData.raised_water)
				var ks := [a, a + 1, a + nx, a + nx + 1]
				var top := INF   # the cell's lowest raised level
				for k: int in ks:
					if levels[k] > low:
						top = minf(top, levels[k])
				if top == INF:
					continue
				var q: Array[Vector3] = []
				var wet := false
				for k: int in ks:
					var l := levels[k] if levels[k] > low or verts[k].y < top - 0.05 else top   # as LFTileBaker._corner_water
					q.append(Vector3(verts[k].x, l, verts[k].z))
					wet = wet or verts[k].y < l
				if wet:
					fw.append_array(PackedVector3Array([q[0], q[1], q[2], q[1], q[3], q[2]]))
	return [fv, fn, fc, fw]


static func _preview_water_material() -> StandardMaterial3D:
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.16, 0.45, 0.6, 0.75)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.2
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return wm


func _finish_land() -> void:
	WorkerThreadPool.wait_for_task_completion(_land_task)
	_land_task = -1
	var out := _land_out
	_land_out = {}
	if _refresh_wanted or _prog[2] or out.is_empty() or not is_inside_tree():
		return   # stale (the next refresh replaces it) or cancelled
	var size: Vector2 = out["size"]
	if _preview != null:
		_preview.queue_free()
	_preview = Node3D.new()
	_preview.name = "_Preview"
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	for key in ["land", "rest"]:
		if not out.has(key) or (out[key][0] as PackedVector3Array).is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = out[key][0]
		arrays[Mesh.ARRAY_NORMAL] = out[key][1]
		arrays[Mesh.ARRAY_COLOR] = out[key][2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var land := MeshInstance3D.new()
		land.name = "Land" if key == "land" else "Rest"
		land.mesh = mesh
		land.material_override = mat
		_preview.add_child(land)
	for key in ["land", "rest"]:
		var arrs: Array = out.get(key, [])
		if arrs.size() > 3 and not (arrs[3] as PackedVector3Array).is_empty():
			var wa: Array = []
			wa.resize(Mesh.ARRAY_MAX)
			wa[Mesh.ARRAY_VERTEX] = arrs[3]
			var raised_mesh := ArrayMesh.new()
			raised_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
			var raised := MeshInstance3D.new()
			raised.name = "RaisedWater"
			raised.mesh = raised_mesh
			raised.material_override = _preview_water_material()
			_preview.add_child(raised)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = out["fs"]
	water.mesh = plane
	water.material_override = _preview_water_material()
	var mid: Vector2 = out["fo"] + out["fs"] * 0.5 - (out["o"] + size * 0.5)
	water.position = Vector3(mid.x, LFTerrainGenerator.WATER_LEVEL, mid.y)
	_preview.add_child(water)
	var fa: Array = out.get("flow", [])
	if not fa.is_empty():
		var ra: Array = []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = fa[0]
		ra[Mesh.ARRAY_TEX_UV] = fa[1]
		ra[Mesh.ARRAY_COLOR] = fa[2]
		ra[Mesh.ARRAY_INDEX] = fa[3]
		var normals := PackedVector3Array()
		normals.resize((fa[0] as PackedVector3Array).size())
		normals.fill(Vector3.UP)
		ra[Mesh.ARRAY_NORMAL] = normals
		var fm := ArrayMesh.new()
		fm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
		var flow := MeshInstance3D.new()
		flow.name = "RiverFlow"
		flow.mesh = fm
		var fmat := ShaderMaterial.new()
		fmat.shader = load("res://addons/lowland_forge/shaders/river_flow.gdshader")
		flow.material_override = fmat
		flow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview.add_child(flow)
	var falls := (out["g"] as LFTerrainGenerator).waterfalls()
	if not falls.is_empty():
		var mats := LFWaterfall.make_materials()
		var shift: Vector2 = out["o"] + size * 0.5
		for f in falls:
			_preview.add_child(LFWaterfall.build(f, mats, Vector3(shift.x, 0.0, shift.y)))
	_add_tile_labels(size)
	add_child(_preview)   # no owner: never saved with the scene
	var rs: Vector2 = out["rs"]
	print("LFMapBaker: preview %d x %d m (%.0f m step) in %d ms" % [rs.x, rs.y, out["step"], out["ms"]])
	if not _with_props:
		if preview_props and props != LFTileBaker.Props.NONE:
			print("LFMapBaker: preview props left out (%.1f km² > Preview Props Limit): work on one tile to see them"
					% (rs.x * rs.y / 1e6))
		_preview_done()
		return
	_start_props(out["g"], out["r0"], rs, out["o"] + size * 0.5, out["step"])


## "x, z" over the middle of every tile (the work tile's in yellow), when there is more than one. With New
## Tiles Only, the tiles already baked say "kept".
func _add_tile_labels(size: Vector2) -> void:
	var r := tile_rect()
	if r.get_area() < 2:
		return
	var top := 40.0 + (params.mountain_height if params != null else 0.0)
	for tz in range(r.position.y, r.end.y):
		for tx in range(r.position.x, r.end.x):
			var l := Label3D.new()
			l.text = "%d, %d" % [tx, tz]
			if new_tiles_only and FileAccess.file_exists("%s/tile_%d_%d.tscn" % [output_dir, tx, tz]):
				l.text += "\nkept"
				l.modulate = Color(0.7, 0.7, 0.7)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.font_size = 64
			l.outline_size = 12
			l.pixel_size = tile_size * 0.12 / 64.0
			if one_tile and Vector2i(tx, tz) == current_tile():
				l.modulate = Color(1.0, 0.85, 0.3)
			l.position = Vector3((tx + 0.5) * tile_size - size.x * 0.5, top, (tz + 0.5) * tile_size - size.y * 0.5)
			_preview.add_child(l)


## Places the preview's trees, rocks and logs on a worker thread (LFPropPlacer.place_large: where the bake
## puts them) over `rs` metres from world `r0`; `shift` is the world point at the preview's centre.
func _start_props(g: LFTerrainGenerator, r0: Vector2, rs: Vector2, shift: Vector2, step: float) -> void:
	var swaps_sig := _signature(g.params.prop_swaps, 0)
	if _lib == null or _lib_seed != map_seed or _lib.rock_color != g.params.rock_color or _lib_swaps != swaps_sig:
		_lib = LFPropMeshes.new()
		_lib.rock_color = g.params.rock_color
		_lib.swaps = g.params.prop_swaps
		_lib.build(map_seed)
		_lib_seed = map_seed
		_lib_swaps = swaps_sig
	_props_out = {}
	_prog = [0, int(rs.x / LFTerrainGenerator.CHUNK_SIZE) * int(rs.y / LFTerrainGenerator.CHUNK_SIZE), false]
	_props_task = WorkerThreadPool.add_task(_place_props.bind(g, _lib, r0, rs, shift, step), false,
			"LFMapBaker preview props")


func _place_props(g: LFTerrainGenerator, lib: LFPropMeshes, r0: Vector2, rs: Vector2, shift: Vector2,
		step: float) -> void:
	var cs := LFTerrainGenerator.CHUNK_SIZE
	var V := LFTerrainGenerator.VERTS
	var S := LFTerrainGenerator.STEP
	var out := {}
	var c0 := Vector2i(roundi(r0.x / cs), roundi(r0.y / cs))
	for cj in int(rs.y / cs):
		for ci in int(rs.x / cs):
			if _prog[2]:
				_props_out = {}
				return
			var coord := c0 + Vector2i(ci, cj)
			var heights := PackedFloat32Array()
			heights.resize(V * V)
			for j in V:
				for i in V:
					heights[j * V + i] = g.get_height(coord.x * cs + i * S, coord.y * cs + j * S)
			var off := Vector3(coord.x * cs - shift.x, 0, coord.y * cs - shift.y)
			var batches := LFPropPlacer.place_large(g, lib, coord, heights,
					LFChunkData.water_levels(g, Vector3(coord.x, 0, coord.y) * LFTerrainGenerator.CHUNK_SIZE))
			for key: Vector2i in batches:
				if not out.has(key):
					out[key] = [] as Array[Transform3D]
				for xf: Transform3D in batches[key]:
					if key.x == LFPropMeshes.Kind.CLIFF:   # onto the preview's coarser land (else they float)
						xf.origin.y = _coarse_base(g, r0, step, xf, Vector2(off.x + shift.x, off.z + shift.y))
					out[key].append(xf.translated(off))
			_prog[0] += 1
	_props_out = out


## A cliff rock's base height on the preview land: as far under the coarse land as it is under the real
## ground, and under the lowest coarse ground across its footprint. `at`: its chunk's world corner.
static func _coarse_base(g: LFTerrainGenerator, r0: Vector2, step: float, xf: Transform3D, at: Vector2) -> float:
	var y := xf.origin.y + _coarse_height(g, r0, step, at.x + xf.origin.x, at.y + xf.origin.z) \
			- g.get_height(at.x + xf.origin.x, at.y + xf.origin.z)
	for d: Vector3 in [Vector3(-2, 0, -1), Vector3(2, 0, -1), Vector3(-2, 0, 1), Vector3(2, 0, 1)]:
		var p := xf.origin + xf.basis * d
		y = minf(y, _coarse_height(g, r0, step, at.x + p.x, at.y + p.z) - 0.6)
	return y


## The preview land's height at world (x, z): its samples are `step` apart from `r0`, drawn as flat
## triangles, so between samples it is near their bilinear blend.
static func _coarse_height(g: LFTerrainGenerator, r0: Vector2, step: float, x: float, z: float) -> float:
	var f := (Vector2(x, z) - r0) / step
	var c := f.floor()
	var t := f - c
	var p := r0 + c * step
	var h00 := g.get_height(p.x, p.y)
	var h10 := g.get_height(p.x + step, p.y)
	var h01 := g.get_height(p.x, p.y + step)
	var h11 := g.get_height(p.x + step, p.y + step)
	return lerpf(lerpf(h00, h10, t.x), lerpf(h01, h11, t.x), t.y)


func _finish_props() -> void:
	WorkerThreadPool.wait_for_task_completion(_props_task)
	_props_task = -1
	if _refresh_wanted or _prog[2]:
		_props_out = {}
		return   # the next refresh replaces it, or it was cancelled
	_preview_done()
	if _preview == null or not is_instance_valid(_preview) or not preview_props or props == LFTileBaker.Props.NONE:
		return
	var names: Array = LFPropMeshes.Kind.keys()
	var n := 0
	for key: Vector2i in _props_out:
		var xfs: Array = _props_out[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _lib.get_mesh(key.x, key.y)
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [String(names[key.x]).capitalize(), key.y]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # thousands of trees: shadows cost the most
		_preview.add_child(mmi)
		n += xfs.size()
	_props_out = {}
	print("LFMapBaker: preview props %d (%.1f s)" % [n, preview_seconds()])


## Stops the preview being built (the land keeps the last preview; props stop where they got to, none shown).
## Auto Preview starts again on the next change, or press Refresh preview.
func cancel_preview() -> void:
	_dirty = false
	_refresh_wanted = false
	if _land_task < 0 and _props_task < 0:
		return
	_prog[2] = true
	_preview_done()
	print("LFMapBaker: preview cancelled")


func _preview_done() -> void:
	if loading == self:
		loading = null


## Blocks until the preview (land, then props) is built and shown (tools and tests; the editor just waits).
func wait_preview() -> void:
	while true:
		if _land_task >= 0:
			_finish_land()
		elif _props_task >= 0:
			_finish_props()
		elif _refresh_wanted:
			refresh_preview()
		else:
			return


## A cheap fingerprint of a resource's saved properties (nested resources included, `limit` levels deep).
func _signature(r: Variant, depth: int, limit := 4) -> String:
	if r == null or depth > limit:
		return "-"
	if r is Mesh:   # by name: its vertex data is huge
		return "mesh:%s:%d" % [(r as Mesh).resource_path, (r as Mesh).get_surface_count()]
	if r is Resource:
		var parts := PackedStringArray()
		for p in (r as Resource).get_property_list():
			if p["usage"] & PROPERTY_USAGE_STORAGE and p["name"] != "resource_path":
				# Settings added after Map Baker 2.0 stay out of the signature (so a map baked before them keeps its
				# land key): roamers never shape the land, biome_regions only counts once one is set.
				if p["name"] == "roamers" or (p["name"] == "biome_regions" and r.get(p["name"]) == null):
					continue
				if (p["name"] == "rim_pass" or p["name"] == "rim_pass_width") and not r.get("rim_pass"):
					continue   # rim_pass counts only once it is on
				if p["name"] == "prop_swaps" and (r.get(p["name"]) as Array).is_empty():
					continue
				parts.append(_signature(r.get(p["name"]), depth + 1, limit))
		return "{" + ",".join(parts) + "}"
	if r is Array:
		var parts := PackedStringArray()
		for v in r:
			parts.append(_signature(v, depth + 1, limit))
		return "[" + ",".join(parts) + "]"
	return var_to_str(r)
