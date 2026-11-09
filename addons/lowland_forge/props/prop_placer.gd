class_name LFPropPlacer
extends RefCounted
## Decides where props go in one chunk. Fully deterministic: the RNG is seeded
## from (world seed, chunk coords), so a rebuilt chunk is identical.
## Uses a jittered grid (one candidate per cell, randomly nudged) - cheap and avoids
## the clumping of pure random scatter.

const K := LFPropMeshes.Kind
const SPAWN_CLEAR_RADIUS := 3.5

# What grows where is each biome's (LFBiomeDef: trees, plants, rock_chance, log_chance, habitats).
# Mushrooms and berry bushes are not in the plant rules: they are food, so they grow
# in rare clustered patches (see _forage). Plain bushes in the rules are undergrowth (variant 0).
const BUSH_PLAIN := 0
const BUSH_BERRY := 1
## Patch attempts per chunk and base acceptance (times habitat suitability 0..1).
const BERRY_ATTEMPTS := 3
const BERRY_CHANCE := 0.07
const MUSHROOM_ATTEMPTS := 4
const MUSHROOM_CHANCE := 0.03  # lowered: logs host many of the mushroom patches
## Extra fern/grass chance multiplier right at a river bank.
const RIVER_FERN_BONUS := 0.35
## Fallen logs: attempts per chunk; each is accepted by LFBiomeDef.log_chance blended by biome weights.
## Old growth (0.21) gives ~0.65 logs per 32x32 m chunk (~1 per 40x40 m).
const LOG_ATTEMPTS := 3
const LOG_MUSHROOM_BASE := 0.18  # chance a log has a mushroom patch (+ LFBiomeDef.log_mushroom_bonus)


## Returns { "batches": {Vector2i(kind, variant): Array[Transform3D]}, "colliders": Array,
## "log_colliders": Array, "cliff_colliders": Array, "forage": Array }.
## Transforms are in chunk-local space. A collider is [is_sphere, Vector3 pos, radius, height].
## A log collider is [Transform3D (capsule centre + orientation), radius, length].
## A cliff collider is a cliff rock's convex hull as triangles (PackedVector3Array, chunk-local).
## `levels`: the chunk's water levels (LFChunkData.water_levels) if the caller has them, else worked out here.
## A forage entry is { id, kind (&"berries"/&"mushroom"), key: Vector2i (batch), idx: int (index in the
## batch), pos: Vector3 (chunk-local), xf: Transform3D }. Ids are stable across rebuilds.
static func place(gen: LFTerrainGenerator, lib: LFPropMeshes, coord: Vector2i, heights: PackedFloat32Array,
		levels := PackedFloat32Array()) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.chunk_seed(coord, 101)
	var origin := Vector2(coord.x, coord.y) * LFTerrainGenerator.CHUNK_SIZE
	if levels.is_empty():   # (the caller's grid saves working it out again; empty when all water is the sea's)
		levels = LFChunkData.water_levels(gen, Vector3(origin.x, 0.0, origin.y))
	var batches: Dictionary = {}
	var colliders: Array = []
	_trees(gen, lib, rng, origin, heights, levels, batches, colliders)
	_rocks(gen, lib, rng, origin, heights, levels, batches, colliders)
	_plants(gen, lib, rng, origin, heights, levels, batches)
	var forage: Array = []
	var log_colliders: Array = []
	_logs(gen, lib, coord, origin, heights, levels, batches, colliders, forage, log_colliders)
	_forage(gen, lib, rng, origin, heights, levels, batches, colliders, forage)
	var cliff_colliders: Array = []
	_cliff_rocks(gen, lib, coord, origin, heights, levels, batches, cliff_colliders)
	_scree_rocks(gen, lib, coord, origin, heights, levels, batches, colliders)
	_clear_bare(gen, origin, batches, forage)
	var counts: Dictionary = {}
	for e: Dictionary in forage:
		var kind: StringName = e["kind"]
		var n: int = counts.get(kind, 0)
		counts[kind] = n + 1
		e["id"] = "%d_%d_%s_%d" % [coord.x, coord.y, kind, n]
	return {"batches": batches, "colliders": colliders, "log_colliders": log_colliders,
			"cliff_colliders": cliff_colliders, "forage": forage}


