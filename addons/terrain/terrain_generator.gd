class_name LFTerrainGenerator
extends RefCounted
## Pure world-shape logic: height, biomes, ground colours. No nodes in here.
## Everything is a deterministic function of (world_seed, x, z).

## The land's version: goes up whenever the same seed and params give different land (a fingerprint change in
## tests/fingerprints.json). Baked maps record it (tiles.json), so tiles from an older version aren't grown onto.
const LAND_VERSION := 2
const CHUNK_SIZE := 32.0
const CELLS := 16  # quads per chunk side
const STEP := CHUNK_SIZE / CELLS  # 2 m vertex spacing - coarse on purpose: that's the low-poly look
const VERTS := CELLS + 1
const WATER_LEVEL := 0.0

# --- rivers (tuning) ---------------------------------------------------------
# The counted rivers (river_count) are placed lines (_place_rivers). A noise ("river mask") varies each one
# from creek to full river along its course.
const RIVER_WARP_AMP := 110.0     # metres of sideways meander
const RIVER_MASK_FREQ := 0.00045  # lower = bigger regions of creeks (or of full rivers)
const RIVER_MASK_ON := 0.0  # mask noise above this is full river; raise it for more creeks
const RIVER_BED := -2.2  # channel bed height (m)
const RIVER_CORE := 2.5  # flat-bed half width (m)
const RIVER_BANK_END := 13.0  # distance where the bank meets the land (m); gentle enough to stay grass, not rock
const RIVER_BANK_H := 2.0  # land height just beside the bank (m); above the 1.2 m sand line so banks are grassy
const LAKE_SIDE := 80.0  # m past a lake's shore its side may reach (at least; or 55 % of its radius)
const VALLEY_WALL := 1.5  # steepest a river valley's side gets (rise per m), out past its gentle banks
const RIVER_VALLEY := 90.0  # half width of the gentle valley blend (m)
const RIVER_WATER_EDGE := 8.0  # approx distance from line to the waterline (m)
const RIVER_NEAR := 30.0  # river_factor fades to 0 this far from the water (m)
const RIVER_CELL := 128.0   # grid cell (m) of the counted rivers' segment index
const RIVER_STEP := 16.0   # spacing (m) of a counted river's points
const PASS_CELL := 64.0   # grid cell (m) of the rim pass segment index
const HEIGHT_OUT := 12.0  # climate score a biome loses below its min height (LFBiomeDef.only_above): out of the running
const HEIGHT_IN := 2.0  # and gains above it, over a band (_bup): the heights are its, the climate only ragging the edge
const ESTUARY_RUN := 56.0  # m before the coast where a river into the sea is down at the sea's level
const ESTUARY_RISE := 0.05  # m per m: how fast its level may rise upstream of that
const LAKE_RAGGED := 0.53   # how far (in radii) a counted lake's ragged shore can wander from its circle
const RAISED_CELL := 64.0   # grid cell (m) of _raised_cells
const FALL_STEEP := 1.5   # m a river's water drops over one RIVER_STEP for that stretch to fall instead (waterfalls)
const FALL_MIN := 3.0   # m a steep stretch drops in all for its water to fall: less stays rapids
const FALL_MAX := 10.0   # m at most in one fall: a taller drop is a cascade of falls
const FALL_LIP := 1.0   # m over which the water falls (an extra river point after the lip)
const FALL_STRENGTH := 0.08   # river strength (a creek fading in at its spring) a fall needs: a trickle runs down
const RIVER_JOIN_ROUND := 4.0   # m of smooth min where two rivers' channels meet (rounded banks, no sharp V)
const HOLD_MARGIN := 6.0   # m the banks of water above the sea stay full height past its edge (> a cell's diagonal)

## Slots of the default biome list (LFBiomeDef.defaults()). Custom lists: look biomes up by name instead.
enum Biome { MEADOW, PINE, BIRCH, OLD_GROWTH }
const BIOME_NAMES: Array[String] = ["Meadow", "Pine Forest", "Birch Woods", "Old Growth"]

const GROUND_COLORS: Array[Color] = [
	Color(0.50, 0.70, 0.26),  # meadow: bright grass
	Color(0.20, 0.38, 0.19),  # pine: dark needles/grass
	Color(0.58, 0.74, 0.32),  # birch: light grass
	Color(0.16, 0.30, 0.15),  # old growth: dark moss
]
const SAND := Color(0.76, 0.70, 0.48)
const MUD := Color(0.32, 0.30, 0.22)
const ROCK := Color(0.46, 0.45, 0.43)
const SNOW := Color(0.92, 0.94, 0.96)
const SCREE := Color(0.58, 0.55, 0.50)

## The land's settings (island, height, rivers, ground colours). Set before setup(); null = the defaults.
var params: LFMapParams
var world_seed: int = 0
var spawn_xz := Vector2.ZERO
var spawn_height := 3.0
## Centre of the starting region (start_radius); chosen so every biome is in reach.
var region_center := Vector2.ZERO
## Prop density multipliers (from params at setup: prop_density x tree_density / rock_density /
## ground_cover_density); LFPropPlacer scales its chances by them.
var tree_density := 1.0
var rock_density := 1.0
var cover_density := 1.0
## Radius (m) of the starting region the spawn search scores (from params.start_radius at setup).
var start_radius := START_RADIUS
## Sites planned from the seed before any chunk is built (_plan_sites / add_site), so the land can be
## shaped for them: {"id": String, "plan": the site's plan, "spot": [position, yaw], "radius": metres kept clear}.
var sites: Array[Dictionary] = []
## Height stamps, applied in order at the end of base_height: objects with `height(x, z, h) -> float`
## that reshape the land under a site (terraces under a town, say). A stamp may also have
## `shade(x, z, h, ny, colour) -> Color` to colour its ground (LFCliffBand does).
var stamps: Array = []
var roads := LFTerrainRoads.new()
## Replays the slow site and road searches of an earlier planning of this world (null = search them all). Set it
## before setup(); LFWorld does when its plan_cache_dir is set. See LFPlanCache.
var plan_cache: LFPlanCache
## Bare ground (lanes, plazas, floors, roads): LFPropPlacer keeps grass and flowers off it.
var ground_mask := LFGroundMask.new()

## Default start_radius (m): the spawn search picks a centre with every biome within it.
const START_RADIUS := 1400.0
const REGION_TRIES := 40
## The island: full land out to about ISLAND_R from region_center (seeded lobes and noise bend the
## coastline), a beach band, then sea floor at SEA_FLOOR for ever. Never closer than ISLAND_MIN_R, so
## the start region (START_RADIUS) is untouched.
const ISLAND_R := 3200.0
const ISLAND_LOBES: Array[int] = [2, 3, 5]
const ISLAND_LOBE_AMP: Array[float] = [0.10, 0.06, 0.04]  # share of ISLAND_R
const COAST_NOISE_AMP := 160.0   # metres of ragged coastline
const COAST_BAND := 220.0        # land starts dropping this far inside the coastline
const COAST_SHELF := 260.0       # sea floor reached this far outside the coastline
const SEA_FLOOR := -20.0
const ISLAND_MIN_R := ISLAND_R * 0.8 - COAST_NOISE_AMP - COAST_BAND   # nothing changes inside this
const MOUNTAIN_CHILL := 1.6   # how much colder (climate noise units) a mountain's peak is than its foot
const REGION_MIN_SHARE := 0.08  # each biome must cover at least this share of the region's land
const STRATA_LAYERS := 64   # rock layers in one repeat of the stack (even: soft, hard, soft, hard ...)
const CLIFF_MIN_RISE := 8.0   # cliff bands only where the mountains add more than this (m), full at twice it
const CLIFF_MAX_SLOPE := 2.5   # steepest riser (m per m) the 2 m grid still draws cleanly; rock meshes give the wall
const CLIFF_SHELF := 0.12   # share of a cliff layer's rise left for the shelf on top of its riser
const CLIFF_SHELF_W := 3.0   # at least this wide (m) where the slope allows
const TALUS_FOOT := 0.4   # share of a talus apron (from its foot up) that curves out into the shelf below
const CLIFF_WARP := 4.0   # metres the layer boundaries wander (low-frequency noise)
const CLIFF_DETAIL_DAMP := 0.8   # share of the small bumps taken off steep ground: bigger, flatter facets
const CLIFF_REF_SLOPE := 1.2   # the slope a band's profile is laid out for (steeper land: steeper risers too)

var _hills: FastNoiseLite
var _ridge: FastNoiseLite
var _ridge_mask: FastNoiseLite
var _mountain: FastNoiseLite
var _mountain_mask: FastNoiseLite
var _detail: FastNoiseLite
var _temp: FastNoiseLite
var _moist: FastNoiseLite
var _clearing: FastNoiseLite
var _flowers: FastNoiseLite
var _stand: FastNoiseLite
var _river_mask: FastNoiseLite
var _coast: FastNoiseLite
var _cliff_warp: FastNoiseLite   # wanders the rock layer boundaries
var _cliff_patch: FastNoiseLite   # where cliff bands show (cliffs)
var _strata_base := PackedFloat32Array()   # each layer's base in layer space (STRATA_LAYERS + 1: the last = the repeat)
var _strata_hard := PackedByteArray()   # 1: a hard (cliff) layer
var _strata_period := 1.0
var _dip := Vector2.ZERO   # the layers' tilt: cliff_dip m per m along a seeded direction
var _placing_water := false   # only in setup (one thread): heights leave the cliff bands out
var _coast_inner := -INF   # see _apply_params
var _island := false   ## off while _find_spawn picks region_center (the island is centred on it)
var _island_phases := PackedFloat32Array()
var _rim := false   # the mountain rim (boundary MOUNTAINS): off, like _island, until region_center is known
var _pass_seg := PackedVector2Array()   # rim_pass: the segments (a, b pairs) of the rivers leaving through the rim
var _pass_cells := {}   # Vector2i (PASS_CELL grid) -> PackedInt32Array: the _pass_seg pair starts within reach of it
var _rim_rect := Rect2()   # the land inside the rim
# params copied to members at setup (read on every height sample: member reads are the cheapest)
var _p: LFMapParams
var _island_on := true
var _island_r := ISLAND_R
var _island_min_r := ISLAND_MIN_R
var _lobes: Array[int] = []
var _lobe_amp: Array[float] = []
var _coast_noise := COAST_NOISE_AMP
var _coast_band := COAST_BAND
var _coast_shelf := COAST_SHELF
var _sea_floor := SEA_FLOOR
var _base_h := 3.0
var _hills_h := 10.0
var _ridge_h := 18.0
var _relief_v := 0.0   # params.relief_variation
var _relief: FastNoiseLite
var _mountain_h := 0.0
var _mountain_at := 0.0   # mask noise where the ranges start (from mountain_cover)
var _peaks := PackedVector4Array()   # counted mountains: (x, z, radius, height share); placed after the spawn
var _lakes := PackedVector4Array()   # counted lakes: (x, z, radius, water level); placed after the mountains
var _fill_hollows := false   # natural_lakes off: hollows below the water are raised to dry ground
var _river_lines := false   # river_count > 0: there are rivers (the placed lines below)
var _river_pts := PackedVector4Array()   # every counted river's points: (x, z, strength, leg index)
var _river_lvl := PackedFloat32Array()   # the water surface at each of _river_pts (falls along a leg)
var _raised := false   # some counted lake or river lies above WATER_LEVEL (water_level_at is not flat)
var _raised_cells := {}   # Vector2i cell (RAISED_CELL m) -> true where water above the sea or its banks reach
var _raised_ready := false   # _raised_cells is filled (after placement): elsewhere there's nothing to look up
# The counted rivers' segment index: a flat grid of RIVER_CELL m cells from _cell_lo, _cell_w x _cell_h; cell i
# lists the segment starts (in _river_pts) near it in _cell_segs[_cell_at[i] .. _cell_at[i + 1]].
var _cell_lo := Vector2i.ZERO
var _cell_w := 0
var _cell_h := 0
var _cell_at := PackedInt32Array([0])
var _cell_segs := PackedInt32Array()
var _seg_a := PackedVector2Array()   # per segment k: its start (x, z), its run to point k + 1, that run's
var _seg_ab := PackedVector2Array()  # squared length (at least 1e-6)
var _seg_l2 := PackedFloat64Array()
var _rv_x := NAN   # the last point _river_info3 was worked out for, and its result (one generator per thread)
var _rv_z := NAN
var _rv := Vector3.ZERO
var _rim_h := 0.0   # rim_height when the boundary is MOUNTAINS
var _rim_w := 300.0
var _cold := false   # mountains or a rim: biomes get colder up them
var _snow_on := true   # height snow line; with mountains only when a snow biome is on
var _detail_h := 1.2
var _river_mask_on := RIVER_MASK_ON
var _river_warp_amp := RIVER_WARP_AMP
var _river_bed := RIVER_BED
var _river_core := RIVER_CORE
var _river_bank_end := RIVER_BANK_END
var _river_bank_h := RIVER_BANK_H
var _river_valley := RIVER_VALLEY
var _river_water_edge := RIVER_WATER_EDGE
var _river_near := RIVER_NEAR
var _river_bank_slope := 0.35
var _highland := 24.0
var _rock_mid := 21.0
var _line_up := 0.0   # the rock and snow lines move up by half how high the mountains rise (_fit_lines_to_mountains)
var _biomes: Array[LFBiomeDef] = []
var _bheat := PackedFloat64Array()   # per biome climate score coefficients (LFBiomeDef.score, inlined)
var _bwet := PackedFloat64Array()
var _bcommon := PackedFloat64Array()
var _bcustom := false   # a biome subclass scores itself: call LFBiomeDef.score
var _looks := false   # some biome has a look setting (rock_tint, beach, snow, snow_cover): ground_shade weighs them
var _dip_on := false   # some biome sinks the ground (ground_dip)
var _brock := PackedColorArray()   # per biome look settings (LFBiomeDef.rock_tint, beach, snow, snow_cover, ground_dip)
var _bbeach := PackedFloat32Array()
var _bsnow := PackedFloat32Array()
var _bcover := PackedFloat32Array()
var _bdip := PackedFloat32Array()
var _barea := false   # a subclass overrides biome_allowed: ask it per biome and sample
var _rg: LFBiomeRegions = null   # params.biome_regions (null: none)
var _rg_fac: Array[PackedFloat32Array] = []   # its per biome factors: each wedge, then the central disc
var _rg_on := false   # on once setup knows region_center (the wedges turn round it); copied to worker clones
var _snow_line_h := -INF   # where the high biomes (only_above) start: snow_line of the way up the land (_fit_snow_line)
var _snow_top := -INF   # the top of the land it was measured against
var _falls: Array[Dictionary] = []   # waterfalls(), read off the rivers once they are placed
var _bmin := PackedFloat32Array()   # each biome's min height (only_above; -INF: none), empty when no biome has one
var _bfade := PackedFloat32Array()
var _bup := PackedFloat32Array()   # metres above its min height over which a high biome takes the ground over
var _blend := 5.0
var _f32 := PackedFloat32Array([0.0])   # rounds a value to 32 bits (biome weights match the old Vector4 maths)
var _snow_takes_over := false   # params.snow_takes_over
var _snow_lo := INF   # the height the high biomes (only_above) start at, and the band over which they take over
var _snow_band := 1.0
var _landforms: Array[LFHeightLayer] = []   # this generator's own prepared copies of params.landforms
var _landform_biomes: Array[PackedInt32Array] = []   # per landform, the biome indices of its biome mask
var _plant_p: Array[PackedFloat32Array] = []   # per biome, its plant rules' chances in 32 bits (as the old tables)


func setup(seed_value: int) -> void:
	_apply_params()
	_make_noises(seed_value)
	_find_spawn()
	_rg_on = _rg != null
	_enable_island()
	_enable_rim()
	_place_mountains()
	_fit_lines_to_mountains()
	# the water is placed on the land without its cliff bands: the cliff params never move a lake or a river
	_placing_water = true
	_place_lakes()
	_place_rivers()
	_placing_water = false
	_fit_snow_line()
	_plan_sites()
	if plan_cache != null:
		plan_cache.finish()
	_mask_roads()


