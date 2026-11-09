@tool
class_name LFCliffBand
extends RefCounted
## A cliff across a road: a height stamp that raises the land on one side of a line by `rise` m, so a road
## coming up to it ends at the foot and the way on is on top. For a game where the only way up is through
## something (a dungeon with a mouth at the foot and another on top).
##
## It is an escarpment, not a wall: the face climbs in `ledges` + 1 steep risers (each `face` m of run) with a flat
## ledge between them (`ledge` m deep), the steps at seeded uneven heights and the lines of the risers wandering
## along the face, the top lip broken and lumpy, the back easing down into the land over a noisy `back` stretch,
## the ends fading out over `end_width` m. The stamp also colours the face (shade): each riser its own tone of the
## terrain's rock colour, the ledges soil.
##
## Along the face `t` (m from `origin`) stays within `length` / 2; across it `s` runs from the foot (0, the first
## riser) toward the top. Nothing here walls the ends: with the default `end_width` the land slopes away there
## and a way round exists. For a band nobody may walk round, set `end_width` to 6 (sheer ends, a mesa) and give
## it a `length` the playable area can't get round, put it where the ends meet high ground or water, or wall the
## ends in the game.
## Deterministic: seeded noise (`noise_seed`) only. Read-only once added (thread safe).
##
## Use it from the host's LFTerrainGenerator._plan_sites, after the sites and before the roads that cross it:
##
##   var route := LFTerrainRoads.route(self, from, to)
##   var band := LFCliffBand.across(route, 0.5 * length_of_route, 40.0, 160.0)   # height 40 m, 160 m wide
##   stamps.append(band)
##   band.add_roads(self, route)           # the road in two pieces: it ends at foot_mouth, resumes at top_mouth
##   dungeon_door_at(band.foot_mouth)      # {"position": Vector3, "facing": Vector2, "yaw": float}
##
## A road that LFRoadNetwork plans across a band is not split (it would climb the face as a cutting): route that
## one yourself as above.

## How far the top stands over the land at the foot (m).
var rise := 40.0
## Width of the band along the face (m).
var length := 160.0
## Horizontal run of one riser (m). Under 2 m the grid can't draw it; 3 reads as a wall.
var face := 3.0
## Number of ledges (flat steps) in the face, 0 to 5.
var ledges := 3
## Depth of a ledge (m).
var ledge := 5.0
## How far behind the face the raised land goes before it eases down again (m).
var depth := 360.0
## The stretch at the back where the raised land eases back down into the land (m; its line wanders by half of it).
var back := 160.0
## How far the ends slope away (m): small (6) = sheer ends.
var end_width := 36.0
## How far the risers wander along `dir` (m, seeded noise; the top lip wanders more).
var wobble := 4.5
## Where the road crosses the face (x, z), and the way across it, foot to top (unit vector).
var origin := Vector2.ZERO
var dir := Vector2.DOWN
## Seeds the steps and the noise.
var noise_seed := 0
## How far each mouth stands from the face (m): the foot's from the base of it, the top's from the lip.
var foot_gap := 4.0
var top_gap := 7.0

## The two entrances, set by mouths() / add_roads(): {"position": Vector3 (on the ground), "facing": Vector2 (the
## way out of it, x z), "yaw": float}. `yaw` turns a frame whose +Z points out of the entrance (the sites' convention)
## to face that way. The foot's faces away from the cliff (down the road), the top's faces on along the road.
var foot_mouth := {}
var top_mouth := {}

var _noise: FastNoiseLite
var _cum := PackedFloat32Array()   # cumulative share of the rise at the top of each riser (0 to 1)


## A band across `route` (x, z points) where it has gone `at` metres along it (negative = from the end): origin
## on the route there, dir the route's heading. `seed_value` seeds the steps (default: from the position).
static func across(route: PackedVector2Array, at: float, height_m := 40.0, length_m := 160.0, seed_value := -1) -> LFCliffBand:
	var b := LFCliffBand.new()
	route = LFTerrainRoads._resample(route, 4.0)   # evenly spaced: the heading below is over a set distance
	if route.size() < 2:
		return b
	b.rise = height_m
	b.length = length_m
	var total := 0.0
	for k in route.size() - 1:
		total += route[k].distance_to(route[k + 1])
	var want := clampf(at if at >= 0.0 else total + at, 0.0, total)
	var run := 0.0
	var k := 0
	while k < route.size() - 2 and run + route[k].distance_to(route[k + 1]) < want:
		run += route[k].distance_to(route[k + 1])
		k += 1
	var seg := route[k + 1] - route[k]
	b.origin = route[k] + seg.normalized() * clampf(want - run, 0.0, seg.length())
	# the heading over about 40 m round the crossing, so a wiggle in one segment doesn't turn the band
	var before := route[maxi(k - 5, 0)]
	var after := route[mini(k + 6, route.size() - 1)]
	b.dir = (after - before).normalized() if after.distance_to(before) > 0.1 else seg.normalized()
	b.noise_seed = seed_value if seed_value >= 0 else hash("%d/%d/cliff_band" % [roundi(b.origin.x), roundi(b.origin.y)])
	b.prepare()
	return b


