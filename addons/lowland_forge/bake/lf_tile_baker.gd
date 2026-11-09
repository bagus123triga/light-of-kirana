class_name LFTileBaker
extends RefCounted
## Bakes a generated map to plain scenes (no scripts): a grid of tiles, each `<out>/tile_<x>_<z>.tscn`, made of
## 128 m block scenes (`<out>/blocks/block_<x>_<z>.scn`: terrain mesh, height-field collision, river overlay,
## props as MultiMeshes, prop collision as one shape per block). Prop meshes and materials are saved once
## (`<out>/shared/`) and shared; materials point at the addon's shaders by path. `<out>/shared/props/` holds a
## ready scene per prop (mesh + collision) to drag into a map by hand, whatever `props` was baked.
## `<out>/map_edge.tscn` holds what lies round the whole map: invisible walls at its edge and the open sea past
## it. `<out>/map.tscn` instances every tile and the edge; `<out>/tiles.json` lists them. The map is centred on
## the origin: a tile scene added at (0, 0, 0) sits in its place, so tiles can be loaded one by one (a loading
## screen per tile) and still line up. A grown map (`tiles`) keeps that centre: its added tiles are numbered
## on past the grid, below 0 to the west and north (`tile_-1_0.tscn`).
## Every height, colour and prop is a function of seed + params + world position, so tiles join exactly.
##
##   var info := LFTileBaker.bake(gen, Vector2(-1024, -1024), 1024.0, 2, 2, "res://maps/map")

const BLOCK := 128.0
const BLOCK_CHUNKS := 4   # BLOCK / LFTerrainGenerator.CHUNK_SIZE
const BLOCK_CELLS := 64   # height samples per block side - 1 (2 m apart)
const SMALL_PROP_RANGE := 120.0   # grass, flowers, ferns, mushrooms stop drawing this far away (m)
const DRY := -1000000   # a cell with no water (_cell_bands)
const WATER_BAND := 0.5   # m: water areas are split by water level in steps this tall (a lake up in the hills, a falling river)
## How far the sea reaches past a map side that ends in open sea (m): a few big water quads in each edge
## tile, so an island bake doesn't end in a square slab of sea.
const SEA_RING := 6000.0
## Which props a bake places: all of them, only the big ones (trees, rocks, logs), or none (bare terrain;
## the prop scenes in shared/props are still written, to place by hand).
enum Props { ALL, LARGE, NONE }
## The groups baked nodes are in (saved with the scenes), so a game can tell what a ray or a body hit:
## `collider.is_in_group(LFTileBaker.GROUP_TREE)`. The spawn Marker3D is in GROUP_SPAWN.
const GROUP_TERRAIN := &"terrain"
const GROUP_TREE := &"tree"
const GROUP_ROCK := &"rock"
const GROUP_LOG := &"log"
const GROUP_WATER := &"water"
const GROUP_EDGE_WALL := &"edge_wall"
const GROUP_SPAWN := &"spawn"
## tiles.json's layout: 2 adds "format", "land_version" and "grid" (the Tiles X x Tiles Z grid that places
## the map; "tiles_x" / "tiles_z" / "first_tile" are every tile's, a grown map's too).
const TILES_FORMAT := 2


## Bakes tiles_x x tiles_z tiles of `tile_size` metres (a multiple of BLOCK), the first starting at world
## `origin` (snapped to BLOCK). Returns {"error": Error, "tiles": Array, "ms": int, "props": int}.
## `progress` (optional) is called with (done: int, total: int) after each block. `props`: Props.
## `river_flow`: a moving-streaks overlay on rivers (RiverFlow); off, rivers are still water like lakes.
## `only` (optional): the tiles (column, row) to bake; the rest of the folder is kept (see Job).
## `tiles` (optional): the map's tiles when it reaches past the grid (a grown map): columns and rows may go
## below 0 and past tiles_x / tiles_z, the grid still placing the map and its centre. Empty: the grid.
static func bake(gen: LFTerrainGenerator, origin: Vector2, tile_size: float, tiles_x: int, tiles_z: int,
		out_dir: String, collision := true, progress := Callable(), props := Props.ALL,
		river_flow := false, only: Array[Vector2i] = [], tiles := Rect2i()) -> Dictionary:
	var job := start(gen, origin, tile_size, tiles_x, tiles_z, out_dir, collision, props, river_flow, only, tiles)
	while not job.step():
		if progress.is_valid():
			progress.call(job.done, job.total)
	if progress.is_valid() and job.done > 0:
		progress.call(job.done, job.total)
	return job.result


## The same bake as a Job to run a step at a time (an editor draws a progress bar between steps).
static func start(gen: LFTerrainGenerator, origin: Vector2, tile_size: float, tiles_x: int, tiles_z: int,
		out_dir: String, collision := true, props := Props.ALL, river_flow := false,
		only: Array[Vector2i] = [], tiles := Rect2i()) -> Job:
	var job := Job.new()
	job.setup(gen, origin, tile_size, tiles_x, tiles_z, out_dir, collision, props, river_flow, only, tiles)
	return job


