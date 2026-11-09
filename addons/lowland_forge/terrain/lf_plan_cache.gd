class_name LFPlanCache
extends RefCounted
## What the slow planning searches found the last time a world was planned, replayed so the next load of the
## same world skips them: LFSitePlanner.find_spot / find_shore_spot / find_coast_spot and LFTerrainRoads.route
## ask the generator's cache first (LFTerrainGenerator.plan_cache). Results are replayed in the order they were
## asked, each only when it is asked with the same arguments; from the first call that differs everything is
## searched again (and recorded in its place), so a replayed plan is the plan a search gives, bit for bit.
## What it can't see is the host's own rules: a host whose planning changes (its _plan_sites, a site_allowed
## override, a search of its own) changes `key` (LFWorld.plan_cache_version), and then nothing is replayed.
## LFWorld keeps one file per world (LFWorld.plan_cache_dir). A host can wrap its own slow searches the same
## way: `recall` before searching, `remember` after.

const FORMAT := 1   # the file's layout; a file of another format is not read

## What this cache is for (the world: seed, params, versions; see make_key). A file under another key is not read.
var key := ""
## True when something was searched (and recorded) this time, or the plan got shorter: save it again.
var changed := false

var _calls: Array = []   # [call key, result] in the order they were asked
var _next := 0   # the next recorded call to replay
var _replaying := true   # false from the first call that wasn't the recorded one
var _replayed := 0


## A short, stable key for `parts` (plain values: numbers, strings, vectors, arrays, dictionaries; no objects).
static func make_key(parts: Array) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(var_to_bytes(parts))
	return hc.finish().hex_encode()


## The result recorded for the call `call_key` (make_key of its name and arguments), or null when it must be
## searched: it isn't the next recorded call (or nothing is recorded), and from then on nothing is replayed.
func recall(call_key: String) -> Variant:
	if _replaying and _next < _calls.size() and _calls[_next][0] == call_key:
		_next += 1
		_replayed += 1
		var r: Variant = _calls[_next - 1][1]
		return r.duplicate(true) if r is Array else r   # the caller may change what it gets
	if _replaying:
		_replaying = false
		_calls.resize(_next)   # what came after it was planned from other results
		changed = true
	return null


## Records `result`, which the call `call_key` searched for (after recall gave null).
func remember(call_key: String, result: Variant) -> void:
	_calls.append([call_key, result.duplicate(true) if result is Array else result])
	_next = _calls.size()
	changed = true


## Called when planning is done: recorded calls nobody asked for this time are dropped.
func finish() -> void:
	if _next < _calls.size():
		_calls.resize(_next)
		changed = true


## How many calls are recorded, and how many of them were replayed this time.
func size() -> int:
	return _calls.size()


func replayed() -> int:
	return _replayed


## Writes the cache to `path` (its folder must exist). Returns the error, OK when written.
func save(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var({"format": FORMAT, "key": key, "calls": _calls})
	f.close()
	changed = false
	return OK


## The cache saved at `path` when it was saved for `cache_key`, else an empty one for it (nothing to replay).
static func open(path: String, cache_key: String) -> LFPlanCache:
	var c := LFPlanCache.new()
	c.key = cache_key
	if not FileAccess.file_exists(path):
		return c
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return c
	var d: Variant = f.get_var()
	f.close()
	if d is Dictionary and d.get("format") == FORMAT and d.get("key") == cache_key and d.get("calls") is Array:
		c._calls = d["calls"]
	return c


## The call key of a planning search: its name and arguments, with the objects it reads turned into their data.
static func call_key(fn: String, args: Array) -> String:
	return make_key([fn] + args)


## The roads `roads` (LFTerrainRoads) as plain data for a call key: every road's points.
static func roads_data(roads: LFTerrainRoads) -> Array:
	var out: Array = []
	if roads != null:
		for rd in roads.roads:
			out.append(rd["pts"])
	return out
