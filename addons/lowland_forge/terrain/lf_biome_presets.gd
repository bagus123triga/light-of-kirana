@tool
class_name LFBiomePresets
extends RefCounted
## Ready-made biomes beyond the four defaults (LFBiomeDef.defaults()): add them to LFMapParams.biomes, alone
## (a single-biome map) or next to the defaults (each takes the climate it scores best in). Each call builds
## a fresh LFBiomeDef, so tweaking one never changes another map's.
##
##   var p := LFMapParams.new()
##   p.biomes.append(LFBiomePresets.make("Desert"))

## True: the presets are built exactly as before 1.1 (no look settings, no near-water rules, no ground dip), so a
## map baked with an older version re-bakes the same. Set it before calling make / all or a preset function.
static var legacy := false

## Every preset's name, in a stable order.
const NAMES: Array[String] = ["Desert", "Palm Coast", "Frozen Highlands", "Ash Barrens", "Drowned Marsh"]


## A new preset biome by name (case and `_` / `-` for spaces don't matter), or null if there is none.
static func make(biome_name: String) -> LFBiomeDef:
	match biome_name.to_lower().replace("_", " ").replace("-", " "):
		"desert":
			return desert()
		"palm coast":
			return palm_coast()
		"frozen highlands":
			return frozen_highlands()
		"ash barrens":
			return ash_barrens()
		"drowned marsh":
			return drowned_marsh()
	push_warning("Lowland Forge: no biome preset '%s' (valid: %s); returning null." % [biome_name, ", ".join(NAMES)])
	return null


## Every preset, freshly built, in NAMES order.
static func all() -> Array[LFBiomeDef]:
	var out: Array[LFBiomeDef] = []
	for n in NAMES:
		out.append(make(n))
	return out


# --- hot ----------------------------------------------------------------------


## Hot and dry: sand, cacti, dry scrub, scattered rocks.
static func desert() -> LFBiomeDef:
	var K := LFPropMeshes.Kind
	var b := _make("Desert", 1.6, -1.6, -0.6, Color(0.80, 0.64, 0.38))
	b.surface = &"sand"
	b.clearings = false
	b.trees = [LFPropRule.make(K.CACTUS, 0.03), LFPropRule.make(K.PALM, 0.0008, {"from_top": true})]
	b.plants = [LFPropRule.make(K.DRY_BUSH, 0.07), LFPropRule.make(K.GRASS, 0.02, {"river_bonus": true})]
	b.rock_chance = 0.25
	b.dryness = 1.0
	if not legacy:
		b.rock_tint = Color(1.3, 1.02, 0.78)   # sandstone, not mossy grey
		b.grass_tint = Color(1.6, 1.15, 0.5)   # dry yellow grass
		b.trees[1] = LFPropRule.make(K.PALM, 0.03, {"from_top": true, "near_water": 30.0})   # oasis palms
	b.roamers = [LFRoamer.make(&"lizard", 3.0), LFRoamer.make(&"camel", 0.6), LFRoamer.make(&"vulture", 1.0, {"day_only": true}), LFRoamer.make(&"scorpion", 1.0, {"night_only": true}), LFRoamer.make(&"fox", 0.8, {"night_only": true}), LFRoamer.make(&"snake", 0.5, {"rare": true})]
	return b


## Hot and wet: palms over pale grass and flowering bushes.
static func palm_coast() -> LFBiomeDef:
	var K := LFPropMeshes.Kind
	var b := _make("Palm Coast", 1.4, 0.8, -0.35, Color(0.42, 0.64, 0.24))
	b.trees = [LFPropRule.make(K.PALM, 0.13, {"scale_min": 0.85, "scale_max": 1.25}), LFPropRule.make(K.BROAD, 0.003, {"from_top": true})]
	b.plants = [LFPropRule.make(K.GRASS, 0.35, {"river_bonus": true}), LFPropRule.make(K.FERN, 0.08, {"river_bonus": true}),
			LFPropRule.make(K.BUSH, 0.06), LFPropRule.make(K.FLOWER, 0.08, {"patchy": true})]
	b.rock_chance = 0.12
	b.berry_habitat = 0.2
	b.dryness = 0.3
	if not legacy:
		b.trees[0].near_water = 60.0   # palms on the coast and by rivers...
		b.trees.append(LFPropRule.make(K.PALM, 0.012))   # ... a few inland
	b.roamers = [LFRoamer.make(&"crab", 3.0), LFRoamer.make(&"gull", 2.0, {"day_only": true}), LFRoamer.make(&"monkey", 1.0), LFRoamer.make(&"parrot", 1.0, {"day_only": true}), LFRoamer.make(&"frog", 0.8), LFRoamer.make(&"turtle", 0.3, {"rare": true})]
	return b


