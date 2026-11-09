class_name LFTerrainRoads
extends RefCounted
## Roads that shape the land. Planned once from the seed (LFTerrainGenerator.setup), then applied inside
## LFTerrainGenerator.get_height, so terrain meshes, collision, props, grass and anything else that asks
## for a height all agree.
##  - route(): AStarGrid2D over a coarse height grid. Cost rises steeply with slope, so a road winds
##    along hillsides and around rises when it can; water is a costly ford; `avoid` circles are walls.
##  - add_road(): resamples the route, smooths it, and builds a height profile limited to MAX_GRADE
##    (cuts into rises and banks up over hollows). Near the road the ground is pulled to that profile:
##    flat across the carriageway, then blended back to the land over a shoulder whose width grows with
##    the cut, so a road through a cliff becomes a cutting with steep earth walls.
##  - apply(): the height modifier (fast reject by bounding box and a bucket grid of segments).
## Rivers are left alone: a road crossing one is a ford, not a dam. Read-only after setup (thread safe), except
## the open / cleared state (set_open ...): a game's runtime marks, kept here, touching neither terrain nor
## fingerprints. Read and write that state from the main thread only.

const CELL := 4.0            # A* grid spacing (m)
const STEP := 2.0            # profile sample spacing (m)
const BRIDGE_WET := 0.3        # land this close above the waterline (m) counts as water for a bridge
const MAX_BRIDGE := 40.0       # longest bridge (m); wider water stays a ford
const MAX_GRADE := 0.13      # rise per metre the road profile may have (~7.4 degrees)
const HALF_WIDTH := 2.2      # flat carriageway half width (m)
const BANK := 0.85           # shoulder width per metre of cut or fill (lower = steeper walls)
const MIN_SHOULDER := 2.5
const MAX_SHOULDER := 22.0
const BUCKET := 16.0

## A road was marked open or closed (set_open): its index in `roads` and the new state.
signal open_changed(road_index: int, open: bool)

## Keep the points of a road that lie under water at its ends (before 0.14.0, a road planned to end in a lake
## ran into it and got a short bridge out to its end). Set true before setup for the old roads of a seed.
static var keep_wet_ends := false

## Each road: {"pts": PackedVector2Array, "prof": PackedFloat32Array (road height at each point),
## "cut": PackedFloat32Array (land height minus road height), "ford": PackedByteArray}.
var roads: Array[Dictionary] = []
var _bounds := Rect2()
# Every road segment gets a global id in add order; its start, vector and (clamped) squared length are cached
# flat so apply() / distance_to() skip the dictionary lookups. Same values the old code computed per call.
var _buckets := {}   # Vector2i -> PackedInt32Array of global segment ids
var _seg_a := PackedVector2Array()      # segment start pts[k]
var _seg_ab := PackedVector2Array()     # pts[k + 1] - pts[k]
var _seg_l2 := PackedFloat64Array()     # maxf(ab.length_squared(), 0.0001)
var _seg_road := PackedInt32Array()     # road index
var _seg_k := PackedInt32Array()        # point index k of the segment start
var _open := {}   # road index -> true while open (runtime state, set_open)
var _ids := PackedStringArray()   # road_id cache, one per road (rebuilt when roads are added)


func is_empty() -> bool:
	return roads.is_empty()


# --- planning ----------------------------------------------------------------------------------------------

## A route over the land from `from` to `to` (x, z) for `gen` (base heights, before any roads). `avoid`
## holds Vector3(x, z, radius) circles the road must not enter. With `follow`, cells on its roads cost
## `follow_cost` (against 1 for flat open land), so the route runs along them where that is shorter
## (LFRoadNetwork cuts those parts out again). Returns smoothed points (may be empty).
static func route(gen: LFTerrainGenerator, from: Vector2, to: Vector2, avoid: Array[Vector3] = [],
		follow: LFTerrainRoads = null, follow_cost := 0.3) -> PackedVector2Array:
	var pc := gen.plan_cache
	var ck := ""
	if pc != null:
		ck = LFPlanCache.call_key("route", [from, to, avoid, LFPlanCache.roads_data(follow), follow_cost])
		var r: Variant = pc.recall(ck)
		if r != null:
			return r
	var out := _route(gen, from, to, avoid, follow, follow_cost)
	if pc != null:
		pc.remember(ck, out)
	return out


