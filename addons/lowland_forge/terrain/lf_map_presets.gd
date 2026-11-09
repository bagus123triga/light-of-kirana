@tool
class_name LFMapPresets
extends RefCounted
## Ready-made maps: whole LFMapParams to start from (the land, its biomes, its props). Each call builds fresh
## params, so editing one never changes another map's. The Map Baker's *Preset* picker uses these; in code:
##
##   gen.params = LFMapPresets.make("Badlands")
##
## Every biome (the four defaults and every LFBiomePresets one) is listed in a preset's biomes, those the
## preset doesn't use unticked, so Biomes On can tick them back.

## Every preset's name, in a stable order.
const NAMES: Array[String] = ["Classic Island", "Highland Island", "Mountain Valley", "Rolling Plains",
		"Deep Forest", "Badlands", "Frozen Isle", "Great Mountains", "Deep Valleys"]


## A new preset by name (case and `_` / `-` for spaces don't matter), or null if there is none.
static func make(preset_name: String) -> LFMapParams:
	match preset_name.to_lower().replace("_", " ").replace("-", " "):
		"classic island":
			return classic_island()
		"highland island":
			return highland_island()
		"mountain valley":
			return mountain_valley()
		"rolling plains":
			return rolling_plains()
		"deep forest":
			return deep_forest()
		"badlands":
			return badlands()
		"frozen isle":
			return frozen_isle()
		"great mountains":
			return great_mountains()
		"deep valleys":
			return deep_valleys()
	push_warning("Lowland Forge: no map preset '%s' (valid: %s); returning null." % [preset_name, ", ".join(NAMES)])
	return null


## The stock island (what a new Map Baker starts with): meadows, pine, birch and old growth, one lake and a
## river from the high ground through it to the coast.
static func classic_island() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Meadow", "Pine Forest", "Birch Woods", "Old Growth"])
	p.natural_lakes = false
	p.lake_count = 1
	return p


## An island with two snow-capped mountains and steeper ridges.
static func highland_island() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Meadow", "Pine Forest", "Birch Woods", "Old Growth",
			"Frozen Highlands"])
	p.ridge_height = 26.0
	p.mountain_height = 120.0
	p.mountain_count = 2   # two peaks on every seed (ranges by cover could miss a small island)
	p.mountain_flats = 0.15   # peaks, not tiered tops
	return p


## A green valley closed in by a rim of mountains, three peaks inside it (snow on the heights), a river from
## each peak to a lake.
static func mountain_valley() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Meadow", "Pine Forest", "Birch Woods", "Old Growth",
			"Frozen Highlands"])
	p.boundary = LFMapParams.Boundary.MOUNTAINS
	p.mountain_height = 70.0
	p.mountain_count = 3
	p.mountain_flats = 0.6
	p.lake_count = 1
	p.lake_size = 260.0
	p.river_count = 3   # one from each peak down to the lake
	return p


## Endless open country: broad hills, meadows and birch woods, few trees.
static func rolling_plains() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Meadow", "Birch Woods"])
	p.boundary = LFMapParams.Boundary.OPEN
	p.base_height = 6.0   # fewer hollows below the water: a few lakes, not a lake district
	p.hills_height = 14.0
	p.hills_freq = 0.003
	p.ridge_height = 8.0
	p.tree_density = 0.6
	p.climate_freq = 0.0015
	return p


## Endless forest: pine, birch and old growth, close-packed trees, little open ground.
static func deep_forest() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Pine Forest", "Birch Woods", "Old Growth"])
	p.boundary = LFMapParams.Boundary.OPEN
	p.base_height = 5.0
	p.hills_height = 12.0
	p.tree_density = 1.8
	p.ground_cover_density = 1.2
	return p


## Dry, broken land: desert and ash, mesas ringed by layered cliff bands, terraced cliffs cut by gorges, sparse
## props.
static func badlands() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Desert", "Ash Barrens"])
	p.boundary = LFMapParams.Boundary.OPEN
	p.base_height = 12.0   # dry: only the deepest hollows and the gorge floors hold water
	p.hills_height = 18.0
	p.ridge_height = 24.0
	p.prop_density = 0.6
	p.river_count = 0   # the gorges are its watercourses
	p.rock_height_start = 34.0   # raised land: rock only on the tops...
	p.rock_height_full = 46.0
	p.snow_height_start = 900.0   # ... and never snow
	p.snow_height_full = 1000.0
	p.highland_height = 40.0
	p.mountain_height = 60.0   # mesas: flat-topped, ringed by bands of cliff and scree
	p.mountain_count = 3
	p.mountain_size = 260.0
	p.mountain_cover = 0.25
	p.mountain_flats = 0.85
	p.cliffs = 0.9
	p.cliff_rocks = 0.6
	p.cliff_layer_min = 4.0
	p.cliff_layer_max = 9.0
	p.cliff_hard_share = 0.7
	p.cliff_dip = 0.02
	p.rock_strata = 0.8
	p.rock_color = Color(0.6, 0.42, 0.32)   # red-brown sandstone
	p.scree_color = Color(0.72, 0.58, 0.44)
	var cliffs := LFTerraceLayer.new()
	cliffs.id = "badlands_cliffs"
	cliffs.face = 0.15
	cliffs.mask_from = -0.4   # cliffs over most of the land, not in patches
	cliffs.mask_to = -0.1
	var gorges := LFGorgeLayer.new()
	gorges.id = "badlands_gorges"
	p.landforms.append(cliffs)
	p.landforms.append(gorges)
	return p


