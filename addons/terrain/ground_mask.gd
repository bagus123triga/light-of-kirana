class_name LFGroundMask
extends RefCounted
## Where the ground is bare: lanes, plazas, building floors and roads, planned from the seed by
## LFTerrainGenerator. LFPropPlacer leaves grass, flowers, ferns, bushes and mushrooms off it, so village
## lanes and floors look trodden. Shapes are segments (with a half width) and circles, bucketed on a
## grid for quick lookups. Read-only after setup (thread safe).

const BUCKET := 16.0

var _segs: Array = []      # [a: Vector2, b: Vector2, half: float]
var _circles: Array = []   # Vector3(x, z, r)
var _buckets := {}         # Vector2i -> Array of ["s", i] / ["c", i]
var _bounds := Rect2()


func is_empty() -> bool:
	return _segs.is_empty() and _circles.is_empty()


func add_segment(a: Vector2, b: Vector2, half: float) -> void:
	_segs.append([a, b, half])
	_index(Rect2(a, Vector2.ZERO).expand(b).grow(half), ["s", _segs.size() - 1])


func add_circle(c: Vector2, r: float) -> void:
	_circles.append(Vector3(c.x, c.y, r))
	_index(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), ["c", _circles.size() - 1])


## Adds bare-ground shapes, as a site plan's bare_shapes() lists them.
func add_shapes(shapes: Dictionary) -> void:
	for s: Array in shapes.get("segments", []):
		add_segment(s[0], s[1], s[2])
	for c: Vector3 in shapes.get("circles", []):
		add_circle(Vector2(c.x, c.y), c.z)


func _index(r: Rect2, entry: Array) -> void:
	_bounds = r if _bounds.size == Vector2.ZERO and _bounds.position == Vector2.ZERO else _bounds.merge(r)
	for bx in range(floori(r.position.x / BUCKET), floori(r.end.x / BUCKET) + 1):
		for bz in range(floori(r.position.y / BUCKET), floori(r.end.y / BUCKET) + 1):
			var key := Vector2i(bx, bz)
			if not _buckets.has(key):
				_buckets[key] = []
			(_buckets[key] as Array).append(entry)


## True where the ground is bare.
func covers(x: float, z: float) -> bool:
	if not _bounds.has_point(Vector2(x, z)):
		return false
	var list: Variant = _buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)))
	if list == null:
		return false
	var p := Vector2(x, z)
	for e: Array in list:
		if e[0] == "c":
			var c: Vector3 = _circles[e[1]]
			if p.distance_squared_to(Vector2(c.x, c.y)) < c.z * c.z:
				return true
		else:
			var s: Array = _segs[e[1]]
			var a: Vector2 = s[0]
			var ab: Vector2 = (s[1] as Vector2) - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			if p.distance_to(a + ab * t) < float(s[2]):
				return true
	return false