## route's search (without the plan cache).
static func _route(gen: LFTerrainGenerator, from: Vector2, to: Vector2, avoid: Array[Vector3] = [],
		follow: LFTerrainRoads = null, follow_cost := 0.3) -> PackedVector2Array:
	var lo := Vector2(minf(from.x, to.x), minf(from.y, to.y)) - Vector2(70, 70)
	var hi := Vector2(maxf(from.x, to.x), maxf(from.y, to.y)) + Vector2(70, 70)
	var w := int(ceil((hi.x - lo.x) / CELL)) + 1
	var h := int(ceil((hi.y - lo.y) / CELL)) + 1
	# the grid's heights and water, rows in bands on the worker threads (the sampling is most of a route's cost)
	var heights := PackedFloat32Array()
	var wet := PackedByteArray()   # per cell: 2 water (or just above it), 1 a river's bank, 0 dry
	for band: Array in LFPlanWork.run(gen, h, func(g: LFTerrainGenerator, j0: int, j1: int) -> Array:
			var hs := PackedFloat32Array()
			hs.resize(w * (j1 - j0))
			var ws := PackedByteArray()
			ws.resize(w * (j1 - j0))
			for j in range(j0, j1):
				for i in w:
					var x := lo.x + i * CELL
					var z := lo.y + j * CELL
					var k := (j - j0) * w + i
					hs[k] = g.base_height(x, z)
					# asked right after the height at the same point: one river scan for all three
					if hs[k] < g.water_level_at(x, z) + 0.6:
						ws[k] = 2
					elif g.river_factor(x, z) > 0.4:
						ws[k] = 1
			return [hs, ws]):
		heights.append_array(band[0])
		wet.append_array(band[1])
	# each cell's weight (0: solid), rows in bands again (no sampling: the roads' distance and the avoid circles)
	var weights := PackedFloat32Array()
	for band: PackedFloat32Array in LFPlanWork.run(null, h, func(_g: LFTerrainGenerator, j0: int, j1: int) -> PackedFloat32Array:
			var out := PackedFloat32Array()
			out.resize(w * (j1 - j0))
			for j in range(j0, j1):
				for i in w:
					var x := lo.x + i * CELL
					var z := lo.y + j * CELL
					var hc := heights[j * w + i]
					var grad := 0.0
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var ni := clampi(i + d.x, 0, w - 1)
						var nj := clampi(j + d.y, 0, h - 1)
						grad = maxf(grad, absf(heights[nj * w + ni] - hc) / CELL)
					var weight := 1.0 + 60.0 * grad * grad
					if wet[j * w + i] == 2:
						weight += 30.0
					elif wet[j * w + i] == 1:
						weight += 14.0
					var blocked := false
					for c in avoid:
						if Vector2(x - c.x, z - c.y).length() < c.z:
							blocked = true
							break
					if blocked:
						weight = 0.0
					elif follow != null and follow.distance_to(x, z) < HALF_WIDTH + 1.0:
						weight = 1.0
					elif follow != null:   # (scaled up rather than the road down: the A* heuristic must not overestimate)
						weight = weight / follow_cost
					out[(j - j0) * w + i] = weight
			return out):
		weights.append_array(band)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	for j in h:
		for i in w:
			var weight := weights[j * w + i]
			if weight == 0.0:
				astar.set_point_solid(Vector2i(i, j), true)
			elif weight != 1.0:   # (1.0 is the grid's default)
				astar.set_point_weight_scale(Vector2i(i, j), weight)
	var a := Vector2i(clampi(roundi((from.x - lo.x) / CELL), 0, w - 1), clampi(roundi((from.y - lo.y) / CELL), 0, h - 1))
	var b := Vector2i(clampi(roundi((to.x - lo.x) / CELL), 0, w - 1), clampi(roundi((to.y - lo.y) / CELL), 0, h - 1))
	astar.set_point_solid(a, false)
	astar.set_point_solid(b, false)
	var ids := astar.get_id_path(a, b)
	if ids.is_empty():
		return PackedVector2Array([from, to])
	var pts := PackedVector2Array([from])
	for k in range(1, ids.size() - 1):
		pts.append(lo + Vector2(ids[k]) * CELL)
	pts.append(to)
	return smooth(pts, 3)


