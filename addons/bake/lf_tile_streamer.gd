class_name LFTileStreamer
extends Node3D
## Loads the tiles of a baked map (LFMapBaker's output folder) round a target as it moves and frees the far
## ones, for maps too big to load whole. Reads `tiles.json`; tiles load on background threads
## (ResourceLoader.load_threaded_request) and are added at most one a frame. Add it to your level at the
## origin (where map.tscn would go), set Map Dir and Target:
##
##   var s := LFTileStreamer.new()
##   s.map_dir = "res://maps/map"
##   s.target = $Player
##   add_child(s)
##   await s.load_around(s.spawn_position())   # behind a loading screen: the tiles round the start
##   $Player.position = s.spawn_position()
##
## Tiles are children named like their scenes (`tile_2_3`); edit them in the tile scenes, not here.

## Emitted when a tile's scene is in the tree (x, z: its tile numbers).
signal tile_loaded(x: int, z: int, tile: Node3D)
## Emitted just before a tile is freed.
signal tile_unloaded(x: int, z: int)

## The baked map's folder (with tiles.json). Call reload_index() after changing it.
@export_dir var map_dir := "res://maps/map"
## What the tiles load around (your player). Empty: the current camera.
@export var target: Node3D
## Tiles closer than this to the target are loaded (m).
@export_range(0.0, 8000.0, 10.0, "or_greater", "suffix:m") var load_distance := 1200.0
## Extra distance before a tile is freed again (m), so tiles don't flicker in and out.
@export_range(0.0, 2000.0, 10.0, "or_greater", "suffix:m") var unload_margin := 200.0
## Also load the map's edge (edge walls, the sea round an island).
@export var load_edge := true
## Seconds between checks of which tiles to load or free (s). Higher is cheaper but reacts later.
@export_range(0.05, 2.0, 0.05) var check_every := 0.25

var _info: Dictionary = {}
var _tiles: Dictionary = {}   # Vector2i -> {"path", "rect" (Rect2, x z in this node's space)}
var _loaded: Dictionary = {}   # Vector2i -> Node3D in the tree
var _pending: Dictionary = {}   # Vector2i -> {"path", "drop", "started"}: queued or loading (drop: not wanted now)
var _since := INF
var _edge: Node3D


func _ready() -> void:
	reload_index()


## Reads tiles.json again (after a new bake). Returns OK, or the error (no or bad tiles.json).
func reload_index() -> Error:
	_tiles.clear()
	var path := map_dir.path_join("tiles.json")
	if not FileAccess.file_exists(path):
		push_error("LFTileStreamer: no tiles.json in %s (bake the map first)." % map_dir)
		return ERR_FILE_NOT_FOUND
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not json is Dictionary:
		push_error("LFTileStreamer: %s is not a tiles.json." % path)
		return ERR_PARSE_ERROR
	_info = json
	var ts := float(_info.get("tile_size", 1024))
	for t: Dictionary in _info.get("tiles", []):
		var o: Array = t["offset"]
		_tiles[Vector2i(int(t["x"]), int(t["z"]))] = {"path": map_dir.path_join(String(t["scene"])),
				"rect": Rect2(float(o[0]), float(o[2]), ts, ts)}
	return OK


## Every tile of the map (Vector2i tile numbers).
func tile_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_tiles.keys())
	return out


## The tiles in the tree now.
func loaded_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_loaded.keys())
	return out


## The tile node of `t` if it is loaded, else null.
func tile_node(t: Vector2i) -> Node3D:
	return _loaded.get(t)