## Only the big props of a chunk (trees, rocks, logs, cliff rocks, scree), exactly where place() puts them, at a fraction of the
## cost (no ground cover): {Vector2i(kind, variant): Array[Transform3D]} in chunk-local space. For previews.
static func place_large(gen: LFTerrainGenerator, lib: LFPropMeshes, coord: Vector2i, heights: PackedFloat32Array,
		levels := PackedFloat32Array()) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.chunk_seed(coord, 101)
	var origin := Vector2(coord.x, coord.y) * LFTerrainGenerator.CHUNK_SIZE
	if levels.is_empty():   # (the caller's grid saves working it out again; empty when all water is the sea's)
		levels = LFChunkData.water_levels(gen, Vector3(origin.x, 0.0, origin.y))
	var batches: Dictionary = {}
	var colliders: Array = []
	_trees(gen, lib, rng, origin, heights, levels, batches, colliders)
	_rocks(gen, lib, rng, origin, heights, levels, batches, colliders)
	_logs(gen, lib, coord, origin, heights, levels, batches, colliders, [], [])   # own RNG: same logs as place()
	_cliff_rocks(gen, lib, coord, origin, heights, levels, batches, [])   # own RNG too
	_scree_rocks(gen, lib, coord, origin, heights, levels, batches, [])
	for key: Vector2i in batches.keys():
		if LFPropMeshes.is_small(key.x):
			batches.erase(key)   # the mushrooms beside logs
	return batches


## Ground cover kinds that trodden ground (LFGroundMask: lanes, plazas, floors, roads) stays clear of.
const COVER_KINDS := [K.GRASS, K.FLOWER, K.FERN, K.BUSH, K.MUSHROOM]


## Removes ground cover standing on bare ground, from every placement pass at once (keeping the forage
## records' batch indices right).
static func _clear_bare(gen: LFTerrainGenerator, origin: Vector2, batches: Dictionary, forage: Array) -> void:
	if gen.ground_mask.is_empty():
		return
	var remap := {}
	for key: Vector2i in batches.keys():
		if not COVER_KINDS.has(key.x):
			continue
		var arr: Array = batches[key]
		var kept: Array[Transform3D] = []
		var map := PackedInt32Array()
		for t: Transform3D in arr:
			if gen.ground_mask.covers(origin.x + t.origin.x, origin.y + t.origin.z):
				map.append(-1)
			else:
				map.append(kept.size())
				kept.append(t)
		batches[key] = kept
		remap[key] = map
	var still: Array = []
	for e: Dictionary in forage:
		if remap.has(e["key"]):
			var ni: int = (remap[e["key"]] as PackedInt32Array)[int(e["idx"])]
			if ni < 0:
				continue
			e["idx"] = ni
		still.append(e)
	forage.clear()
	forage.append_array(still)


## A per-biome number (an LFBiomeDef property) blended by the biome weights.
static func _blend(gen: LFTerrainGenerator, w: PackedFloat32Array, prop: StringName) -> float:
	var bs := gen.biomes()
	var v := 0.0
	for i in w.size():
		v += w[i] * float(bs[i].get(prop))
	return v


static func _near_spawn(gen: LFTerrainGenerator, wx: float, wz: float) -> bool:
	return Vector2(wx, wz).distance_squared_to(gen.spawn_xz) < SPAWN_CLEAR_RADIUS * SPAWN_CLEAR_RADIUS


static func _emit(batches: Dictionary, kind: int, variant: int, xf: Transform3D, forage: Array = []) -> void:
	var key := Vector2i(kind, variant)
	if not batches.has(key):
		batches[key] = [] as Array[Transform3D]
	batches[key].append(xf)
	if kind == K.MUSHROOM or (kind == K.BUSH and variant == BUSH_BERRY):
		forage.append({"kind": &"mushroom" if kind == K.MUSHROOM else &"berries", "key": key,
				"idx": batches[key].size() - 1, "pos": xf.origin, "xf": xf})


