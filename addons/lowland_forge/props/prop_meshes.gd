class_name LFPropMeshes
extends RefCounted
## Library of procedural low-poly prop meshes. A few random variants of each kind
## are built once at startup and then instanced thousands of times via MultiMesh.

## New kinds go on the end: the ordinals are stored (LFPropRule.kind, chunk prop records, baked file names).
## DEAD .. CRYSTAL are for drier, colder and wetter biomes than the stock four (none of those use them yet).
## CLIFF: the rock slabs of cliff bands (LFPropPlacer puts them by LFTerrainGenerator.cliff_band, not by biome).
enum Kind { PINE, BIRCH, BROAD, ROCK, BUSH, MUSHROOM, FLOWER, GRASS, FERN, LOG,
		DEAD, SNOW_PINE, WILLOW, PALM, CACTUS, REEDS, DRY_BUSH, CRYSTAL, CLIFF }

const TRUNK_DARK := Color(0.27, 0.19, 0.12)
const TRUNK := Color(0.38, 0.27, 0.17)
const SNOW := Color(0.93, 0.95, 0.98)

const TRUNK_SHADER := "res://addons/lowland_forge/shaders/tree_trunk.gdshader"
const FOLIAGE_SHADER := "res://addons/lowland_forge/shaders/foliage.gdshader"

var variants: Dictionary = {}  # Kind -> Array[ArrayMesh]
## Vector2i(kind, variant) -> PackedVector3Array: mesh-space points on the OUTSIDE of a tree's
## real canopy (upward-facing, not buried in another leaf blob) where a bird can perch visibly.
var perch_points: Dictionary = {}
## Your own meshes for built-in kinds (LFPropSwap): set before build().
var swaps: Array = []
var _pending_perches := PackedVector3Array()
var log_length: Array[float] = []  # per LOG variant, metres at scale 1
var collide_radius: Dictionary = {}  # Kind -> Array[float] (unit-scale collider radius)
## Per CLIFF variant: its collision hull as triangles (mesh space, scale 1; convex).
var cliff_hulls: Array[PackedVector3Array] = []
## The cliff rocks' stone colour (set before build; LFMapParams.rock_color, so slabs match the cliffs they stand in).
var rock_color := LFTerrainGenerator.ROCK
var solid_material: StandardMaterial3D
var crystal_material: StandardMaterial3D  # glossy: crystals catch the sun
var plant_material: ShaderMaterial  # grass/ferns/flowers/bushes: big push, strong wind
var canopy_material: ShaderMaterial  # tree leaves: wider but gentler push, less wind (generic)
var trunk_materials: Dictionary = {}  # Kind -> ShaderMaterial (trunk, whole-tree wind bend)
var canopy_materials: Dictionary = {}  # Kind -> ShaderMaterial (leaves, same bend + flutter)

## Whole-tree wind per kind: [tree_height (m, scale 1), bend amplitude, max top offset (m)].
const TREE_WIND := {
	Kind.PINE: [10.0, 1.0, 0.8],
	Kind.BIRCH: [7.5, 0.9, 0.6],
	Kind.BROAD: [10.7, 0.7, 0.6],
	Kind.DEAD: [6.5, 0.35, 0.25],
	Kind.SNOW_PINE: [10.0, 0.8, 0.6],
	Kind.WILLOW: [8.0, 0.8, 0.6],
	Kind.PALM: [8.5, 1.2, 0.9],
}

## Leaf-puff volumes per kind: [y_min, y_max, radius, taper (1 = cone), r, g, b].
## Heights/radius are in metres at scale 1 (see LFPropPlacer scales).
const FOLIAGE_SHAPE := {
	Kind.PINE: [2.8, 8.0, 1.7, 1.0, 0.15, 0.38, 0.19],
	Kind.BIRCH: [3.4, 9.0, 1.3, 0.0, 0.45, 0.62, 0.25],
	Kind.BROAD: [5.4, 10.2, 3.0, 0.0, 0.25, 0.45, 0.17],
	Kind.BUSH: [0.0, 1.1, 0.8, 0.0, 0.2, 0.4, 0.13],
	Kind.FERN: [0.0, 0.8, 0.7, 0.0, 0.2, 0.45, 0.16],
	Kind.SNOW_PINE: [2.8, 8.0, 1.5, 1.0, 0.85, 0.9, 0.95],
	Kind.WILLOW: [1.8, 7.5, 3.4, 0.0, 0.45, 0.58, 0.22],
	Kind.PALM: [6.0, 9.0, 3.0, 0.0, 0.3, 0.5, 0.18],
	Kind.REEDS: [0.0, 1.8, 0.5, 0.0, 0.45, 0.52, 0.24],
}

const _SMALL: Array[int] = [Kind.BUSH, Kind.MUSHROOM, Kind.FLOWER, Kind.GRASS, Kind.FERN, Kind.REEDS, Kind.DRY_BUSH]
const _SOLID: Array[int] = [Kind.PINE, Kind.BIRCH, Kind.BROAD, Kind.ROCK, Kind.DEAD, Kind.SNOW_PINE, Kind.WILLOW,
		Kind.PALM, Kind.CACTUS, Kind.CRYSTAL]


## Plants are tiny and numerous: no shadows, hidden at distance, no collision.
static func is_small(kind: int) -> bool:
	return _SMALL.has(kind)


## Trees, rocks, cacti and crystals: a collider where they stand (logs get their own, lying down).
static func has_collision(kind: int) -> bool:
	return _SOLID.has(kind)