## Makes the noise and the step heights from the seed. across() and add_roads() call it; call it yourself after
## setting `ledges` or `noise_seed` on a band made by hand.
func prepare() -> void:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = 0.03
	_noise = n
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var steps := clampi(ledges, 0, 5) + 1
	var w := PackedFloat32Array()
	var sum := 0.0
	for i in steps:
		w.append(rng.randf_range(0.5, 1.5) * (1.3 if i == steps - 1 else 1.0))   # uneven; the top riser a little taller
		sum += w[i]
	_cum = PackedFloat32Array()
	var acc := 0.0
	for i in steps:
		acc += w[i] / sum
		_cum.append(acc)


# Noise at (x, z), `k` selecting an independent field (offset by a big step per k).
func _n(x: float, z: float, k: int, freq := 1.0) -> float:
	return _noise.get_noise_2d((x + k * 977.0) * freq, (z - k * 613.0) * freq)


## Stamp interface (LFTerrainGenerator.stamps): the land height `h` at (x, z) plus the band's rise there.
func height(x: float, z: float, h: float) -> float:
	return h + _rise(x, z)


## Metres the band adds at (x, z).
func _rise(x: float, z: float) -> float:
	var p := Vector2(x, z) - origin
	var half := length * 0.5
	var t := absf(p.x * dir.y - p.y * dir.x)   # along the face
	if t >= half + end_width:
		return 0.0
	var s := p.dot(dir)   # across it, foot to top
	var steps := _cum.size()
	var wob := wobble * (1.0 + 0.5 * steps)
	if s <= -wob - 1.0 or s >= depth + back:
		return 0.0
	var fr := _share(x, z, s)
	if fr <= 0.0:
		return 0.0
	var top := fr
	# the top: lumpy, its height a little different along the band; the back eases down along a wandering line
	var local := 1.0 + 0.10 * _n(x, z, 11, 0.4) + 0.04 * _n(x, z, 12, 1.6) * smoothstep(0.9, 1.0, top)
	var bk := 1.0 - smoothstep(depth - back + back * 0.5 * _n(x, z, 13, 0.25), depth + back * 0.5 * _n(x, z, 13, 0.25), s)
	var tt := t + end_width * 0.5 * _n(x, z, 14, 0.4)
	var g := 1.0 - smoothstep(half - end_width, half, tt)
	return rise * fr * local * bk * g


## The share (0 to 1) of the rise reached at distance `s` across the face at (x, z): the risers' smooth steps,
## each riser on its own wandering line.
func _share(x: float, z: float, s: float) -> float:
	var steps := _cum.size()
	var out := 0.0
	var prev := 0.0
	for i in steps:
		var amp := wobble * (1.0 + 0.5 * float(i))   # the top lip wanders most
		var s0 := float(i) * (face + ledge) + _n(x, z, i + 1, 0.8) * amp
		out += (_cum[i] - prev) * smoothstep(s0, s0 + face, s)
		prev = _cum[i]
	return out


## Colours the face (the generator calls it for every shaded point with its colour `c`): each riser its own tone of
## rock, the ledges soil, so the face reads as chunky layered stone. Outside the band `c` comes back unchanged.
func shade(x: float, z: float, _h: float, ny: float, c: Color) -> Color:
	var p := Vector2(x, z) - origin
	if absf(p.x * dir.y - p.y * dir.x) >= length * 0.5 + end_width:
		return c
	var s := p.dot(dir)
	var steps := _cum.size()
	var zone := float(steps) * (face + ledge) + wobble * 3.0 + 4.0   # the face and the lip, where the colour is set
	if s <= -wobble * (1.0 + 0.5 * steps) - 1.0 or s >= zone + 20.0:
		return c
	var fr := _share(x, z, s)
	if fr <= 0.005:
		return c
	var rock := LFTerrainGenerator.ROCK.lerp(Color(0.55, 0.44, 0.34), 0.35)   # warm grey-brown stone
	# no snow white on the face and the lip (the height line of the land beside it can reach the raised ground)
	var white := smoothstep(0.6, 0.8, c.get_luminance()) * (1.0 - smoothstep(zone, zone + 20.0, s))
	var out := c.lerp(LFMeshBuilder.tint(rock, 1.1), white)
	if fr >= 0.995:
		return out
	var idx := 0
	while idx < steps - 1 and fr > _cum[idx] - 0.001:
		idx += 1
	var tone := fposmod(sin((float(idx) + float(noise_seed % 97)) * 12.9898 + 4.1414) * 43758.5453, 1.0)
	var steep := 1.0 - smoothstep(0.55, 0.85, ny)
	rock = LFMeshBuilder.tint(rock, 0.8 + 0.4 * tone)
	out = out.lerp(rock, steep * 0.9)
	var soil := Color(0.46, 0.37, 0.25)
	return out.lerp(soil, (1.0 - steep) * 0.45)