## A cold island: snowfields and snow pines, a pine forest coast, mountains.
static func frozen_isle() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Pine Forest", "Frozen Highlands"])
	for b in p.biomes:
		if b.name == "Frozen Highlands":
			b.commonness += 0.8   # snow over most of it, pine in the milder corners
			b.only_above = false   # down to the shore
	p.mountain_height = 70.0
	p.mountain_count = 2   # peaks on every seed (ranges by cover could miss a small island)
	p.cliffs = 0.7   # dark rock bands through the snow
	return p


## A mountain land: ranges with peaks of 300 to 500 m, snow high up, lakes in the highlands, rivers running down.
## Built for a destination of its own (an island you fly to); the stock height scale is 30 m, so the rock and
## snow lines, the biome line and the lake and river counts are all set for the 400 m scale here.
static func great_mountains() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Meadow", "Pine Forest", "Birch Woods", "Old Growth",
			"Frozen Highlands"])
	p.natural_lakes = false   # the lakes are the counted ones, up in the highlands
	p.mountain_height = 420.0
	p.mountain_count = 0   # ranges
	p.mountain_size = 2400.0
	p.mountain_cover = 0.55
	p.mountain_flats = 0.1   # crags, not shelves
	p.mountain_area = 2600.0
	p.mountain_foot_slope = 0.9   # a coast a mountain can rise from quickly
	p.ridge_height = 30.0
	p.hills_height = 16.0
	p.rock_height_start = 90.0
	p.rock_height_full = 150.0
	p.snow_height_start = 220.0
	p.snow_height_full = 300.0
	p.highland_height = 160.0
	p.snow_line = 0.8   # snow only on the peaks
	p.snow_takes_over = true   # and no forest patches among it
	p.spawn_search = 1500.0   # flat ground may be far from the middle of a range
	p.cliff_layer_min = 8.0
	p.cliff_layer_max = 24.0
	p.lake_count = 4
	p.lake_size = 300.0
	p.highland_lakes = 0.6
	p.river_count = 3
	return p


## Wide deep valleys between mountain ranges: green floors for rivers, roads and towns, mountainsides above.
static func deep_valleys() -> LFMapParams:
	var p := _with_biomes(LFMapParams.new(), ["Meadow", "Pine Forest", "Birch Woods", "Old Growth",
			"Frozen Highlands"])
	p.natural_lakes = false
	p.coast_band = 450.0   # a long slope down to the beach, not a cliff
	p.base_height = 110.0   # an upland the valleys are cut into: where it is lower than depth, the floor is flat
	p.hills_height = 45.0
	p.hills_freq = 0.0025
	p.ridge_height = 24.0
	p.mountain_height = 150.0   # on top of it, mountains between the valleys
	p.mountain_count = 0
	p.mountain_size = 1800.0
	p.mountain_cover = 0.4
	p.mountain_flats = 0.2
	p.mountain_area = 2600.0
	p.mountain_foot_slope = 0.9
	p.rock_height_start = 190.0
	p.rock_height_full = 260.0
	p.snow_height_start = 300.0
	p.snow_height_full = 350.0
	p.highland_height = 220.0
	p.snow_line = 0.8
	p.snow_takes_over = true
	p.spawn_search = 1500.0
	p.cliff_layer_min = 8.0
	p.cliff_layer_max = 20.0
	p.lake_count = 2
	p.lake_size = 220.0
	p.highland_lakes = 0.0
	p.river_count = 2
	var v := LFValleyLayer.new()
	v.id = "deep_valleys"
	v.depth = 125.0
	v.floor_half = 90.0
	v.floor_min = 6.0   # dry grass floors a spawn and a village can stand on
	v.top_half = 340.0
	v.freq = 0.0005
	p.landforms.append(v)
	return p


## `p` with every default and preset biome listed and only those named in `on` ticked.
static func _with_biomes(p: LFMapParams, on: Array[String]) -> LFMapParams:
	var have := {}
	for b in p.biomes:
		have[b.name] = true
	for b in LFBiomePresets.all():
		if not have.has(b.name):
			p.biomes.append(b)
	for b in p.biomes:
		b.enabled = b.name in on
	return p