## Copies `params` (or the defaults) into the members the height maths reads.
func _apply_params() -> void:
	if params == null:
		params = LFMapParams.new()
	_p = params
	start_radius = _p.start_radius
	_island_on = _p.boundary == LFMapParams.Boundary.ISLAND
	_rim_h = _p.rim_height if _p.boundary == LFMapParams.Boundary.MOUNTAINS else 0.0
	_rim_w = _p.rim_width
	_island_r = _p.island_radius
	_lobes = _p.island_lobes.duplicate()
	_lobe_amp = _p.island_lobe_amp.duplicate()
	_coast_noise = _p.coast_noise
	_coast_band = _p.coast_band
	_coast_shelf = _p.coast_shelf
	_sea_floor = _p.sea_floor
	var dip := 1.0
	for a: float in _lobe_amp:
		dip -= a
	_island_min_r = _island_r * dip - _coast_noise - _coast_band   # nothing changes inside this
	# Surely inland of -coast_band (with every lobe and twice the coast noise's range against it, and a metre to
	# spare): closer to the centre than this, _height needs no coast_offset at all.
	var dip_abs := 1.0
	for a: float in _lobe_amp:
		dip_abs -= absf(a)
	_coast_inner = _island_r * dip_abs - 2.0 * absf(_coast_noise) - _coast_band - 1.0
	_base_h = _p.base_height
	_hills_h = _p.hills_height
	_ridge_h = _p.ridge_height
	_relief_v = _p.relief_variation
	_mountain_h = _p.mountain_height
	_mountain_at = lerpf(0.45, -0.45, _p.mountain_cover)
	_detail_h = _p.detail_height
	_river_lines = _p.river_count > 0
	_fill_hollows = not _p.natural_lakes
	_river_mask_on = _p.river_mask_on
	_river_warp_amp = _p.river_warp_amp
	_river_bed = _p.river_bed
	_river_core = _p.river_core
	_river_bank_end = _p.river_bank_end
	_river_bank_h = _p.river_bank_h
	_river_valley = _p.river_valley
	_rv_x = NAN
	_river_water_edge = _p.river_water_edge
	_river_near = _p.river_near
	_river_bank_slope = _p.river_bank_slope
	_highland = _p.highland_height
	tree_density = _p.prop_density * _p.tree_density
	rock_density = _p.prop_density * _p.rock_density
	cover_density = _p.prop_density * _p.ground_cover_density
	_cold = _mountain_h > 0.0 or _rim_h > 0.0
	_line_up = maxf(_mountain_h, _rim_h) * 0.5
	_rock_mid = (_p.rock_height_start + _p.rock_height_full) * 0.5 + _line_up
	_biomes = []
	for b: LFBiomeDef in _p.biomes:
		if b != null and b.enabled:
			_biomes.append(b)
	if _biomes.is_empty():
		if not _p.biomes.is_empty():
			push_warning("LFMapParams: every biome is disabled; using the defaults")
		_biomes = LFBiomeDef.defaults()
	_blend = _p.biome_blend
	_snow_takes_over = _p.snow_takes_over
	_bheat.resize(_biomes.size())
	_bwet.resize(_biomes.size())
	_bcommon.resize(_biomes.size())
	_bcustom = false
	_barea = _overrides(&"biome_allowed")
	_rg = _p.biome_regions
	_rg_on = false
	_rg_fac.clear()
	if _rg != null:
		var names := PackedStringArray()
		for b in _biomes:
			names.append(b.name)
		_rg_fac = _rg.compile(names)
	_plant_p.clear()
	_looks = false
	_dip_on = false
	_brock.clear()
	_bbeach.clear()
	_bsnow.clear()
	_bcover.clear()
	_bdip.clear()
	for i in _biomes.size():
		var b := _biomes[i]
		_brock.append(b.rock_tint)
		_bbeach.append(1.0 if b.beach else 0.0)
		_bsnow.append(1.0 if b.snow else 0.0)
		_bcover.append(b.snow_cover)
		_bdip.append(b.ground_dip)
		if b.rock_tint != Color.WHITE or not b.beach or not b.snow or b.snow_cover > 0.0:
			_looks = true
		if b.ground_dip != 0.0:
			_dip_on = true
		_bheat[i] = b.likes_heat
		_bwet[i] = b.likes_wet
		_bcommon[i] = b.commonness
		if b.get_script() != LFBiomeDef:
			_bcustom = true
		var pp := PackedFloat32Array()
		for r: LFPropRule in b.plants:
			pp.append(r.chance)
		_plant_p.append(pp)
	_snow_on = not _cold or _biomes.any(func(b: LFBiomeDef) -> bool: return b.surface == &"snow")
	_index_biome_heights()


## Each biome's min height for biome_weights: with LFBiomeDef.only_above, the snow line or its own
## min_height, whichever is higher.
func _index_biome_heights() -> void:
	_bmin.clear()
	_bfade.clear()
	_bup.clear()
	if _biomes.size() > 1 and _biomes.any(func(b: LFBiomeDef) -> bool: return b.only_above):
		for b in _biomes:   # one biome alone covers the map whatever its height
			var lo := maxf(b.min_height, _snow_line_h)
			_bmin.append(lo if b.only_above else -INF)
			_bfade.append(maxf(b.height_fade, 0.01))
			_bup.append(maxf(b.height_fade * 2.0, (_snow_top - lo) * 0.25) + 0.01)
		_snow_lo = INF
		for i in _bmin.size():   # where the high biomes begin (the lowest of them), and how far it takes to be theirs
			if _bmin[i] > -INF and _bmin[i] < _snow_lo:
				_snow_lo = _bmin[i]
				_snow_band = _bup[i]


## The snow line: params.snow_line of the way from the lowlands (base height) to the top of the land as it
## really stands, with the lakes and rivers in it (a mountain on a small island is lower than mountain_height),
## so snow comes wherever the land is high, at any mountain height.
func _fit_snow_line() -> void:
	if _biomes.size() < 2 or not _biomes.any(func(b: LFBiomeDef) -> bool: return b.only_above):
		return
	var top := _base_h + (_hills_h + _ridge_h * 0.5) * (1.0 + _relief_v) + _rim_h
	if not _peaks.is_empty():
		for pk in _peaks:   # round each summit (shelves and lakes can put the top off its centre)
			for j in 9:
				for i in 9:
					var q := Vector2(pk.x, pk.y) + Vector2(i - 4, j - 4) * pk.z * 0.125
					top = maxf(top, biome_height(q.x, q.y))
	elif _mountain_h > 0.0:
		var area := _p.mountain_area
		for j in 33:
			for i in 33:
				var q := region_center + Vector2(i - 16, j - 16) * area / 16.0
				top = maxf(top, biome_height(q.x, q.y))
	_snow_top = top
	_snow_line_h = lerpf(_base_h, top, clampf(_p.snow_line, 0.0, 1.0))
	_index_biome_heights()


## The rock line and snow colour move up by half how high the mountains really rise,
## not by half mountain_height: on a small map or island the peaks shrink and ease down to the coast, and
## lines set by the full height would leave them with no snow at all. A mountain rim does reach its height.
func _fit_lines_to_mountains() -> void:
	if _mountain_h <= 0.0:
		return
	var top := -INF
	if not _peaks.is_empty():
		for pk in _peaks:   # round each summit (shelves can put the top a little off its centre)
			for k in 9:
				var q := Vector2(pk.x, pk.y) + (Vector2.from_angle(TAU * k / 8.0) * pk.z * 0.15 if k > 0 else Vector2.ZERO)
				top = maxf(top, biome_height(q.x, q.y))
	else:
		var area := _p.mountain_area
		for j in 33:
			for i in 33:
				var q := region_center + Vector2(i - 16, j - 16) * area / 16.0
				top = maxf(top, biome_height(q.x, q.y))
	var rise := clampf(top - (_base_h + _hills_h), 0.0, _mountain_h)
	_line_up = maxf(rise, _rim_h) * 0.5
	_rock_mid = (_p.rock_height_start + _p.rock_height_full) * 0.5 + _line_up


func _enable_island() -> void:
	if not _island_on:
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash(world_seed) ^ 0x151a
	_island_phases.resize(_lobes.size())
	for i in _lobes.size():
		_island_phases[i] = r.randf() * TAU
	_island = true


## The rim's rectangle: boundary_size round region_center, snapped to 128 m as the Map Baker snaps the map.
func _enable_rim() -> void:
	if _rim_h <= 0.0:
		return
	var size := _p.boundary_size
	_rim_rect = Rect2(((region_center - size * 0.5) / 128.0).floor() * 128.0, size)
	_rim = true


## How far up the mountain rim (x, z) is: 0 inside the map, 1 at its edge and beyond (boundary MOUNTAINS).
func rim_share(x: float, z: float) -> float:
	if not _rim:
		return 0.0
	var o := _rim_rect.position
	var e := _rim_rect.end
	var d := minf(minf(x - o.x, e.x - x), minf(z - o.y, e.y - z))   # metres in from the nearest edge
	d += _coast.get_noise_2d(x, z) * _rim_w * 0.35   # a ragged foot, not a straight wall
	if d >= _rim_w:
		return 0.0
	var u := 1.0 - maxf(d, 0.0) / _rim_w
	var s := u * u * (3.0 - 2.0 * u) * (0.6 + 0.4 * (1.0 - absf(_mountain.get_noise_2d(x, z))))   # ridged crests
	if not _pass_seg.is_empty():
		s *= _pass_open(x, z)
	return s


## rim_pass: how much of the rim stands at (x, z), 0 on a leaving river's pass floor to 1 past its sides.
func _pass_open(x: float, z: float) -> float:
	var cell: PackedInt32Array = _pass_cells.get(Vector2i(floori(x / PASS_CELL), floori(z / PASS_CELL)), PackedInt32Array())
	if cell.is_empty():
		return 1.0
	var p := Vector2(x, z)
	var best := INF
	for i in cell:
		var a := _pass_seg[i]
		var ab := _pass_seg[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_squared_to(a + ab * t))
	var half := _p.rim_pass_width * 0.5
	return smoothstep(half * 0.2, half, sqrt(best))


## rim_pass: forgets the pass segments from pair start `n` on (and their index entries).
func _drop_pass(n: int) -> void:
	_pass_seg.resize(n)
	for key: Vector2i in _pass_cells.keys():
		var list: PackedInt32Array = _pass_cells[key]
		var keep := PackedInt32Array()
		for i in list:
			if i < n:
				keep.append(i)
		if keep.is_empty():
			_pass_cells.erase(key)
		else:
			_pass_cells[key] = keep


## rim_pass: the part of the map well inside the rim's ragged foot, where a river needs no pass. Empty on a map too
## small to have one (a Rect2 shrunk past zero has a negative size, which Godot reports as an error on every use).
func _pass_inner() -> Rect2:
	var margin := _rim_w * 1.4 + _p.rim_pass_width
	if _rim_rect.size.x <= margin * 2.0 or _rim_rect.size.y <= margin * 2.0:
		return Rect2()
	return _rim_rect.grow(-margin)


## rim_pass: adds the stretch of a leaving river's points that crosses the rim (and runs on past it) to the pass.
func _add_pass(pts: PackedVector4Array) -> void:
	var inner := _pass_inner()
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].y)
		var b := Vector2(pts[k + 1].x, pts[k + 1].y)
		if not (inner.has_point(a) and inner.has_point(b)):
			# indexed in every cell within the pass's half width of it (past that the rim stands whole)
			var box := Rect2(a, Vector2.ZERO).expand(b).grow(_p.rim_pass_width * 0.5)
			for cx in range(floori(box.position.x / PASS_CELL), floori(box.end.x / PASS_CELL) + 1):
				for cz in range(floori(box.position.y / PASS_CELL), floori(box.end.y / PASS_CELL) + 1):
					var key := Vector2i(cx, cz)
					var list: PackedInt32Array = _pass_cells.get(key, PackedInt32Array())
					list.append(_pass_seg.size())
					_pass_cells[key] = list
			_pass_seg.append(a)
			_pass_seg.append(b)


## Distance from region_center to the coastline (the waterline, roughly) at this point's angle.
func coast_radius(x: float, z: float) -> float:
	var o := Vector2(x, z) - region_center
	var a := o.angle()
	var k := 1.0
	for i in _lobes.size():
		k += _lobe_amp[i] * sin(float(_lobes[i]) * a + _island_phases[i])
	return _island_r * k + _coast.get_noise_2d(x, z) * _coast_noise


## Metres past the coastline (negative = inland). Continuous everywhere: no shortcut inside the island's safe
## core (one gave a different number there, and the mountains' fade stood as a wall at its edge).
func coast_offset(x: float, z: float) -> float:
	if not _island:
		return -INF
	return Vector2(x, z).distance_to(region_center) - coast_radius(x, z)


## Highest the land may be at `x` metres past the coastline: unlimited inland, easing down to a beach
## near the coast, then a shelf down to the sea floor.
func coast_cap(x: float) -> float:
	if x <= -_coast_band:
		return INF
	if x < 0.0:
		var t := -x / _coast_band
		return 1.0 + t * t * 59.0
	return 1.0 + (_sea_floor - 1.0) * smoothstep(0.0, _coast_shelf, x)


## Plans the sites (towns, camps, anything placed on the map; their roads, bare ground) from the seed before any chunk is built, so the
## land can be shaped for them. Override it in a subclass: register each site with add_site, add roads to
## `roads`, bare ground to `ground_mask` and height stamps to `stamps`. (Plan with base heights: get_height
## includes the roads planned so far.) The base generator plans nothing.
func _plan_sites() -> void:
	pass


## Registers a planned site: site_blocked keeps other things `plan.footprint + margin` (+ pad) clear of it.
## `plan` is any object with a `footprint` (radius in m); the terrain reads nothing else, so it never depends
## on what the site is.
## `tags` (optional, e.g. [&"waystation"]) label the site for sites_tagged(); stored only when given.
func add_site(id: String, plan: Object, spot: Array, margin := 20.0, tags: Array[StringName] = []) -> void:
	var site := {"id": id, "plan": plan, "spot": spot, "radius": float(plan.get("footprint")) + margin}
	if not tags.is_empty():
		site["tags"] = tags.duplicate()
	sites.append(site)