static func _trees(gen: LFTerrainGenerator, lib: LFPropMeshes, rng: RandomNumberGenerator, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary, colliders: Array) -> void:
	var cell := 4.0
	var n := int(LFTerrainGenerator.CHUNK_SIZE / cell)
	for cj in n:
		for ci in n:
			var lx := (ci + rng.randf()) * cell
			var lz := (cj + rng.randf()) * cell
			var roll := rng.randf()
			var biome_roll := rng.randf()
			var yaw := rng.randf() * TAU
			var scl := rng.randf_range(0.8, 1.2)
			var variant_roll := rng.randi()
			var s := LFTerrainGenerator.sample_grid(heights, lx, lz)
			if _above(levels, lx, lz, s.w) < 0.9 or s.y < 0.86:  # underwater/shore or too steep
				continue
			var wx := origin.x + lx
			var wz := origin.y + lz
			if _near_spawn(gen, wx, wz):
				continue
			var bd: LFBiomeDef = gen.biomes()[LFTerrainGenerator.pick_biome(gen.biome_weights(wx, wz), biome_roll)]
			var dens := gen.forest_density(wx, wz) if bd.clearings else 1.0
			var rule := _pick_tree(bd, roll, dens, gen.tree_density)
			if rule == null:
				continue
			if rule.near_water > 0.0 and not gen.near_water(wx, wz, rule.near_water):
				continue
			var kind := int(rule.kind)
			if rule.scale_max > 0.0:
				scl = rng.randf_range(rule.scale_min, rule.scale_max)   # e.g. huge ancient trees
			else:
				scl *= rule.scale
			if not gen.ground_mask.is_empty() and gen.ground_mask.covers(wx, wz):
				continue   # trodden ground: lanes, plazas, floors, roads
			# Size: grove age (young stands smaller, old ones taller) plus a wide per-tree spread,
			# with the odd sapling or veteran so neighbours never match.
			var size_roll := rng.randf()
			scl *= 1.0 + 0.2 * gen.stand_age(wx, wz)
			if size_roll < 0.12:
				scl *= rng.randf_range(0.5, 0.72)
			elif size_roll > 0.94:
				scl *= rng.randf_range(1.2, 1.35)
			scl = minf(scl, 2.1)
			var variant := int(variant_roll % lib.variant_count(kind))
			var pos := Vector3(lx, s.w - 0.1, lz)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scl, scl * rng.randf_range(0.9, 1.15), scl)), pos)
			_emit(batches, kind, variant, xf)
			var trunk_r: float = lib.collide_radius[kind][variant] * scl
			colliders.append([false, pos, trunk_r, 4.0 * scl])


## The tree rule a cell's roll lands on: rules from 0 up (chance x forest density, cumulative), then the
## `from_top` ones from 1 down (not thinned by clearings). Every chance is scaled by `mul` (the map's tree
## density). Null: no tree.
static func _pick_tree(bd: LFBiomeDef, roll: float, dens: float, mul := 1.0) -> LFPropRule:
	var acc := 0.0
	for r: LFPropRule in bd.trees:
		if not r.from_top:
			acc += r.chance * mul
			if roll < acc * dens:
				return r
	var top := 1.0
	for r: LFPropRule in bd.trees:
		if r.from_top:
			top -= r.chance * mul
			if roll > top:
				return r
	return null