## A bake split into steps of one 128 m block each. `step()` until it returns true, then read `result`.
## Blocks are built on worker threads (`threads`), a few ahead of the one being saved; each step saves the next
## block in order on the calling thread, so the files are the same whatever the thread count.
## Baking only some tiles (`only`) keeps the other tile scenes already in the folder, and map.tscn and
## tiles.json list every tile of the map that is on disk; tiles from a different seed or grid are warned of.
class Job:
	extends RefCounted
	## Blocks baked so far, and in all.
	var done := 0
	## Invisible walls along the map's outer sides (an EdgeWall body in map_edge.tscn), so nothing walks
	## or falls off the map. Set before the bake ends.
	var edge_walls := false
	## How far away (m) trees, rocks and logs stop drawing, fading out over the last 10 % (0 = always drawn;
	## ground cover always stops at SMALL_PROP_RANGE). Set before the first step(), as the rest below.
	var prop_range := 0.0
	## The props are batched (a MultiMesh per prop kind and variant, a collision body per kind) over squares
	## this many metres across: a multiple of BLOCK that divides the tile (else the largest that does). BLOCK
	## (128): inside each block scene, as Map Baker 2.0 baked them; more: in their own scenes,
	## `<out>/props/props_<x>_<z>.scn`, for fewer draw calls (a quarter at 256 m).
	var prop_batch := 256.0
	## Worker threads building blocks at once (0: one per CPU core but one; 1: one at a time).
	var threads := 0
	## Physics layers of the baked bodies: the land, the props (trees, rocks, logs) and the edge walls.
	var terrain_layers := 1
	var prop_layers := 1
	var wall_layers := 1
	## An Area3D (WaterArea, in GROUP_WATER) over each block's water and the sea round an island, on
	## water_layers, watching water_mask: body_entered / body_exited say when something goes in or out.
	var water_areas := false
	var water_layers := 1
	var water_mask := 1
	## The spawn point (world x, height, world z) if has_spawn: a Marker3D "Spawn" in its tile, and in tiles.json.
	var has_spawn := false
	var spawn := Vector3.ZERO
	## Names the land (seed, params, grid, generator version) in tiles.json, so a later bake can tell whether
	## the tiles on disk are its land (LFMapBaker: bake only the new tiles of a grown map).
	var land_key := ""
	## The Tiles X x Tiles Z grid that places the map, in tiles.json (a grown map's tiles reach past it).
	var grid := Vector2i.ZERO
	var total := 0
	## bake()'s result once finished (or failed, or cancelled: error ERR_SKIP), else empty.
	var result := {}
	## Tile scenes a full bake removed (off the map it baked), by file name.
	var removed: PackedStringArray = []
	var _gen: LFTerrainGenerator
	var _lib: LFPropMeshes
	var _shared: Dictionary
	var _sea: Dictionary
	var _origin: Vector2
	var _center: Vector2
	var _ts: float
	var _grid: Vector2i
	var _rect: Rect2i   # every tile of the map: the grid, or round it when the map was grown
	var _out: String
	var _collision: bool
	var _props: int
	var _flow: bool
	var _todo: Array[Vector2i] = []
	var _ti := 0   # the tile in _todo being baked...
	var _bi := 0   # ... and its next block
	var _per := 1   # blocks along a tile side
	var _cpb := 1   # blocks along a prop batch side (set on the first step, from prop_batch)
	var _tile: Node3D
	var _cells := {}   # the tile being baked: Vector2i batch (in the tile) -> its blocks' prop data, in order
	var _baked: Array = []
	var _full := true   # every tile of the map (no `only`): leftovers of an earlier bake are removed
	var _written := {}   # block and prop file names this bake wrote
	var _started := false   # the first step ran (shared/props written, once the layers are set)
	var _prop_count := 0
	var _t0 := 0
	var _next := 0   # the next block (in bake order) to hand to a worker
	var _tasks := {}   # block index -> WorkerThreadPool task
	var _ready := {}   # block index -> its data (_block_data), written by the workers under _mutex
	var _mutex := Mutex.new()
	var _stop := false   # read by the workers: skip what isn't started

	func setup(gen: LFTerrainGenerator, origin: Vector2, tile_size: float, tiles_x: int, tiles_z: int,
			out_dir: String, collision: bool, props: int, river_flow: bool, only: Array[Vector2i],
			tiles := Rect2i()) -> void:
		_t0 = Time.get_ticks_msec()
		_gen = gen
		_out = out_dir
		if tiles_x < 1 or tiles_z < 1 or tile_size < BLOCK or not is_finite(tile_size) or gen == null:
			push_error("LFTileBaker: nothing to bake: %d x %d tiles of %s m (at least 1 x 1 tiles of %d m)." \
					% [tiles_x, tiles_z, tile_size, BLOCK])
			_fail(ERR_INVALID_PARAMETER)
			return
		_ts = roundf(tile_size / BLOCK) * BLOCK
		if _ts != tile_size:
			push_warning("LFTileBaker: tile size %s m is not a multiple of %d m: baking %d m tiles." % [tile_size, BLOCK, _ts])
		_origin = (origin / BLOCK).floor() * BLOCK
		_grid = Vector2i(tiles_x, tiles_z)
		grid = _grid
		_center = _origin + Vector2(_grid) * _ts * 0.5
		_rect = tiles if tiles.has_area() else Rect2i(Vector2i.ZERO, _grid)
		_collision = collision
		_props = props
		_flow = river_flow
		for tz in range(_rect.position.y, _rect.end.y):
			for tx in range(_rect.position.x, _rect.end.x):
				if only.is_empty() or only.has(Vector2i(tx, tz)):
					_todo.append(Vector2i(tx, tz))
		_full = _todo.size() == _rect.get_area()
		_per = int(_ts / BLOCK)
		total = _todo.size() * _per * _per
		for d in [out_dir, out_dir + "/blocks", out_dir + "/shared", out_dir + "/shared/props"]:
			if not DirAccess.dir_exists_absolute(d):
				var e := DirAccess.make_dir_recursive_absolute(d)
				if e != OK:
					_fail(e)
					return
		_lib = LFPropMeshes.new()
		if gen.params != null:
			_lib.rock_color = gen.params.rock_color
			_lib.swaps = gen.params.prop_swaps
		_lib.build(gen.world_seed)
		_shared = LFTileBaker._save_shared(_lib, out_dir + "/shared")
		if _shared.has("error"):
			_fail(_shared["error"])
			return
		_sea = LFTileBaker._sea_sides(gen, _origin + Vector2(_rect.position) * _ts, Vector2(_rect.size) * _ts)

	## Saves the next block (and its tile after the tile's last block). True when the bake is over. `wait`
	## false: returns false at once while the next block is still being built (an editor keeps drawing).
	func step(wait := true) -> bool:
		if not result.is_empty():
			return true
		if not _started:
			_started = true
			_cpb = clampi(int(prop_batch / BLOCK), 1, _per)
			while _per % _cpb != 0:
				_cpb -= 1
			if _cpb > 1 and not DirAccess.dir_exists_absolute(_out + "/props"):
				var de := DirAccess.make_dir_recursive_absolute(_out + "/props")
				if de != OK:
					return _fail(de)
			var pe := LFTileBaker._save_prop_scenes(_lib, _shared, _out + "/shared/props", _layers())
			if pe != OK:
				return _fail(pe)
		if _ti >= _todo.size():
			return _end()
		_feed()
		var k := done   # blocks are saved in order: done is the next one's index
		if not WorkerThreadPool.is_task_completed(_tasks[k]) and not wait:
			return false
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
		_tasks.erase(k)
		_mutex.lock()
		var d: Dictionary = _ready[k]
		_ready.erase(k)
		_mutex.unlock()
		var t := _todo[_ti]
		var t_origin := _origin + Vector2(t) * _ts
		if _tile == null:
			_tile = Node3D.new()
			_tile.name = "Tile_%d_%d" % [t.x, t.y]
			_tile.position = Vector3(t_origin.x - _center.x, 0, t_origin.y - _center.y)
		var bx := _bi % _per
		var bz := _bi / _per
		var b_origin := t_origin + Vector2(bx, bz) * BLOCK
		var bc := Vector2i(roundi(b_origin.x / BLOCK), roundi(b_origin.y / BLOCK))
		var path := "%s/blocks/block_%d_%d.scn" % [_out, bc.x, bc.y]
		var root := LFTileBaker._block_scene(d, _gen, _shared, b_origin, _collision, _cpb == 1, prop_range, _layers())
		var err := LFTileBaker._save_scene(root, path)
		root.free()
		_written[path.get_file()] = true
		if err != OK:
			return _fail(err)
		_prop_count += int(d["props"])
		if _cpb > 1:
			var cell := Vector2i(bx / _cpb, bz / _cpb)
			if not _cells.has(cell):
				_cells[cell] = []
			_cells[cell].append(d)
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		inst.position = Vector3(bx * BLOCK, 0, bz * BLOCK)
		_tile.add_child(inst)
		inst.owner = _tile
		done += 1
		_bi += 1
		_feed()
		if _bi < _per * _per:
			return false
		err = _save_prop_cells(t_origin)
		if err == OK:
			err = _save_tile(t)
		if err != OK:
			return _fail(err)
		_bi = 0
		_ti += 1
		return _end() if _ti >= _todo.size() else false

	## Stops the bake (the tile being baked is not saved; tiles already saved stay).
	func cancel() -> void:
		if result.is_empty():
			_fail(ERR_SKIP)

	## Hands blocks to the worker threads, keeping a few more than there are threads under way.
	func _feed() -> void:
		var n := threads if threads > 0 else maxi(1, OS.get_processor_count() - 1)
		while _next < total and _tasks.size() < n + 1:
			var k := _next
			_next += 1
			_tasks[k] = WorkerThreadPool.add_task(_work.bind(k, _gen.clone_for_worker()), true, "LFTileBaker block")   # high: low-priority tasks get only a third of the pool

	## Worker thread: block `k`'s data (LFTileBaker._block_data) with its own generator.
	func _work(k: int, gen: LFTerrainGenerator) -> void:
		var d := {}
		if not _stop:
			var per2 := _per * _per
			var t := _todo[k / per2]
			var bi := k % per2
			var cell_off := Vector3(bi % _per % _cpb, 0, bi / _per % _cpb) * BLOCK
			d = LFTileBaker._block_data(gen, _lib, _origin + Vector2(t) * _ts + Vector2(bi % _per, bi / _per) * BLOCK,
					_flow, _props, cell_off)
		_mutex.lock()
		_ready[k] = d
		_mutex.unlock()

	## Waits for the blocks still being built and drops them.
	func _drain() -> void:
		_stop = true
		for k: int in _tasks:
			WorkerThreadPool.wait_for_task_completion(_tasks[k])
		_tasks.clear()
		_mutex.lock()
		_ready.clear()
		_mutex.unlock()

	## The tile's prop batches (when prop_batch is over BLOCK): a scene each in <out>/props, added to the tile.
	func _save_prop_cells(t_origin: Vector2) -> Error:
		var keys := _cells.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
		var size := _cpb * BLOCK
		for cell: Vector2i in keys:
			var c_origin := t_origin + Vector2(cell) * size
			var cc := Vector2i(roundi(c_origin.x / size), roundi(c_origin.y / size))
			var root := Node3D.new()
			root.name = "Props_%d_%d" % [cc.x, cc.y]
			LFTileBaker._add_props(root, _cells[cell], _shared, _collision, _props, prop_range, _layers())
			var path := "%s/props/props_%d_%d.scn" % [_out, cc.x, cc.y]
			var err := LFTileBaker._save_scene(root, path)
			root.free()
			_written["props/" + path.get_file()] = true
			if err != OK:
				return err
			var inst: Node3D = (load(path) as PackedScene).instantiate()
			inst.position = Vector3(cell.x * size, 0, cell.y * size)
			_tile.add_child(inst)
			inst.owner = _tile
		_cells.clear()
		return OK

	## The layers and areas _bake_block and _save_prop_scenes take.
	func _layers() -> Dictionary:
		return {"terrain": terrain_layers, "props": prop_layers, "water_area": water_areas,
				"water": water_layers, "water_mask": water_mask}

	## The tile (column, row) the spawn is in, if has_spawn.
	func _spawn_tile() -> Vector2i:
		return Vector2i(((Vector2(spawn.x, spawn.z) - _origin) / _ts).floor())

	func _save_tile(t: Vector2i) -> Error:
		if has_spawn and _spawn_tile() == t:
			var m := Marker3D.new()
			m.name = "Spawn"
			m.add_to_group(GROUP_SPAWN, true)
			var t_origin := _origin + Vector2(t) * _ts
			m.position = Vector3(spawn.x - t_origin.x, spawn.y, spawn.z - t_origin.y)
			_tile.add_child(m)
		var err := LFTileBaker._save_scene(_tile, "%s/tile_%d_%d.tscn" % [_out, t.x, t.y])
		_tile.free()
		_tile = null
		if err == OK:
			_baked.append(_entry(t))
		return err

	func _entry(t: Vector2i) -> Dictionary:
		var t_origin := _origin + Vector2(t) * _ts
		return {"x": t.x, "z": t.y, "scene": "tile_%d_%d.tscn" % [t.x, t.y],
				"offset": [t_origin.x - _center.x, 0.0, t_origin.y - _center.y],
				"world_origin": [t_origin.x, t_origin.y]}

	## map_edge.tscn, then map.tscn and tiles.json for every tile of the map on disk. A full bake first removes
	## what an earlier bake left that this one didn't write (blocks elsewhere, tiles off the map: in `removed`,
	## and warned of), so the folder is this map.
	func _end() -> bool:
		_drain()
		if _full:
			_remove_leftovers()
		var all: Array = []
		for tz in range(_rect.position.y, _rect.end.y):
			for tx in range(_rect.position.x, _rect.end.x):
				if FileAccess.file_exists("%s/tile_%d_%d.tscn" % [_out, tx, tz]):
					all.append(_entry(Vector2i(tx, tz)))
		if all.size() > _baked.size():
			_warn_mixed()
		var err := _save_edge()
		if err == OK:
			err = LFTileBaker._save_map(all, _out)
		if err == OK:
			var f := FileAccess.open(_out + "/tiles.json", FileAccess.WRITE)
			if f == null:
				err = FileAccess.get_open_error()
			else:
				var info := {"format": TILES_FORMAT, "land_version": LFTerrainGenerator.LAND_VERSION,
						"seed": _gen.world_seed, "tile_size": _ts, "grid": [_grid.x, _grid.y],
						"tiles_x": _rect.size.x, "tiles_z": _rect.size.y, "first_tile": [_rect.position.x, _rect.position.y],
						"world_center": [_center.x, _center.y], "land": land_key, "edge": "map_edge.tscn",
						"tiles": all}
				if has_spawn:
					var st := _spawn_tile()
					info["spawn"] = {"tile": [st.x, st.y], "scene": "tile_%d_%d.tscn" % [st.x, st.y],
							"position": [spawn.x - _center.x, spawn.y, spawn.z - _center.y]}
				f.store_string(JSON.stringify(info, "\t"))
		result = {"error": err, "tiles": _baked, "ms": Time.get_ticks_msec() - _t0, "props": _prop_count,
				"removed": removed}
		return true

	## map_edge.tscn: the walls and the sea round the whole map, placed like a tile (from the map's north-west
	## corner). Written by every bake, as a grown map's edge moves.
	func _save_edge() -> Error:
		var edge := Node3D.new()
		edge.name = "MapEdge"
		var corner := _origin + Vector2(_rect.position) * _ts
		edge.position = Vector3(corner.x - _center.x, 0, corner.y - _center.y)
		var size := Vector2(_rect.size) * _ts
		if edge_walls:
			var wall := LFTileBaker._edge_wall(size)
			wall.collision_layer = wall_layers
			edge.add_child(wall)
		var ring := LFTileBaker._sea_ring(_sea, size, _shared["water"], _shared["terrain"])
		if ring != null:
			edge.add_child(ring)
			if water_areas:
				var boxes: Array = []
				for rect: Rect2 in LFTileBaker._sea_spans(_sea, size):
					boxes.append([rect, float(_sea["floor"]) - 1.0])
				edge.add_child(LFTileBaker._water_area(boxes, _layers()))
		return LFTileBaker._save_scene(edge, _out + "/map_edge.tscn")

	## Some tiles were kept from an earlier bake: warn if that bake was another map (they won't join).
	func _warn_mixed() -> void:
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(_out + "/tiles.json"))
		if not old is Dictionary:
			return
		var c: Array = old.get("world_center", [])
		if int(old.get("seed", -1)) != _gen.world_seed or float(old.get("tile_size", 0)) != _ts \
				or c.size() != 2 or not Vector2(c[0], c[1]).is_equal_approx(_center) \
				or land_key != "" and old.has("land_version") and String(old.get("land", land_key)) != land_key:
			push_warning("LFTileBaker: %s holds tiles from another seed or map size: re-bake them all so they join." % _out)

	func _remove_leftovers() -> void:
		for f in DirAccess.get_files_at(_out + "/blocks"):
			if f.begins_with("block_") and f.ends_with(".scn") and not _written.has(f):
				DirAccess.remove_absolute(_out + "/blocks/" + f)
		if DirAccess.dir_exists_absolute(_out + "/props"):
			for f in DirAccess.get_files_at(_out + "/props"):
				if f.begins_with("props_") and f.ends_with(".scn") and not _written.has("props/" + f):
					DirAccess.remove_absolute(_out + "/props/" + f)
		for f in DirAccess.get_files_at(_out):
			if f.begins_with("tile_") and (f.ends_with(".tscn") or f.ends_with(".tscn.uid")):
				var xz := f.trim_prefix("tile_").get_slice(".", 0).split("_")
				if xz.size() == 2 and not _rect.has_point(Vector2i(int(xz[0]), int(xz[1]))):
					DirAccess.remove_absolute(_out + "/" + f)
					if f.ends_with(".tscn"):
						removed.append(f)
		if not removed.is_empty():
			push_warning("LFTileBaker: removed %d tile scenes off the map from %s: %s" % [removed.size(), _out,
					", ".join(removed)])

	func _fail(err: Error) -> bool:
		_drain()
		if _tile != null:
			_tile.free()
			_tile = null
		if _full and (_baked.size() > 0 or done > 0) and FileAccess.file_exists(_out + "/tiles.json"):
			push_warning("LFTileBaker: bake %s: %s now mixes this bake's pieces with the last one's. Bake again before using it." \
					% ["cancelled" if err == ERR_SKIP else "failed", _out])
		result = {"error": err, "tiles": _baked, "ms": Time.get_ticks_msec() - _t0, "props": _prop_count,
				"removed": removed}
		return true