## Every planned site (the `sites` entries) carrying `tag`, in planning order.
func sites_tagged(tag: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for site: Dictionary in sites:
		if (site.get("tags", []) as Array).has(tag):
			out.append(site)
	return out


## False where no site may stand (LFSitePlanner.spot_score asks). `margin` is how far inside the playable
## area the spot must be. Override it to keep sites out of places the game reserves. The base allows all.
func site_allowed(_x: float, _z: float, _margin: float) -> bool:
	return true


## Every planned road gets a bare strip (no grass or flowers) the width of the road plus a margin.
func _mask_roads() -> void:
	for rd: Dictionary in roads.roads:
		var pts: PackedVector2Array = rd["pts"]
		for k in pts.size() - 1:
			ground_mask.add_segment(pts[k], pts[k + 1], LFTerrainRoads.HALF_WIDTH + 0.4)


## True if (x, z) is inside a planned site or within `pad` metres of a planned road (other sites
## such as shelters, ruins and shrines stay clear of them).
func site_blocked(x: float, z: float, pad := 8.0) -> bool:
	for site: Dictionary in sites:
		var c: Vector3 = (site["spot"] as Array)[0]
		if Vector2(x - c.x, z - c.z).length() < float(site["radius"]) + pad:
			return true
	return roads.distance_to(x, z) < LFTerrainRoads.HALF_WIDTH + pad


## A second generator with identical noise and spawn that skips the spawn search. FastNoiseLite
## reads are thread-safe, but each worker task builds its own copy so no object is shared at all
## (a generator keeps scratch state while it samples: use one per thread).
func clone_for_worker() -> LFTerrainGenerator:
	var g: LFTerrainGenerator = get_script().new()
	g.params = params
	g._apply_params()
	g._make_noises(world_seed)
	# the lines setup fitted to the mountains (a copy that kept its defaults had no snow line and the rock line low)
	g._line_up = _line_up
	g._rock_mid = _rock_mid
	g._snow_line_h = _snow_line_h
	g._snow_top = _snow_top
	g._index_biome_heights()
	g.spawn_xz = spawn_xz
	g.spawn_height = spawn_height
	g.region_center = region_center
	g._rg_on = _rg_on
	g._island = _island
	g._island_phases = _island_phases
	g._rim = _rim
	g._rim_rect = _rim_rect
	g._pass_seg = _pass_seg
	g._pass_cells = _pass_cells   # read-only once the rivers are placed
	g._peaks = _peaks
	g._lakes = _lakes
	g._river_pts = _river_pts
	g._river_lvl = _river_lvl
	g._cell_lo = _cell_lo
	g._cell_w = _cell_w
	g._cell_h = _cell_h
	g._cell_at = _cell_at
	g._cell_segs = _cell_segs
	g._seg_a = _seg_a
	g._seg_ab = _seg_ab
	g._seg_l2 = _seg_l2
	g._raised = _raised
	g._raised_cells = _raised_cells
	g._raised_ready = _raised_ready
	_copy_planned(g)
	return g


## Hands the planned sites, stamps, roads and mask (read-only after setup) to a worker copy. A subclass that
## keeps more planned data copies it too (and calls super).
func _copy_planned(g: LFTerrainGenerator) -> void:
	g.sites = sites
	g.stamps = stamps
	g.roads = roads
	g.ground_mask = ground_mask


func _make_noises(seed_value: int) -> void:
	world_seed = seed_value
	_hills = _make_noise(1, _p.hills_freq, 3)
	_ridge = _make_noise(2, _p.ridge_freq, 2)
	_ridge_mask = _make_noise(3, _p.ridge_mask_freq, 1)
	_detail = _make_noise(4, _p.detail_freq, 2)
	_temp = _make_noise(5, _p.climate_freq, 1)
	_moist = _make_noise(6, _p.climate_freq, 1)
	_clearing = _make_noise(7, 0.014, 1)
	_flowers = _make_noise(8, 0.03, 1)
	_stand = _make_noise(13, 0.02, 1)
	_mountain = _make_noise(15, 2.5 / _p.mountain_size, 4)
	_mountain_mask = _make_noise(16, 0.64 / _p.mountain_size, 2)
	_river_mask = _make_noise(10, _p.river_mask_freq, 1)
	_coast = _make_noise(14, 0.0012, 3)
	_cliff_warp = _make_noise(17, 0.008, 2)
	_cliff_patch = _make_noise(18, 0.004, 2)
	_relief = _make_noise(19, 1.0 / maxf(_p.relief_size, 1.0), 2)
	_make_strata()
	_landforms.clear()
	_landform_biomes.clear()
	for l: LFHeightLayer in _p.landforms:
		if l == null or not l.enabled:
			continue
		var own: LFHeightLayer = l.duplicate()
		own.prepare(seed_value)
		_landforms.append(own)
		var idx := PackedInt32Array()
		for i in _biomes.size():
			if _biomes[i].name in l.biomes:
				idx.append(i)
		_landform_biomes.append(idx)


func _make_noise(offset: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + offset * 7919
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


## The land height at (x, z), including the cuttings and banks of planned roads. Everything that
## builds or places things on the ground uses this.
func get_height(x: float, z: float) -> float:
	var h := base_height(x, z)
	return h if roads.is_empty() else roads.apply(x, z, h)


## Rolling hills + ridged mountain bands + small bumps, then rivers carved in (no roads).
## Roughly -8..+30 m, plus mountain_height where the ranges are.
func base_height(x: float, z: float) -> float:
	return _height(x, z, true)


## base_height, with or without the landforms (biome_height). `pre_cliff`: stop just before the cliff bands are
## cut in (the samples that measure the slope for them).
func _height(x: float, z: float, landforms: bool, pre_cliff := false) -> float:
	var hills := _hills.get_noise_2d(x, z)
	var r := 1.0 - absf(_ridge.get_noise_2d(x, z))  # ridged noise: sharp crests
	r *= r
	var mask := smoothstep(-0.05, 0.45, _ridge_mask.get_noise_2d(x, z))  # where ridges are allowed
	var rf := _relief_at(x, z)
	var h := _base_h + (hills * _hills_h + r * mask * _ridge_h) * rf + _detail.get_noise_2d(x, z) * _detail_h
	var rise := 0.0
	if _mountain_h > 0.0:
		rise = _mountain_rise(x, z)
		h += rise
	if _fill_hollows:   # smooth max with the bank height: the hollows become low, dry flats
		var f := _river_bank_h
		var kk := 3.0
		var t := clampf(0.5 + 0.5 * (h - f) / kk, 0.0, 1.0)
		h = lerpf(f, h, t) + kk * t * (1.0 - t)
	if landforms:
		for k in _landforms.size():
			h = _apply_landform(k, x, z, h)
		if _dip_on:   # the sunken biomes (LFBiomeDef.ground_dip), before the water is cut in
			h -= _ground_dip(x, z)
	for lk in _lakes:
		h = _lake_floor(lk, x, z, h)
	var keep := 1.0   # where no counted river crosses a lake's rim
	var keep_lv := -INF   # that river's level: only one at a lake's own level (flowing in or out) opens its rim
	var rv := Vector3(INF, 0.0, WATER_LEVEL)
	if _river_lines:
		h = _carve_rivers(x, z, h)   # one pass: the cut and the nearest river (_rv)
		rv = _rv
	if rv.y > 0.0:
		var d := rv.x
		var m := rv.y
		var lv := rv.z
		var bank := lv + _river_bank_h
		var width := lerpf(0.35, 1.0, smoothstep(0.0, 1.0, m))
		var reach := _river_bank_end * width
		var chan := lerpf(lv + _river_bed, bank, smoothstep(_river_core * width, reach, d))
		if lv > WATER_LEVEL + 0.05:
			# 3) a river above the sea runs in its own channel: where the land beside it is lower than the
			# water, banks hold the water in (out to where water_level_at stops calling it river), but not
			# inside a lake it flows into or out of.
			var floor_h := chan if d < reach else bank
			if h < floor_h:
				# full out past the water's edge (reach * 1.6) by more than a mesh cell, then easing off
				var hold := (1.0 - smoothstep(reach * 1.6 + HOLD_MARGIN, reach * 2.4 + HOLD_MARGIN, d)) * smoothstep(0.0, 0.02, m)
				h = lerpf(h, floor_h, hold * (1.0 - _in_raised_lake(x, z)))
		if _river_lines:
			keep = smoothstep(reach, reach * 2.2, d)
			keep_lv = lv
	if _raised and _near_raised(x, z):
		for lk in _lakes:
			if lk.w > WATER_LEVEL + 0.05:
				h = _lake_rim(lk, x, z, h, keep if keep_lv > lk.w - 0.5 else 1.0)
	if pre_cliff:
		return h
	if landforms and _p.cliffs > 0.0 and rise > CLIFF_MIN_RISE and not _placing_water:
		var away := _cliff_gate(x, z, rise, rv)
		if away > 0.0:   # not by a river: its banks and falls keep their shape
			h = _cliffed(x, z, h, away)
	if _rim:
		h += _rim_h * rim_share(x, z)
	if _island and Vector2(x, z).distance_to(region_center) >= _coast_inner:
		var co := coast_offset(x, z)
		if co > -_coast_band:
			var cap := coast_cap(co)
			var k := 3.0   # smooth min: rounds the crease where the land meets the coastal slope
			var hh := clampf(0.5 + 0.5 * (cap - h) / k, 0.0, 1.0)
			h = lerpf(cap, h, hh) - k * hh * (1.0 - hh)
			if co > 0.0:
				h += _detail.get_noise_2d(x, z) * 1.5 * smoothstep(0.0, _coast_shelf, co)   # a lumpy sea bed
	for st: Object in stamps:
		h = st.height(x, z, h)
	return h


## Height `h` at (x, z) with cliff bands and talus where the land is steep (cliffs): inside a hard rock layer
## (rock_layer) the slope rises as a steep riser with a shelf on top, inside the soft layer below it lies back as
## a talus apron with a concave foot. Each pair of layers keeps its heights (so rock_layer of the result says
## which part it is), only how they spread across the slope changes. The small bumps are damped on steep ground
## too. `k` (0..1) scales it.
func _cliffed(x: float, z: float, h: float, k: float) -> float:
	# Slope of the bare shape (_cliff_base: hills, ridges, mountains; no bumps, they are what gets damped) over
	# 4 m: the weights below follow it (over 2 m it swung fast where the land creases, mountain_flats' steps).
	# Not of the full height: that carves every river near, three times per sample (bakes ~40 % slower);
	# rivers' and lakes' sides, which the bare shape doesn't know, get no cliffs (`k`).
	var d := _detail.get_noise_2d(x, z) * _detail_h
	var b0 := _cliff_base(x, z)
	var s := Vector2(_cliff_base(x + 4.0, z) - b0, _cliff_base(x, z + 4.0) - b0).length() * 0.25
	h -= d * CLIFF_DETAIL_DAMP * smoothstep(0.6, 1.2, s) * k
	# steep ground, but not ground already steeper than a riser (it is a cliff as it is)
	var w := smoothstep(0.8, 1.5, s) * (1.0 - smoothstep(CLIFF_MAX_SLOPE * 0.8, CLIFF_MAX_SLOPE * 2.0, s)) * k
	if w <= 0.0:
		return h
	var t0 := lerpf(0.45, -0.75, _p.cliffs)
	w *= smoothstep(t0, t0 + 0.35, _cliff_patch.get_noise_2d(x, z))
	if w <= 0.0:
		return h
	var shift := _layer_shift(x, z)
	var u := h - shift
	var rep := floorf(u / _strata_period)
	var v := u - rep * _strata_period
	var j := clampi(_strata_base.bsearch(v, false) - 1, 0, STRATA_LAYERS - 1)
	j -= j % 2   # the pair: soft layer j, hard layer j + 1 above it
	if _strata_hard[j + 1] == 0:
		return h   # no cliff in this pair: the slope stays smooth
	var u0 := _strata_base[j]
	var u1 := _strata_base[j + 1]
	var u2 := _strata_base[j + 2]
	var tt := u2 - u0
	var ts := u1 - u0
	var th := u2 - u1
	var t := (v - u0) / tt   # 0..1 across the pair's width on the slope
	# Shares of that width, laid out for a slope of CLIFF_REF_SLOPE (a fixed profile per pair: one that followed
	# the local slope moved whole bands sideways wherever the slope wavered): the riser at most CLIFF_MAX_SLOPE
	# steep, a shelf, and the talus as close to talus_slope (its straight upper part) as the rest allows, never
	# steeper than the land
	var sr := CLIFF_REF_SLOPE
	var rf := minf(th * (1.0 - CLIFF_SHELF) * sr / (CLIFF_MAX_SLOPE * tt), th / tt)
	var talus := _p.talus_slope * (1.0 - TALUS_FOOT * 0.5)
	var a := clampf(ts * sr / (talus * tt), ts / tt, maxf(ts / tt, 1.0 - rf - CLIFF_SHELF_W * sr / tt))
	var out: float
	if t < a:
		var x2 := t / a
		var m := 1.0 / (1.0 - TALUS_FOOT * 0.5)   # straight part's slope (x mean), its foot a parabola
		out = u0 + ts * (m / (2.0 * TALUS_FOOT) * x2 * x2 if x2 < TALUS_FOOT else 1.0 - m * (1.0 - x2))
	else:
		var y := (t - a) / (1.0 - a)
		var rr := minf(rf / (1.0 - a), 1.0)
		# the shelf's share of the rise shrinks to 0 as it runs out of width (a riser over the whole layer)
		var shelf := CLIFF_SHELF * clampf((1.0 - rr) * 5.0, 0.0, 1.0)
		if y < rr:
			out = u1 + th * (1.0 - shelf) * y / rr
		else:
			out = u1 + th * (1.0 - shelf + shelf * (y - rr) / (1.0 - rr))
	return h + (out - v) * w


## How far the cliff bands may reach at (x, z) (0..1): from the mountains' `rise` there, none by a river (`rv`:
## _river_info3) or on a lake's sides.
func _cliff_gate(x: float, z: float, rise: float, rv: Vector3) -> float:
	var away := 1.0 if rv.y <= 0.0 else smoothstep(_river_bank_end * 2.0, _river_bank_end * 4.0, rv.x)
	for lk in _lakes:   # nor on a lake's sides
		var reach := lk.z * (1.05 + LAKE_RAGGED) + maxf(lk.z * 0.55, LAKE_SIDE)
		away *= smoothstep(reach, reach + 30.0, Vector2(x - lk.x, z - lk.y).length())
	return away * minf(1.0, (rise - CLIFF_MIN_RISE) / CLIFF_MIN_RISE)


## How much (x, z) lies where the cliff bands are (0..1): on the mountains, in their patches (cliffs), not by
## rivers or on lakes' sides. Steep ground there in a hard rock layer (rock_layer) is a cliff face: LFPropPlacer
## stands cliff rocks on it; a host can use it for climbing spots or nests.
func cliff_band(x: float, z: float) -> float:
	if _p.cliffs <= 0.0 or _mountain_h <= 0.0:
		return 0.0
	var rise := _mountain_rise(x, z)
	if rise <= CLIFF_MIN_RISE:
		return 0.0
	var t0 := lerpf(0.45, -0.75, _p.cliffs)
	var patch := smoothstep(t0, t0 + 0.35, _cliff_patch.get_noise_2d(x, z))
	if patch <= 0.0:
		return 0.0
	return patch * _cliff_gate(x, z, rise, _river_info3(x, z))


## The land's bare shape at (x, z) (hills, ridges, mountains): what _cliffed measures the slope on.
func _cliff_base(x: float, z: float) -> float:
	var r := 1.0 - absf(_ridge.get_noise_2d(x, z))
	var mask := smoothstep(-0.05, 0.45, _ridge_mask.get_noise_2d(x, z))
	return (_hills.get_noise_2d(x, z) * _hills_h + r * r * mask * _ridge_h) * _relief_at(x, z) + _mountain_rise(x, z)


## How rugged the land is at (x, z): 1 everywhere when relief_variation is 0, else 1 - v (flat) .. 1 + v.
func _relief_at(x: float, z: float) -> float:
	if _relief_v <= 0.0:
		return 1.0
	return clampf(1.0 + _relief_v * 2.5 * _relief.get_noise_2d(x, z), 1.0 - _relief_v, 1.0 + _relief_v)


## How far (m) the rock layers are lifted at (x, z): their tilt (cliff_dip) plus a slow wander, so bands cross
## the contour lines like real bedding.
func _layer_shift(x: float, z: float) -> float:
	return _dip.dot(Vector2(x, z)) + _cliff_warp.get_noise_2d(x, z) * CLIFF_WARP


## Builds the rock layer stack from the seed (cliff_layer_min..max thick, every second one hard by
## cliff_hard_share); it repeats every _strata_period m.
func _make_strata() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/strata" % world_seed)
	_dip = Vector2.from_angle(rng.randf() * TAU) * _p.cliff_dip
	var lo := minf(_p.cliff_layer_min, _p.cliff_layer_max)
	var hi := maxf(_p.cliff_layer_min, _p.cliff_layer_max)
	_strata_base = PackedFloat32Array()
	_strata_hard = PackedByteArray()
	var u := 0.0
	var phase := rng.randf()
	for i in STRATA_LAYERS:
		_strata_base.append(u)
		u += rng.randf_range(lo, hi)
		# spread evenly by the share (a golden-ratio sequence), not drawn one by one: a face never goes without bands
		# for long by bad luck
		_strata_hard.append(1 if i % 2 == 1 and fposmod(phase + i * 0.309017, 1.0) < _p.cliff_hard_share else 0)
	_strata_base.append(u)
	_strata_period = u


## The rock layer at (x, z) and height `h`: (layer index, 0..1 how far up it, 1 if hard rock (a cliff band) else 0).
## Layers are level sheets tilted by cliff_dip and wandering a few metres, cliff_layer_min..max thick; the same
## model shapes the cliffs, so a host can put ores, caves or climbing spots by it.
func rock_layer(x: float, z: float, h: float) -> Vector3:
	var u := h - _layer_shift(x, z)
	var rep := floorf(u / _strata_period)
	var v := u - rep * _strata_period
	var j := clampi(_strata_base.bsearch(v, false) - 1, 0, STRATA_LAYERS - 1)
	var frac := (v - _strata_base[j]) / (_strata_base[j + 1] - _strata_base[j])
	return Vector3(rep * STRATA_LAYERS + j, frac, _strata_hard[j])


## The heights (bottom, top) of the rock layer at (x, z) that height `h` lies in (rock_layer).
func rock_layer_span(x: float, z: float, h: float) -> Vector2:
	var shift := _layer_shift(x, z)
	var u := h - shift
	var rep := floorf(u / _strata_period)
	var v := u - rep * _strata_period
	var j := clampi(_strata_base.bsearch(v, false) - 1, 0, STRATA_LAYERS - 1)
	var b := shift + rep * _strata_period
	return Vector2(b + _strata_base[j], b + _strata_base[j + 1])


## Land `h` with one river cut in: `rv` from _river_info3 / _second_river (distance m, strength, water level).
## Only lowers. _carve_rivers has it inlined: change both together.
func _carve_river(h: float, rv: Vector3) -> float:
	var d := rv.x
	var m := rv.y
	var bank := rv.z + _river_bank_h   # rv.z: the water (WATER_LEVEL, or falling from a lake up in the hills)
	# 1) valley: pull high ground down towards bank height near the river
	if h > bank:
		var v := (1.0 - smoothstep(0.0, _river_valley, d)) * m
		h = lerpf(h, bank + (h - bank) * 0.12, v * v * (3.0 - 2.0 * v))
	# 2) channel: a bed below the water with sloped banks.
	# Where the river fades out (mask edge) it gets NARROWER, never shallower, so it stays one
	# continuous stream that tapers like a creek instead of breaking into separate pools.
	var width := lerpf(0.35, 1.0, smoothstep(0.0, 1.0, m))
	var reach := _river_bank_end * width
	var chan := lerpf(rv.z + _river_bed, bank, smoothstep(_river_core * width, reach, d))
	# Past the bank the land may rise only at bank_slope, then steeper (_bank_cap), out to where it meets the
	# ground: gentle banks however high the land round a creek ...
	var cap := chan if d < reach else _bank_cap(bank, d - reach)
	# ... letting go before the valley's edge, where the mask ends: else the land past it stood as a wall
	cap = lerpf(cap, maxf(cap, h), _cap_release(d))
	if cap < h:
		h = lerpf(h, cap, smoothstep(0.0, 0.12, m))
	return h


## Highest the land may be `out` m past the top of a river's bank (at `bank`): river_bank_slope near the river,
## steepening from 0.15 valley widths out to a rock face (VALLEY_WALL), so high ground beside a river climbs to
## its height as a valley side, not a flat shelf ending in a wall.
func _bank_cap(bank: float, out: float) -> float:
	var u := maxf(out - _river_valley * 0.15, 0.0)
	var r := _river_valley * 0.2   # over which the slope steepens
	var wall := u * u / (2.0 * r) if u < r else u - r * 0.5
	return bank + out * _river_bank_slope + wall * maxf(VALLEY_WALL - _river_bank_slope, 0.0)


## 0 near a river, rising to 1 by 1.3 valley widths out (where its mask ends): how far the bank cap has let go
## of the land. Only a peak too tall for _bank_cap to reach in time still gets a steep face there.
func _cap_release(d: float) -> float:
	return smoothstep(_river_valley * 1.0, _river_valley * 1.27, d)


## The height of the land at (x, z) that biomes with a minimum height (LFBiomeDef.only_above) go by:
## base_height without the landforms (a landform may ask for the biomes while it shapes the land).
func biome_height(x: float, z: float) -> float:
	return _height(x, z, false)


## Metres the mountains add at (x, z).
func _mountain_rise(x: float, z: float) -> float:
	return _mountain_h * mountain_share(x, z)


## How far up a mountain (x, z) is: 0 off the mountains, 1 at the highest peak. Ranges (mountain_count 0)
## or counted mountains, with shelves (mountain_flats), faded out before an island's coast.
func mountain_share(x: float, z: float) -> float:
	if _mountain_h <= 0.0:
		return 0.0
	var t := 0.0
	if _p.mountain_count <= 0:
		var m := smoothstep(_mountain_at, _mountain_at + 0.35, _mountain_mask.get_noise_2d(x, z))
		if m <= 0.0:
			return 0.0
		var r := 1.0 - absf(_mountain.get_noise_2d(x, z))   # ridged: sharp crests and peaks
		t = m * m * (0.3 + 0.7 * r * r)
	else:
		if _peaks.is_empty():
			return 0.0
		var wobble := _mountain_mask.get_noise_2d(x, z) * 0.3   # ragged outlines, not circles
		for pk in _peaks:
			var d := Vector2(x - pk.x, z - pk.y).length() / pk.z + wobble
			if d < 1.0:
				var u := 1.0 - d
				t = maxf(t, u * u * (3.0 - 2.0 * u) * pk.w)
		if t <= 0.0:
			return 0.0
		t *= 0.75 + 0.25 * (1.0 - absf(_mountain.get_noise_2d(x, z)))   # ridged detail on the slopes
	if _p.mountain_flats > 0.0:   # soft steps: three shelves and a flat top
		var s3 := t * 3.0
		var f := floorf(s3)
		t = lerpf(t, (f + smoothstep(0.55, 1.0, s3 - f)) / 3.0, _p.mountain_flats)
	if _island:
		var co := coast_offset(x, z)
		t *= 1.0 - smoothstep(-_coast_band - 150.0, -_coast_band * 0.4, co)
		# Keep the rise under a ramp that carries on from the coast cap's slope, so the cap trims the foot
		# gently and the mountain never meets it as a wall.
		var rise := t * _mountain_h
		if co > -_coast_band - 600.0 and rise > 0.0:
			var ramp := coast_cap(co) if co > -_coast_band else coast_cap(-_coast_band + 0.001) \
					+ (-_coast_band - co) * _p.mountain_foot_slope
			var k := 12.0
			var hh := clampf(0.5 + 0.5 * (ramp - rise) / k, 0.0, 1.0)
			t = (lerpf(ramp, rise, hh) - k * hh * (1.0 - hh)) / _mountain_h
	return maxf(t, 0.0)


## Places the counted mountains (mountain_count) from the seed inside mountain_area around the region centre
## (inside the coast on an island), apart from each other and clear of the spawn. A peak that finds no room
## clear of the spawn tries again with only the spawn spot itself kept clear (a small map).
func _place_mountains() -> void:
	_peaks = PackedVector4Array()
	if _mountain_h <= 0.0 or _p.mountain_count <= 0:
		return
	var area := _p.mountain_area
	if _island:
		area = minf(area, _island_min_r)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/mountains" % world_seed)
	for i in _p.mountain_count:
		var rad := minf(_p.mountain_size * rng.randf_range(0.7, 1.2), area * 0.8)   # a small area: smaller peaks
		var share := 1.0 if i == 0 else rng.randf_range(0.6, 1.0)   # the first is the tallest
		for attempt in 80:
			var c := region_center + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * area
			if c.distance_to(spawn_xz) < (rad + 60.0 if attempt < 40 else 60.0):
				continue
			var ok := true
			for pk in _peaks:
				if c.distance_to(Vector2(pk.x, pk.y)) < (rad + pk.z) * 0.55:
					ok = false
					break
			if ok:
				_peaks.append(Vector4(c.x, c.y, rad, share))
				break


## Places the counted lakes (lake_count, about lake_size m across; the first big_lake m when set) from the seed
## inside mountain_area round the region centre (inside the coast on an island), apart from each other and the
## spawn (on a small map only the spawn spot itself). A share (highland_lakes) sits on the counted mountains'
## lower slopes (out in the land when there is no room there), the rest clear of the peaks. Of a few spots
## that fit, the flattest wins (for a highland lake, the flattest high up). Each lake's water
## lies 1 m under the lowest ground round its shore, so a lake up in the hills sits at its own height (one
## lower than 1.5 m lies at the sea's level, as before). A lake that finds no room is left out
## (lake_count_placed() says how many did).
func _place_lakes() -> void:
	_lakes = PackedVector4Array()
	_raised = false
	if _p.lake_count <= 0:
		return
	var area := _p.mountain_area
	if _island:
		area = minf(area, _island_min_r)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/lakes" % world_seed)
	for i in _p.lake_count:
		var rad := _p.lake_size * 0.5 * rng.randf_range(0.6, 1.3)
		if i == 0 and _p.big_lake > 0.0:
			rad = _p.big_lake * 0.5
		rad = minf(rad, area * 0.4)
		var high := not _peaks.is_empty() and rng.randf() < _p.highland_lakes
		var best := Vector2.INF
		var best_spread := INF
		var best_low := 0.0
		var fits := 0
		for attempt in 80:
			if high and attempt == 50 and fits == 0:
				high = false   # no room on the mountains: out in the land instead
			var c := Vector2.ZERO
			if high:   # on a mountain's lower slopes, its shore clear of the summit (water there flattens the peak)
				var pk := _peaks[rng.randi() % _peaks.size()]
				c = Vector2(pk.x, pk.y) + Vector2.from_angle(rng.randf() * TAU) * (rad + pk.z * rng.randf_range(0.35, 0.6))
				if c.distance_to(region_center) > area - rad:
					continue
			else:
				c = region_center + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * maxf(area - rad, 0.0)
			# clear of the spawn's surroundings; on a small map, after 40 tries, of the spawn spot itself
			if c.distance_to(spawn_xz) < (rad * 1.6 + 40.0 if attempt < 40 else rad + 6.0):
				continue
			var ok := true
			for lk in _lakes:
				if c.distance_to(Vector2(lk.x, lk.y)) < (rad + lk.z) * 1.7:
					ok = false
					break
			for pk in _peaks:
				var away := rad + pk.z * 0.35 if high else rad * 1.6 + pk.z * 0.6
				if ok and c.distance_to(Vector2(pk.x, pk.y)) < away:
					ok = false
			if not ok:
				continue
			var ring := _shore_heights(c, rad)   # (lowest, highest) ground round the shore
			var score := ring.y - ring.x - (ring.x * 0.5 if high else 0.0)   # flat; up high for a highland lake
			if score < best_spread:
				best = c
				best_spread = score
				best_low = ring.x
			fits += 1
			if fits >= 6:
				break
		if best != Vector2.INF:
			var level := best_low - 1.0
			if level < 1.5:
				level = WATER_LEVEL
			_lakes.append(Vector4(best.x, best.y, rad, level))
			_raised = _raised or level > WATER_LEVEL + 0.05


## The lowest and highest ground (base_height, before this lake) on a ring just outside a lake's shore.
func _shore_heights(c: Vector2, rad: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for k in 12:
		var q := c + Vector2.from_angle(k * TAU / 12.0) * rad * 1.15
		var h := base_height(q.x, q.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)


## How many counted lakes found room (fewer than lake_count when the area is too small for them).
func lake_count_placed() -> int:
	return _lakes.size()


## The land at (x, z) with lake `lk` dug in: a bed 3 m under its water out to about its radius (ragged), a
## shore just above the water, and the land past it rising like a river's valley side (_bank_cap), let go
## over the larger of 55 % of the radius and LAKE_SIDE m: a lake cut into a mountainside gets a slope up to
## the mountain, not a wall round its bowl. Only lowers (a lake up in the hills gets its rim later: _lake_rim).
func _lake_floor(lk: Vector4, x: float, z: float, h: float) -> float:
	var dx := x - lk.x
	var dz := z - lk.y
	var side := maxf(lk.z * 0.55, LAKE_SIDE)
	var reach := lk.z * (1.05 + LAKE_RAGGED) + side
	if dx * dx + dz * dz > reach * reach:
		return h
	var d := _lake_d(lk, x, z)
	var target := 0.0
	if d <= 1.05:
		target = lk.w - 3.0 + 4.0 * smoothstep(0.45, 1.05, d)   # 1 m above the water at the shore
	else:
		var out := (d - 1.05) * lk.z
		target = _bank_cap(lk.w + 1.0, out)
		target = lerpf(target, maxf(target, h), smoothstep(side * 0.5, side, out))
	return minf(h, target)


## A lake up in the hills: its rim, where the land round it is lower than its water (after the rivers, so a
## valley crossing it is dammed), out to where its water stops (1.3 radii) and easing down by 1.8; `keep`
## (0..1) lowers it where a counted river flows in or out.
func _lake_rim(lk: Vector4, x: float, z: float, h: float, keep: float) -> float:
	var dx := x - lk.x
	var dz := z - lk.y
	var r := lk.z * (1.8 + LAKE_RAGGED) + HOLD_MARGIN
	if dx * dx + dz * dz > r * r:
		return h
	var d := _lake_d(lk, x, z)
	if d <= 0.95:
		return h
	var edge := 1.3 + HOLD_MARGIN / lk.z   # full out past the water's edge by more than a mesh cell
	var rim := smoothstep(0.95, 1.05, d) * (1.0 - smoothstep(edge, edge + 0.5, d)) * keep
	return maxf(h, lerpf(h, lk.w + _river_bank_h, rim))   # as high as a river's bank: grass, not a ring of sand


## How far (x, z) is from lake `lk`'s centre, in its radii, with its ragged shore's noise added.
func _lake_d(lk: Vector4, x: float, z: float) -> float:
	var dx := x - lk.x
	var dz := z - lk.y
	var ragged := _coast.get_noise_2d(x * 3.0, z * 3.0) * 0.18   # a ragged edge...
	# ... on bays and points: a broad wobble scaled to the lake (up to 0.53 radii in all, LAKE_RAGGED)
	ragged += _coast.get_noise_2d(lk.x + (x - lk.x) * 700.0 / lk.z, lk.y + (z - lk.y) * 700.0 / lk.z) * 0.35
	return sqrt(dx * dx + dz * dz) / lk.z + ragged


## 1 inside a lake above the sea's level (its water), fading to 0 just past its shore.
func _in_raised_lake(x: float, z: float) -> float:
	var out := 0.0
	for lk in _lakes:
		if lk.w > WATER_LEVEL + 0.05:
			var dx := x - lk.x
			var dz := z - lk.y
			var r := lk.z * (1.25 + LAKE_RAGGED)   # past the fade, whatever the shore's noise
			if dx * dx + dz * dz < r * r:
				out = maxf(out, 1.0 - smoothstep(1.0, 1.25, _lake_d(lk, x, z)))
	return out


## The water surface over (x, z): WATER_LEVEL (the sea, the natural lakes, rivers at the sea's level), or a
## counted lake's or river's own level where that water lies up in the hills. Water is wherever the ground
## (get_height) is below it. Cheap: the counted lakes and the river index near the point.
func water_level_at(x: float, z: float) -> float:
	if not _raised or not _near_raised(x, z):
		return WATER_LEVEL
	for lk in _lakes:
		if lk.w > WATER_LEVEL + 0.05:
			var dx := x - lk.x
			var dz := z - lk.y
			var r := lk.z * (1.3 + LAKE_RAGGED)
			if dx * dx + dz * dz < r * r and _lake_d(lk, x, z) <= 1.3:
				return lk.w
	var rv := _river_info3(x, z)
	if rv.y > 0.02 and rv.z > WATER_LEVEL + 0.05:   # where base_height's banks hold it in full
		var width := lerpf(0.35, 1.0, smoothstep(0.0, 1.0, rv.y))
		if rv.x < _river_bank_end * width * 1.6:
			return rv.z
	return WATER_LEVEL


## False where no water above the sea (nor its rim or banks) can reach (x, z); true while still placing.
func _near_raised(x: float, z: float) -> bool:
	return not _raised_ready or _raised_cells.has(Vector2i(floori(x / RAISED_CELL), floori(z / RAISED_CELL)))


## Marks the RAISED_CELL cells the raised lakes' rims and the raised rivers' banks reach (_near_raised).
func _index_raised() -> void:
	_raised_cells = {}
	_raised_ready = false
	if not _raised:
		return
	var marks: Array[Vector3] = []   # (x, z, radius) circles to mark
	for lk in _lakes:
		if lk.w > WATER_LEVEL + 0.05:
			marks.append(Vector3(lk.x, lk.y, lk.z * (1.8 + LAKE_RAGGED) + HOLD_MARGIN * 2.0))
	var bank := _river_bank_end * 2.4 + HOLD_MARGIN * 2.0
	for k in _river_pts.size():
		if _river_lvl[k] > WATER_LEVEL + 0.05 or (k > 0 and _river_lvl[k - 1] > WATER_LEVEL + 0.05):
			marks.append(Vector3(_river_pts[k].x, _river_pts[k].y, bank + RIVER_STEP))
	for c in marks:
		var lo := Vector2i(floori((c.x - c.z) / RAISED_CELL), floori((c.y - c.z) / RAISED_CELL))
		var hi := Vector2i(floori((c.x + c.z) / RAISED_CELL), floori((c.y + c.z) / RAISED_CELL))
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				_raised_cells[Vector2i(cx, cz)] = true
	_raised_ready = true


## True when some water lies above WATER_LEVEL (a counted lake or river up in the hills): meshes and checks
## then need water_level_at, not the one level.
func has_raised_water() -> bool:
	return _raised


## Lays out the counted rivers (river_count) from the seed. Each starts at a spring up a counted mountain's
## slope (taking them in turn), or, with none, on an island at a spring on its highest ground (300 m apart),
## else at the highest counted lake no river leaves yet, else at the map's edge. From there it runs downhill
## through the lakes on its way (natural lakes too, with natural_lakes on)
## (up to three, each lower than the last: a chain mountain -> lake -> river -> lake -> sea), then to the sea
## on an island or off the map's edge (inside a mountain rim it ends in its last lake, or with rim_pass cuts a pass
## through the rim and leaves; one coming in from past the edge cuts one too). A river that reaches a
## lake another river already leaves joins it there (a tributary). Its water surface falls along each leg,
## following the land (rapids where the land drops), from the lake or spring above to the one below.
## The legs meander (river_warp_amp), keep 100 m from the spawn if they can, and vary from creek to river.
func _place_rivers() -> void:
	_river_pts = PackedVector4Array()
	_river_lvl = PackedFloat32Array()
	_pass_seg = PackedVector2Array()
	_pass_cells = {}
	_index_river_segments()
	_falls = []
	if not _river_lines:
		_index_raised()   # the lakes'
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/rivers" % world_seed)
	var bend := FastNoiseLite.new()
	bend.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bend.fractal_octaves = 2
	bend.frequency = 1.0 / 420.0
	var area := _p.mountain_area
	var reach := area + 800.0   # well past the map's edge
	var sea := _island_r * 1.3 + _coast_shelf
	var drained := {}   # lake index (a natural lake: -1 - its index in pools) -> true once a river leaves it
	var scan := _scan_for_rivers(area)
	var pools: Array[Vector4] = scan[0]
	var highs: Array[Vector3] = scan[1]
	var springs: Array[Vector2] = []
	var leg := 0
	for i in _p.river_count:
		var a := rng.randf() * TAU
		var jitter := rng.randf_range(-0.5, 0.5)
		var swing := PI * rng.randf_range(0.45, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0)
		var from := Vector2.ZERO
		var from_lake := -1
		var spring := true
		var peak := Vector4.INF   # the mountain a river springs on: its spring is placed once the outlet is known
		var from_edge := false   # it comes in from past the map's edge
		var turn := 0.0
		if not _peaks.is_empty():
			peak = _peaks[i % _peaks.size()]
			from = Vector2(peak.x, peak.y)
			if from.distance_to(region_center) < 1.0:
				from = region_center + Vector2.from_angle(a)
			# rivers from the same mountain fan out round it
			turn = ceilf((i / _peaks.size()) * 0.5) * (1.0 if (i / _peaks.size()) % 2 == 1 else -1.0)
		else:
			# an island's rivers spring on its high ground and run down through the lakes; else from a lake
			from_lake = -1 if _island and not highs.is_empty() else _highest_lake(drained)
			if from_lake >= 0:
				from = Vector2(_lakes[from_lake].x, _lakes[from_lake].y)
				drained[from_lake] = true
				spring = false
			elif _island:
				# the highest ground inland, 300 m from the springs before it: water starts up high
				from = region_center + Vector2.from_angle(a) * rng.randf_range(0.0, 0.45) * minf(area, _island_min_r)
				for hi in highs:
					var far := true
					for sp in springs:
						far = far and sp.distance_to(Vector2(hi.x, hi.y)) > 300.0
					if far:
						from = Vector2(hi.x, hi.y)
						break
				springs.append(from)
			else:
				from = region_center + Vector2.from_angle(a) * reach + Vector2.from_angle(a + PI * 0.5) * jitter * area
				spring = false
				from_edge = true
		# where it leaves the map: the sea round an island, else the far edge
		var out_dir := from - region_center
		var ang := out_dir.angle() if out_dir.length() > 1.0 else a
		var outlet := region_center + Vector2.from_angle(ang + PI + swing) * sea if _island \
				else region_center - Vector2.from_angle(ang + jitter * 0.8) * reach
		if peak != Vector4.INF:
			# the spring is up the slope facing the way it goes, so the river runs down and away from the summit
			# (from the far side it ran back over the top, and its valley cut the mountain down)
			from = Vector2(peak.x, peak.y) + (outlet - Vector2(peak.x, peak.y)).normalized().rotated(jitter * 0.4 + turn * 1.3) * peak.z * 0.5
		var top := _lakes[from_lake].w if from_lake >= 0 else maxf(base_height(from.x, from.y) - 1.2, WATER_LEVEL)
		# downhill through the lakes on the way
		var stops: Array[Vector2] = [from]
		var levels: Array[float] = [top]
		var stop_r: Array[float] = [_lakes[from_lake].z if from_lake >= 0 else 0.0]   # each stop's lake radius
		var first_leg := leg   # this river's legs are from here on
		var joined := false
		while stops.size() < 4:
			var cur := stops[stops.size() - 1]
			var to_out := (outlet - cur).normalized()
			var pick := -1
			var pick_score := INF
			for k in _lakes.size():
				var lk := _lakes[k]
				var lp := Vector2(lk.x, lk.y)
				if k == from_lake or stops.has(lp) or lk.w > levels[levels.size() - 1] - 0.3:
					continue
				var dist := cur.distance_to(lp)
				if dist > area * 2.0 or dist < 1.0 or _crosses_summit(cur, lp):   # the spring and the lakes all lie within area of the centre
					continue
				var score := dist * (1.6 - (lp - cur).normalized().dot(to_out))
				if score < pick_score:
					pick = k
					pick_score = score
			for k in pools.size() if pick < 0 else 0:   # else a natural lake (at the sea's level) on the way down
				var pl := pools[k]
				var lp := Vector2(pl.x, pl.y)
				if stops.has(lp) or pl.w > levels[levels.size() - 1] - 0.3:
					continue
				var dist := cur.distance_to(lp)
				if dist > area * 2.0 or dist < 1.0 or _crosses_summit(cur, lp):   # the spring and the lakes all lie within area of the centre
					continue
				var score := dist * (1.6 - (lp - cur).normalized().dot(to_out))
				if score < pick_score:
					pick = -1 - k
					pick_score = score
			if pick_score == INF:   # nothing on the way (pick -1 is also natural lake 0)
				break
			var stop := _lakes[pick] if pick >= 0 else pools[-1 - pick]
			stops.append(Vector2(stop.x, stop.y))
			levels.append(stop.w)
			stop_r.append(stop.z)
			if drained.has(pick):
				joined = true   # another river leaves this lake: join it there
				break
			drained[pick] = true
		var ends_in_lake := joined or (_rim and not _p.rim_pass and stops.size() > 1)
		if not ends_in_lake:
			stops.append(outlet)
			levels.append(WATER_LEVEL if _island else -INF)
			stop_r.append(0.0)
		for s_i in stops.size() - 1:
			var pts := PackedVector4Array()
			for attempt in 30:
				bend.seed = world_seed + 7919 * 31 + leg * 101 + attempt
				pts = _river_path(stops[s_i], stops[s_i + 1], bend, leg, spring and s_i == 0)
				if attempt == 29 or _path_clear_of(pts, spawn_xz, 100.0):
					break
			# rim_pass: a leg that leaves the valley, or comes in from past the edge, cuts its pass through the rim
			# before its levels are set (they follow the land)
			var pass_n := _pass_seg.size()
			var enters := _rim and _p.rim_pass and from_edge and s_i == 0
			if enters or (_rim and _p.rim_pass and not ends_in_lake and s_i == stops.size() - 2):
				_add_pass(pts)
			# running into another river whose water is not above this leg's there: it joins that river there
			# (crossing it, one's water would stand over the other's channel; two at the sea's level crossed).
			# Not its own river's legs, nor rivers at the lake it leaves.
			var bottom := levels[s_i + 1]
			var lv_try := _river_levels(pts, levels[s_i], bottom)
			var meet := -1
			for k in range(1, pts.size()):
				var q := Vector2(pts[k].x, pts[k].y)
				if q.distance_to(stops[s_i]) < stop_r[s_i] + _river_bank_end * 2.0:
					continue
				var hit := _nearest_river_seg(q.x, q.y)
				if hit.x < 0.0 or _river_pts[int(hit.x)].w >= first_leg:
					continue
				var other := _river_info3(q.x, q.y)
				if other.y > 0.02 and other.x < _river_bank_end and other.z < maxf(lv_try[k], WATER_LEVEL) + 0.05:
					meet = k
					bottom = minf(other.z, lv_try[k])
					break
			if meet > 0:
				pts = pts.slice(0, meet + 1)
				_drop_pass(pass_n)   # it joins another river before it leaves: only the way in keeps a pass
				if enters:
					_add_pass(pts)
				# ending on the other river's line, not up to a bank's width past it (its last stretch crossed)
				var hit := _nearest_river_seg(pts[meet].x, pts[meet].y)
				var on := _river_pts[int(hit.x)].lerp(_river_pts[int(hit.x) + 1], hit.y)
				pts[meet] = Vector4(on.x, on.y, pts[meet].z, pts[meet].w)
			var lv := _river_levels(pts, levels[s_i], bottom)
			if _p.waterfalls:
				var fall := _make_falls(pts, lv)
				pts = fall[0]
				lv = fall[1]
			_cut_crossed(pts, lv)
			_river_lvl.append_array(lv)
			_river_pts.append_array(pts)
			_index_river_segments()   # so the next leg meets this one at its level (and sees its valley)
			leg += 1
			if meet > 0:
				break
	for lv in _river_lvl:
		_raised = _raised or lv > WATER_LEVEL + 0.05
	_index_raised()
	_find_falls()


## A new leg crossing (or running beside) a river placed before it whose water stands higher there: that
## river ends where it first comes near the new one, falling into it at its edge (left whole, its water
## would stand over the new channel, or beside it behind a wall). One left as a stub is taken out.
func _cut_crossed(pts: PackedVector4Array, lv: PackedFloat32Array) -> void:
	var done := {}   # the legs already cut
	for k in range(1, pts.size()):
		var q := Vector2(pts[k].x, pts[k].y)
		var q0 := Vector2(pts[k - 1].x, pts[k - 1].y)
		for j in _river_pts.size():
			var e := _river_pts[j]
			if done.has(e.w) or _river_lvl[j] <= lv[k] + 0.05:
				continue
			var e2 := _river_pts[j + 1] if j + 1 < _river_pts.size() else e
			var crosses := e2.w == e.w and Geometry2D.segment_intersects_segment(q0, q,
					Vector2(e.x, e.y), Vector2(e2.x, e2.y)) != null
			if crosses or q.distance_to(Vector2(e.x, e.y)) < _river_bank_end * 1.5:
				done[e.w] = true
				_cut_leg(e.w, pts, lv, _first_crossing(e.w, pts))
				break


## The index in _river_pts of the point after leg `w` first crosses the line `pts`, or -1 if it doesn't.
func _first_crossing(w: float, pts: PackedVector4Array) -> int:
	for j in _river_pts.size() - 1:
		var e := _river_pts[j]
		var e2 := _river_pts[j + 1]
		if e.w != w or e2.w != w:
			continue
		for k in range(1, pts.size()):
			if Geometry2D.segment_intersects_segment(Vector2(pts[k - 1].x, pts[k - 1].y), Vector2(pts[k].x, pts[k].y),
					Vector2(e.x, e.y), Vector2(e2.x, e2.y)) != null:
				return j + 1
	return -1


## Ends leg `w` (of _river_pts) where the new leg's valley would cut the land beside it below its water (its
## banks would stand as walls): its last point there is the lip, and it falls (with waterfalls) and runs on
## at the new river's level into it. Taken out if that leaves less than two of its points. `cross`: the point
## after it crosses the new leg (_first_crossing), or -1: it is cut there at the latest, walls or not.
func _cut_leg(w: float, pts: PackedVector4Array, lv: PackedFloat32Array, cross := -1) -> void:
	var s := 0
	while s < _river_pts.size() and _river_pts[s].w != w:
		s += 1
	var end := s
	while end < _river_pts.size() and _river_pts[end].w == w:
		end += 1
	for j in range(s, end):
		var p := Vector2(_river_pts[j].x, _river_pts[j].y)
		var kk := -1
		var best := _river_valley
		for k in pts.size():
			var dk := p.distance_to(Vector2(pts[k].x, pts[k].y))
			if dk < best:
				best = dk
				kk = k
		var forced := cross >= 0 and j >= cross   # it crosses the new leg before this point: cut here at the latest
		if kk < 0 or (_river_lvl[j] <= lv[kk] + 0.5 and not forced):
			continue
		# the land beside this leg (its bank), as the new river's valley and bank slope would leave it
		var bank := lv[kk] + _river_bank_h
		var h := _river_lvl[j] + _river_bank_h
		var v := 1.0 - smoothstep(0.0, _river_valley, best)
		h = lerpf(h, bank + (h - bank) * 0.12, v * v * (3.0 - 2.0 * v))
		h = minf(h, bank + maxf(best - _river_bank_end, 0.0) * _river_bank_slope)
		if h > _river_lvl[j] + _river_bank_h * 0.5 and not forced:
			continue
		var tail := PackedVector4Array()
		var tail_lv := PackedFloat32Array()
		if j - s >= 2:
			var e := _river_pts[j - 1]
			var lip := Vector2(e.x, e.y)
			var q := Vector2(pts[kk].x, pts[kk].y)
			var dir := (q - lip).normalized()
			if _p.waterfalls:   # falls at the last point that keeps its banks, then runs into the new river
				var foot := lip + dir * FALL_LIP
				tail = PackedVector4Array([Vector4(foot.x, foot.y, e.z, w), Vector4(q.x, q.y, e.z, w)])
				tail_lv = PackedFloat32Array([lv[kk], lv[kk]])
			else:
				tail = PackedVector4Array([Vector4(q.x, q.y, e.z, w)])
				tail_lv = PackedFloat32Array([lv[kk]])
			_river_pts = _river_pts.slice(0, j) + tail + _river_pts.slice(end)
			_river_lvl = _river_lvl.slice(0, j) + tail_lv + _river_lvl.slice(end)
		else:
			_river_pts = _river_pts.slice(0, s) + _river_pts.slice(end)
			_river_lvl = _river_lvl.slice(0, s) + _river_lvl.slice(end)
		_index_river_segments()
		return


## Waterfalls: each steep stretch of a leg (every RIVER_STEP dropping FALL_STEEP m or more, FALL_MIN m in all)
## becomes level water and falls of FALL_MAX m at most, each falling right after a point (an extra point
## FALL_LIP m on), so the water is never above where it was (no banks raised to hold it) and the river
## cuts a gorge below each fall. Not at a spring's trickle, nor down onto a beach. Returns [points, levels].
func _make_falls(pts: PackedVector4Array, lv: PackedFloat32Array) -> Array:
	var n := pts.size()
	var steep := PackedByteArray()   # segment k (k to k + 1) may be part of a fall
	steep.resize(n)
	for k in n - 1:
		var ok := lv[k] - lv[k + 1] >= FALL_STEEP and pts[k].z >= FALL_STRENGTH
		if ok and _island and lv[k + 1] < 1.0:   # not down onto a beach
			ok = coast_offset(pts[k + 1].x, pts[k + 1].y) < -ESTUARY_RUN * 1.5
		steep[k] = 1 if ok else 0
	var q := lv.duplicate()
	var lips := PackedInt32Array()
	var k0 := 0
	while k0 < n - 1:
		if steep[k0] == 0:
			k0 += 1
			continue
		var e := k0
		while e < n - 1 and steep[e] == 1:
			e += 1
		var total := lv[k0] - lv[e]
		if total >= FALL_MIN:
			var step := total / ceilf(total / FALL_MAX)
			for k in range(k0 + 1, e):
				q[k] = lv[e] + floorf((lv[k] - lv[e]) / step + 0.001) * step
			for k in range(k0, e):
				if q[k] - q[k + 1] > 0.5:
					lips.append(k)
		k0 = e
	if lips.is_empty():
		return [pts, lv]
	var out_p := PackedVector4Array()
	var out_l := PackedFloat32Array()
	for k in n:
		out_p.append(pts[k])
		out_l.append(q[k])
		if lips.has(k):   # the water falls just past the lip; a drop of more than FALL_MAX in one segment
			# (a steep mountainside) is a cascade of lips along it
			var a := Vector2(pts[k].x, pts[k].y)
			var seg := Vector2(pts[k + 1].x, pts[k + 1].y) - a
			var steps := ceili((q[k] - q[k + 1]) / FALL_MAX - 0.01)
			var sub := (q[k] - q[k + 1]) / steps
			for i in steps:
				var lip := a + seg * float(i) / steps
				if i > 0:
					out_p.append(Vector4(lip.x, lip.y, pts[k].z, pts[k].w))
					out_l.append(q[k] - sub * i)
				var b := lip + seg.normalized() * FALL_LIP
				out_p.append(Vector4(b.x, b.y, pts[k].z, pts[k].w))
				out_l.append(q[k] - sub * (i + 1))
	return [out_p, out_l]


## Reads the waterfalls off the placed rivers: two points of a leg FALL_LIP m apart (or so) whose water drops.
func _find_falls() -> void:
	_falls = []
	for k in _river_pts.size() - 1:
		var a := _river_pts[k]
		var b := _river_pts[k + 1]
		var drop := _river_lvl[k] - _river_lvl[k + 1]
		if a.w != b.w or drop < 1.0 or get_height(a.x, a.y) > _river_lvl[k]:   # on dry ground: past a river's end
			continue
		var d := Vector2(b.x - a.x, b.y - a.y)
		if d.length() > FALL_LIP * 2.5:
			continue
		var m := a.z
		_falls.append({"position": Vector3(a.x, _river_lvl[k], a.y), "bottom": _river_lvl[k + 1],
				"direction": d.normalized(), "width": 2.0 * _river_water_edge * lerpf(0.35, 1.0, smoothstep(0.0, 1.0, m))})


## The waterfalls: one Dictionary each, {position: the lip (x, water level at the top, z), bottom: the water
## level below it, direction: the way the water falls (x, z), width: across the river (m)}. Empty with
## params.waterfalls off, or where no river drops steeply enough.
func waterfalls() -> Array[Dictionary]:
	return _falls


## Whether the straight run from a to b passes over a mountain's summit: a river there pulls the peak down
## to its banks, so it goes round to another lake instead.
func _crosses_summit(a: Vector2, b: Vector2) -> bool:
	for pk in _peaks:
		var c := Vector2(pk.x, pk.y)
		if c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)) < pk.z * 0.4:
			return true
	return false


## What the rivers need from the land inside `area` m of the centre, on a coarse grid: [the natural lakes
## (natural_lakes on: hollows below the sea's level, inland, 30 m wide or more, as (x, z, radius,
## WATER_LEVEL), biggest first), the high ground (island, no counted mountains: (x, z, height) 150 m inland
## and 100 m from the spawn, highest first)].
func _scan_for_rivers(area: float) -> Array:
	var pools: Array[Vector4] = []
	var highs: Array[Vector3] = []
	var want_pools := _p.natural_lakes
	var want_highs := _island and _peaks.is_empty()
	if not want_pools and not want_highs:
		return [pools, highs]
	var half := minf(area, _island_r * 1.1) if _island else area
	var step := maxf(16.0, half * 2.0 / 160.0)   # at most 160 x 160 samples
	var n := int(half * 2.0 / step) + 1
	var o := region_center - Vector2(half, half)
	var wet := {}
	for j in n:
		for i in n:
			var x := o.x + i * step
			var z := o.y + j * step
			if _island and coast_offset(x, z) > -150.0:
				continue
			var h := base_height(x, z)
			if want_pools and h < WATER_LEVEL - 0.3:
				var in_lake := false
				for lk in _lakes:
					in_lake = in_lake or _lake_d(lk, x, z) < 1.3
				if not in_lake:
					wet[Vector2i(i, j)] = true
			elif want_highs and Vector2(x, z).distance_to(spawn_xz) > 100.0:
				highs.append(Vector3(x, z, h))
	highs.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.z > q.z or (p.z == q.z and p.x < q.x))
	if highs.size() > 64:
		highs.resize(64)
	# the wet cells in 4-connected clumps, in grid order so the result is the same every time
	var seen := {}
	for j in n:
		for i in n:
			var c := Vector2i(i, j)
			if not wet.has(c) or seen.has(c):
				continue
			seen[c] = true
			var stack: Array[Vector2i] = [c]
			var sum := Vector2.ZERO
			var cnt := 0
			while not stack.is_empty():
				var q: Vector2i = stack.pop_back()
				sum += Vector2(q)
				cnt += 1
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if wet.has(q + d) and not seen.has(q + d):
						seen[q + d] = true
						stack.append(q + d)
			var r := sqrt(cnt / PI) * step
			if r >= 15.0:
				var mid := o + sum / cnt * step
				pools.append(Vector4(mid.x, mid.y, r, WATER_LEVEL))
	pools.sort_custom(func(p: Vector4, q: Vector4) -> bool: return p.z > q.z or (p.z == q.z and p.x < q.x))
	return [pools, highs]