static func _rocks(gen: LFTerrainGenerator, lib: LFPropMeshes, rng: RandomNumberGenerator, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary, colliders: Array) -> void:
	var cell := 8.0
	var n := int(LFTerrainGenerator.CHUNK_SIZE / cell)
	var count := lib.variant_count(K.ROCK)
	for cj in n:
		for ci in n:
			var lx := (ci + rng.randf()) * cell
			var lz := (cj + rng.randf()) * cell
			var roll := rng.randf()
			var biome_roll := rng.randf()
			var size_roll := rng.randf()
			var yaw := rng.randf() * TAU
			var scl := rng.randf_range(0.8, 1.3)
			var tilt := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			var s := LFTerrainGenerator.sample_grid(heights, lx, lz)
			if _above(levels, lx, lz, s.w) < -0.3 or s.y < 0.4:
				continue
			var wx := origin.x + lx
			var wz := origin.y + lz
			if _near_spawn(gen, wx, wz):
				continue
			var bd: LFBiomeDef = gen.biomes()[LFTerrainGenerator.pick_biome(gen.biome_weights(wx, wz), biome_roll)]
			if roll > bd.rock_chance * gen.rock_density:
				continue
			# a power > 1 biases towards small rocks; old growth (1.4) gets bigger boulders
			var bias := bd.rock_size_bias
			var variant := mini(int(pow(size_roll, bias) * count), count - 1)
			var pos := Vector3(lx, s.w, lz)
			var basis := Basis.from_euler(tilt + Vector3(0, yaw, 0)).scaled(Vector3(scl, scl, scl))
			_emit(batches, K.ROCK, variant, Transform3D(basis, pos))
			var r: float = lib.collide_radius[K.ROCK][variant] * scl
			if r > 0.5:  # pebbles don't block the player
				colliders.append([true, pos + Vector3(0, r * 0.45, 0), r, 0.0])


static func _plants(gen: LFTerrainGenerator, lib: LFPropMeshes, rng: RandomNumberGenerator, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary) -> void:
	var cell := 2.0
	var n := int(LFTerrainGenerator.CHUNK_SIZE / cell)
	for cj in n:
		for ci in n:
			var lx := (ci + rng.randf()) * cell
			var lz := (cj + rng.randf()) * cell
			var roll := rng.randf()
			var biome_roll := rng.randf()
			var yaw := rng.randf() * TAU
			var scl := rng.randf_range(0.8, 1.3)
			var variant_roll := rng.randi()
			var s := LFTerrainGenerator.sample_grid(heights, lx, lz)
			var above := _above(levels, lx, lz, s.w)
			if above < 0.5 or s.y < 0.7:
				continue
			var wx := origin.x + lx
			var wz := origin.y + lz
			var b := LFTerrainGenerator.pick_biome(gen.biome_weights(wx, wz), biome_roll)
			var acc := 0.0
			var kind := -1
			var picked: LFPropRule = null
			var bank := gen.river_factor(wx, wz) if above < 3.0 else 0.0
			var rules: Array[LFPropRule] = gen.biomes()[b].plants
			var chances := gen.plant_chances(b)
			for k in rules.size():
				var rule := rules[k]
				var p := chances[k]
				if bank > 0.0 and rule.river_bonus:
					p += RIVER_FERN_BONUS * bank  # lush vegetation along river banks
				if rule.patchy:
					p *= 0.15 + 1.7 * gen.flower_patch(wx, wz)  # flowers come in patches
				p *= gen.cover_density
				acc += p
				if roll < acc:
					kind = int(rule.kind)
					picked = rule
					break
			if kind < 0:
				continue
			if picked.near_water > 0.0 and not gen.near_water(wx, wz, picked.near_water):
				continue
			if kind == K.BUSH and _near_spawn(gen, wx, wz):
				continue
			var variant := int(variant_roll % lib.variant_count(kind))
			if kind == K.BUSH:
				variant = BUSH_PLAIN
			if kind == K.GRASS or kind == K.FERN or kind == K.BUSH:   # the biome's undergrowth colour
				variant = LFPropMeshes.tinted_variant(variant, gen.biomes()[b].grass_tint)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scl, scl, scl)), Vector3(lx, s.w - 0.02, lz))
			_emit(batches, kind, variant, xf)