## Which sides of the map (west, east, north, south) end in open sea: every height sampled along the side
## (16 m apart) is under water. Endless land, or a coast cut by the map edge, gets no sea ring on that side.
## Returns {"sides": Array[bool], "floor": the sea floor height at the map corner, "color": its ground colour}.
static func _sea_sides(gen: LFTerrainGenerator, origin: Vector2, size: Vector2) -> Dictionary:
	var sides: Array[bool] = []
	for side in 4:
		var a := origin + Vector2(size.x if side == 1 else 0.0, size.y if side == 3 else 0.0)
		var b := a + (Vector2(0, size.y) if side < 2 else Vector2(size.x, 0))
		var n := ceili(a.distance_to(b) / 16.0)
		var all_sea := true
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			if gen.get_height(p.x, p.y) >= LFTerrainGenerator.WATER_LEVEL:
				all_sea = false
				break
		sides.append(all_sea)
	var y := gen.get_height(origin.x, origin.y)
	var base := gen.biome_color(gen.biome_weights(origin.x, origin.y))
	return {"sides": sides, "floor": y, "color": gen.ground_shade(base, y, 1.0)}


## The sea past the edge of a map `size` metres across: one quad per side that ends in sea, and the corner
## squares where both sides do; a water surface, and under it the flat sea floor the bake ends on, so the
## water reads the same past the edge. Null when no side is sea. From the map's north-west corner.
static func _sea_ring(sea_info: Dictionary, size: Vector2, water_mat: Material, floor_mat: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	for rect: Rect2 in _sea_spans(sea_info, size):
		var x0 := rect.position.x
		var x1 := rect.end.x
		var z0 := rect.position.y
		var z1 := rect.end.y
		verts.append_array(PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1),
				Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]))
	if verts.is_empty():
		return null
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var mesh := ArrayMesh.new()
	for y: float in [LFTerrainGenerator.WATER_LEVEL, float(sea_info["floor"])]:
		var at := PackedVector3Array()
		for v in verts:
			at.append(Vector3(v.x, y, v.z))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = at
		arrays[Mesh.ARRAY_NORMAL] = normals
		if mesh.get_surface_count() == 1:
			var cols := PackedColorArray()
			cols.resize(verts.size())
			cols.fill(sea_info["color"])
			arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, water_mat)
	mesh.surface_set_material(1, floor_mat)
	var mi := MeshInstance3D.new()
	mi.name = "SeaRing"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Saves the prop meshes and the materials once, so every block references them.
static func _save_shared(lib: LFPropMeshes, dir: String) -> Dictionary:
	var out := {"meshes": {}}
	var terrain := StandardMaterial3D.new()
	terrain.vertex_color_use_as_albedo = true
	terrain.vertex_color_is_srgb = true
	terrain.roughness = 1.0
	var water := ShaderMaterial.new()
	water.shader = load("res://addons/lowland_forge/shaders/water.gdshader")
	water.render_priority = -1
	water.set_shader_parameter("fade_start", 0.0)   # a flat plane: no vertex swell
	water.set_shader_parameter("fade_end", 0.0)
	var river := ShaderMaterial.new()
	river.shader = load("res://addons/lowland_forge/shaders/river_flow.gdshader")
	var falls := LFWaterfall.make_materials()
	out["terrain_shader"] = load("res://addons/lowland_forge/shaders/terrain_baked.gdshader")
	for pair: Array in [["terrain", terrain, "terrain_material.tres"], ["water", water, "water_material.tres"],
			["river", river, "river_material.tres"], ["fall", falls[0], "waterfall_material.tres"],
			["fall_pool", falls[1], "waterfall_pool_material.tres"]]:
		var path: String = dir + "/" + pair[2]
		var e := _save(pair[1], path)
		if e != OK:
			return {"error": e}
		out[pair[0]] = pair[1]
	var names: Array = LFPropMeshes.Kind.keys()
	for kind in names.size():
		for v in lib.variant_count(kind):
			var mesh := lib.get_mesh(kind, v)
			var path := "%s/%s_%d.res" % [dir, String(names[kind]).to_lower(), v]
			var e := _save(mesh, path)
			if e != OK:
				return {"error": e}
			out["meshes"][Vector2i(kind, v)] = mesh
	return out