## The highest counted lake no river leaves yet (index), or -1.
func _highest_lake(drained: Dictionary) -> int:
	var best := -1
	for k in _lakes.size():
		if not drained.has(k) and (best < 0 or _lakes[k].w > _lakes[best].w):
			best = k
	return best


## The water surface along one leg's points: from `top` down to `bottom` (-INF: wherever the land takes it),
## never rising, 1.2 m under the land it crosses (inside a lake: that lake's level; beside a river already
## placed: that river's, so the two meet at one level), never below the sea's; then smoothed (still never
## rising), so steep land gives rapids rather than steps.
func _river_levels(pts: PackedVector4Array, top: float, bottom: float) -> PackedFloat32Array:
	var n := pts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	# An estuary: a leg into the sea comes down to the sea's level ESTUARY_RUN m before the coast and rises
	# at most ESTUARY_RISE per m upstream of that, so its water above the sea never reaches the sea itself
	# (that stood over the sea as a stair of water and sand bars at the mouth).
	var cap := PackedFloat32Array()
	cap.resize(n)
	cap.fill(INF)
	if _island and bottom == WATER_LEVEL:
		var mouth := n - 1
		for k in n:
			if coast_offset(pts[k].x, pts[k].y) >= 0.0:
				mouth = k
				break
		var run := 0.0
		for k in range(mouth, -1, -1):
			if k < mouth:
				run += Vector2(pts[k].x, pts[k].y).distance_to(Vector2(pts[k + 1].x, pts[k + 1].y))
			cap[k] = WATER_LEVEL + maxf(0.0, run - ESTUARY_RUN) * ESTUARY_RISE
		for k in range(mouth, n):
			cap[k] = WATER_LEVEL
	var s := top
	for k in n:
		var x := pts[k].x
		var z := pts[k].y
		var g := INF
		for lk in _lakes:
			if _lake_d(lk, x, z) < 1.05:
				g = minf(g, lk.w)
		var in_lake := g < INF
		if g == INF:
			var other := _river_info3(x, z)   # the legs placed before this one
			if other.y > 0.02 and other.x < _river_bank_end * 2.4 + HOLD_MARGIN:
				g = other.z
			else:
				g = base_height(x, z) - 1.2
		s = minf(s, g)
		if bottom > -INF:
			s = maxf(s, bottom)
		s = maxf(s if in_lake else minf(s, cap[k]), WATER_LEVEL)   # in a lake: the lake's level
		out[k] = s
	if bottom > -INF:
		out[n - 1] = maxf(bottom, WATER_LEVEL)
	var at_sea := PackedByteArray()   # where the water has come down to the sea's level: it stays there
	at_sea.resize(n)
	for k in n:
		at_sea[k] = 1 if out[k] <= WATER_LEVEL + 0.001 else 0
	var tmp := out.duplicate()
	for pass_i in 4:
		for k in range(1, n - 1):
			tmp[k] = (out[k - 1] + 2.0 * out[k] + out[k + 1]) * 0.25
		for k in range(1, n - 1):
			# pinned at sea: smoothing would lift the last stretch a little over the sea, and that sliver of
			# raised river (with its banks) stood in the sea as a stair of sand bars
			out[k] = WATER_LEVEL if at_sea[k] == 1 else tmp[k]
	return out