func build(world_seed: int) -> void:
	LFEnvironment.register_globals()
	solid_material = _make_material(false)
	crystal_material = _make_material(false)
	crystal_material.roughness = 0.18
	crystal_material.metallic_specular = 0.9
	plant_material = _make_foliage_material(1.1, 0.7, 1.0)
	canopy_material = _make_foliage_material(2.0, 4.0, 0.35)
	for k in TREE_WIND:
		var tw: Array = TREE_WIND[k]
		var tm := ShaderMaterial.new()
		tm.shader = load(TRUNK_SHADER)
		tm.set_shader_parameter("tree_height", tw[0])
		tm.set_shader_parameter("tree_amp", tw[1])
		tm.set_shader_parameter("max_tree_offset", tw[2])
		trunk_materials[k] = tm
		var cm := _make_foliage_material(2.0, 4.0, 0.35)
		cm.set_shader_parameter("tree_height", tw[0])
		cm.set_shader_parameter("tree_amp", tw[1])
		cm.set_shader_parameter("max_tree_offset", tw[2])
		canopy_materials[k] = cm
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 31 + 12345
	for k in Kind.values():
		variants[k] = []
		collide_radius[k] = []
	for i in 6:  # several shapes per kind so neighbouring trees rarely match
		_add(Kind.PINE, _make_pine(rng), 0.32)
		_add(Kind.BIRCH, _make_birch(rng), 0.2)
		_add(Kind.BROAD, _make_broad(rng), 0.7)
	for r in [0.4, 0.7, 1.1, 1.8, 2.6]:
		_add(Kind.ROCK, _make_rock(rng, r), r * 0.8)
	_add(Kind.BUSH, _make_bush(rng, false), 0.0)
	_add(Kind.BUSH, _make_bush(rng, true), 0.0)
	for col in [Color(0.78, 0.12, 0.10), Color(0.52, 0.33, 0.18), Color(0.88, 0.62, 0.20)]:
		_add(Kind.MUSHROOM, _make_mushroom(rng, col), 0.0)
	for col in [Color(0.95, 0.95, 0.9), Color(0.95, 0.85, 0.2), Color(0.6, 0.35, 0.8), Color(0.9, 0.3, 0.4)]:
		_add(Kind.FLOWER, _make_flowers(rng, col), 0.0)
	_add(Kind.GRASS, _make_grass(rng, Color(0.22, 0.42, 0.14), Color(0.55, 0.75, 0.3)), 0.0)
	_add(Kind.GRASS, _make_grass(rng, Color(0.3, 0.45, 0.15), Color(0.72, 0.78, 0.35)), 0.0)
	_add(Kind.FERN, _make_fern(rng), 0.0)
	_add(Kind.FERN, _make_fern(rng), 0.0)
	for i in 3:
		_make_log(i, rng)
	# The newer kinds roll their own generators, so adding one never reshapes the meshes above.
	rng = _kind_rng(world_seed, Kind.DEAD)
	for i in 4:
		_add(Kind.DEAD, _make_dead(rng, i % 2 == 0), 0.3)
	rng = _kind_rng(world_seed, Kind.SNOW_PINE)
	for i in 4:
		_add(Kind.SNOW_PINE, _make_pine(rng, true), 0.32)
	rng = _kind_rng(world_seed, Kind.WILLOW)
	for i in 3:
		_add(Kind.WILLOW, _make_willow(rng), 0.55)
	rng = _kind_rng(world_seed, Kind.PALM)
	for i in 4:
		_add(Kind.PALM, _make_palm(rng), 0.25)
	rng = _kind_rng(world_seed, Kind.CACTUS)
	for i in 4:
		_add(Kind.CACTUS, _make_cactus(rng, i), [0.35, 0.35, 0.5, 0.45][i])
	rng = _kind_rng(world_seed, Kind.REEDS)
	for i in 2:
		_add(Kind.REEDS, _make_reeds(rng), 0.0)
	rng = _kind_rng(world_seed, Kind.DRY_BUSH)
	_add(Kind.DRY_BUSH, _make_dry_bush(rng, false), 0.0)
	_add(Kind.DRY_BUSH, _make_dry_bush(rng, true), 0.0)
	rng = _kind_rng(world_seed, Kind.CRYSTAL)
	for col in [Color(0.45, 0.85, 0.92), Color(0.64, 0.44, 0.88), Color(0.96, 0.66, 0.28), Color(0.86, 0.90, 0.95)]:
		_add(Kind.CRYSTAL, _make_crystal(rng, col), 0.6)
	rng = _kind_rng(world_seed, Kind.CLIFF)
	for i in 6:
		_add(Kind.CLIFF, _make_cliff(rng), 0.0)
	_apply_swaps()


## Puts the swaps' meshes in place of the built-in variants: their number stays, so placement does not change. A
## private copy per variant: the bake saves these and takes over their paths, which must not be the user's file.
func _apply_swaps() -> void:
	for s: LFPropSwap in swaps:
		if s == null:
			continue
		var list: Array[ArrayMesh] = []
		for m: Mesh in s.meshes:
			if m != null and m.get_surface_count() > 0:
				list.append(_scaled_mesh(_as_array_mesh(m), s.mesh_scale))
		if list.is_empty():
			continue
		var k := int(s.kind)
		for v in variants[k].size():
			variants[k][v] = list[v % list.size()].duplicate()
			perch_points.erase(Vector2i(k, v))   # the old tree's perches would float
			if s.collide_radius >= 0.0 and has_collision(k):
				collide_radius[k][v] = s.collide_radius


## `m` with its vertices multiplied by `size` (materials kept); `m` itself at size 1.
static func _scaled_mesh(m: ArrayMesh, size: float) -> ArrayMesh:
	if is_equal_approx(size, 1.0):
		return m
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arrays := m.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] *= size
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(m.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, m.surface_get_material(s))
	return out


## `m` as an ArrayMesh (a BoxMesh or other primitive is converted; materials kept).
static func _as_array_mesh(m: Mesh) -> ArrayMesh:
	if m is ArrayMesh:
		return m
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s))
		out.surface_set_material(s, m.surface_get_material(s))
	return out


## Plain variants are below this; a tinted plant variant is `variant | (tint code << 8)` (tinted_variant).
const TINT_SHIFT := 8

var _tinted: Dictionary = {}   # Vector2i(kind, tinted variant) -> ArrayMesh, made when first asked for
var _tint_lock := Mutex.new()


func get_mesh(kind: int, variant: int) -> ArrayMesh:
	if variant >> TINT_SHIFT == 0:
		return variants[kind][variant]
	var key := Vector2i(kind, variant)
	_tint_lock.lock()
	if not _tinted.has(key):
		_tinted[key] = tint_mesh(variants[kind][variant & ((1 << TINT_SHIFT) - 1)], tint_of(variant))
	var m: ArrayMesh = _tinted[key]
	_tint_lock.unlock()
	return m


## The variant number of plain variant `variant` coloured by `tint` (multiplied into its vertex colours; white
## gives `variant` itself). The tint is kept to 5 bits a channel, so the same biome always gets the same number.
## For small plants (grass, ferns, plain bushes): they have no collider and no perch points.
static func tinted_variant(variant: int, tint: Color) -> int:
	if tint == Color.WHITE:
		return variant
	var code := 0
	for v in [tint.r, tint.g, tint.b]:
		code = code * 32 + clampi(roundi(v / 2.0 * 31.0), 0, 31)   # 0..2 in 32 steps
	return variant | ((code + 1) << TINT_SHIFT)