## One scene per prop kind and variant (`pine_0.tscn`...): the shared mesh, and for trees, rocks and logs a
## StaticBody3D root with the same collider the bake gives them, in the same group (tree, rock, log) and on
## layers["props"]. Drag them into a map to place props by hand.
static func _save_prop_scenes(lib: LFPropMeshes, shared: Dictionary, dir: String, layers := {}) -> Error:
	var names: Array = LFPropMeshes.Kind.keys()
	for key: Vector2i in shared["meshes"]:
		var kind := key.x
		var r: float = lib.collide_radius[kind][key.y]
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		if kind == LFPropMeshes.Kind.ROCK:
			var sph := SphereShape3D.new()
			sph.radius = r
			cs.shape = sph
			cs.position = Vector3(0, r * 0.45, 0)
		elif kind == LFPropMeshes.Kind.CLIFF:
			var convex := ConvexPolygonShape3D.new()
			convex.points = lib.cliff_hulls[key.y]
			cs.shape = convex
		elif kind == LFPropMeshes.Kind.LOG:
			var cap := CapsuleShape3D.new()
			cap.radius = r * 0.9
			cap.height = lib.log_length[key.y]
			cs.shape = cap
			cs.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, r, 0))
		elif not LFPropMeshes.is_small(kind):
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = 4.0
			cs.shape = cyl
			cs.position = Vector3(0, 2.0, 0)
		else:
			cs.free()
			cs = null
		var label := "%s%d" % [String(names[kind]).capitalize(), key.y]
		var mi := MeshInstance3D.new()
		mi.mesh = shared["meshes"][key]
		if LFPropMeshes.is_small(kind):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var root: Node3D = mi
		if cs != null:
			var body := StaticBody3D.new()
			body.collision_layer = layers.get("props", 1)
			body.add_to_group(GROUP_ROCK if kind in [LFPropMeshes.Kind.ROCK, LFPropMeshes.Kind.CLIFF] else GROUP_LOG \
					if kind == LFPropMeshes.Kind.LOG else GROUP_TREE, true)
			mi.name = "Mesh"
			body.add_child(mi)
			body.add_child(cs)
			root = body
		root.name = label
		var err := _save_scene(root, "%s/%s_%d.tscn" % [dir, String(names[kind]).to_lower(), key.y])
		root.free()
		if err != OK:
			return err
	return OK


## The sea round a map `size` metres across (from its north-west corner) as rectangles (x, z): one per side
## that ends in sea, and the corner squares where both sides do. Empty when no side is sea.
static func _sea_spans(sea_info: Dictionary, size: Vector2) -> Array[Rect2]:
	var sea: Array[bool] = sea_info["sides"]
	var xs: Array = [[0.0, size.x]]   # x spans: the map, and past the west / east side
	var zs: Array = [[0.0, size.y]]
	if sea[0]:
		xs.append([-SEA_RING, 0.0])
	if sea[1]:
		xs.append([size.x, size.x + SEA_RING])
	if sea[2]:
		zs.append([-SEA_RING, 0.0])
	if sea[3]:
		zs.append([size.y, size.y + SEA_RING])
	var out: Array[Rect2] = []
	for i in xs.size():
		for j in zs.size():
			if i > 0 or j > 0:   # (0, 0) is the map itself: its blocks' Water
				out.append(Rect2(xs[i][0], zs[j][0], xs[i][1] - xs[i][0], zs[j][1] - zs[j][0]))
	return out


## An Area3D "WaterArea" (in GROUP_WATER, its `water_level` meta the surface height `top`) of one box per
## [Rect2 (x, z), bottom y], from the bottom up to `top`, on layers["water"] watching layers["water_mask"].
static func _water_area(boxes: Array, layers: Dictionary, top := LFTerrainGenerator.WATER_LEVEL) -> Area3D:
	var area := Area3D.new()
	area.name = "WaterArea"
	area.add_to_group(GROUP_WATER, true)
	area.collision_layer = layers.get("water", 1)
	area.collision_mask = layers.get("water_mask", 1)
	area.set_meta(&"water_level", top)
	for k in boxes.size():
		var rect: Rect2 = boxes[k][0]
		var bottom: float = boxes[k][1]
		var box := BoxShape3D.new()
		box.size = Vector3(rect.size.x, top - bottom, rect.size.y)
		var cs := CollisionShape3D.new()
		cs.name = "Box%d" % k
		cs.shape = box
		cs.position = Vector3(rect.get_center().x, (top + bottom) * 0.5, rect.get_center().y)
		area.add_child(cs)
	return area


## An invisible wall (boxes 2 m thick, 4 km tall) along each side of a map `size` metres across, from its
## north-west corner.
static func _edge_wall(size: Vector2) -> StaticBody3D:
	var h := 4000.0
	var sides: Array = [   # [centre, size]: west, east, north, south
		[Vector3(-1.0, 0, size.y * 0.5), Vector3(2.0, h, size.y + 4.0)],
		[Vector3(size.x + 1.0, 0, size.y * 0.5), Vector3(2.0, h, size.y + 4.0)],
		[Vector3(size.x * 0.5, 0, -1.0), Vector3(size.x + 4.0, h, 2.0)],
		[Vector3(size.x * 0.5, 0, size.y + 1.0), Vector3(size.x + 4.0, h, 2.0)]]
	var body := StaticBody3D.new()
	body.name = "EdgeWall"
	body.add_to_group(GROUP_EDGE_WALL, true)
	for k in sides.size():
		var box := BoxShape3D.new()
		box.size = sides[k][1]
		var cs := CollisionShape3D.new()
		cs.name = "Side%d" % k
		cs.shape = box
		cs.position = sides[k][0]
		body.add_child(cs)
	return body


## One 128 m block: 4 x 4 chunks merged into one terrain mesh, one height field, one river overlay, one
## MultiMesh per prop kind and variant, one collision shape each for its trees, rocks and logs, and a water
## area if asked. Saved as a binary scene. `layers`: Job._layers(). (Job builds blocks with _block_data on
## worker threads and _block_scene; this is both in one go.)
static func _bake_block(gen: LFTerrainGenerator, lib: LFPropMeshes, shared: Dictionary, b_origin: Vector2,
		path: String, collision: bool, props := Props.ALL, river_flow := false, prop_range := 0.0,
		layers := {}) -> Dictionary:
	var d := _block_data(gen, lib, b_origin, river_flow, props)
	var root := _block_scene(d, gen, shared, b_origin, collision, true, prop_range, layers)
	var err := _save_scene(root, path)
	root.free()
	return {"error": err, "props": d["props"], "water": not (d["water"][0] as PackedVector3Array).is_empty()}