## Berry bushes and mushrooms: rare patches of several plants. Each attempt picks a
## spot, scores how suitable the habitat is (0..1), and only then grows a patch.
## Berries: Birch Woods and Meadow margins, not deep forest. Mushrooms: Old Growth,
## beside tree trunks, plus damp spots near water.
static func _forage(gen: LFTerrainGenerator, lib: LFPropMeshes, rng: RandomNumberGenerator, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary, colliders: Array, forage: Array) -> void:
	var trunks: Array = []
	for c: Array in colliders:
		if not c[0]:
			trunks.append(c[1])
	var size := LFTerrainGenerator.CHUNK_SIZE
	for a in BERRY_ATTEMPTS:
		var cx := rng.randf() * size
		var cz := rng.randf() * size
		var accept := rng.randf()
		var count := 2 + rng.randi() % 3  # 2..4
		var spread := rng.randf_range(1.0, 2.2)
		var wx := origin.x + cx
		var wz := origin.y + cz
		var w := gen.biome_weights(wx, wz)
		# LFBiomeDef.berry_habitat: birch is the home habitat; meadow is OK; old growth/pine barely.
		var hab := _blend(gen, w, &"berry_habitat")
		# Forest edges and clearings: dense forest is bad, open ground is good.
		hab *= 1.0 - 0.7 * smoothstep(0.6, 1.0, gen.forest_density(wx, wz))
		if accept < BERRY_CHANCE * hab * gen.cover_density:
			_patch(gen, rng, origin, heights, levels, batches, K.BUSH, BUSH_BERRY, count, spread, cx, cz, false, 0.9, 1.2, forage)
	for a in MUSHROOM_ATTEMPTS:
		var cx := rng.randf() * size
		var cz := rng.randf() * size
		var accept := rng.randf()
		var count := 3 + rng.randi() % 4  # 3..6
		var ring := rng.randf() < 0.4
		var tree_pick := rng.randi()
		var at_tree := not trunks.is_empty() and rng.randf() < 0.7
		var spread := rng.randf_range(0.8, 1.8)
		var variant := int(rng.randi() % lib.variant_count(K.MUSHROOM))
		if at_tree:  # next to a trunk (outside its radius)
			var t: Vector3 = trunks[tree_pick % trunks.size()]
			var ang := rng.randf() * TAU
			cx = t.x + cos(ang) * (spread + 1.0)
			cz = t.z + sin(ang) * (spread + 1.0)
		var wx := origin.x + cx
		var wz := origin.y + cz
		var w := gen.biome_weights(wx, wz)
		var hab := _blend(gen, w, &"mushroom_habitat")
		if not at_tree:
			hab *= 0.6  # open ground, away from shade, is less likely
		# damp spots near water: low ground a few metres above the waterline
		var hh := _above(levels, cx, cz, gen.get_height(wx, wz))
		if hh > 0.8 and hh < 2.6:
			hab = maxf(hab, 0.45 * (1.0 - _blend(gen, w, &"dryness")))
		if accept < MUSHROOM_CHANCE * hab * gen.cover_density:
			_patch(gen, rng, origin, heights, levels, batches, K.MUSHROOM, variant, count, spread, cx, cz, ring, 0.8, 1.2, forage)


## Grows `count` plants around (cx, cz) (chunk-local), scattered or on a ring.
static func _patch(gen: LFTerrainGenerator, rng: RandomNumberGenerator, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary, kind: int, variant: int, count: int,
		spread: float, cx: float, cz: float, ring: bool, smin: float, smax: float, forage: Array) -> void:
	var phase := rng.randf() * TAU
	for i in count:
		var ang := rng.randf() * TAU
		var dist := spread * sqrt(rng.randf())
		if ring:
			ang = phase + TAU * float(i) / float(count) + rng.randf_range(-0.3, 0.3)
			dist = spread * (0.85 + rng.randf() * 0.3)
		var lx := cx + cos(ang) * dist
		var lz := cz + sin(ang) * dist
		var yaw := rng.randf() * TAU
		var scl := rng.randf_range(smin, smax)
		if lx < 0.0 or lz < 0.0 or lx >= LFTerrainGenerator.CHUNK_SIZE or lz >= LFTerrainGenerator.CHUNK_SIZE:
			continue
		var s := LFTerrainGenerator.sample_grid(heights, lx, lz)
		if _above(levels, lx, lz, s.w) < 0.9 or s.y < 0.75:
			continue
		if _near_spawn(gen, origin.x + lx, origin.y + lz):
			continue
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scl, scl, scl)), Vector3(lx, s.w - 0.02, lz))
		_emit(batches, kind, variant, xf, forage)