## Points every RIVER_STEP m from `from` to `to`, bent sideways by `bend` (up to 1.6 x river_warp_amp m, none at
## the ends), each with its strength: the river mask's creek-to-river size, faded in from 0 at a spring.
func _river_path(from: Vector2, to: Vector2, bend: FastNoiseLite, idx: int, spring: bool) -> PackedVector4Array:
	var out := PackedVector4Array()
	var length := from.distance_to(to)
	var n := maxi(int(length / RIVER_STEP), 2)
	var side := (to - from).normalized().orthogonal()
	for k in n + 1:
		var t := float(k) / n
		var q := from.lerp(to, t) + side * bend.get_noise_1d(t * length) * _river_warp_amp * 1.6 * sin(t * PI)
		var m := lerpf(0.45, 1.0, smoothstep(_river_mask_on - 0.3, _river_mask_on + 0.3, _river_mask.get_noise_2d(q.x, q.y)))
		if spring:
			m *= smoothstep(0.0, minf(300.0 / length, 0.4), t)   # the channel fades in over the first ~300 m
		out.append(Vector4(q.x, q.y, m, idx))
	return out


## True if no point of the path is within `r` m of `p`.
static func _path_clear_of(pts: PackedVector4Array, p: Vector2, r: float) -> bool:
	for q in pts:
		if Vector2(q.x, q.y).distance_squared_to(p) < r * r:
			return false
	return true