## Chaikin corner cutting (keeps the end points).
static func smooth(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var p := pts
	for it in iterations:
		if p.size() < 3:
			return p
		var q := PackedVector2Array([p[0]])
		for k in p.size() - 1:
			q.append(p[k].lerp(p[k + 1], 0.25))
			q.append(p[k].lerp(p[k + 1], 0.75))
		q.append(p[p.size() - 1])
		p = q
	return p


## Adds a road along `route_pts` (x, z): resampled every STEP, with a grade-limited height profile.
## `meta` is kept on the road (e.g. {"from": plan id, "from_name", "to_name"} for its signposts). A road
## that branches off another at its end has "joins" (that road's index) and "end_h" (its surface height
## there); at its start, "joins_start" and "start_h".
func add_road(gen: LFTerrainGenerator, route_pts: PackedVector2Array, meta := {}) -> void:
	var pts := _resample(route_pts, STEP)
	if not keep_wet_ends:   # a road ends at the shore, never out in the water (a branch's joined end stays)
		while pts.size() > 2 and not meta.has("end_h") and _under_water(gen, pts[pts.size() - 1]):
			pts.remove_at(pts.size() - 1)
		while pts.size() > 2 and not meta.has("start_h") and _under_water(gen, pts[0]):
			pts.remove_at(0)
	if pts.size() < 2:
		return
	var n := pts.size()
	var land := PackedFloat32Array()
	var wet := PackedFloat32Array()   # the land as height over the water there, on WATER_LEVEL's scale
	var ford := PackedByteArray()
	land.resize(n)
	wet.resize(n)
	ford.resize(n)
	for k in n:
		land[k] = gen.base_height(pts[k].x, pts[k].y)
		wet[k] = land[k] - gen.water_level_at(pts[k].x, pts[k].y) + LFTerrainGenerator.WATER_LEVEL
		ford[k] = 1 if gen.river_factor(pts[k].x, pts[k].y) > 0.35 or wet[k] < LFTerrainGenerator.WATER_LEVEL + 0.3 else 0
	# Bridged water: the profile runs straight across from bank to bank (no dip into the channel), and
	# the banks around it are shaped and surfaced like any road; only the water under the deck keeps
	# its river bed.
	var bridges := _bridges(wet)
	var shaped := land.duplicate()
	for span: Vector2i in bridges:
		var lo := span.x
		while lo > 0 and ford[lo - 1] == 1:
			lo -= 1
		var hi := span.y
		while hi < n - 1 and ford[hi + 1] == 1:
			hi += 1
		for k in range(lo, hi + 1):
			ford[k] = 1 if k > span.x and k < span.y else 0
		for k in range(span.x + 1, span.y):
			shaped[k] = lerpf(land[span.x], land[span.y], float(k - span.x) / float(span.y - span.x))
	# Smooth the land a little first, then limit the grade both ways (cut the rises, fill the dips).
	var prof := shaped.duplicate()
	for pass_i in 3:
		var nxt := prof.duplicate()
		for k in range(1, n - 1):
			nxt[k] = (prof[k - 1] + prof[k] * 2.0 + prof[k + 1]) * 0.25
		prof = nxt
	var dh := MAX_GRADE * STEP
	for k in range(1, n):
		prof[k] = clampf(prof[k], prof[k - 1] - dh, prof[k - 1] + dh)
	for k in range(n - 2, -1, -1):
		prof[k] = clampf(prof[k], prof[k + 1] - dh, prof[k + 1] + dh)
	prof[0] = float(meta.get("start_h", land[0]))   # meet the ground at both ends (or the road a branch joins)
	prof[n - 1] = float(meta.get("end_h", land[n - 1]))
	for k in range(n - 2, -1, -1):
		prof[k] = clampf(prof[k], prof[k + 1] - dh, prof[k + 1] + dh)
	for k in range(1, n):
		prof[k] = clampf(prof[k], prof[k - 1] - dh * 1.5, prof[k - 1] + dh * 1.5)
	var cut := PackedFloat32Array()
	cut.resize(n)
	for k in n:
		cut[k] = land[k] - prof[k]
	var ri := roads.size()
	var rd := {"pts": pts, "prof": prof, "cut": cut, "ford": ford, "bridges": bridges}
	rd.merge(meta)
	roads.append(rd)
	for k in n - 1:
		var sid := _seg_a.size()
		var sa := pts[k]
		var sab := pts[k + 1] - sa
		_seg_a.append(sa)
		_seg_ab.append(sab)
		_seg_l2.append(maxf(sab.length_squared(), 0.0001))
		_seg_road.append(ri)
		_seg_k.append(k)
		var reach := HALF_WIDTH + _shoulder(maxf(absf(cut[k]), absf(cut[k + 1])))
		var r := Rect2(pts[k], Vector2.ZERO).expand(pts[k + 1]).grow(reach)
		_bounds = r if _bounds.size == Vector2.ZERO else _bounds.merge(r)
		for bx in range(floori(r.position.x / BUCKET), floori(r.end.x / BUCKET) + 1):
			for bz in range(floori(r.position.y / BUCKET), floori(r.end.y / BUCKET) + 1):
				var key := Vector2i(bx, bz)
				# (packed arrays are values in a Dictionary: take it out, append, put it back)
				var ids: PackedInt32Array = _buckets.get(key, PackedInt32Array())
				ids.append(sid)
				_buckets[key] = ids


## Where the road goes under water (land below the waterline), short enough to span and with dry land
## on both sides: a plank bridge from the last dry point to the next ([Vector2i(first, last)] point indices). Longer water stays a ford.
static func _bridges(land: PackedFloat32Array) -> Array:
	var out: Array = []
	var n := land.size()
	var k := 0
	while k < n:
		if land[k] >= LFTerrainGenerator.WATER_LEVEL + BRIDGE_WET:
			k += 1
			continue
		var a := k
		while k < n and land[k] < LFTerrainGenerator.WATER_LEVEL + BRIDGE_WET:
			k += 1
		var span := Vector2i(maxi(a - 1, 0), mini(k, n - 1))
		if (keep_wet_ends or a > 0 and k < n) and float(span.y - span.x) * STEP <= MAX_BRIDGE:   # dry banks at both ends
			out.append(span)
	return out


## True where the land (before roads) at `p` is below the water there.
static func _under_water(gen: LFTerrainGenerator, p: Vector2) -> bool:
	return gen.base_height(p.x, p.y) < gen.water_level_at(p.x, p.y)


static func _shoulder(cut: float) -> float:
	return clampf(MIN_SHOULDER + cut * BANK, MIN_SHOULDER, MAX_SHOULDER)


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return out
	out.append(pts[0])
	var carry := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var len := a.distance_to(b)
		var t := step - carry
		while t <= len:
			out.append(a.lerp(b, t / len))
			t += step
		carry = len - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.3:
		out.append(pts[pts.size() - 1])
	return out


# --- applying ----------------------------------------------------------------------------------------------

## The land height `h` at (x, z), reshaped by any road nearby.
func apply(x: float, z: float, h: float) -> float:
	if roads.is_empty() or not _bounds.has_point(Vector2(x, z)):
		return h
	var segs: Variant = _buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)))
	if segs == null:
		return h
	var p := Vector2(x, z)
	var best_d := INF
	var best_id := -1
	var best_t := 0.0
	for sid: int in segs:
		var a := _seg_a[sid]
		var ab := _seg_ab[sid]
		var t := clampf((p - a).dot(ab) / _seg_l2[sid], 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_id = sid
			best_t = t
	if best_id < 0:
		return h
	var rd: Dictionary = roads[_seg_road[best_id]]
	var k := _seg_k[best_id]
	var prof: PackedFloat32Array = rd["prof"]
	var cut: PackedFloat32Array = rd["cut"]
	var ford: PackedByteArray = rd["ford"]
	var best_cut := lerpf(cut[k], cut[k + 1], best_t)
	var reach := HALF_WIDTH + _shoulder(absf(best_cut))
	if best_d >= reach:
		return h
	var best_prof := lerpf(prof[k], prof[k + 1], best_t)
	var best_ford := lerpf(float(ford[k]), float(ford[k + 1]), best_t)
	var f := 1.0 - smoothstep(HALF_WIDTH, reach, best_d)
	f *= 1.0 - best_ford   # fords keep the river bed
	return lerpf(h, best_prof, f)


## Where a branch from `from` should join road `ri` (a Y junction): the point of the road nearest to
## `from`, skipping the first `skip_start` and last `skip_end` metres of it. Returns [point, surface height].
func junction(ri: int, from: Vector2, skip_start: float, skip_end: float) -> Array:
	var rd: Dictionary = roads[ri]
	var pts: PackedVector2Array = rd["pts"]
	var prof: PackedFloat32Array = rd["prof"]
	var n := pts.size()
	var k0 := mini(int(skip_start / STEP), n - 1)
	var k1 := maxi(n - 1 - int(skip_end / STEP), k0)
	var best := k0
	for k in range(k0, k1 + 1):
		if pts[k].distance_squared_to(from) < pts[best].distance_squared_to(from):
			best = k
	return [pts[best], prof[best]]


## The road point nearest to `p` over every road: Vector2i(road index, point index), or (-1, -1) when
## there are no roads.
func nearest_point(p: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for ri in roads.size():
		var pts: PackedVector2Array = roads[ri]["pts"]
		for k in pts.size():
			var d := pts[k].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = Vector2i(ri, k)
	return best


## True when a circle of `radius` m round (x, z) reaches onto a road: its carriageway or the shoulder its cut or
## fill reshapes (the ground a road changes). Use it to keep a footprint (a camp, a building, a marker) off roads.
func overlaps(x: float, z: float, radius: float) -> bool:
	return _road_clearance(Vector2(x, z), radius, PackedVector2Array()) < 0.0


## True when polygon `poly` (world x/z, any winding) touches a road's carriageway or shoulder.
func overlaps_polygon(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	var lo := poly[0]
	var hi := poly[0]
	for v in poly:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	return _road_clearance((lo + hi) * 0.5, (hi - lo).length() * 0.5, poly) < 0.0


## How far the footprint (a circle round `c`, or `poly` inside that circle) stays from the nearest road's reach
## (carriageway + shoulder); below 0 = it overlaps. INF when no road is near.
func _road_clearance(c: Vector2, radius: float, poly: PackedVector2Array) -> float:
	if roads.is_empty():
		return INF
	var best := INF
	var seen := {}
	var reach_max := HALF_WIDTH + MAX_SHOULDER
	for bx in range(floori((c.x - radius - reach_max) / BUCKET), floori((c.x + radius + reach_max) / BUCKET) + 1):
		for bz in range(floori((c.y - radius - reach_max) / BUCKET), floori((c.y + radius + reach_max) / BUCKET) + 1):
			var segs: Variant = _buckets.get(Vector2i(bx, bz))
			if segs == null:
				continue
			for sid: int in segs:
				if seen.has(sid):
					continue
				seen[sid] = true
				var a := _seg_a[sid]
				var b := a + _seg_ab[sid]
				var rd: Dictionary = roads[_seg_road[sid]]
				var k := _seg_k[sid]
				var cut: PackedFloat32Array = rd["cut"]
				var reach := HALF_WIDTH + _shoulder(maxf(absf(cut[k]), absf(cut[k + 1])))
				var d := 0.0
				if poly.is_empty():
					d = c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)) - radius
				elif Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
					d = 0.0
				else:
					d = INF
					for i in poly.size():
						var pq := Geometry2D.get_closest_points_between_segments(a, b, poly[i], poly[(i + 1) % poly.size()])
						d = minf(d, (pq[0] as Vector2).distance_to(pq[1]))
				best = minf(best, d - reach)
	return best


## Distance from (x, z) to the nearest road centreline (INF when none is near).
func distance_to(x: float, z: float) -> float:
	var segs: Variant = _buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)))
	if segs == null:
		return INF
	var p := Vector2(x, z)
	var best := INF
	for sid: int in segs:
		var a := _seg_a[sid]
		var ab := _seg_ab[sid]
		var t := clampf((p - a).dot(ab) / _seg_l2[sid], 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


# --- open / cleared roads (runtime state) -------------------------------------------------------------------

## A stable name for road `ri`, made from the land alone (the plan id it starts from, its end points rounded to
## the metre, a counter if two would clash): the same seed and settings give the same ids, so a save can list them.
## "" for an index out of range.
func road_id(ri: int) -> String:
	if ri < 0 or ri >= roads.size():
		return ""
	if _ids.size() != roads.size():
		_ids.clear()
		var seen := {}
		for i in roads.size():
			var rd: Dictionary = roads[i]
			var pts: PackedVector2Array = rd["pts"]
			var a := pts[0]
			var b := pts[pts.size() - 1]
			var base := "%s:%d,%d>%d,%d" % [str(rd.get("from", "")), roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y)]
			var n: int = seen.get(base, 0)
			seen[base] = n + 1
			_ids.append(base if n == 0 else "%s#%d" % [base, n])
	return _ids[ri]