## The tint of a tinted variant number (white for a plain one).
static func tint_of(variant: int) -> Color:
	var code := (variant >> TINT_SHIFT) - 1
	if code < 0:
		return Color.WHITE
	return Color((code >> 10 & 31) / 31.0 * 2.0, (code >> 5 & 31) / 31.0 * 2.0, (code & 31) / 31.0 * 2.0)


## A copy of `mesh` with every vertex colour multiplied by `tint` (materials kept).
static func tint_mesh(mesh: ArrayMesh, tint: Color) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if arrays[Mesh.ARRAY_COLOR] != null:   # a swapped-in mesh may have none
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for i in cols.size():
				var c := cols[i]
				cols[i] = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a)
			arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


func variant_count(kind: int) -> int:
	return variants[kind].size()


static func _kind_rng(world_seed: int, kind: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/prop_meshes/%s" % [world_seed, Kind.keys()[kind]])
	return rng


## A per-tree colour shift (multiply a colour by it) so neighbouring trees of one kind never share one exact
## green: a little lighter or darker, a little yellower or bluer.
static func _tree_tint(rng: RandomNumberGenerator) -> Color:
	var v := rng.randf_range(0.88, 1.1)
	var warm := rng.randf_range(-0.07, 0.07)
	return Color(v * (1.0 + warm), v, v * (1.0 - warm * 1.5))


func _add(kind: int, mesh: ArrayMesh, radius: float) -> void:
	variants[kind].append(mesh)
	if not _pending_perches.is_empty():
		perch_points[Vector2i(kind, variants[kind].size() - 1)] = _pending_perches
		_pending_perches = PackedVector3Array()
	collide_radius[kind].append(radius)


func _make_material(double_sided: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true  # colour comes from the mesh, so no textures needed
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Shader material for anything that bends when the player touches it.
## radius = push range (m), height_ref = height above the base at which the push
## is at full strength (roots stay planted), wind = ambient sway strength.
func _make_foliage_material(radius: float, height_ref: float, wind: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(FOLIAGE_SHADER)
	m.set_shader_parameter("push_radius", radius)
	m.set_shader_parameter("height_ref", height_ref)
	m.set_shader_parameter("wind_response", wind)
	return m


# --- trees -----------------------------------------------------------------

## Stacked cone tiers on a bare trunk. Tiers sit a little off-centre and tilted, ragged at the rim, so no two
## pines share a silhouette. `snow`: the SNOW_PINE kind, slimmer and blue-green with snow on every tier.
func _make_pine(rng: RandomNumberGenerator, snow := false) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var leaves := LFMeshBuilder.new()
	var trunk_h := rng.randf_range(2.6, 4.2)
	var tiers := rng.randi_range(5, 8) if snow else rng.randi_range(4, 7)
	var y := trunk_h * 0.9  # bare lower trunk: the lowest tier sits above the camera's usual height
	var r := rng.randf_range(1.3, 2.0) if snow else rng.randf_range(1.4, 2.4)
	var tier_h := rng.randf_range(1.6, 2.4)
	var shrink := rng.randf_range(0.7, 0.8) if snow else rng.randf_range(0.72, 0.84)  # low = slim spire
	var tint := _tree_tint(rng)
	var dark := [Color(0.07, 0.20, 0.16), Color(0.10, 0.26, 0.20)] if snow else [Color(0.09, 0.24, 0.13), Color(0.13, 0.30, 0.16)]
	var light := [Color(0.12, 0.32, 0.24), Color(0.18, 0.40, 0.28)] if snow else [Color(0.16, 0.38, 0.19), Color(0.24, 0.48, 0.24)]
	b.frustum(Vector3.ZERO, Vector3.UP, trunk_h + tiers * 0.5, 0.3, 0.1, 6, TRUNK_DARK, TRUNK, rng, 0.08)
	for i in tiers:
		var t := float(i) / float(tiers - 1)
		var low: Color = (dark[0] as Color).lerp(dark[1], t) * tint
		var high: Color = (light[0] as Color).lerp(light[1], t) * tint
		var rr := r * rng.randf_range(0.88, 1.1)
		var c := Vector3(rng.randf_range(-0.1, 0.1), y, rng.randf_range(-0.1, 0.1))
		var axis := Vector3(rng.randf_range(-0.07, 0.07), 1.0, rng.randf_range(-0.07, 0.07)).normalized()
		var twist := rng.randf() * TAU
		if snow:
			_snow_tier(leaves, c, axis, tier_h, rr, low, high, rng, twist)
		else:
			leaves.frustum(c, axis, tier_h, rr, 0.0, 7, low, high, rng, 0.16, true, twist)
		# Bird perches: the outer rim of each middle tier (branch tips), clear of the tier above.
		if i >= 1 and i <= tiers - 2:
			for a in 8:
				var ang := TAU * a / 8.0 + i * 0.4
				_pending_perches.append(c + Vector3(cos(ang) * rr * 0.92, 0.08, sin(ang) * rr * 0.92))
		y += tier_h * 0.55
		r *= shrink
	return _commit_tree(Kind.SNOW_PINE if snow else Kind.PINE, b, leaves)


## A snow pine's tier: a ragged cone like the pine's, its faces green at the rim and snow above a jagged snow
## line. The snow is painted on the tier's own faces (not a second cone over it), so it sways with the branch.
func _snow_tier(b: LFMeshBuilder, base: Vector3, axis: Vector3, length: float, r: float, low: Color, high: Color,
		rng: RandomNumberGenerator, twist: float) -> void:
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u)
	var top := base + axis * length
	var inside := base + axis * (length * 0.5)
	var rim: Array[Vector3] = []
	var line: Array[Vector3] = []   # the snow line: on the rim-to-top edge, so each face stays one plane
	var at: Array[float] = []
	for i in 7:
		var ang := TAU * float(i) / 7.0 + twist
		rim.append(base + (u * cos(ang) + v * sin(ang)) * (r * (1.0 + rng.randf_range(-0.16, 0.16))))
		at.append(rng.randf_range(0.12, 0.4) if i % 2 == 0 else rng.randf_range(0.04, 0.2))   # green tips between drifts
		line.append(rim[i].lerp(top, at[i]))
	for i in 7:
		var k := (i + 1) % 7
		var f := 1.0 + rng.randf_range(-0.06, 0.06)   # per-face shade jitter
		var g0 := LFMeshBuilder.tint(low, f)
		b.quad_out(rim[i], rim[k], line[k], line[i], g0, g0, LFMeshBuilder.tint(low.lerp(high, at[k]), f),
				LFMeshBuilder.tint(low.lerp(high, at[i]), f), inside)
		var s0 := LFMeshBuilder.tint(SNOW, 0.88 * f)
		b.tri_out(line[i], line[k], top, s0, s0, LFMeshBuilder.tint(SNOW, f), inside)
		b.tri_out(base, rim[i], rim[k], g0, g0, g0, inside)   # the underside


## A slim, slightly leaning white trunk with a tall narrow crown down its upper half (not a ball on a pole).
func _make_birch(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var leaves := LFMeshBuilder.new()
	var h := rng.randf_range(6.0, 8.5)
	var lean := Vector3(rng.randf_range(-0.1, 0.1), 1.0, rng.randf_range(-0.1, 0.1)).normalized()
	var r0 := 0.17
	var r1 := 0.06
	var bark := Color(0.88, 0.86, 0.80)
	b.frustum(Vector3.ZERO, lean, h, r0, r1, 6, Color(0.80, 0.78, 0.72), bark, rng, 0.04)
	for i in rng.randi_range(6, 9):  # dark bark marks: thin slightly fatter rings
		var y := rng.randf_range(0.3, h - 1.0)
		var rr := lerpf(r0, r1, y / h) * 1.06
		var dark := Color(0.12, 0.11, 0.10)
		b.frustum(lean * y, lean, rng.randf_range(0.06, 0.18), rr, rr, 6, dark, dark, rng, 0.05)
	var crown := maxf(3.4, h * 0.45)  # crown bottom: above the camera's usual height
	for i in rng.randi_range(3, 4):  # thin upswept branches, mostly hidden by the leaves
		var a := rng.randf() * TAU
		var y := rng.randf_range(crown, h - 0.8)
		b.frustum(lean * y, Vector3(cos(a), 1.3, sin(a)), rng.randf_range(0.9, 1.4), 0.05, 0.02, 4, bark, bark, rng)
	var tint := _tree_tint(rng)
	var lo := Color(0.30, 0.48, 0.17) * tint
	var hi := Color(0.58, 0.72, 0.30) * tint
	var blobs: Array = []
	var n := rng.randi_range(5, 7)
	for i in n:
		var t := float(i) / float(n - 1)
		var rad := lerpf(1.3, 0.75, t) * rng.randf_range(0.85, 1.1)
		var wob := 0.25 + 0.55 * (1.0 - t)
		var c := lean * lerpf(crown + 1.0, h + 0.3, t) + Vector3(rng.randf_range(-wob, wob), 0, rng.randf_range(-wob, wob))
		var radii := Vector3(rad, rad * 1.15, rad)
		leaves.blob(c, radii, 1, 0.16, rng, lo, hi)
		blobs.append([c, radii])
	_pending_perches = _blob_perches(blobs)
	return _commit_tree(Kind.BIRCH, b, leaves)


func _make_broad(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var leaves := LFMeshBuilder.new()
	var th := rng.randf_range(4.6, 6.0)  # trunk height; branches fork ~1.2 m below its top
	b.frustum(Vector3.ZERO, Vector3.UP, th, 0.75, 0.38, 7, TRUNK_DARK, TRUNK, rng, 0.08)
	b.frustum(Vector3.ZERO, Vector3.UP, 0.8, 1.15, 0.75, 7, TRUNK_DARK, TRUNK_DARK, rng, 0.1)  # root flare
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		b.frustum(Vector3(0, th - 1.2, 0), Vector3(cos(a), 1.1, sin(a)), 2.6, 0.3, 0.14, 5, TRUNK, TRUNK, rng, 0.05)
	var blobs: Array = []
	var spread := rng.randf_range(1.6, 2.8)
	var tint := _tree_tint(rng)
	var lo := Color(0.14, 0.32, 0.13) * tint
	var hi := Color(0.34, 0.55, 0.20) * tint
	for i in rng.randi_range(4, 6):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.6, spread)
		var c := Vector3(cos(a) * d, rng.randf_range(th + 1.0, th + 2.8), sin(a) * d)  # canopy bottom ~th - 1.2
		var rad := rng.randf_range(1.8, 2.9)
		leaves.blob(c, Vector3(rad, rad * 0.78, rad), 1, 0.2, rng, lo, hi)
		blobs.append([c, Vector3(rad, rad * 0.78, rad)])
	for i in rng.randi_range(2, 4):  # small clumps out at the rim break up the round outline
		var a := rng.randf() * TAU
		var d := spread + rng.randf_range(0.2, 0.8)
		var c := Vector3(cos(a) * d, rng.randf_range(th + 0.4, th + 2.0), sin(a) * d)
		var rad := rng.randf_range(0.9, 1.3)
		leaves.blob(c, Vector3(rad, rad * 0.8, rad), 1, 0.2, rng, lo, hi)
		blobs.append([c, Vector3(rad, rad * 0.8, rad)])
	_pending_perches = _blob_perches(blobs)
	return _commit_tree(Kind.BROAD, b, leaves)


## Candidate perch points on the upper-outer surface of a cluster of leaf blobs ([center, radii]
## pairs), skipping any point buried inside a neighbouring blob. Deterministic (no RNG) so the
## world's mesh variants stay identical. Points sit slightly proud of the surface because blobs
## are randomly perturbed by up to ~20%.
func _blob_perches(blobs: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for bi in blobs.size():
		var c: Vector3 = blobs[bi][0]
		var rad: Vector3 = blobs[bi][1]
		for el in [0.3, 0.65]:
			for ai in 10:
				var a := TAU * ai / 10.0 + bi * 0.37
				var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
				var p := c + dir * rad * 1.08
				var buried := false
				for bj in blobs.size():
					if bj != bi and ((p - blobs[bj][0]) / blobs[bj][1]).length() < 1.0:
						buried = true
						break
				if not buried:
					out.append(p)
	return out


## Trunk + canopy surfaces, both bending with the same whole-tree wind function.
func _commit_tree(kind: int, trunk: LFMeshBuilder, leaves: LFMeshBuilder) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	trunk.add_surface_to(mesh, trunk_materials[kind])
	leaves.add_surface_to(mesh, canopy_materials[kind])
	return mesh


# --- ground clutter ----------------------------------------------------------

func _make_rock(rng: RandomNumberGenerator, r: float) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	b.blob(Vector3(0, r * 0.35, 0), Vector3(r, r * 0.7, r * rng.randf_range(0.8, 1.1)), 1, 0.22, rng,
		Color(0.27, 0.26, 0.24), Color(0.47, 0.45, 0.41), Color(0.26, 0.38, 0.16, 0.6))
	return b.commit(solid_material)


func _make_bush(rng: RandomNumberGenerator, berries: bool) -> ArrayMesh:
	var b := LFMeshBuilder.new()  # berries are part of the swaying bush too
	for i in 3:
		var rad := rng.randf_range(0.4, 0.65)
		var c := Vector3(rng.randf_range(-0.4, 0.4), rad * 0.7, rng.randf_range(-0.4, 0.4))
		b.blob(c, Vector3(rad, rad * 0.85, rad), 1, 0.15, rng, Color(0.12, 0.28, 0.10), Color(0.28, 0.48, 0.16))
		if berries:
			for j in 4:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1), rng.randf_range(-1, 1)).normalized()
				var red := Color(0.8, 0.12, 0.15)
				b.blob(c + d * rad * 0.95, Vector3.ONE * 0.06, 0, 0.0, rng, red, red)
	return b.commit(plant_material)


func _make_mushroom(rng: RandomNumberGenerator, cap: Color) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	for i in rng.randi_range(2, 4):
		var p := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.2, 0.45)
		var rc := h * rng.randf_range(0.45, 0.7)
		var cream := Color(0.9, 0.86, 0.74)
		b.frustum(p, Vector3.UP, h, 0.05, 0.04, 5, cream, cream, rng)
		b.frustum(p + Vector3(0, h, 0), Vector3.UP, rc * 0.4, rc, rc * 0.7, 8, LFMeshBuilder.tint(cap, 0.8), cap, rng, 0.05, true)
		b.frustum(p + Vector3(0, h + rc * 0.4, 0), Vector3.UP, rc * 0.3, rc * 0.7, 0.0, 8, cap, LFMeshBuilder.tint(cap, 1.15), rng, 0.05)
	return b.commit(solid_material)


func _make_flowers(rng: RandomNumberGenerator, col: Color) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var green := Color(0.2, 0.42, 0.14)
	for i in rng.randi_range(6, 9):
		var p := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var h := rng.randf_range(0.3, 0.6)
		var lean := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
		b.blade(p, h, 0.04, lean, green, green)
		var head := p + Vector3(0, h, 0) + lean
		b.frustum(head - Vector3(0, 0.02, 0), Vector3.UP, 0.07, 0.09, 0.0, 5, col, LFMeshBuilder.tint(col, 1.1), rng, 0.1, true)
	return b.commit(plant_material)


func _make_grass(rng: RandomNumberGenerator, c_base: Color, c_tip: Color) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	for i in rng.randi_range(7, 10):
		var p := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var a := rng.randf() * TAU
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.25)
		b.blade(p, rng.randf_range(0.5, 0.9), 0.08, lean, c_base, c_tip)
	return b.commit(plant_material)