## Marks the risers as bare ground in `mask` (gen.ground_mask), so no trees, rocks or grass stand on the faces; the
## ledges and the top stay open for scatter. add_roads() calls it.
func mask_face(mask: LFGroundMask) -> void:
	if _noise == null:
		prepare()
	var perp := Vector2(-dir.y, dir.x)
	for i in _cum.size():
		var amp := wobble * (1.0 + 0.5 * float(i))
		var prev := Vector2.INF
		var t := -length * 0.5 - end_width * 0.5
		while t <= length * 0.5 + end_width * 0.5 + 0.1:
			var s0 := float(i) * (face + ledge)
			for it in 2:   # the riser's line at this point: noise at where it lands
				var q := origin + perp * t + dir * s0
				s0 = float(i) * (face + ledge) + _n(q.x, q.y, i + 1, 0.8) * amp
			var pt := origin + perp * t + dir * (s0 + face * 0.5)
			if prev.is_finite():
				mask.add_segment(prev, pt, face * 0.5 + 1.0)
			prev = pt
			t += 6.0


## Sets and returns the two mouths (foot_mouth, top_mouth) on the ground of `gen` (its heights include the band
## once it is in `gen.stamps`): the foot a little before the first riser, the top a little past the lip.
func mouths(gen: LFTerrainGenerator) -> Array[Dictionary]:
	if _noise == null:
		prepare()
	var foot_s := -foot_gap
	while foot_s < 40.0 and _share_on_axis(foot_s) < 0.02:
		foot_s += 0.5
	foot_s -= foot_gap + 0.5
	var top_s := float(_cum.size()) * (face + ledge) + wobble * 3.0 + 12.0
	while top_s > 0.0 and _share_on_axis(top_s) > 0.97:
		top_s -= 0.5
	top_s += top_gap + 0.5
	var foot := origin + dir * foot_s
	var top := origin + dir * top_s
	foot_mouth = {"position": Vector3(foot.x, gen.get_height(foot.x, foot.y), foot.y), "facing": -dir,
			"yaw": atan2(-dir.x, -dir.y)}
	top_mouth = {"position": Vector3(top.x, gen.get_height(top.x, top.y), top.y), "facing": dir,
			"yaw": atan2(dir.x, dir.y)}
	return [foot_mouth, top_mouth]


# The share of the rise on the road's axis (through origin along dir) at distance s.
func _share_on_axis(s: float) -> float:
	var p := origin + dir * s
	return _share(p.x, p.y, s)


## Splits `route` (x, z points, running foot to top) at the band: [the part up to the foot mouth, the part from
## the top mouth on]. Either is empty when the route doesn't reach that side. Call mouths() first.
func split_route(route: PackedVector2Array) -> Array[PackedVector2Array]:
	var foot_p := Vector2(foot_mouth["position"].x, foot_mouth["position"].z)
	var top_p := Vector2(top_mouth["position"].x, top_mouth["position"].z)
	var s_foot := (foot_p - origin).dot(dir)
	var s_top := (top_p - origin).dot(dir)
	var low := PackedVector2Array()
	var high := PackedVector2Array()
	for p in route:
		var s := (p - origin).dot(dir)
		if s < s_foot - 1.0:
			low.append(p)
		elif s > s_top + 1.0:
			high.append(p)
	if low.size() >= 1:
		low.append(foot_p)
	if high.size() >= 1:
		high.insert(0, top_p)
	return [low if low.size() >= 2 else PackedVector2Array(), high if high.size() >= 2 else PackedVector2Array()]


## Adds `route` to `gen.roads` as two roads, one ending at foot_mouth and one starting at top_mouth, so no road
## climbs the face. Adds the band to `gen.stamps` first if it is not there (the roads must see the raised land).
## `meta` goes on both (see LFTerrainRoads.add_road). Returns the two pieces. Sets the mouths.
func add_roads(gen: LFTerrainGenerator, route: PackedVector2Array, meta := {}) -> Array[PackedVector2Array]:
	if not gen.stamps.has(self):
		gen.stamps.append(self)
	mouths(gen)
	var pieces := split_route(route)
	for part in pieces:
		if part.size() >= 2:
			gen.roads.add_road(gen, part, meta.duplicate())
	mask_face(gen.ground_mask)
	mouths(gen)   # the road changed the ground at the mouths a little
	return pieces