## The tile numbers under `p` (in this node's space), or Vector2i(-99999, -99999) off the map.
func tile_at(p: Vector3) -> Vector2i:
	for t: Vector2i in _tiles:
		if (_tiles[t]["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
			return t
	return Vector2i(-99999, -99999)


## The start point a bake marked (the `Spawn` marker), in this node's space, or the origin if none.
func spawn_position() -> Vector3:
	var sp: Dictionary = _info.get("spawn", {})
	var p: Array = sp.get("position", [0.0, 0.0, 0.0])
	return Vector3(p[0], p[1], p[2])


## True when every tile within load_distance of `p` is in the tree.
func is_ready_at(p: Vector3) -> bool:
	for t in _wanted(p, load_distance):
		if not _loaded.has(t):
			return false
	return true


## True while tiles are loading on threads.
func is_loading() -> bool:
	for t: Vector2i in _pending:
		if not _pending[t]["drop"]:
			return true
	return false


## Loads the tiles round `p` and returns once they are all in the tree (await it behind a loading screen).
func load_around(p: Vector3) -> void:
	for t in _wanted(p, load_distance):
		_request(t)
	while not is_ready_at(p):
		_poll(1 << 20)   # no one-a-frame limit here: the player is waiting
		if not is_ready_at(p):
			await get_tree().process_frame


func _process(delta: float) -> void:
	_since += delta
	if _since >= check_every:
		_since = 0.0
		var at := _target_position()
		if at != null:
			_update(at)
	_poll(1)


func _target_position() -> Variant:
	var t: Node3D = target
	if t == null or not is_instance_valid(t):
		t = get_viewport().get_camera_3d() if get_viewport() != null else null
	if t == null:
		return null
	return to_local(t.global_position)


## Asks for the tiles near `p` and frees the far ones.
func _update(p: Vector3) -> void:
	for t in _wanted(p, load_distance):
		_request(t)
	var far := load_distance + unload_margin
	for t: Vector2i in _loaded.keys():
		if _distance(t, p) > far:
			tile_unloaded.emit(t.x, t.y)
			(_loaded[t] as Node).queue_free()
			_loaded.erase(t)
	for t: Vector2i in _pending:
		if _distance(t, p) > far:
			_pending[t]["drop"] = true   # collected when its thread ends (_poll), then thrown away


func _wanted(p: Vector3, dist: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t: Vector2i in _tiles:
		if _distance(t, p) <= dist:
			out.append(t)
	return out


## Distance (m) from `p` to the nearest point of tile `t`, on the ground plane (0 inside it).
func _distance(t: Vector2i, p: Vector3) -> float:
	var r: Rect2 = _tiles[t]["rect"]
	var q := Vector2(p.x, p.z).clamp(r.position, r.end)
	return q.distance_to(Vector2(p.x, p.z))


func _request(t: Vector2i) -> void:
	if _pending.has(t):
		_pending[t]["drop"] = false
		return
	if _loaded.has(t):
		return
	_pending[t] = {"path": _tiles[t]["path"], "drop": false, "started": false}
	_start_next()
	if load_edge and _edge == null and _info.has("edge"):
		var ep := map_dir.path_join(String(_info["edge"]))
		if ResourceLoader.exists(ep):
			_edge = (load(ep) as PackedScene).instantiate()
			add_child(_edge)


## Starts loading the next queued tile on a thread, when none is loading. One tile at a time and no sub-threads:
## tiles share the resources in shared/, and Godot 4.7's threaded loader, given several at once (or a tile's
## blocks on sub-threads), now and then loads a block twice ("Another resource is loaded from path ...").
func _start_next() -> void:
	for t: Vector2i in _pending:
		if _pending[t]["started"]:
			return
	for t: Vector2i in _pending.keys():
		if _pending[t]["drop"]:
			_pending.erase(t)   # not started: nothing to collect
			continue
		var path: String = _pending[t]["path"]
		var err := ResourceLoader.load_threaded_request(path, "PackedScene", false)
		if err != OK:
			push_error("LFTileStreamer: can't load %s (%s)." % [path, error_string(err)])
			_pending.erase(t)
			continue
		_pending[t]["started"] = true
		return


## Adds up to `budget` tiles whose threads have finished.
func _poll(budget: int) -> void:
	for t: Vector2i in _pending.keys():
		if budget <= 0:
			return
		if not _pending[t]["started"]:
			continue
		var path: String = _pending[t]["path"]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var drop: bool = _pending[t]["drop"]
		_pending.erase(t)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_error("LFTileStreamer: loading %s failed." % path)
			_start_next()
			continue
		var ps := ResourceLoader.load_threaded_get(path) as PackedScene   # always collected, even if dropped
		_start_next()
		if drop:
			continue
		var node := ps.instantiate() as Node3D
		node.name = path.get_file().get_basename()
		add_child(node)
		_loaded[t] = node
		tile_loaded.emit(t.x, t.y, node)
		budget -= 1