func _make_fern(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var dark := Color(0.12, 0.32, 0.12)
	var light := Color(0.30, 0.55, 0.20)
	var fronds := rng.randi_range(6, 8)
	for f in fronds:
		var a := TAU * float(f) / float(fronds) + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(0.8, 1.1)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_c := dark
		for s in range(1, 5):
			var t := float(s) / 4.0
			# arcs up then droops outward
			var centre := dir * (length * t) + Vector3(0, length * 0.55 * sin(t * PI * 0.85), 0)
			var wd := 0.17 * sin(minf(t * 1.1, 1.0) * PI * 0.9) + 0.02
			var l := centre - side * wd
			var rr := centre + side * wd
			var c := dark.lerp(light, t)
			b.tri(prev_l, prev_r, rr, prev_c, prev_c, c)
			b.tri(prev_l, rr, l, prev_c, c, c)
			prev_l = l
			prev_r = rr
			prev_c = c
	return b.commit(plant_material)


## Fallen trunk lying along +X, centred on x = 0, bottom at y = 0 (axis at y = radius).
## Variants: 0 = root plate at the butt, snapped top; 1 = both ends snapped; 2 = root plate + stubs.
func _make_log(variant: int, rng: RandomNumberGenerator) -> void:
	var b := LFMeshBuilder.new()
	var length := [rng.randf_range(4.0, 5.5), rng.randf_range(6.0, 7.2), rng.randf_range(7.5, 9.0)][variant] as float
	var r0 := rng.randf_range(0.42, 0.55) + 0.04 * variant
	var r1 := r0 * rng.randf_range(0.65, 0.8)
	var half := length * 0.5
	var pale := Color(0.62, 0.50, 0.34)
	var earth := Color(0.22, 0.16, 0.11)
	b.frustum(Vector3(-half, r0, 0), Vector3.RIGHT, length, r0, r1, 7, TRUNK_DARK, TRUNK, rng, 0.1)
	# snapped top end: a short jagged cone of pale wood
	b.frustum(Vector3(half - 0.02, r0 * 0.98, 0), Vector3.RIGHT, rng.randf_range(0.3, 0.5), r1, 0.0, 7, pale, pale, rng, 0.15)
	if variant == 1:
		b.frustum(Vector3(-half + 0.02, r0, 0), Vector3.LEFT, rng.randf_range(0.25, 0.45), r0 * 0.98, 0.0, 7, pale, pale, rng, 0.15)
	else:
		# root plate: an upright lump of earth and roots at the butt
		b.blob(Vector3(-half - 0.05, r0 + 0.1, 0), Vector3(0.28, r0 * 2.1, r0 * 2.0), 1, 0.25, rng, earth, TRUNK_DARK)
		for i in 4:
			var a := TAU * i / 4.0 + rng.randf_range(-0.4, 0.4)
			var d := Vector3(-1.0, sin(a) * 0.9, cos(a) * 0.9)
			b.frustum(Vector3(-half, r0 + sin(a) * r0 * 0.8, cos(a) * r0 * 0.8), d, rng.randf_range(0.5, 0.9),
					0.12, 0.03, 4, TRUNK_DARK, TRUNK, rng, 0.1)
	# moss patches on top
	var moss_lo := Color(0.16, 0.32, 0.12)
	var moss_hi := Color(0.32, 0.50, 0.20)
	for i in rng.randi_range(3, 5):
		var x := rng.randf_range(-half * 0.8, half * 0.8)
		var rr := lerpf(r0, r1, (x + half) / length)
		b.blob(Vector3(x, r0 + rr * 0.85, rng.randf_range(-0.12, 0.12)),
				Vector3(rng.randf_range(0.35, 0.8), 0.13, rr * 0.7), 1, 0.2, rng, moss_lo, moss_hi)
	# stub branches
	if variant != 1:
		for i in rng.randi_range(1, 3):
			var x := rng.randf_range(-half * 0.5, half * 0.7)
			var rr := lerpf(r0, r1, (x + half) / length)
			var d := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.9, 0.9)).normalized()
			b.frustum(Vector3(x, r0, 0) + d * rr * 0.7, d, rng.randf_range(0.4, 0.9), 0.1, 0.035, 5, TRUNK, TRUNK_DARK, rng, 0.1)
	_add(Kind.LOG, b.commit(solid_material), r0)
	log_length.append(length)