## Fallen logs, mostly Old Growth and Pine. Own RNG stream (does not disturb the other props).
## Skips steep/wet ground and anything overlapping a tree trunk or rock. Some logs get a mushroom
## patch along their sides.
static func _logs(gen: LFTerrainGenerator, lib: LFPropMeshes, coord: Vector2i, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary, colliders: Array, forage: Array,
		log_colliders: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.chunk_seed(coord, 102)
	var size := LFTerrainGenerator.CHUNK_SIZE
	var count := lib.variant_count(K.LOG)
	for a in LOG_ATTEMPTS:
		var cx := rng.randf() * size
		var cz := rng.randf() * size
		var accept := rng.randf()
		var yaw := rng.randf() * TAU
		var variant := int(rng.randi() % count)
		var scl := rng.randf_range(0.9, 1.1)
		var mush_roll := rng.randf()
		var mush_n := 3 + rng.randi() % 4
		var mush_variant := int(rng.randi() % lib.variant_count(K.MUSHROOM))
		var mush_seed := rng.randi()
		var wx := origin.x + cx
		var wz := origin.y + cz
		var w := gen.biome_weights(wx, wz)
		if accept >= _blend(gen, w, &"log_chance") * gen.tree_density:
			continue
		var length: float = lib.log_length[variant] * scl
		var radius: float = lib.collide_radius[K.LOG][variant] * scl
		var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
		var half := length * 0.5
		var e0 := Vector2(cx, cz) - Vector2(dir.x, dir.z) * half
		var e1 := Vector2(cx, cz) + Vector2(dir.x, dir.z) * half
		if minf(e0.x, e1.x) < 1.0 or minf(e0.y, e1.y) < 1.0 or maxf(e0.x, e1.x) > size - 1.0 or maxf(e0.y, e1.y) > size - 1.0:
			continue
		var s0 := LFTerrainGenerator.sample_grid(heights, e0.x, e0.y)
		var s1 := LFTerrainGenerator.sample_grid(heights, e1.x, e1.y)
		var sc := LFTerrainGenerator.sample_grid(heights, cx, cz)
		if minf(s0.w, minf(s1.w, sc.w)) < 1.0 or sc.y < 0.85 or absf(s1.w - s0.w) > 0.3 * length:
			continue
		if _near_spawn(gen, wx, wz) or _near_spawn(gen, origin.x + e0.x, origin.y + e0.y) \
				or _near_spawn(gen, origin.x + e1.x, origin.y + e1.y):
			continue
		var blocked := false
		for c: Array in colliders:
			var cp: Vector3 = c[1]
			var q := Vector2(cp.x, cp.z)
			var seg := e1 - e0
			var t := clampf((q - e0).dot(seg) / seg.length_squared(), 0.0, 1.0)
			if q.distance_to(e0 + seg * t) < float(c[2]) + radius + 0.4:
				blocked = true
				break
		if blocked:
			continue
		var axis := Vector3(e1.x - e0.x, s1.w - s0.w, e1.y - e0.y).normalized()
		var zax := axis.cross(Vector3.UP).normalized()
		var yax := zax.cross(axis)
		var basis := Basis(axis * scl, yax * scl, zax * scl)
		var ground := maxf((s0.w + s1.w) * 0.5, sc.w) - 0.14
		var pos := Vector3(cx, ground, cz)
		_emit(batches, K.LOG, variant, Transform3D(basis, pos))
		var axis_center: Vector3 = pos + yax * radius
		var cap_basis := Basis(axis, yax, zax) * Basis(Vector3(0, 0, 1), PI * 0.5)
		log_colliders.append([Transform3D(cap_basis, axis_center), radius * 0.9, length])
		# mushrooms on the damp ground beside the log
		var mp := LOG_MUSHROOM_BASE + _blend(gen, w, &"log_mushroom_bonus")
		if mush_roll >= mp:
			continue
		var mrng := RandomNumberGenerator.new()
		mrng.seed = mush_seed
		var perp := Vector3(-axis.z, 0.0, axis.x).normalized()
		for i in mush_n:
			var along := mrng.randf_range(-0.42, 0.42) * length
			var side := (1.0 if mrng.randf() < 0.5 else -1.0) * (radius + mrng.randf_range(0.3, 0.9))
			var lx := cx + dir.x * along + perp.x * side
			var lz := cz + dir.z * along + perp.z * side
			var ms := mrng.randf_range(0.8, 1.2)
			var myaw := mrng.randf() * TAU
			if lx < 0.0 or lz < 0.0 or lx >= size or lz >= size:
				continue
			var s := LFTerrainGenerator.sample_grid(heights, lx, lz)
			if _above(levels, lx, lz, s.w) < 0.9 or s.y < 0.75:
				continue
			var xf := Transform3D(Basis(Vector3.UP, myaw).scaled(Vector3(ms, ms, ms)), Vector3(lx, s.w - 0.02, lz))
			_emit(batches, K.MUSHROOM, mush_variant, xf, forage)


## Cliff rocks: slabs of layered rock (LFPropMeshes.Kind.CLIFF) in the cliff bands (LFTerrainGenerator.cliff_band)
## on steep ground in a hard rock layer, and thinner on any ground steeper than about 2 m per m; their faces turned down the slope, leaning back into it and half sunk, so a
## cliff band shows rock faces and a broken outline. Never in water, on roads or bare ground, at sites or the
## spawn. Its own RNG (the other props don't move with cliff_rocks); their hulls go to `cliff_colliders`.
static func _cliff_rocks(gen: LFTerrainGenerator, lib: LFPropMeshes, coord: Vector2i, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary, cliff_colliders: Array) -> void:
	var p := gen.params
	var count := lib.variant_count(K.CLIFF)
	if p == null or p.cliffs <= 0.0 or p.cliff_rocks <= 0.0 or count == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.chunk_seed(coord, 103)
	var n := 8   # 4 m cells: a band's hard layer is only a few metres across on the slope
	var cell := LFTerrainGenerator.CHUNK_SIZE / n
	for cj in n:
		for ci in n:
			var lx := (ci + rng.randf()) * cell
			var lz := (cj + rng.randf()) * cell
			var roll := rng.randf()
			var variant := int(rng.randi() % count)
			var scl := rng.randf_range(0.85, 1.35) * p.cliff_rock_size
			var turn := rng.randf_range(-0.3, 0.3)
			var lean := rng.randf_range(0.05, 0.2)
			var sink := rng.randf_range(0.3, 0.45)
			var top_jit := rng.randf_range(-0.3, 0.4)
			var s := LFTerrainGenerator.sample_grid(heights, lx, lz)
			if s.y > 0.7 or _above(levels, lx, lz, s.w) < 1.0:   # steeper than 1 m per m, out of the water
				continue
			var wx := origin.x + lx
			var wz := origin.y + lz
			if roll >= 0.9 * p.cliff_rocks:
				continue
			# in a hard layer, fewer where the slope only just makes a cliff; ground steeper than ~2 m per m is a
			# cliff in any layer
			var hard := gen.rock_layer(wx, wz, s.w).z > 0.0
			var want := smoothstep(0.7, 0.55, s.y) if hard else 0.3 * smoothstep(0.5, 0.4, s.y)
			if roll >= 0.9 * p.cliff_rocks * want * gen.cliff_band(wx, wz):
				continue
			if _near_spawn(gen, wx, wz) or gen.site_blocked(wx, wz, 4.0) \
					or (not gen.ground_mask.is_empty() and gen.ground_mask.covers(wx, wz)):
				continue
			var down := Vector2(s.x, s.z).normalized().rotated(turn)   # the normal leans down the slope
			var face := Vector3(down.x, 0.0, down.y)
			var side := Vector3.UP.cross(face)
			var mesh_tall := lib.get_mesh(K.CLIFF, variant).get_aabb().end.y
			var deep := lib.get_mesh(K.CLIFF, variant).get_aabb().end.z * scl
			# the base under the lowest ground below it (its face, down the slope), never floating; the top at the
			# layer's top in a hard layer, so a band's slabs line up, else its own height
			var front := gen.get_height(wx + face.x * deep, wz + face.z * deep)
			var bottom := minf(s.w, front) - 0.6
			var top := s.w + mesh_tall * scl * (1.0 - sink)
			if hard:
				top = gen.rock_layer_span(wx, wz, s.w).y + top_jit
			top = clampf(top, s.w + 1.0, bottom + 14.0 * p.cliff_rock_size)
			var basis := Basis(side, Vector3.UP, face) * Basis(Vector3.RIGHT, -lean)
			basis = basis.scaled(Vector3(scl, (top - bottom) / mesh_tall, scl))
			var xf := Transform3D(basis, Vector3(lx, bottom, lz))
			_emit(batches, K.CLIFF, variant, xf)
			var hull := PackedVector3Array()
			for q in lib.cliff_hulls[variant]:
				hull.append(xf * q)
			cliff_colliders.append(hull)


## Scree boulders: rocks (Kind.ROCK, mostly small) strewn on the scree below a cliff band: in a soft rock layer
## under a hard one, thickest at the riser's foot and thinning down the slope. Its own RNG (after the cliff rocks,
## so the other props don't move); big ones add sphere colliders to `colliders` (after everything else's).
static func _scree_rocks(gen: LFTerrainGenerator, lib: LFPropMeshes, coord: Vector2i, origin: Vector2,
		heights: PackedFloat32Array, levels: PackedFloat32Array, batches: Dictionary, colliders: Array) -> void:
	var p := gen.params
	var count := lib.variant_count(K.ROCK)
	if p == null or p.cliffs <= 0.0 or p.cliff_rocks <= 0.0 or count == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.chunk_seed(coord, 104)
	var n := 10   # 3.2 m cells
	var cell := LFTerrainGenerator.CHUNK_SIZE / n
	for cj in n:
		for ci in n:
			var lx := (ci + rng.randf()) * cell
			var lz := (cj + rng.randf()) * cell
			var roll := rng.randf()
			var size_roll := rng.randf()
			var yaw := rng.randf() * TAU
			var scl := rng.randf_range(0.8, 1.6) * p.cliff_rock_size
			var tilt := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
			var s := LFTerrainGenerator.sample_grid(heights, lx, lz)
			# scree lies back: steeper than ~0.3 m per m, gentler than a cliff
			if s.y < 0.55 or s.y > 0.96 or _above(levels, lx, lz, s.w) < 0.5:
				continue
			if roll >= 0.7 * p.cliff_rocks:
				continue
			var wx := origin.x + lx
			var wz := origin.y + lz
			if gen.rock_layer(wx, wz, s.w).z > 0.0:
				continue
			var span := gen.rock_layer_span(wx, wz, s.w)
			if gen.rock_layer(wx, wz, span.y + 0.5).z <= 0.0:
				continue   # no riser above this layer
			var below := (span.y - s.w) / maxf(span.y - span.x, 1.0)   # 0 at the riser's foot, 1 a layer down
			if roll >= 0.7 * p.cliff_rocks * (1.0 - below) * gen.cliff_band(wx, wz):
				continue
			if _near_spawn(gen, wx, wz) or gen.site_blocked(wx, wz, 2.0) \
					or (not gen.ground_mask.is_empty() and gen.ground_mask.covers(wx, wz)):
				continue
			var variant := mini(int(pow(size_roll, 1.4) * count), count - 1)   # mostly small
			var pos := Vector3(lx, s.w - 0.1 * scl, lz)
			var basis := Basis.from_euler(tilt + Vector3(0, yaw, 0)).scaled(Vector3(scl, scl, scl))
			_emit(batches, K.ROCK, variant, Transform3D(basis, pos))
			var r: float = lib.collide_radius[K.ROCK][variant] * scl
			if r > 0.5:
				colliders.append([true, pos + Vector3(0, r * 0.45, 0), r, 0.0])


## How high ground `h` at chunk-local (lx, lz) stands above the water there: `levels` is the chunk's water
## level grid (LFChunkData.water_levels; a lake or river up in the hills has its own), empty for the sea's.
static func _above(levels: PackedFloat32Array, lx: float, lz: float, h: float) -> float:
	if levels.is_empty():
		return h - LFTerrainGenerator.WATER_LEVEL
	var V := LFTerrainGenerator.VERTS
	var i := clampi(roundi(lx / LFTerrainGenerator.STEP), 0, V - 1)
	var j := clampi(roundi(lz / LFTerrainGenerator.STEP), 0, V - 1)
	return h - levels[j * V + i]