## Files every segment of _river_pts under each grid cell within valley reach of it (afresh).
func _index_river_segments() -> void:
	_rv_x = NAN
	var n := maxi(_river_pts.size() - 1, 0)
	_seg_a.resize(n)
	_seg_ab.resize(n)
	_seg_l2.resize(n)
	for k in n:
		var a := Vector2(_river_pts[k].x, _river_pts[k].y)
		var ab := Vector2(_river_pts[k + 1].x, _river_pts[k + 1].y) - a
		_seg_a[k] = a
		_seg_ab[k] = ab
		_seg_l2[k] = maxf(ab.length_squared(), 1e-6)
	var grid := {}
	var reach := _river_valley * 1.3
	for k in n:
		var a := _river_pts[k]
		var b := _river_pts[k + 1]
		if a.w != b.w:
			continue   # the next river starts here
		var lo := (Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)) / RIVER_CELL
		var hi := (Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)) / RIVER_CELL
		for cz in range(floori(lo.y), floori(hi.y) + 1):
			for cx in range(floori(lo.x), floori(hi.x) + 1):
				var c := Vector2i(cx, cz)
				var list: PackedInt32Array = grid.get(c, PackedInt32Array())
				list.append(k)   # a packed array is a value: store it back
				grid[c] = list
	# flattened: a lookup is two array reads, not a dictionary's hash
	var lo_c := Vector2i(1 << 30, 1 << 30)
	var hi_c := -lo_c
	for c: Vector2i in grid:
		lo_c = lo_c.min(c)
		hi_c = hi_c.max(c)
	_cell_lo = lo_c if not grid.is_empty() else Vector2i.ZERO
	_cell_w = hi_c.x - lo_c.x + 1 if not grid.is_empty() else 0
	_cell_h = hi_c.y - lo_c.y + 1 if not grid.is_empty() else 0
	_cell_at = PackedInt32Array()
	_cell_at.resize(_cell_w * _cell_h + 1)
	_cell_segs = PackedInt32Array()
	for i in _cell_w * _cell_h:
		_cell_at[i] = _cell_segs.size()
		var list: Variant = grid.get(_cell_lo + Vector2i(i % _cell_w, i / _cell_w))
		if list != null:
			_cell_segs.append_array(list)
	_cell_at[_cell_w * _cell_h] = _cell_segs.size()


## The river index cell at (x, z): Vector2i(first, end) into _cell_segs (first == end: no river near).
func _river_cell(x: float, z: float) -> Vector2i:
	var cx := floori(x / RIVER_CELL) - _cell_lo.x
	var cz := floori(z / RIVER_CELL) - _cell_lo.y
	if cx < 0 or cz < 0 or cx >= _cell_w or cz >= _cell_h:
		return Vector2i.ZERO
	var i := cz * _cell_w + cx
	return Vector2i(_cell_at[i], _cell_at[i + 1])


## The nearest counted river at (x, z): (distance m, strength, flow direction x, z), or (INF, 0, 0, 0) when
## none is within the valley's reach. The direction is downstream (spring to the sea or the map's edge).
func _river_line_at(x: float, z: float) -> Vector4:
	var hit := _nearest_river_seg(x, z)
	if hit.x < 0.0:
		return Vector4(INF, 0.0, 0.0, 0.0)
	var k := int(hit.x)
	var a4 := _river_pts[k]
	var b4 := _river_pts[k + 1]
	var dir := Vector2(b4.x - a4.x, b4.y - a4.y).normalized()
	return Vector4(hit.z, lerpf(a4.z, b4.z, hit.y), dir.x, dir.y)


## The nearest segment of the counted rivers to (x, z) within the valley's reach: (its first point's index,
## how far along it 0..1, distance m), or (-1, 0, INF).
func _nearest_river_seg(x: float, z: float) -> Vector3:
	var cell := _river_cell(x, z)
	if cell.x == cell.y:
		return Vector3(-1.0, 0.0, INF)
	var best := INF
	var out := Vector3(-1.0, 0.0, INF)
	var p := Vector2(x, z)
	for i in range(cell.x, cell.y):
		var k := _cell_segs[i]
		var a := _seg_a[k]
		var ab := _seg_ab[k]
		var t := clampf((p - a).dot(ab) / _seg_l2[k], 0.0, 1.0)
		var d2 := p.distance_squared_to(a + ab * t)
		if d2 < best:
			best = d2
			out = Vector3(k, t, sqrt(d2))
	if out.z > _river_valley * 1.3:
		return Vector3(-1.0, 0.0, INF)
	return out


## The nearest segment of a river leg other than the nearest segment's: (its first point's index, how far
## along 0..1, distance m), or (-1, 0, INF).
func _second_river_seg(x: float, z: float) -> Vector3:
	var cell := _river_cell(x, z)
	if cell.x == cell.y:
		return Vector3(-1.0, 0.0, INF)
	var p := Vector2(x, z)
	var best := INF
	var best_w := -1.0
	var second := INF
	var out := Vector3(-1.0, 0.0, INF)   # (segment, t, distance) of the second
	var first := Vector3(-1.0, 0.0, INF)
	for i in range(cell.x, cell.y):
		var k := _cell_segs[i]
		var a4 := _river_pts[k]
		var a := _seg_a[k]
		var ab := _seg_ab[k]
		var t := clampf((p - a).dot(ab) / _seg_l2[k], 0.0, 1.0)
		var d2 := p.distance_squared_to(a + ab * t)
		if d2 < best:
			if a4.w != best_w:
				second = best
				out = first
			best = d2
			best_w = a4.w
			first = Vector3(k, t, d2)
		elif a4.w != best_w and d2 < second:
			second = d2
			out = Vector3(k, t, d2)
	if out.x < 0.0:
		return Vector3(-1.0, 0.0, INF)
	return Vector3(out.x, out.y, sqrt(second))