# --- props for other biomes (barrens, snow, marsh, desert, coast) ----------------------------------------------

## Dead tree: a bare leaning trunk with a snapped top and a few crooked limbs, each forking once.
## `charred`: black and ash grey (burnt land); otherwise bleached silver deadwood (dry plains, tundra).
func _make_dead(rng: RandomNumberGenerator, charred: bool) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var c0 := Color(0.08, 0.07, 0.06) if charred else Color(0.36, 0.33, 0.29)
	var c1 := Color(0.25, 0.23, 0.21) if charred else Color(0.64, 0.60, 0.54)
	var h := rng.randf_range(4.5, 7.0)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12)).normalized()
	b.frustum(Vector3.ZERO, lean, h, 0.34, 0.11, 6, c0, c1, rng, 0.1)
	b.frustum(Vector3.ZERO, Vector3.UP, 0.6, 0.55, 0.3, 6, c0, c0, rng, 0.15)  # root flare
	var perches := PackedVector3Array([lean * h])
	for i in rng.randi_range(3, 5):
		var y := rng.randf_range(h * 0.4, h * 0.9)
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), rng.randf_range(0.5, 1.3), sin(a)).normalized()
		var length := rng.randf_range(1.4, 2.6) * (1.2 - y / h * 0.5)
		var rr := lerpf(0.34, 0.11, y / h) * 0.6
		var base := lean * y
		b.frustum(base, dir, length, rr, rr * 0.35, 5, c0, c1, rng, 0.08)
		var tip := base + dir * length
		var a2 := a + rng.randf_range(-1.0, 1.0)
		var dir2 := Vector3(cos(a2), rng.randf_range(0.6, 1.6), sin(a2)).normalized()
		b.frustum(tip - dir * 0.05, dir2, length * rng.randf_range(0.4, 0.7), rr * 0.4, 0.015, 4, c1, c1, rng, 0.05)
		perches.append(tip)
	_pending_perches = perches
	return _commit_tree(Kind.DEAD, b, LFMeshBuilder.new())