# --- cold and dead ------------------------------------------------------------


## Cold: snow ground, snow-laden pines, rocks.
static func frozen_highlands() -> LFBiomeDef:
	var K := LFPropMeshes.Kind
	var b := _make("Frozen Highlands", -3.0, 0.0, -0.9, Color(0.88, 0.90, 0.94))
	b.surface = &"snow"
	b.only_above = true   # snow on the heights, not in patches beside the pines
	b.trees = [LFPropRule.make(K.SNOW_PINE, 0.18)]
	b.plants = [LFPropRule.make(K.GRASS, 0.03), LFPropRule.make(K.DRY_BUSH, 0.02)]
	b.rock_chance = 0.35
	b.dryness = 0.8
	if not legacy:
		b.beach = false
		b.snow_cover = 0.8
		b.rock_tint = Color(0.92, 0.98, 1.1)
		b.grass_tint = Color(1.25, 1.3, 1.4)   # pale, frosted
	b.roamers = [LFRoamer.make(&"goat", 2.0), LFRoamer.make(&"hare", 1.5), LFRoamer.make(&"wolf", 1.0), LFRoamer.make(&"owl", 0.6, {"night_only": true}), LFRoamer.make(&"bear", 0.3, {"rare": true})]
	return b


## Burnt land: grey ash, dead trees, dry scrub, the odd crystal.
static func ash_barrens() -> LFBiomeDef:
	var K := LFPropMeshes.Kind
	var b := _make("Ash Barrens", 0.5, -2.2, -0.5, Color(0.27, 0.25, 0.24))
	b.surface = &"rock"
	b.clearings = false
	b.trees = [LFPropRule.make(K.DEAD, 0.09)]
	b.plants = [LFPropRule.make(K.DRY_BUSH, 0.03), LFPropRule.make(K.CRYSTAL, 0.0006)]
	b.rock_chance = 0.5
	b.rock_size_bias = 1.8
	b.log_chance = 0.05
	b.dryness = 1.0
	if not legacy:
		b.surface = &"ash"
		b.beach = false
		b.snow = false
		b.rock_tint = Color(0.78, 0.76, 0.78)
		b.grass_tint = Color(1.5, 0.75, 0.9)   # scorched
	b.roamers = [LFRoamer.make(&"crow", 2.0, {"day_only": true}), LFRoamer.make(&"bat", 1.5, {"night_only": true}), LFRoamer.make(&"lizard", 1.0), LFRoamer.make(&"wolf", 0.6, {"night_only": true}), LFRoamer.make(&"snake", 0.4, {"rare": true})]
	return b


# --- wet ----------------------------------------------------------------------


## Waterlogged lowland: willows, reeds, mud, rotting logs and mushrooms.
static func drowned_marsh() -> LFBiomeDef:
	var K := LFPropMeshes.Kind
	var b := _make("Drowned Marsh", -0.2, 1.8, -0.4, Color(0.22, 0.26, 0.12))
	b.surface = &"mud"
	b.trees = [LFPropRule.make(K.WILLOW, 0.1, {"scale_min": 1.0, "scale_max": 1.5}),
			LFPropRule.make(K.DEAD, 0.05, {"from_top": true})]
	b.plants = [LFPropRule.make(K.REEDS, 0.6, {"river_bonus": true, "patchy": true}),
			LFPropRule.make(K.GRASS, 0.12, {"river_bonus": true}),
			LFPropRule.make(K.MUSHROOM, 0.03, {"patchy": true}), LFPropRule.make(K.FERN, 0.04)]
	b.rock_chance = 0.05
	b.log_chance = 0.3
	b.log_mushroom_bonus = 0.5
	b.mushroom_habitat = 0.8
	if not legacy:
		b.plants[0].near_water = 14.0   # reeds at the water, not across the dry ground
		b.plants.insert(1, LFPropRule.make(K.REEDS, 0.03, {"patchy": true}))
		b.grass_tint = Color(0.72, 0.82, 0.55)
		b.rock_tint = Color(0.8, 0.95, 0.7)   # mossy
		b.ground_dip = 1.6
	b.roamers = [LFRoamer.make(&"frog", 3.0), LFRoamer.make(&"heron", 1.5, {"day_only": true}), LFRoamer.make(&"duck", 1.5, {"day_only": true}), LFRoamer.make(&"snake", 0.8), LFRoamer.make(&"owl", 0.8, {"night_only": true}), LFRoamer.make(&"otter", 0.3, {"rare": true})]
	return b


static func _make(n: String, heat: float, wet: float, common: float, col: Color) -> LFBiomeDef:
	var b := LFBiomeDef.new()
	b.name = n
	b.likes_heat = heat
	b.likes_wet = wet
	b.commonness = common
	b.ground_color = col
	return b