## The index of the road with this id (road_id), or -1.
func road_index(id: String) -> int:
	for i in roads.size():
		if road_id(i) == id:
			return i
	return -1


## Marks a road open (cleared, safe, usable ...) or not. `road` is its index or its id. Emits open_changed when
## the state changes; an unknown road is ignored. Meaning is yours: the addon only remembers and answers.
func set_open(road: Variant, open: bool) -> void:
	var ri := road_index(road) if road is String else int(road)
	if ri < 0 or ri >= roads.size() or is_open(ri) == open:
		return
	if open:
		_open[ri] = true
	else:
		_open.erase(ri)
	open_changed.emit(ri, open)


## True while road `ri` is open (see set_open). Every road starts closed.
func is_open(ri: int) -> bool:
	return _open.has(ri)


## The ids (road_id) of the open roads, in road order: store them in a save and give them to restore_open.
func open_roads() -> PackedStringArray:
	var out := PackedStringArray()
	var idx: Array = _open.keys()
	idx.sort()
	for ri: int in idx:
		out.append(road_id(ri))
	return out


## Opens exactly the roads in `ids` (from open_roads) and closes the others; ids that match no road are skipped.
## Emits open_changed for each road that changed.
func restore_open(ids: PackedStringArray) -> void:
	var want := {}
	for id in ids:
		var ri := road_index(id)
		if ri >= 0:
			want[ri] = true
	for ri: int in _open.keys():
		if not want.has(ri):
			set_open(ri, false)
	for ri: int in want.keys():
		set_open(ri, true)