## Weeping willow (marsh, riverside): a short thick leaning trunk, a low wide crown and curtains of long
## strands hanging from its rim to about head height.
func _make_willow(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var leaves := LFMeshBuilder.new()
	var lean := Vector3(rng.randf_range(-0.18, 0.18), 1.0, rng.randf_range(-0.18, 0.18)).normalized()
	var th := rng.randf_range(3.2, 4.2)
	b.frustum(Vector3.ZERO, lean, th, 0.6, 0.35, 7, TRUNK_DARK, TRUNK, rng, 0.1)
	b.frustum(Vector3.ZERO, Vector3.UP, 0.7, 0.95, 0.6, 7, TRUNK_DARK, TRUNK_DARK, rng, 0.12)  # root flare
	var top := lean * th
	for i in rng.randi_range(3, 4):
		var a := rng.randf() * TAU
		b.frustum(top - lean * 0.3, Vector3(cos(a), 0.8, sin(a)), rng.randf_range(1.6, 2.2), 0.25, 0.1, 5, TRUNK, TRUNK, rng, 0.05)
	var tint := _tree_tint(rng)
	var lo := Color(0.28, 0.42, 0.15) * tint
	var hi := Color(0.60, 0.70, 0.30) * tint
	var blobs: Array = []
	for i in rng.randi_range(4, 5):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.4, 1.8)
		var c := top + Vector3(cos(a) * d, rng.randf_range(1.0, 2.4), sin(a) * d)
		var rad := rng.randf_range(1.5, 2.1)
		var radii := Vector3(rad, rad * 0.75, rad)
		leaves.blob(c, radii, 1, 0.18, rng, lo, hi)
		blobs.append([c, radii])
		# Strands start inside the blob's lower rim, so their tops never show.
		for k in 9:
			var sa := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
			var start := c + Vector3(cos(sa) * radii.x * 0.85, -radii.y * 0.5, sin(sa) * radii.z * 0.85)
			var bottom := rng.randf_range(1.5, 2.6)
			var dir := Vector3(cos(sa) * 0.12, -1.0, sin(sa) * 0.12)
			leaves.frustum(start, dir, start.y - bottom, 0.24, 0.04, 3, lo.lerp(hi, 0.3), hi, rng, 0.1, false, sa)
	_pending_perches = _blob_perches(blobs)
	return _commit_tree(Kind.WILLOW, b, leaves)