## Everything a block is made of, as plain arrays (no nodes, no resources: safe on a worker thread, with a
## generator of its own): the terrain grid, its facet colours and mesh arrays, the water surface and boxes,
## the river overlay, and the props kept by `props`: their MultiMesh buffers and collision faces, placed
## `prop_off` further on (the block's place in its prop batch).
static func _block_data(gen: LFTerrainGenerator, lib: LFPropMeshes, b_origin: Vector2, river_flow := false,
		props := Props.ALL, prop_off := Vector3.ZERO) -> Dictionary:
	var c0 := Vector2i(roundi(b_origin.x / LFTerrainGenerator.CHUNK_SIZE), roundi(b_origin.y / LFTerrainGenerator.CHUNK_SIZE))
	var facets := PackedByteArray()   # each triangle's colour, RGB8: 2 texels per cell, a row per cell row
	facets.resize(BLOCK_CELLS * 2 * BLOCK_CELLS * 3)
	var hm := PackedFloat32Array()
	hm.resize((BLOCK_CELLS + 1) * (BLOCK_CELLS + 1))
	var lm := PackedFloat32Array()   # the water level at each height point, on a map with water up in the hills
	if gen.has_raised_water():
		lm.resize(hm.size())
	var rv := {"verts": PackedVector3Array(), "uvs": PackedVector2Array(), "normals": PackedVector3Array(),
			"cols": PackedColorArray(), "idx": PackedInt32Array()}
	var batches := {}   # Vector2i(kind, variant) -> PackedFloat32Array (MultiMesh buffer, block-local)
	var colliders: Array = []
	var log_colliders: Array = []
	var cliff_colliders: Array = []
	var V := LFTerrainGenerator.VERTS
	var cells := LFTerrainGenerator.CELLS
	for cj in BLOCK_CHUNKS:
		for ci in BLOCK_CHUNKS:
			var coord := c0 + Vector2i(ci, cj)
			var off := Vector3(ci, 0, cj) * LFTerrainGenerator.CHUNK_SIZE
			var poff := off + prop_off
			var td := LFChunkData.compute_terrain(gen, coord)
			var heights: PackedFloat32Array = td["heights"]
			var cols: PackedColorArray = td["colors"]
			for j in cells:
				for i in cells:
					for t in 2:
						var col := cols[((j * cells + i) * 2 + t) * 3]
						var px := (((cj * cells + j) * BLOCK_CELLS + ci * cells + i) * 2 + t) * 3
						facets[px] = col.r8
						facets[px + 1] = col.g8
						facets[px + 2] = col.b8
			var levels: PackedFloat32Array = td.get("levels", PackedFloat32Array())
			for j in V:
				for i in V:
					var h := heights[j * V + i]
					hm[(cj * cells + j) * (BLOCK_CELLS + 1) + ci * cells + i] = h
					if not lm.is_empty():
						lm[(cj * cells + j) * (BLOCK_CELLS + 1) + ci * cells + i] = levels[j * V + i]
			var pd := LFChunkData.compute_props(gen, lib, coord, heights, true, levels)
			var r: Dictionary = pd["river"]
			if river_flow and not r.is_empty():
				var base: int = (rv["verts"] as PackedVector3Array).size()
				for p: Vector3 in r["verts"]:
					rv["verts"].append(p + off)
				rv["uvs"].append_array(r["uvs"])
				rv["normals"].append_array(r["normals"])
				rv["cols"].append_array(r["cols"])
				for k: int in r["idx"]:
					rv["idx"].append(k + base)
			for mm: Dictionary in pd["mms"]:
				var buf: PackedFloat32Array = mm["buf"]
				for k in range(0, buf.size(), 12):
					buf[k + 3] += poff.x
					buf[k + 11] += poff.z
				var key: Vector2i = mm["key"]
				if not batches.has(key):
					batches[key] = PackedFloat32Array()
				batches[key].append_array(buf)
			for c: Array in pd["colliders"]:
				colliders.append([c[0], (c[1] as Vector3) + poff, c[2], c[3]])
			for lc: Array in pd["log_colliders"]:
				log_colliders.append([(lc[0] as Transform3D).translated(poff), lc[1], lc[2]])
			for hull: PackedVector3Array in pd["cliff_colliders"]:
				var moved := PackedVector3Array()
				for q in hull:
					moved.append(q + poff)
				cliff_colliders.append(moved)
	var raised_here := false   # this block has water above the sea (else the sea's flat strips will do)
	for l in lm:
		if l > LFTerrainGenerator.WATER_LEVEL + 0.05:
			raised_here = true
			break
	if not raised_here:
		lm = PackedFloat32Array()
	var rf := _river_mask(gen, b_origin)
	var water := _water_arrays(hm, rf) if lm.is_empty() else _water_arrays_levels(hm, lm, rf)
	var areas: Array = []   # [name, boxes, top] per water area
	if not (water[0] as PackedVector3Array).is_empty():
		if lm.is_empty():
			areas.append(["WaterArea", _wet_boxes(hm), LFTerrainGenerator.WATER_LEVEL])
		else:   # an area per water level (0.5 m steps): the sea's, each lake's, a falling river's
			var cell_bands := _cell_bands(hm, lm)
			var bands := _wet_bands(cell_bands)
			for band: int in bands:
				areas.append(["WaterArea" if band == bands[0] else "WaterArea%d" % (bands.find(band) + 1),
						_wet_boxes(hm, cell_bands, band), band * WATER_BAND])
	var scaled := PackedFloat32Array()
	scaled.resize(hm.size())
	for k in hm.size():
		scaled[k] = hm[k] / LFTerrainGenerator.STEP   # the shape is scaled by STEP, uniformly
	var mms: Array = []   # [key, buffer], in key order
	var count := 0
	var keys := batches.keys()
	keys.sort()
	for key: Vector2i in keys:
		var buf: PackedFloat32Array = batches[key]
		if buf.is_empty() or props == Props.NONE or (props == Props.LARGE and LFPropMeshes.is_small(key.x)):
			continue
		mms.append([key, buf])
		count += buf.size() / 12
	return {"facets": facets, "terrain": _terrain_arrays(hm), "water": water, "areas": areas, "heights": scaled,
			"river": rv, "mms": mms, "props": count,
			"bodies": _prop_faces(colliders, log_colliders, cliff_colliders) if props != Props.NONE else []}


## The block scene from _block_data `d` (main thread): Terrain, Water, WaterArea(s), TerrainBody, RiverFlow,
## Waterfall(s) and, `with_props`, its props (_add_props).
static func _block_scene(d: Dictionary, gen: LFTerrainGenerator, shared: Dictionary, b_origin: Vector2,
		collision: bool, with_props: bool, prop_range: float, layers: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Block_%d_%d" % [roundi(b_origin.x / BLOCK), roundi(b_origin.y / BLOCK)]
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	var ta: Array = d["terrain"]
	var tm := ArrayMesh.new()
	tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta[0], [], ta[1])
	terrain.mesh = tm
	var mat := ShaderMaterial.new()
	mat.shader = shared["terrain_shader"]
	mat.set_shader_parameter("facets", ImageTexture.create_from_image(
			Image.create_from_data(BLOCK_CELLS * 2, BLOCK_CELLS, false, Image.FORMAT_RGB8, d["facets"])))
	mat.set_shader_parameter("cell", LFTerrainGenerator.STEP)
	terrain.material_override = mat
	root.add_child(terrain)
	var water := _water_node(d["water"])
	if water != null:
		water.material_override = shared["water"]
		root.add_child(water)
		if layers.get("water_area", false):
			for a: Array in d["areas"]:
				var area := _water_area(a[1], layers, a[2])
				area.name = a[0]
				root.add_child(area)
	if collision:
		var body := StaticBody3D.new()
		body.name = "TerrainBody"
		body.add_to_group(GROUP_TERRAIN, true)
		body.collision_layer = layers.get("terrain", 1)
		var hs := HeightMapShape3D.new()
		hs.map_width = BLOCK_CELLS + 1
		hs.map_depth = BLOCK_CELLS + 1
		hs.map_data = d["heights"]
		var cs := CollisionShape3D.new()
		cs.name = "HeightField"
		cs.shape = hs
		cs.scale = Vector3.ONE * LFTerrainGenerator.STEP
		cs.position = Vector3(BLOCK * 0.5, 0, BLOCK * 0.5)
		body.add_child(cs)
		root.add_child(body)
	var rv: Dictionary = d["river"]
	if not (rv["idx"] as PackedInt32Array).is_empty():
		var ra: Array = []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = rv["verts"]
		ra[Mesh.ARRAY_NORMAL] = rv["normals"]
		ra[Mesh.ARRAY_COLOR] = rv["cols"]
		ra[Mesh.ARRAY_TEX_UV] = rv["uvs"]
		ra[Mesh.ARRAY_INDEX] = rv["idx"]
		var rmesh := ArrayMesh.new()
		rmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
		var river := MeshInstance3D.new()
		river.name = "RiverFlow"
		river.mesh = rmesh
		river.material_override = shared["river"]
		river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(river)
	var fall_mats: Array[ShaderMaterial] = [shared["fall"], shared["fall_pool"]]
	var n_falls := 0
	for f in gen.waterfalls():   # the falls whose lip is in this block
		var lip: Vector3 = f["position"]
		if lip.x >= b_origin.x and lip.x < b_origin.x + BLOCK and lip.z >= b_origin.y and lip.z < b_origin.y + BLOCK:
			var wf := LFWaterfall.build(f, fall_mats, Vector3(b_origin.x, 0.0, b_origin.y))
			n_falls += 1
			if n_falls > 1:
				wf.name = "Waterfall%d" % n_falls
			root.add_child(wf)
	if with_props:
		_add_props(root, [d], shared, collision, Props.ALL, prop_range, layers)
	return root