## Every counted river segment within its valley of (x, z) cuts land `h0` (_carve_river with that segment's
## distance, strength and level); the lowest wins, rounded where two legs both cut (their banks curve into each
## other at a junction). Every segment, not only the nearest: where the nearest switched (two legs, or the arms of
## one leg bending back, at different strengths or levels) the land jumped. The same pass finds the nearest river
## (what _river_info3 gives at (x, z)) and keeps it in _rv; `h0` comes back unchanged where none is in reach.
func _carve_rivers(x: float, z: float, h0: float) -> float:
	_rv_x = x
	_rv_z = z
	_rv = Vector3(INF, 0.0, WATER_LEVEL)
	var cell := _river_cell(x, z)
	if cell.x == cell.y:
		return h0
	var p := Vector2(x, z)
	var far := _river_valley * 1.3
	var h1 := h0   # the lowest cut and its leg
	var w1 := -1.0
	var h2 := h0   # the lowest cut of any other leg
	var w2 := -1.0
	var best := INF   # the nearest segment (as _nearest_river_seg finds it)
	var best_k := -1
	var best_t := 0.0
	var wall_r := _river_valley * 0.2   # _bank_cap's
	var wall_k := maxf(VALLEY_WALL - _river_bank_slope, 0.0)
	var prev_k := -2   # the segment looked at before, and its `t` (32-bit, as _seg_dist2 gives it)
	var prev_t := 0.0
	for i in range(cell.x, cell.y):
		var k := _cell_segs[i]
		var a := _seg_a[k]
		var ab := _seg_ab[k]
		var t := clampf((p - a).dot(ab) / _seg_l2[k], 0.0, 1.0)
		var d2 := p.distance_squared_to(a + ab * t)
		if d2 < best:
			best = d2
			best_k = k
			best_t = t
		var td := Vector2(t, d2)   # = _seg_dist2(p, k)
		var last_k := prev_k
		var last_t := prev_t
		prev_k = k
		prev_t = td.x
		if td.y > far * far:
			continue
		var a4 := _river_pts[k]
		# Nearest at its start, where the segment before it on its leg is nearest at its end: the same spot, the
		# same cut; that one makes it. Only then: skipping more (a neighbour nearer elsewhere) jumped by a creek's
		# tip, where the strength changes fast along the leg.
		if td.x <= 0.0 and k > 0 and _river_pts[k - 1].w == a4.w \
				and (last_t if last_k == k - 1 else _seg_dist2(p, k - 1).x) >= 1.0:
			continue
		var d := sqrt(td.y)
		var m := lerpf(a4.z, _river_pts[k + 1].z, td.x) * (1.0 - smoothstep(_river_valley, far, d))
		if m <= 0.0:
			continue
		# _carve_river(h0, rv), inlined (the hot loop): the same maths, rv 32-bit as it was passed
		var rv := Vector3(d, m, lerpf(_river_lvl[k], _river_lvl[k + 1], td.x))
		var hc := h0
		var rd := rv.x
		var rm := rv.y
		var bank := rv.z + _river_bank_h
		if hc > bank:
			var v := (1.0 - smoothstep(0.0, _river_valley, rd)) * rm
			hc = lerpf(hc, bank + (hc - bank) * 0.12, v * v * (3.0 - 2.0 * v))
		var width := lerpf(0.35, 1.0, smoothstep(0.0, 1.0, rm))
		var reach := _river_bank_end * width
		var cap: float
		if rd < reach:
			cap = lerpf(rv.z + _river_bed, bank, smoothstep(_river_core * width, reach, rd))
		else:
			var out := rd - reach   # _bank_cap(bank, out)
			var u := maxf(out - _river_valley * 0.15, 0.0)
			var wall := u * u / (2.0 * wall_r) if u < wall_r else u - wall_r * 0.5
			cap = bank + out * _river_bank_slope + wall * wall_k
		cap = lerpf(cap, maxf(cap, hc), smoothstep(_river_valley * 1.0, _river_valley * 1.27, rd))   # _cap_release
		if cap < hc:
			hc = lerpf(hc, cap, smoothstep(0.0, 0.12, rm))
		if a4.w == w1:
			h1 = minf(h1, hc)
		elif a4.w == w2:
			h2 = minf(h2, hc)
			if h2 < h1:
				var th := h1
				var tw := w1
				h1 = h2
				w1 = w2
				h2 = th
				w2 = tw
		elif hc < h1:
			h2 = h1
			w2 = w1
			h1 = hc
			w1 = a4.w
		elif hc < h2:
			h2 = hc
			w2 = a4.w
	var hit := Vector3(best_k, best_t, sqrt(best))
	if hit.z > far:
		return h0   # no river in reach: _height doesn't carve here
	_rv = _rv_from_hit(hit)
	var k := RIVER_JOIN_ROUND * smoothstep(0.0, RIVER_JOIN_ROUND, h0 - h2)
	if k > 0.0:
		var kk := clampf(0.5 + 0.5 * (h2 - h1) / k, 0.0, 1.0)
		return lerpf(h2, h1, kk) - k * kk * (1.0 - kk)
	return h1


## Segment k (from _river_pts[k] to k + 1) to `p`: (how far along 0..1, squared distance).
func _seg_dist2(p: Vector2, k: int) -> Vector2:
	var a := _seg_a[k]
	var ab := _seg_ab[k]
	var t := clampf((p - a).dot(ab) / _seg_l2[k], 0.0, 1.0)
	return Vector2(t, p.distance_squared_to(a + ab * t))


## How many counted mountains found room (fewer than mountain_count when the area is too small for them).
func peak_count() -> int:
	return _peaks.size()


## Metres the ground sinks at (x, z): each biome's ground_dip by its weight.
func _ground_dip(x: float, z: float) -> float:
	var w := biome_weights(x, z)
	var d := 0.0
	for i in w.size():
		d += w[i] * _bdip[i]
	return d


## One landform at its mask's strength (noise region x share of its biomes).
func _apply_landform(k: int, x: float, z: float, h: float) -> float:
	var l := _landforms[k]
	var m := l.mask_at(x, z)
	if m <= 0.0:
		return h
	if not l.biomes.is_empty():
		var w := biome_weights(x, z)
		var share := 0.0
		for i in _landform_biomes[k]:
			share += w[i]
		m *= share
		if m <= 0.0:
			return h
	return lerpf(h, l.shape(x, z, h), m)


## The nearest counted river at (x, z): (distance in metres to its centre line, strength 0..1). Strength 0 =
## no river here.
func _river_info(x: float, z: float) -> Vector2:
	var r := _river_info3(x, z)
	return Vector2(r.x, r.y)


## _river_info with the river's water surface: (distance m, strength 0..1, water level). A river's surface
## falls along its course (from a lake or a spring up in the hills to the sea).
## Remembers the last point (base_height, then water_level_at or river_factor there, costs one scan).
func _river_info3(x: float, z: float) -> Vector3:
	if not _river_lines:
		return Vector3(INF, 0.0, WATER_LEVEL)
	if x == _rv_x and z == _rv_z:
		return _rv
	var hit := _nearest_river_seg(x, z)
	_rv_x = x
	_rv_z = z
	_rv = Vector3(INF, 0.0, WATER_LEVEL) if hit.x < 0.0 else _rv_from_hit(hit)
	return _rv


## _river_info3 from the nearest segment (_nearest_river_seg's result, one within reach).
func _rv_from_hit(hit: Vector3) -> Vector3:
	var k := int(hit.x)
	var m := lerpf(_river_pts[k].z, _river_pts[k + 1].z, hit.y)
	m *= 1.0 - smoothstep(_river_valley, _river_valley * 1.3, hit.z)
	return Vector3(hit.z, m, lerpf(_river_lvl[k], _river_lvl[k + 1], hit.y))


## The first open water from `from` along `dir` (x, z), within `reach` m: ground at least `depth` m under the
## water level (a lake, the sea or a river). Returns that point, or Vector2.INF if there is none. For a host
## checking a spot: can a fisher here cast a line, where does the float land.
func find_water(from: Vector2, dir: Vector2, reach: float, depth := 0.5, step := 1.0) -> Vector2:
	var d := dir.normalized()
	var t := 0.0
	while t <= reach:
		var q := from + d * t
		if get_height(q.x, q.y) < water_level_at(q.x, q.y) - depth:
			return q
		t += step
	return Vector2.INF


## ~1 inside the river channel, fading to 0 at RIVER_NEAR (30 m) from the waterline.
## Read-only; for ambience (running-water sound), bank vegetation, etc.
func river_factor(x: float, z: float) -> float:
	var rv := _river_info(x, z)
	if rv.y <= 0.0:
		return 0.0
	return (1.0 - smoothstep(_river_water_edge, _river_water_edge + _river_near, rv.x)) * smoothstep(0.0, 0.2, rv.y)


## Unit direction the river flows in at (x, z) (downstream: spring to sea or the map's edge), or Vector2.ZERO
## where there is no river within reach.
func river_flow_dir(x: float, z: float) -> Vector2:
	if _river_info(x, z).y <= 0.0:
		return Vector2.ZERO
	var l := _river_line_at(x, z)
	var dir := Vector2(l.z, l.w)
	# where two rivers meet, the flow turns from one into the other (halfway between them, half each)
	var s := _second_river_seg(x, z)
	if s.x >= 0.0 and s.z - l.x < 16.0:
		var k := int(s.x)
		var d2 := Vector2(_river_pts[k + 1].x - _river_pts[k].x, _river_pts[k + 1].y - _river_pts[k].y).normalized()
		var blend := dir.lerp(d2, 0.5 * (1.0 - smoothstep(0.0, 16.0, s.z - l.x)))
		if blend.length() > 0.2:
			dir = blend.normalized()
	return dir


## Biome `i`'s plant rule chances (LFBiomeDef.plants), as 32-bit floats.
func plant_chances(i: int) -> PackedFloat32Array:
	return _plant_p[i]


## True when open water (the sea, a lake or a river) lies within `reach` m of (x, z): probes the ground around the
## point on two rings. For LFPropRule.near_water.
func near_water(x: float, z: float, reach: float) -> bool:
	var here := get_height(x, z)
	var wl := water_level_at(x, z)
	if here < wl - 0.05:
		return true
	if here - wl > reach + 3.0:   # high above any water: a bank or cliff, not a shore
		return false
	for ring in [0.5, 1.0]:
		var r: float = reach * ring
		for k in 8:
			var a := k * TAU / 8.0
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if get_height(px, pz) < water_level_at(px, pz) - 0.05:
				return true
	return false


## The biome list in use (params.biomes, or the defaults), indexed like biome_weights.
func biomes() -> Array[LFBiomeDef]:
	return _biomes


## Soft biome weights, one per biome (biomes()), summing to 1. Temperature + moisture noise give a score
## per biome (LFBiomeDef.score); a softmax makes the borders blend instead of switching abruptly.
## 32-bit floats, rounded where the old Vector4 maths rounded, so the stock world stays bit for bit.
func biome_weights(x: float, z: float) -> PackedFloat32Array:
	var t := _temp.get_noise_2d(x, z)
	if _cold:
		t -= maxf(mountain_share(x, z), rim_share(x, z)) * MOUNTAIN_CHILL   # colder up a mountain or the rim
	var m := _moist.get_noise_2d(x, z)
	var n := _biomes.size()
	var w := PackedFloat32Array()
	w.resize(n)
	for i in n:
		w[i] = _biomes[i].score(t, m) if _bcustom else t * _bheat[i] + m * _bwet[i] + _bcommon[i]
	if not _bmin.is_empty():   # biomes only up high: below their height they give way to the others
		var hb := biome_height(x, z)
		for i in n:
			if _bmin[i] > -INF:
				w[i] += HEIGHT_IN * smoothstep(_bmin[i], _bmin[i] + _bup[i], hb) \
						- HEIGHT_OUT * (1.0 - smoothstep(_bmin[i] - _bfade[i], _bmin[i], hb))
			elif _snow_takes_over:   # the other biomes give way to the high biomes above the snow line
				w[i] -= HEIGHT_OUT * smoothstep(_snow_lo, _snow_lo + _snow_band, hb)
	var sum := 0.0
	for i in n:
		w[i] = exp(w[i] * _blend)
		sum += w[i]
	if _barea or _rg_on:   # the host's areas (and biome_regions) scale each biome before the blend, so borders between areas still blend
		var kept := 0.0
		var raw := w.duplicate()
		var loc := _rg.locate(x, z, region_center) if _rg_on else Vector4.ZERO
		for i in n:
			if _rg_on:
				var sa := _rg_fac[int(loc.x)][i]
				var sb := _rg_fac[int(loc.y)][i]
				var wedge := sa * loc.z + sb * (1.0 - loc.z)
				w[i] *= maxf(_rg_fac[_rg_fac.size() - 1][i] * loc.w + wedge * (1.0 - loc.w), 0.0)
			if _barea:
				w[i] *= maxf(biome_allowed(i, x, z), 0.0)
			kept += w[i]
		if kept > 0.0:
			sum = kept
		else:   # every biome forbidden here: the climate's choice
			w = raw
	_f32[0] = sum
	var s32 := _f32[0]
	for i in n:
		w[i] = w[i] / s32
	return w


## How far the ground within `radius` m of (x, z) rises or falls from the height at (x, z) (m, the largest
## difference; roads included): 0 on flat ground. Samples rings about 2 m apart. Use it to check a spot is flat
## enough for a building, a camp or a marker.
func max_step(x: float, z: float, radius: float) -> float:
	var h0 := get_height(x, z)
	var worst := 0.0
	var rings := maxi(1, ceili(radius / 2.0))
	for ri in range(1, rings + 1):
		var r := radius * float(ri) / float(rings)
		var n := maxi(6, ceili(TAU * r / 2.0))
		for k in n:
			var a := TAU * float(k) / float(n)
			worst = maxf(worst, absf(get_height(x + cos(a) * r, z + sin(a) * r) - h0))
	return worst


## How much biome `i` (an index into the map's biome list) may grow at (x, z): a factor on its weight before
## the biomes blend. 1 = as the climate says, 0 = never here, between = fainter. Override it in a subclass to
## give areas their own biomes (regions, islands, a cursed valley); a factor that fades over some metres keeps
## the borders between areas blended. Where every biome gets 0 the climate's weights stand. Called for every
## height and colour sample, also from worker threads: keep it cheap and read-only. When no subclass overrides
## it, it is never called and the world is the same bit for bit.
func biome_allowed(_i: int, _x: float, _z: float) -> float:
	return 1.0


## Which region of LFMapParams.biome_regions (x, z) is in: 0 .. count - 1, -1 in its central disc, and -1 when
## the map has no biome_regions. Cheap; safe from any thread once the map is set up.
func region_at(x: float, z: float) -> int:
	return _rg.region_at(x, z, region_center) if _rg != null else -1