## Distance (m) from (x, z) to the nearest open road's centreline; INF when no road is open or none lies within
## `max_dist` of the point (the search stops there). Main thread.
func distance_to_open(x: float, z: float, max_dist := 32.0) -> float:
	if _open.is_empty():
		return INF
	var p := Vector2(x, z)
	var best := INF
	for bx in range(floori((x - max_dist) / BUCKET), floori((x + max_dist) / BUCKET) + 1):
		for bz in range(floori((z - max_dist) / BUCKET), floori((z + max_dist) / BUCKET) + 1):
			var segs: Variant = _buckets.get(Vector2i(bx, bz))
			if segs == null:
				continue
			for sid: int in segs:
				if not _open.has(_seg_road[sid]):
					continue
				var a := _seg_a[sid]
				var ab := _seg_ab[sid]
				var t := clampf((p - a).dot(ab) / _seg_l2[sid], 0.0, 1.0)
				best = minf(best, p.distance_to(a + ab * t))
	return best if best <= max_dist else INF


## True when (x, z) is on an open road: within the carriageway (HALF_WIDTH) plus `margin` m of its centreline.
func on_open_road(x: float, z: float, margin := 0.0) -> bool:
	var reach := HALF_WIDTH + maxf(margin, 0.0)
	return distance_to_open(x, z, reach) <= reach