## The props of `parts` (_block_data results, in one batch's frame) under `root`: one MultiMesh per prop kind
## and variant (their buffers joined in order) and TreeBody / RockBody / LogBody (_prop_bodies), each body
## knowing its parts (lf_anchors, lf_ends metas: LFBakedProps finds and removes one prop by them).
static func _add_props(root: Node3D, parts: Array, shared: Dictionary, collision: bool, props: int,
		prop_range: float, layers: Dictionary) -> void:
	var bufs := {}
	var order: Array = []
	for d: Dictionary in parts:
		for m: Array in d["mms"]:
			if not bufs.has(m[0]):
				bufs[m[0]] = PackedFloat32Array()
				order.append(m[0])
			bufs[m[0]].append_array(m[1])
	order.sort()
	var names: Array = LFPropMeshes.Kind.keys()
	for key: Vector2i in order:
		var buf: PackedFloat32Array = bufs[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shared["meshes"][key] if shared["meshes"].has(key) else LFPropMeshes.tint_mesh(
				shared["meshes"][Vector2i(key.x, key.y & ((1 << LFPropMeshes.TINT_SHIFT) - 1))], LFPropMeshes.tint_of(key.y))   # a tinted plant
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [String(names[key.x]).capitalize(), key.y]
		mmi.multimesh = mm
		if LFPropMeshes.is_small(key.x):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = SMALL_PROP_RANGE
			mmi.visibility_range_end_margin = 15.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		elif prop_range > 0.0 and key.x != LFPropMeshes.Kind.CLIFF:   # cliff rocks are part of the land's look
			mmi.visibility_range_end = prop_range
			mmi.visibility_range_end_margin = prop_range * 0.1
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
	if not collision or props == Props.NONE:
		return
	for kind: Array in [["Tree", GROUP_TREE], ["Rock", GROUP_ROCK], ["Log", GROUP_LOG]]:
		var faces := PackedVector3Array()
		var anchors := PackedVector3Array()
		var ends := PackedInt32Array()
		for d: Dictionary in parts:
			for b: Array in d["bodies"]:
				if b[0] != kind[0]:
					continue
				var base := faces.size()
				faces.append_array(b[1])
				anchors.append_array(b[2])
				for e: int in b[3]:
					ends.append(e + base)
		if faces.is_empty():
			continue
		var body := _prop_body(kind[0], kind[1], faces)
		body.collision_layer = layers.get("props", 1)
		body.set_meta(&"lf_anchors", anchors)
		body.set_meta(&"lf_ends", ends)
		root.add_child(body)


## The block's terrain: the 2 m height grid with shared corners (terrain_baked.gdshader gives it its flat
## facets and their colours), two coarser LODs (4 m and 8 m) that Godot picks by their measured height error,
## and a skirt hanging from every side so blocks drawn at different LODs show no cracks between them.
static func _terrain_mesh(hm: PackedFloat32Array) -> ArrayMesh:
	var ta := _terrain_arrays(hm)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta[0], [], ta[1])
	return mesh


## _terrain_mesh's surface arrays and LODs: [arrays, lods] (no resource made: safe on a worker thread).
static func _terrain_arrays(hm: PackedFloat32Array) -> Array:
	var n := BLOCK_CELLS + 1
	var s := LFTerrainGenerator.STEP
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for j in n:
		for i in n:
			var h := hm[j * n + i]
			verts[j * n + i] = Vector3(i * s, h, j * s)
			var dx := hm[j * n + mini(i + 1, n - 1)] - hm[j * n + maxi(i - 1, 0)]
			var dz := hm[mini(j + 1, n - 1) * n + i] - hm[maxi(j - 1, 0) * n + i]
			normals[j * n + i] = Vector3(-dx, 2.0 * s, -dz).normalized()   # smooth: only for shadow bias
	var errors := {1: 0.0, 2: _lod_error(hm, 2), 4: _lod_error(hm, 4)}
	var depth := maxf(errors[2], errors[4]) + 1.0
	# skirt: every edge vertex again, `depth` lower; per side, in order along it
	var sides: Array = []   # [grid indices, skirt indices, outward]
	for side in 4:
		var grid := PackedInt32Array()
		var skirt := PackedInt32Array()
		for k in n:
			var g: int = [k * n, k * n + n - 1, k, (n - 1) * n + k][side]   # west, east, north, south
			grid.append(g)
			skirt.append(verts.size())
			verts.append(verts[g] - Vector3(0, depth, 0))
			normals.append(normals[g])
		sides.append([grid, skirt, [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK][side]])
	var lods := {}
	var lod0 := PackedInt32Array()
	for step: int in [1, 2, 4]:
		var idx := PackedInt32Array()
		for j in range(0, BLOCK_CELLS, step):
			for i in range(0, BLOCK_CELLS, step):
				var a := j * n + i
				var b := a + step
				var c := a + step * n
				var d := c + step
				idx.append_array(PackedInt32Array([a, b, c, b, d, c]))   # as LFChunkData: split p10-p01
		for sd: Array in sides:
			var grid: PackedInt32Array = sd[0]
			var skirt: PackedInt32Array = sd[1]
			for k in range(0, BLOCK_CELLS, step):
				var tri := [grid[k], grid[k + step], skirt[k]]
				var tri2 := [grid[k + step], skirt[k + step], skirt[k]]
				for t: Array in [tri, tri2]:
					# front faces outward (Godot: (c - a) x (b - a) is the front normal)
					if (verts[t[2]] - verts[t[0]]).cross(verts[t[1]] - verts[t[0]]).dot(sd[2]) < 0.0:
						t.reverse()
					idx.append_array(PackedInt32Array(t))
		if step == 1:
			lod0 = idx
		else:
			lods[maxf(errors[step], 0.01)] = idx
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = lod0
	return [arrays, lods]


## How far (m, at most) the grid drawn every `step` cells misses the 2 m heights it leaves out.
static func _lod_error(hm: PackedFloat32Array, step: int) -> float:
	var n := BLOCK_CELLS + 1
	var worst := 0.0
	for j in n:
		for i in n:
			if i % step == 0 and j % step == 0:
				continue
			var ci := mini(i / step * step, BLOCK_CELLS - step)
			var cj := mini(j / step * step, BLOCK_CELLS - step)
			var u := float(i - ci) / step
			var v := float(j - cj) / step
			var a := hm[cj * n + ci]
			var b := hm[cj * n + ci + step]
			var c := hm[(cj + step) * n + ci]
			var d := hm[(cj + step) * n + ci + step]
			var h := a + (b - a) * u + (c - a) * v if u + v <= 1.0 else d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)
			worst = maxf(worst, absf(hm[j * n + i] - h))
	return worst


## The block's water surface: only over the 2 m cells that dip below the water level (lakes, rivers, sea),
## a strip per run of them along each row, so nothing hangs past a map edge that ends on land. Null if dry.
static func _water_mesh(hm: PackedFloat32Array, rf := PackedFloat32Array()) -> MeshInstance3D:
	return _water_node(_water_arrays(hm, rf))


## _water_mesh's [vertices, colours] (both empty when dry; colours only over a river).
static func _water_arrays(hm: PackedFloat32Array, rf := PackedFloat32Array()) -> Array:
	var n := BLOCK_CELLS + 1
	var s := LFTerrainGenerator.STEP
	var y := LFTerrainGenerator.WATER_LEVEL
	# A river here (rf): the vertices carry 1 - river in alpha (the water shader draws no lapping lines on a
	# river), so a cell a river touches is a quad of its own; the rest still merge into strips.
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for j in BLOCK_CELLS:
		var run := -1
		for i in BLOCK_CELLS + 1:
			var ks := [j * n + i, j * n + i + 1, (j + 1) * n + i, (j + 1) * n + i + 1]
			var wet := i < BLOCK_CELLS and minf(minf(hm[ks[0]], hm[ks[1]]), minf(hm[ks[2]], hm[ks[3]])) < y
			var river := wet and not rf.is_empty() and rf[ks[0]] + rf[ks[1]] + rf[ks[2]] + rf[ks[3]] > 0.0
			if wet and not river and run < 0:
				run = i
			elif (not wet or river) and run >= 0:
				var x0 := run * s
				var x1 := i * s
				var z0 := j * s
				var z1 := (j + 1) * s
				verts.append_array(PackedVector3Array([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
						Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]))
				if not rf.is_empty():
					for k in 6:
						cols.append(Color(1, 1, 1, 1))
				run = -1
			if river:
				var p00 := Vector3(i * s, y, j * s)
				var p10 := Vector3((i + 1) * s, y, j * s)
				var p01 := Vector3(i * s, y, (j + 1) * s)
				var p11 := Vector3((i + 1) * s, y, (j + 1) * s)
				verts.append_array(PackedVector3Array([p00, p10, p11, p00, p11, p01]))
				for k: int in [0, 1, 3, 0, 3, 2]:
					cols.append(Color(1, 1, 1, 1.0 - rf[ks[k]]))
	return [verts, cols]


## The "Water" MeshInstance3D of _water_arrays' [vertices, colours], or null when there are none.
static func _water_node(w: Array) -> MeshInstance3D:
	var verts: PackedVector3Array = w[0]
	if verts.is_empty():
		return null
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not (w[1] as PackedColorArray).is_empty():
		arrays[Mesh.ARRAY_COLOR] = w[1]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## How much each height point of the block at `b_origin` is river (LFTerrainGenerator.river_factor), for the
## water shader (no lapping lines on a river), or empty where no river is near.
static func _river_mask(gen: LFTerrainGenerator, b_origin: Vector2) -> PackedFloat32Array:
	var n := BLOCK_CELLS + 1
	var out := PackedFloat32Array()
	out.resize(n * n)
	var any := false
	for j in n:
		for i in n:
			var r := gen.river_factor(b_origin.x + i * LFTerrainGenerator.STEP, b_origin.y + j * LFTerrainGenerator.STEP)
			out[j * n + i] = r
			any = any or r > 0.0
	return out if any else PackedFloat32Array()