## Palm (warm coasts, oases): a ringed trunk curving to one side, a crown of arched, drooping fronds with a
## V cross-section and saw-toothed edges, and a few coconuts.
func _make_palm(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var leaves := LFMeshBuilder.new()
	var h := rng.randf_range(6.0, 8.5)
	var a0 := rng.randf() * TAU
	var bend := Vector3(cos(a0), 0, sin(a0)) * rng.randf_range(0.6, 2.0)  # top's sideways offset
	var segs := 7
	var prev := Vector3.ZERO
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p1 := Vector3(0, h * t1, 0) + bend * t1 * t1
		b.frustum(prev, p1 - prev, (p1 - prev).length(), lerpf(0.32, 0.18, t0) * 1.1, lerpf(0.32, 0.18, t1), 6,
				Color(0.34, 0.27, 0.18), Color(0.50, 0.40, 0.27), rng, 0.04)
		prev = p1
	var top := prev
	b.frustum(top - Vector3(0, 0.1, 0), Vector3.UP, 0.4, 0.22, 0.1, 6, Color(0.30, 0.36, 0.16), Color(0.36, 0.42, 0.18), rng)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf()
		var nut := Color(0.36, 0.26, 0.14)
		b.blob(top + Vector3(cos(a) * 0.24, -0.22, sin(a) * 0.24), Vector3.ONE * 0.15, 0, 0.05, rng, nut, LFMeshBuilder.tint(nut, 1.3))
	var tint := _tree_tint(rng)
	var lo := Color(0.18, 0.38, 0.13) * tint
	var hi := Color(0.46, 0.62, 0.22) * tint
	var n := rng.randi_range(7, 9)
	var perches := PackedVector3Array()
	for f in n:
		var a := TAU * f / n + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(2.8, 3.8)
		var rise := rng.randf_range(0.5, 1.1)
		var prev_c := top
		var prev_l := top
		var prev_r := top
		var prev_col := lo
		for s in range(1, 9):
			var t := float(s) / 8.0
			var c := top + dir * (length * t) + Vector3(0, rise * sin(t * PI * 0.8) - 1.3 * t * t, 0)
			var w := 0.5 * sin(minf(t * 1.15, 1.0) * PI * 0.95) + 0.04
			var fwd := dir * length * 0.06  # leaflet tips point forward: saw-toothed outline
			var l := c - side * w + fwd - Vector3(0, w * 0.4, 0)
			var r := c + side * w + fwd - Vector3(0, w * 0.4, 0)
			var col := lo.lerp(hi, t)
			leaves.tri(prev_c, prev_l, l, prev_col, prev_col, col)
			leaves.tri(prev_c, l, c, prev_col, col, col)
			leaves.tri(prev_c, c, r, prev_col, col, col)
			leaves.tri(prev_c, r, prev_r, prev_col, col, prev_col)
			prev_c = c
			prev_l = l
			prev_r = r
			prev_col = col
			if s == 3:
				perches.append(c + Vector3(0, 0.05, 0))
	_pending_perches = perches
	return _commit_tree(Kind.PALM, b, leaves)


## Cactus (deserts). Variants: 0, 1 = tall column with up-turned arms; 2 = a cluster of squat barrels with
## flowers; 3 = prickly-pear pads with red fruit.
func _make_cactus(rng: RandomNumberGenerator, variant: int) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var lo := Color(0.16, 0.34, 0.17)
	var hi := Color(0.32, 0.52, 0.26)
	if variant <= 1:
		var h := rng.randf_range(3.2, 4.8)
		var r := rng.randf_range(0.28, 0.36)
		_cactus_column(b, rng, Vector3(0, -0.1, 0), h, r, lo, hi)
		var a := rng.randf() * TAU
		for i in rng.randi_range(1, 3):
			a += rng.randf_range(1.6, 2.6)
			var y := rng.randf_range(1.2, h * 0.6)
			var out := Vector3(cos(a), 0.25, sin(a)).normalized()
			var reach := r + rng.randf_range(0.35, 0.6)
			b.frustum(Vector3(0, y, 0), out, reach, r * 0.68, r * 0.68, 8, lo, hi, rng, 0.03)
			_cactus_column(b, rng, Vector3(0, y, 0) + out * reach - Vector3(0, r * 0.6, 0), rng.randf_range(0.8, 1.8), r * 0.7, lo, hi)
	elif variant == 2:
		for i in rng.randi_range(3, 5):
			var a := rng.randf() * TAU
			var d := 0.0 if i == 0 else rng.randf_range(0.4, 0.7)
			var r := rng.randf_range(0.26, 0.4)
			var p := Vector3(cos(a) * d, -0.05, sin(a) * d)
			var h := r * rng.randf_range(1.4, 2.4)
			_cactus_column(b, rng, p, h, r, lo, hi)
			var bloom := Color(0.95, 0.75, 0.2) if i % 2 == 0 else Color(0.92, 0.35, 0.45)
			b.blob(p + Vector3(0, h + r * 0.75, 0), Vector3(0.1, 0.06, 0.1), 0, 0.1, rng, bloom, bloom)
	else:
		var pads := [[Vector3(0, 0.38, 0), true], [Vector3(0.28, 0.9, 0.05), false], [Vector3(-0.3, 0.85, -0.05), false],
				[Vector3(0.1, 1.35, -0.25), true], [Vector3(0.55, 0.4, 0.3), false]]
		var fruit := Color(0.78, 0.16, 0.28)
		for pd: Array in pads:
			var flat_z: bool = pd[1]  # pads are flat discs, alternately facing z and x
			var size := Vector3(0.36, 0.42, 0.09) if flat_z else Vector3(0.09, 0.42, 0.36)
			size *= rng.randf_range(0.85, 1.1)
			b.blob(pd[0], size, 1, 0.08, rng, lo, hi)
			for k in 2:
				var up := Vector3(0, size.y * 0.9, 0) + (Vector3(size.x, 0, 0) if flat_z else Vector3(0, 0, size.z)) * (0.5 - k)
				b.blob(pd[0] + up, Vector3.ONE * 0.06, 0, 0.1, rng, fruit, fruit)
	return b.commit(solid_material)


## One ribbed cactus column from `base` up `h` m, with a rounded top.
func _cactus_column(b: LFMeshBuilder, rng: RandomNumberGenerator, base: Vector3, h: float, r: float, lo: Color, hi: Color) -> void:
	b.frustum(base, Vector3.UP, h, r, r * 0.92, 8, lo, hi, rng, 0.04)
	var top := base + Vector3(0, h, 0)
	b.frustum(top, Vector3.UP, r * 0.45, r * 0.92, r * 0.6, 8, hi, hi, rng, 0.03)
	b.frustum(top + Vector3(0, r * 0.45, 0), Vector3.UP, r * 0.3, r * 0.6, 0.0, 8, hi, LFMeshBuilder.tint(hi, 1.1), rng)


## Reeds (marsh, lake shallows): a clump of tall thin blades and a few cattails with brown heads.
func _make_reeds(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var base := Color(0.22, 0.36, 0.14)
	var tip := Color(0.62, 0.66, 0.32)
	for i in rng.randi_range(10, 14):
		var p := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var a := rng.randf() * TAU
		b.blade(p, rng.randf_range(1.1, 1.9), 0.07, Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.35), base, tip)
	var head := Color(0.34, 0.21, 0.11)
	for i in rng.randi_range(2, 4):
		var p := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(1.3, 1.8)
		var lean := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
		b.blade(p, h + 0.15, 0.03, lean, base, base)
		b.frustum(p + lean * 0.8 + Vector3(0, h - 0.3, 0), Vector3.UP + lean, 0.28, 0.05, 0.045, 5, head, LFMeshBuilder.tint(head, 1.2), rng, 0.05, true)
	return b.commit(plant_material)


## Dry scrub (desert, barrens, dry plains): a tangle of thin forking twigs. `sage`: grey-green tufts on
## the twig ends (sagebrush); otherwise bare and dead.
func _make_dry_bush(rng: RandomNumberGenerator, sage: bool) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var c0 := Color(0.30, 0.24, 0.17)
	var c1 := Color(0.50, 0.42, 0.31)
	var tuft_lo := Color(0.26, 0.34, 0.22)
	var tuft_hi := Color(0.46, 0.53, 0.36)
	for i in rng.randi_range(11, 15):
		var dir := Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(1.0, 1.6), rng.randf_range(-0.8, 0.8)).normalized()
		var length := rng.randf_range(0.6, 1.0)
		b.frustum(Vector3.ZERO, dir, length, 0.035, 0.01, 3, c0, c1, rng)
		var fork := dir * length * 0.6
		var dir2 := (dir + Vector3(rng.randf_range(-0.6, 0.6), 0.2, rng.randf_range(-0.6, 0.6))).normalized()
		b.frustum(fork, dir2, length * 0.5, 0.02, 0.006, 3, c1, c1, rng)
		if sage:
			b.blob(dir * length, Vector3(0.17, 0.13, 0.17) * rng.randf_range(0.8, 1.3), 0, 0.2, rng, tuft_lo, tuft_hi)
			b.blob(fork + dir2 * length * 0.5, Vector3(0.12, 0.1, 0.12) * rng.randf_range(0.8, 1.3), 0, 0.2, rng, tuft_lo, tuft_hi)
	return b.commit(plant_material)