## The creatures that roam at (x, z): one {"id": StringName, "weight": float, "rare": bool} per id, from the
## roamers of the biomes there (LFBiomeDef.roamers), each weighed by the biome's share and the roamer's own
## weight. `night` keeps the night-only ones and drops the day-only ones (the reverse by day); `include_rare`
## false drops the rare ones. Weights are relative, not normalised. Lowland Forge draws no creatures: your game
## maps the ids to its own. Reads the biome list, so call it from the main thread.
func roamers_at(x: float, z: float, night: bool, include_rare := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := {}   # id -> index in out
	var w := biome_weights(x, z)
	for i in w.size():
		if w[i] <= 0.0001:
			continue
		for r in _biomes[i].roamers:
			if r == null or r.id == &"" or r.weight <= 0.0:
				continue
			if (r.night_only and not night) or (r.day_only and night) or (r.rare and not include_rare):
				continue
			var add := w[i] * r.weight
			if at.has(r.id):
				var e: Dictionary = out[at[r.id]]
				e["weight"] = float(e["weight"]) + add
				e["rare"] = bool(e["rare"]) and r.rare
			else:
				at[r.id] = out.size()
				out.append({"id": r.id, "weight": add, "rare": r.rare})
	return out


## One roamer id drawn at random from roamers_at(x, z, night, include_rare) by weight, using `rng` (so a seeded
## RandomNumberGenerator keeps it deterministic). &"" when nothing roams there.
func roll_roamer(x: float, z: float, night: bool, rng: RandomNumberGenerator, include_rare := true) -> StringName:
	var list := roamers_at(x, z, night, include_rare)
	var total := 0.0
	for e in list:
		total += float(e["weight"])
	if total <= 0.0:
		return &""
	var pick := rng.randf() * total
	for e in list:
		pick -= float(e["weight"])
		if pick <= 0.0:
			return e["id"]
	return list[list.size() - 1]["id"]


## True when this generator's script (a subclass) overrides `method` of LFTerrainGenerator.
func _overrides(method: StringName) -> bool:
	var count := 0
	for m in (get_script() as Script).get_script_method_list():
		if m["name"] == method:
			count += 1
	return count > 1


## Index of the heaviest biome (the first on a tie).
static func dominant_biome(w: PackedFloat32Array) -> int:
	var best := 0
	var bv := w[0]
	for i in range(1, w.size()):
		if w[i] > bv:
			best = i
			bv = w[i]
	return best


## Pick a biome randomly in proportion to its weight (r in 0..1): gives ragged,
## natural-looking forest borders for props.
static func pick_biome(w: PackedFloat32Array, r: float) -> int:
	var acc := 0.0
	for i in w.size() - 1:
		acc += w[i]
		if r < acc:
			return i
	return w.size() - 1


## 1 = full forest density, small = natural clearing.
func forest_density(x: float, z: float) -> float:
	return 0.12 + 0.88 * smoothstep(-0.5, -0.1, _clearing.get_noise_2d(x, z))


## -1..1 age of the tree stand here (~50 m groves): young groves grow smaller trees, old ones bigger.
func stand_age(x: float, z: float) -> float:
	return clampf(_stand.get_noise_2d(x, z) * 1.6, -1.0, 1.0)


## 0..1 patchiness so flowers grow in clumps instead of uniformly.
func flower_patch(x: float, z: float) -> float:
	return smoothstep(0.0, 0.5, _flowers.get_noise_2d(x, z))


func biome_name_at(x: float, z: float) -> String:
	var h := get_height(x, z)
	if h < water_level_at(x, z) - 0.15:
		if river_factor(x, z) > 0.9:
			return "River"
		return "Sea" if coast_offset(x, z) > -60.0 else "Lake"
	if h < 0.8:
		return "Lakeshore"
	if h > _highland + _line_up:
		return "Rocky Highlands"
	return _biomes[dominant_biome(biome_weights(x, z))].name


## Footstep surface at (x, z): &"water", &"mud", &"sand", &"rock", &"forest" or &"grass".
## Mirrors shade_ground(): sand/mud near water, rock on steep or high ground, biome decides grass/forest.
func surface_at(x: float, z: float) -> StringName:
	var h := get_height(x, z)
	var wl := water_level_at(x, z)
	if h < wl - 0.1:
		return &"water"
	var dx := get_height(x + 1.0, z) - get_height(x - 1.0, z)
	var dz := get_height(x, z + 1.0) - get_height(x, z - 1.0)
	var ny := 1.0 / sqrt(1.0 + (dx * dx + dz * dz) * 0.25)
	if ny < 0.78 or h > _rock_mid:
		return &"rock"
	var above := h - wl   # sand and mud by the water, wherever its level
	var b := _biomes[dominant_biome(biome_weights(x, z))]
	if above < 1.2 and b.beach:
		if above < 0.5 and river_factor(x, z) > 0.3:  # river banks are muddy
			return &"mud"
		return &"mud" if (above < 0.35 and _moist.get_noise_2d(x, z) > 0.0) else &"sand"
	if b.dense_surface != &"" and forest_density(x, z) > b.dense_above:
		return b.dense_surface
	return b.surface


## How snowy the ground at (x, z) is, 0..1: the snow the terrain colouring lays there (height snow line, the
## biomes' snow and snow_cover settings), for a host that wants to dress something to match (a roof under snow).
func snow_at(x: float, z: float) -> float:
	var h := get_height(x, z)
	var look := _look_at(Vector2(x, z)) if _looks else PackedFloat32Array()
	var snow := 0.0
	if _snow_on:
		snow = smoothstep(_p.snow_height_start + _line_up, _p.snow_height_full + _line_up, h)
	if not look.is_empty():
		snow = maxf(snow * look[4], look[5] * smoothstep(-0.2, 0.4, h - water_level_at(x, z)))
	return clampf(snow, 0.0, 1.0)


func chunk_seed(c: Vector2i, salt: int) -> int:
	var h := world_seed * 374761393 + c.x * 668265263 + c.y * 2147483629 + salt * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	return h ^ (h >> 16)


# --- colours ---------------------------------------------------------------

## Ground colour from biome weights: each biome's ground_color, blended.
func biome_color(w: PackedFloat32Array) -> Color:
	var c := _biomes[0].ground_color * w[0]
	for i in range(1, w.size()):
		c += _biomes[i].ground_color * w[i]
	return c


## biome_color with the default biomes (for hosts that colour a map without a generator at hand).
static func biome_ground(w: PackedFloat32Array) -> Color:
	var c := GROUND_COLORS[0] * w[0]
	for i in range(1, mini(w.size(), GROUND_COLORS.size())):
		c += GROUND_COLORS[i] * w[i]
	return c


## Final ground colour of one triangle from biome base colour, height and slope, with this generator's params
## (sand on beaches, mud under water, rock on steep or high ground, snow on top). `water`: the water level
## there (water_level_at), so a lake up in the hills gets its own beach. `xz`: where it is; given (and cliffs on),
## the rock follows the rock layers (rock_layer): hard layers bare rock in bands one per layer, the steep ground of
## soft layers scree (scree_color). Without it the bands go by height (rock_strata_height).
func ground_shade(base: Color, h: float, ny: float, water := WATER_LEVEL, xz := Vector2.INF) -> Color:
	return _shade(base, h, ny, water, xz, _look_at(xz) if _looks and xz.is_finite() else PackedFloat32Array())


## The biomes' look settings blended by weight at `xz`: rock tint r, g, b, beach, snow, snow cover.
func _look_at(xz: Vector2) -> PackedFloat32Array:
	var w := biome_weights(xz.x, xz.y)
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for i in w.size():
		var t := _brock[i]
		out[0] += w[i] * t.r
		out[1] += w[i] * t.g
		out[2] += w[i] * t.b
		out[3] += w[i] * _bbeach[i]
		out[4] += w[i] * _bsnow[i]
		out[5] += w[i] * _bcover[i]
	return out


## ground_shade with the look settings already blended (`look`, _look_at; empty: none).
func _shade(base: Color, h: float, ny: float, water: float, xz: Vector2, look: PackedFloat32Array) -> Color:
	var c := base
	var rock_c := _p.rock_color
	var scree_c := _p.scree_color
	var sand_k := smoothstep(_p.beach_top, _p.beach_full, h - water)
	if not look.is_empty():
		var tint := Color(look[0], look[1], look[2])
		rock_c *= tint
		scree_c *= tint
		sand_k *= look[3]
	c = c.lerp(_p.sand_color, sand_k)
	c = c.lerp(_p.mud_color, smoothstep(-0.2, -2.0, h - water))
	var rock_s := smoothstep(_p.rock_slope_start, _p.rock_slope_full, ny)
	var rock_h := smoothstep(_p.rock_height_start + _line_up, _p.rock_height_full + _line_up, h) * 0.8
	c = c.lerp(rock_c, rock_s)
	c = c.lerp(rock_c, rock_h)
	# steepness past "all rock": 0 on ledges, 1 on near-vertical faces
	var steep := smoothstep(_p.rock_slope_full, _p.rock_slope_full - 0.35, ny)
	var rocky := maxf(rock_s, rock_h)
	if _p.cliffs > 0.0 and xz.is_finite() and rocky > 0.0:
		var lay := rock_layer(xz.x, xz.y, h)
		if lay.z == 0.0:
			# a soft layer: loose scree where it is steep; steeper than scree lies, rock with its dust (so the layers
			# still read as bands against the hard ones)
			c = c.lerp(scree_c, rock_s * lerpf(0.55, 1.0, smoothstep(0.4, 0.55, ny)))
		else:
			c = LFMeshBuilder.tint(c, 1.0 - 0.15 * rock_s)
		if _p.rock_strata > 0.0:   # one band of stone per layer, so the colour bands match the shape's
			var r := fposmod(sin(lay.x * 12.9898 + 4.1414) * 43758.5453, 1.0)
			c = LFMeshBuilder.tint(c, 1.0 + (r - 0.5) * 0.8 * _p.rock_strata * rocky)
	elif _p.rock_strata > 0.0:
		# a stable hash per band of height, so contours of lighter and darker stone run round a slope; eased from
		# one band into the next, else a steep face's triangles (metres apart in height) alternated as teeth
		var bh := h / _p.rock_strata_height
		var band := floorf(bh)
		var r0 := fposmod(sin(band * 12.9898 + 4.1414) * 43758.5453, 1.0)
		var r1 := fposmod(sin((band + 1.0) * 12.9898 + 4.1414) * 43758.5453, 1.0)
		var r := lerpf(r0, r1, smoothstep(0.0, 1.0, bh - band))
		c = LFMeshBuilder.tint(c, 1.0 + (r - 0.5) * 1.0 * _p.rock_strata * rocky)
	c = LFMeshBuilder.tint(c, 1.0 - 0.6 * _p.cliff_shade * steep)
	if _snow_on or (not look.is_empty() and look[5] > 0.0):
		var snow := 0.0
		if _snow_on:
			snow = smoothstep(_p.snow_height_start + _line_up, _p.snow_height_full + _line_up, h)
		if not look.is_empty():
			snow = maxf(snow * look[4], look[5] * smoothstep(-0.2, 0.4, h - water))
		snow *= 1.0 - _p.cliff_shade * (1.0 - smoothstep(0.35, 0.65, ny))
		c = c.lerp(_p.snow_color, snow)
	if not stamps.is_empty() and xz.is_finite():   # a stamp may colour its own ground: shade(x, z, h, ny, colour)
		for st: Object in stamps:
			if st.has_method(&"shade"):
				c = st.call(&"shade", xz.x, xz.y, h, ny, c)
	return c


## The colours of one 2 m grid quad, centre `xz`: (height, normal y, water level) of its two triangles in `t0` and
## `t1`. On gentle ground one colour per triangle (ground_shade); where either is steep enough for rock, one for the
## whole quad from their mean (else a ledge narrower than a quad shows as alternate green and grey triangles), and
## then it returns just that one.
func quad_shade(base: Color, xz: Vector2, t0: Vector3, t1: Vector3) -> PackedColorArray:
	var look := _look_at(xz) if _looks else PackedFloat32Array()   # one weighing for the quad
	if minf(t0.y, t1.y) >= _p.rock_slope_start:
		return PackedColorArray([_shade(base, t0.x, t0.y, t0.z, xz, look), _shade(base, t1.x, t1.y, t1.z, xz, look)])
	var m := (t0 + t1) * 0.5
	return PackedColorArray([_shade(base, m.x, m.y, m.z, xz, look)])


## How much more the colour jitter of steep facets is (a multiple of the usual one): 1 at full cliff_shade.
func cliff_jitter() -> float:
	return _p.cliff_shade * 1.5


## ground_shade with the default params (for hosts that colour a map without a generator at hand).
static func shade_ground(base: Color, h: float, ny: float) -> Color:
	var c := base
	c = c.lerp(SAND, smoothstep(1.5, 0.3, h))
	c = c.lerp(MUD, smoothstep(-0.2, -2.0, h))
	c = c.lerp(ROCK, smoothstep(0.9, 0.72, ny))
	c = c.lerp(ROCK, smoothstep(17.0, 25.0, h) * 0.8)
	c = c.lerp(SNOW, smoothstep(26.0, 30.0, h))
	return c


# --- height grid helpers (used for props so they sit on the faceted mesh) --

## Samples the chunk's height grid exactly as the mesh is triangulated.
## Returns (normal.x, normal.y, normal.z, height).
static func sample_grid(heights: PackedFloat32Array, lx: float, lz: float) -> Vector4:
	var fx := clampf(lx / STEP, 0.0, CELLS - 0.001)
	var fz := clampf(lz / STEP, 0.0, CELLS - 0.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var h00 := heights[j * VERTS + i]
	var h10 := heights[j * VERTS + i + 1]
	var h01 := heights[(j + 1) * VERTS + i]
	var h11 := heights[(j + 1) * VERTS + i + 1]
	var h: float
	var gx: float
	var gz: float
	if u + v <= 1.0:  # triangle (00, 10, 01)
		h = h00 + u * (h10 - h00) + v * (h01 - h00)
		gx = (h10 - h00) / STEP
		gz = (h01 - h00) / STEP
	else:  # triangle (10, 11, 01)
		h = h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)
		gx = (h11 - h01) / STEP
		gz = (h11 - h10) / STEP
	var n := Vector3(-gx, 1.0, -gz).normalized()
	return Vector4(n.x, n.y, n.z, h)


# --- spawn -----------------------------------------------------------------

## Picks the starting region (every biome inside the fog wall), then spirals out from its centre
## to find dry, gentle ground for the spawn.
func _find_spawn() -> void:
	# Every noise layer is 0 at the world origin, so searching from (0,0) made every seed's
	# spawn look alike. Start from a seed-dependent point up to ~3 km out instead.
	var r := RandomNumberGenerator.new()
	r.seed = hash(world_seed) ^ 0x5eed
	var best_c := Vector2.ZERO
	var best_score := -1.0
	for i in REGION_TRIES:
		var c := Vector2(r.randf_range(-3000.0, 3000.0), r.randf_range(-3000.0, 3000.0)).snapped(Vector2(6, 6))
		var score := region_score(c, start_radius)
		if score > best_score:
			best_score = score
			best_c = c
		if score >= REGION_MIN_SHARE:
			break
	region_center = best_c
	var center := best_c
	var best := center
	var best_h := -INF
	for ring in roundi(_p.spawn_search / 6.0):
		var count := maxi(1, ring * 6)
		for k in count:
			var a := TAU * float(k) / float(count)
			var p := center + Vector2(cos(a), sin(a)) * (ring * 6.0)
			var h := get_height(p.x, p.y)
			if h > best_h:
				best_h = h
				best = p
			if h < 2.0 or h > 9.0:
				continue
			var dx := get_height(p.x + 3.0, p.y) - get_height(p.x - 3.0, p.y)
			var dz := get_height(p.x, p.y + 3.0) - get_height(p.x, p.y - 3.0)
			if absf(dx) < 2.0 and absf(dz) < 2.0:
				spawn_xz = p
				spawn_height = h
				return
	spawn_xz = best
	spawn_height = best_h


## Share of land (0..1) covered by the RAREST biome inside a circle. 0 means at least one biome is missing.
func region_score(c: Vector2, radius: float) -> float:
	var counts := []
	counts.resize(_biomes.size())
	counts.fill(0)
	var land := 0
	var step := radius / 11.0
	for gx in range(-11, 12):
		for gz in range(-11, 12):
			var o := Vector2(gx, gz) * step
			if o.length() > radius * 0.92:  # keep a margin off the wobbly wall
				continue
			var p := c + o
			var h := get_height(p.x, p.y)
			if h < 0.8 or h > _highland:
				continue
			land += 1
			counts[dominant_biome(biome_weights(p.x, p.y))] += 1
	if land == 0:
		return 0.0
	return float(counts.min()) / float(land)