## Each cell's water level in WATER_BAND steps (row by row), or DRY where it has no water.
static func _cell_bands(hm: PackedFloat32Array, lm: PackedFloat32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(BLOCK_CELLS * BLOCK_CELLS)
	for j in BLOCK_CELLS:
		for i in BLOCK_CELLS:
			var cw := _cell_water(hm, lm, i, j)
			out[j * BLOCK_CELLS + i] = _band(cw.y) if cw.x > 0.5 else DRY
	return out


## The water levels (WATER_BAND steps) of a block's wet cells (_cell_bands), lowest first.
static func _wet_bands(cells: PackedInt32Array) -> Array[int]:
	var seen := {}
	for b in cells:
		if b != DRY:
			seen[b] = true
	var out: Array[int] = []
	out.assign(seen.keys())
	out.sort()
	return out


static func _band(level: float) -> int:
	return ceili(level / WATER_BAND - 0.001)


## Cell (i, j) of a block: (1 if any corner's ground is below its water, the cell's water level: the highest
## of its corners'), with the water levels `lm`. A corner at the sea's level in a cell with raised water takes
## the lowest raised level there (as LFChunkData.raised_water): _corner_water.
static func _cell_water(hm: PackedFloat32Array, lm: PackedFloat32Array, i: int, j: int) -> Vector2:
	var n := BLOCK_CELLS + 1
	var ks := [j * n + i, j * n + i + 1, (j + 1) * n + i, (j + 1) * n + i + 1]
	var top := -INF
	for k: int in ks:
		top = maxf(top, lm[k])
	var wet := false
	for k: int in ks:
		wet = wet or hm[k] < _corner_water(hm, lm, ks, k)
	return Vector2(1.0 if wet else 0.0, top)


## The water level drawn at corner `k` of the cell with corners `ks`: its own, or, out at the sea's level in a
## cell with raised water, the cell's lowest raised level where the ground there is above it (the raised
## water ends under its bank). A corner down below a fall or a cliff keeps its own: lifted, its water would
## hang over the drop.
static func _corner_water(hm: PackedFloat32Array, lm: PackedFloat32Array, ks: Array, k: int) -> float:
	var low := LFTerrainGenerator.WATER_LEVEL + 0.05
	if lm[k] > low:
		return lm[k]
	var sub := INF
	for q: int in ks:
		if lm[q] > low:
			sub = minf(sub, lm[q])
	return lm[k] if sub == INF or hm[k] < sub - 0.05 else sub


## _water_mesh on a map with water up in the hills: every wet cell (_cell_water) as two triangles, each
## corner at its own water level (_corner_water).
static func _water_mesh_levels(hm: PackedFloat32Array, lm: PackedFloat32Array, rf := PackedFloat32Array()) -> MeshInstance3D:
	return _water_node(_water_arrays_levels(hm, lm, rf))


## _water_mesh_levels' [vertices, colours].
static func _water_arrays_levels(hm: PackedFloat32Array, lm: PackedFloat32Array, rf := PackedFloat32Array()) -> Array:
	var n := BLOCK_CELLS + 1
	var s := LFTerrainGenerator.STEP
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for j in BLOCK_CELLS:
		for i in BLOCK_CELLS:
			var cw := _cell_water(hm, lm, i, j)
			if cw.x < 0.5:
				continue
			var ks := [j * n + i, j * n + i + 1, (j + 1) * n + i, (j + 1) * n + i + 1]
			var y := PackedFloat32Array()
			for k: int in ks:
				y.append(_corner_water(hm, lm, ks, k))
			var p00 := Vector3(i * s, y[0], j * s)
			var p10 := Vector3((i + 1) * s, y[1], j * s)
			var p01 := Vector3(i * s, y[2], (j + 1) * s)
			var p11 := Vector3((i + 1) * s, y[3], (j + 1) * s)
			verts.append_array(PackedVector3Array([p00, p10, p11, p00, p11, p01]))
			if not rf.is_empty():
				for k: int in [0, 1, 3, 0, 3, 2]:
					cols.append(Color(1, 1, 1, 1.0 - rf[ks[k]]))
	return [verts, cols]


## The water's boxes for _water_area: the block's wet cells (as _water_mesh) merged into rectangles (runs
## along a row, joined with the same run on the rows below), each down to its lowest ground. With the water
## levels' cell bands (_cell_bands), only the cells whose water is in `band`.
static func _wet_boxes(hm: PackedFloat32Array, cells := PackedInt32Array(), band := 0) -> Array:
	var n := BLOCK_CELLS + 1
	var s := LFTerrainGenerator.STEP
	var y := LFTerrainGenerator.WATER_LEVEL
	var open := {}   # Vector2i(first, end) of a run -> [first row, lowest ground]
	var out: Array = []
	for j in BLOCK_CELLS + 1:
		var runs := {}
		var run := -1
		var low := INF
		for i in BLOCK_CELLS + 1:
			var lo := INF
			var wet := false
			if j < BLOCK_CELLS and i < BLOCK_CELLS:
				lo = minf(minf(hm[j * n + i], hm[j * n + i + 1]), minf(hm[(j + 1) * n + i], hm[(j + 1) * n + i + 1]))
				wet = lo < y if cells.is_empty() else cells[j * BLOCK_CELLS + i] == band
			if wet:
				if run < 0:
					run = i
					low = INF
				low = minf(low, lo)
			elif run >= 0:
				runs[Vector2i(run, i)] = low
				run = -1
		for key: Vector2i in open.keys():
			if not runs.has(key):
				var o: Array = open[key]
				out.append([Rect2(key.x * s, o[0] * s, (key.y - key.x) * s, (j - o[0]) * s), o[1] - 0.5])
				open.erase(key)
		for key: Vector2i in runs:
			if open.has(key):
				open[key][1] = minf(open[key][1], runs[key])
			else:
				open[key] = [j, runs[key]]
	return out


## Trunks, boulders, logs and cliff rocks (the cylinders, spheres, capsules and hulls LFPropPlacer lists) as one low-poly
## triangle shape per kind: TreeBody, RockBody, LogBody (in GROUP_TREE / ROCK / LOG), a node each per block
## instead of thousands (each a gizmo in the editor). Kinds with none are left out.
static func _prop_bodies(colliders: Array, log_colliders: Array, cliff_colliders: Array = []) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for b: Array in _prop_faces(colliders, log_colliders, cliff_colliders):
		out.append(_prop_body(b[0], {"Tree": GROUP_TREE, "Rock": GROUP_ROCK, "Log": GROUP_LOG}[b[0]], b[1]))
	return out


## _prop_bodies' shapes as [label ("Tree", "Rock", "Log"), faces, anchors, ends] for the kinds there are:
## anchors[i] is part i's place (a trunk's foot, a boulder's or cliff rock's centre, a log's middle) and its
## faces end at ends[i]. Plain arrays: safe on a worker thread.
static func _prop_faces(colliders: Array, log_colliders: Array, cliff_colliders: Array = []) -> Array:
	var trees := PackedVector3Array()
	var rocks := PackedVector3Array()
	var logs := PackedVector3Array()
	var at := {"Tree": PackedVector3Array(), "Rock": PackedVector3Array(), "Log": PackedVector3Array()}
	var ends := {"Tree": PackedInt32Array(), "Rock": PackedInt32Array(), "Log": PackedInt32Array()}
	for c: Array in colliders:
		var pos: Vector3 = c[1]
		if c[0]:
			_sphere_faces(rocks, pos, c[2])
			at["Rock"].append(pos)
			ends["Rock"].append(rocks.size())
		else:
			_prism_faces(trees, Transform3D(Basis(), pos + Vector3(0, c[3] * 0.5, 0)), c[2], c[3], false)
			at["Tree"].append(pos)
			ends["Tree"].append(trees.size())
	for lc: Array in log_colliders:
		_prism_faces(logs, lc[0], lc[1], lc[2])   # the capsule's axis is its local y
		at["Log"].append((lc[0] as Transform3D).origin)
		ends["Log"].append(logs.size())
	for hull: PackedVector3Array in cliff_colliders:
		rocks.append_array(hull)   # cliff rocks: their hulls' triangles
		var mid := Vector3.ZERO
		for q in hull:
			mid += q
		at["Rock"].append(mid / maxf(hull.size(), 1.0))
		ends["Rock"].append(rocks.size())
	var out: Array = []
	for kind: Array in [["Tree", trees], ["Rock", rocks], ["Log", logs]]:
		if not (kind[1] as PackedVector3Array).is_empty():
			out.append([kind[0], kind[1], at[kind[0]], ends[kind[0]]])
	return out


## A StaticBody3D "<label>Body" in `group` with one triangle shape "<label>s" of `faces`.
static func _prop_body(label: String, group: StringName, faces: PackedVector3Array) -> StaticBody3D:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true   # closed solids: hits from any side, winding doesn't matter
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = "%ss" % label
	cs.shape = shape
	var body := StaticBody3D.new()
	body.name = "%sBody" % label
	body.add_to_group(group, true)
	body.add_child(cs)
	return body


const COLLIDE_SIDES := 6
static var _ids_warned := false   # _stable_node_ids' warning, given once


## A COLLIDE_SIDES-sided prism of `height` along xf's local y, centred on xf.origin; `bottom` false leaves
## its bottom open (a trunk's, under the ground).
static func _prism_faces(f: PackedVector3Array, xf: Transform3D, r: float, height: float, bottom := true) -> void:
	var h := height * 0.5
	var top := xf * Vector3(0, h, 0)
	var bot := xf * Vector3(0, -h, 0)
	for i in COLLIDE_SIDES:
		var a0 := TAU * i / COLLIDE_SIDES
		var a1 := TAU * (i + 1) / COLLIDE_SIDES
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var t0 := xf * (p0 + Vector3(0, h, 0))
		var t1 := xf * (p1 + Vector3(0, h, 0))
		var b0 := xf * (p0 - Vector3(0, h, 0))
		var b1 := xf * (p1 - Vector3(0, h, 0))
		f.append_array(PackedVector3Array([b0, t0, t1, b0, t1, b1, top, t1, t0]))
		if bottom:
			f.append_array(PackedVector3Array([bot, b0, b1]))


## A low-poly sphere (COLLIDE_SIDES segments, 3 bands).
static func _sphere_faces(f: PackedVector3Array, c: Vector3, r: float) -> void:
	var rings: Array[float] = [-PI * 0.5, -PI / 6.0, PI / 6.0, PI * 0.5]
	for k in rings.size() - 1:
		for i in COLLIDE_SIDES:
			var a0 := TAU * i / COLLIDE_SIDES
			var a1 := TAU * (i + 1) / COLLIDE_SIDES
			var q := [Vector2(a0, rings[k]), Vector2(a1, rings[k]), Vector2(a1, rings[k + 1]), Vector2(a0, rings[k + 1])]
			var p: Array[Vector3] = []
			for v: Vector2 in q:
				p.append(c + Vector3(cos(v.x) * cos(v.y), sin(v.y), sin(v.x) * cos(v.y)) * r)
			if k > 0:   # the bottom band's lower edge is the pole: one triangle per segment
				f.append_array(PackedVector3Array([p[0], p[1], p[2]]))
			if k < rings.size() - 2:
				f.append_array(PackedVector3Array([p[0], p[2], p[3]]))


## A map.tscn that instances every tile and map_edge.tscn (the whole map at once, for small maps or an overview).
## Written as text that only names the tile scenes: nothing is loaded, so a 16 x 16 map costs no memory here.
## Each tile's root ("Tile_<x>_<z>") carries its own offset; map.tscn keeps its UID across re-bakes.
static func _save_map(tiles: Array, out_dir: String) -> Error:
	var path := out_dir + "/map.tscn"
	var scenes: Array = tiles.map(func(t: Dictionary) -> String: return String(t["scene"]))
	scenes.append("map_edge.tscn")
	var uid := ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID
	if uid == ResourceUID.INVALID_ID:   # a new one from the path, not random: the same bake writes the same bytes
		uid = (hash(path) & 0x7fffffff) << 31 | (hash(path + "#map") & 0x7fffffff)
	var ext := PackedStringArray()
	var nodes := PackedStringArray(['[node name="Map" type="Node3D"]'])
	for k in scenes.size():
		var scene: String = scenes[k]
		var su := ResourceLoader.get_resource_uid(out_dir + "/" + scene)
		ext.append('[ext_resource type="PackedScene"%s path="%s" id="%d"]' % [
				' uid="%s"' % ResourceUID.id_to_text(su) if su != ResourceUID.INVALID_ID else "",
				out_dir + "/" + scene, k + 1])
		var root_name := "MapEdge" if scene == "map_edge.tscn" \
				else "Tile_" + scene.trim_prefix("tile_").trim_suffix(".tscn")
		nodes.append('[node name="%s" parent="." instance=ExtResource("%d")]' % [root_name, k + 1])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string('[gd_scene format=3 uid="%s"]\n\n%s\n\n%s\n' % [ResourceUID.id_to_text(uid),
			"\n".join(ext), "\n\n".join(nodes)])
	f.close()
	if ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, path)
	else:
		ResourceUID.add_id(uid, path)
	if ResourceLoader.has_cached(path):   # someone has the old one loaded (the editor): reload it
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return OK