## Crystal cluster (glass deserts, caverns, magic places): hexagonal prisms with pointed tips, the biggest
## upright and the rest leaning out from a rocky base.
func _make_crystal(rng: RandomNumberGenerator, col: Color) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	b.blob(Vector3(0, 0.05, 0), Vector3(0.7, 0.3, 0.7), 1, 0.25, rng, Color(0.22, 0.21, 0.22), Color(0.38, 0.36, 0.36))
	var dark := LFMeshBuilder.tint(col, 0.55)
	var light := col.lerp(Color.WHITE, 0.45)
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var tilt := 0.08 if i == 0 else rng.randf_range(0.3, 0.8)
		var dir := Vector3(cos(a) * tilt, 1.0, sin(a) * tilt).normalized()
		var h := rng.randf_range(1.6, 2.4) if i == 0 else rng.randf_range(0.5, 1.4)
		var r := h * rng.randf_range(0.14, 0.2)
		var d := 0.0 if i == 0 else rng.randf_range(0.1, 0.4)
		var base := Vector3(cos(a) * d, -0.15, sin(a) * d)
		var twist := rng.randf() * TAU
		b.frustum(base, dir, h, r, r, 6, dark, col, rng, 0.0, false, twist)
		b.frustum(base + dir * h, dir, r * 1.6, r, 0.0, 6, col, light, rng, 0.0, false, twist)
	return b.commit(crystal_material)


## A slab of layered rock for a cliff band: an irregular 5-8 sided block, 6-10 m along the band (x), 3-5 m deep
## (z), 3-6 m tall from y = 0 (LFPropPlacer stretches it to its rock layer), in two or three tiers that step in a little (the layers), a bevelled flat top. Its
## face looks along +z (LFPropPlacer turns that down the slope). Adds its hull to cliff_hulls.
func _make_cliff(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := LFMeshBuilder.new()
	var n := rng.randi_range(5, 8)
	var wide := rng.randf_range(3.2, 4.8)
	var deep := rng.randf_range(1.6, 2.4)
	var tall := rng.randf_range(3.0, 6.0)
	var ring := PackedVector2Array()
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * (i + rng.randf_range(-0.2, 0.2)) / n
		var r := rng.randf_range(0.85, 1.05)
		ring.append(Vector2(cos(a) * wide * r, sin(a) * deep * r))
	var tiers := rng.randi_range(2, 3)
	var ys := PackedFloat32Array([0.0])
	for t in tiers:
		ys.append(tall * (t + 1) / tiers + (rng.randf_range(-0.12, 0.12) * tall / tiers if t < tiers - 1 else 0.0))
	var inside := Vector3(0.0, tall * 0.5, 0.0)
	var scale := 1.0
	var shift := Vector2.ZERO
	var top_ring := PackedVector3Array()
	for t in tiers:
		var shade := rng.randf_range(0.85, 1.12)
		var warm := rng.randf_range(-0.03, 0.03)
		var col := LFMeshBuilder.tint(rock_color, shade) + Color(warm, warm * 0.5, -warm, 0.0)
		var low := LFMeshBuilder.tint(col, 0.82)
		var s1 := scale * rng.randf_range(0.9, 0.97)   # each tier tapers, the next steps in from it
		var lo := PackedVector3Array()
		var hi := PackedVector3Array()
		var top := ys[t + 1] - (0.35 if t == tiers - 1 else 0.0)   # the top tier's bevel above
		for p in ring:
			lo.append(Vector3(p.x * scale + shift.x, ys[t], p.y * scale + shift.y))
			hi.append(Vector3(p.x * s1 + shift.x, top, p.y * s1 + shift.y))
		for i in n:
			var k := (i + 1) % n
			b.quad_out(lo[i], lo[k], hi[k], hi[i], low, low, col, col, inside)
		var cap := LFMeshBuilder.tint(col, 1.12)
		if t == tiers - 1:   # bevel up to an inset flat top
			var ins := PackedVector3Array()
			for p in hi:
				ins.append(Vector3(p.x * 0.8, ys[t + 1], p.z * 0.8))
			for i in n:
				var k := (i + 1) % n
				b.quad_out(hi[i], hi[k], ins[k], ins[i], col, col, cap, cap, inside)
			hi = ins
			top_ring = hi
		var c := Vector3(shift.x, hi[0].y, shift.y)
		for i in n:
			b.tri_out(c, hi[i], hi[(i + 1) % n], cap, cap, cap, c - Vector3(0, 1, 0))
		scale = s1 * rng.randf_range(0.93, 0.99)
		shift += Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.2, 0.1))
	# the hull: the bottom ring up to the flat top (convex enough to walk on; the tiers' steps are small)
	var hull := PackedVector3Array()
	var bot := PackedVector3Array()
	for p in ring:
		bot.append(Vector3(p.x, 0.0, p.y))
	var cb := Vector3(0, 0, 0)
	var ct := Vector3(0, ys[tiers], 0)
	for i in n:
		var k := (i + 1) % n
		hull.append_array(PackedVector3Array([bot[i], bot[k], top_ring[k], bot[i], top_ring[k], top_ring[i],
				ct, top_ring[i], top_ring[k], cb, bot[k], bot[i]]))
	cliff_hulls.append(hull)
	return b.commit(solid_material)