## Packs `root` with every descendant it made (instanced scenes keep their own insides) and saves it.
## Embedded resources get ids numbered in node order (Godot picks random ones), so the same bake writes the
## same bytes: re-bakes don't churn version control.
static func _save_scene(root: Node, path: String) -> Error:
	_own(root, root)
	var n := [0]
	_number(root, root, n)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		return err
	_stable_node_ids(ps, path)
	return _save(ps, path)


## Godot gives every saved node a random unique_id: number them from the file name and node order instead, so
## the same bake writes the same bytes. This reads the scene's bundled data through PackedScene's internal
## _get_bundled_scene / _set_bundled_scene: a Godot without them still bakes (warned once), only re-bakes then
## differ in those ids.
static func _stable_node_ids(ps: PackedScene, path: String) -> void:
	if not ps.has_method(&"_get_bundled_scene") or not ps.has_method(&"_set_bundled_scene"):
		if not _ids_warned:
			_ids_warned = true
			push_warning("LFTileBaker: this Godot can't renumber scene node ids: re-baking the same map gives files that differ in node ids (the map is the same).")
		return
	var b: Variant = ps.call(&"_get_bundled_scene")
	if not b is Dictionary or not (b as Dictionary).has("node_ids"):
		return
	var ids := PackedInt32Array()
	var used := {}
	for i in (b["node_ids"] as PackedInt32Array).size():
		var id := (hash("%s/%d" % [path.get_file(), i]) & 0x3fffffff) | 1
		while used.has(id):
			id += 2
		used[id] = true
		ids.append(id)
	b["node_ids"] = ids
	ps.call(&"_set_bundled_scene", b)


## Saves `res` to `path`, which it then stands for. Its UID is registered at once: in the editor a new file's
## UID is only known after the next filesystem scan, and every scene loaded before that which uses the file
## would warn "invalid UID" (thousands of warnings on a first bake).
static func _save(res: Resource, path: String) -> Error:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return err
	res.take_over_path(path)
	var uid := ResourceLoader.get_resource_uid(path)
	if uid == ResourceUID.INVALID_ID and not Engine.is_editor_hint():
		uid = _give_uid(path)
	if uid != ResourceUID.INVALID_ID:
		if ResourceUID.has_id(uid):
			ResourceUID.set_id(uid, path)
		else:
			ResourceUID.add_id(uid, path)
		if path.ends_with(".tscn") and not Engine.is_editor_hint():
			_name_uids(path)
	return OK


## Headless only: Godot names the files a text scene uses by path alone (the editor adds their UIDs), so this adds
## `uid="..."` to each `[ext_resource ...]` line of the scene at `path` that has none and whose file has a UID.
static func _name_uids(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var out := PackedStringArray()
	var changed := false
	for line in text.split("\n"):
		if line.begins_with("[ext_resource ") and not " uid=\"" in line:
			var a := line.find(" path=\"")
			var b := line.find("\"", a + 7) if a >= 0 else -1
			if b > a:
				var u := ResourceLoader.get_resource_uid(line.substr(a + 7, b - a - 7))
				if u != ResourceUID.INVALID_ID:
					line = line.insert(a, ' uid="%s"' % ResourceUID.id_to_text(u))
					changed = true
		out.append(line)
	if changed:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(out))
			f.close()


## A headless (command line) bake into the project (res://): Godot only gives a saved file a UID in the editor, so the scenes that name it
## would name it by path alone. This writes a UID into the file (made from its path, not random: the same bake
## writes the same bytes) and returns it, or INVALID_ID if the file takes none.
static func _give_uid(path: String) -> int:
	if not path.begins_with("res://"):
		return ResourceUID.INVALID_ID   # outside the project Godot writes a .uid file beside it instead
	var uid := (hash(path) & 0x7fffffff) << 31 | (hash(path + "#uid") & 0x7fffffff)
	if ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) != path:
		return ResourceUID.INVALID_ID
	if ResourceSaver.set_uid(path, uid) != OK:
		return ResourceUID.INVALID_ID
	return uid


static func _number(node: Node, root: Node, n: Array) -> void:
	if node != root and node.owner != root:
		return   # inside an instanced scene: that scene's own file
	for p in node.get_property_list():
		if p["type"] == TYPE_OBJECT and p["usage"] & PROPERTY_USAGE_STORAGE:
			_number_res(node.get(p["name"]), n)
	for c in node.get_children():
		_number(c, root, n)


static func _number_res(r: Variant, n: Array) -> void:
	if not (r is Resource) or (r as Resource).resource_path != "":
		return   # nothing, or saved in its own file
	n[0] += 1
	(r as Resource).resource_scene_unique_id = "lf_%d" % n[0]
	for p in (r as Resource).get_property_list():
		if p["type"] == TYPE_OBJECT and p["usage"] & PROPERTY_USAGE_STORAGE:
			_number_res(r.get(p["name"]), n)


static func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c.owner == null:
			c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)
