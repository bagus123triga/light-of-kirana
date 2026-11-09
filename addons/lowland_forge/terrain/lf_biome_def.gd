@tool
class_name LFBiomeDef
extends Resource
## One biome: where it grows (climate), the ground colour and footstep surface, and its props. A list of
## them is LFMapParams.biomes; each place gets a weight per biome from the temperature and moisture noise
## (a softmax of `climate score`, so borders blend). Known by `name`, never by slot.
## Subclass it to score climate your own way (override `score`).

## The biome's name. Other settings refer to it by name, so keep it unique.
@export var name := "Meadow"
## Off: this biome is left out of the map (the others share its land). Tick only one for a single-biome map.
@export var enabled := true

@export_group("Climate")
## How much this biome likes hot places (negative = cold).
@export var likes_heat := 0.0
## How much this biome likes wet places (negative = dry).
@export var likes_wet := 0.0
## Higher = this biome covers more of the map.
@export var commonness := 0.0
## Only on high ground: below the map's Snow Line this biome gives way to the others.
@export var only_above := false
## With Only Above: never below this height (m), even if the Snow Line is lower.
@export var min_height := 0.0
## How many metres below Min Height it fades out.
@export_range(0.0, 50.0, 0.5, "or_greater", "suffix:m") var height_fade := 4.0

@export_group("Ground")
## Colour of this biome's open ground.
@export var ground_color := Color(0.50, 0.70, 0.26)
## Footstep surface name your game gets for this biome's ground.
@export var surface := &"grass"
## ... and where forest_density is above Dense Above (empty: never, the open surface everywhere).
@export var dense_surface := &""
## Forest density (0..1) above which the ground takes Dense Surface. Does nothing while Dense Surface is empty.
@export var dense_above := 0.5

@export_group("Look")
## Multiplies the colour of rock and scree on this biome's ground (white = unchanged): warm for sandstone, dark
## for ash, mossy green for a marsh. Blends with the neighbouring biome by weight.
@export var rock_tint := Color.WHITE
## Multiplies the colour of the grass, ferns and bushes (plain undergrowth) this biome grows (white = unchanged).
@export var grass_tint := Color.WHITE
## Sand and mud rims by the water. Off: this biome's own ground runs down to the water.
@export var beach := true
## Snow may settle on this biome's high ground (the map's snow line). Off: bare rock up the mountain instead.
@export var snow := true
## Snow lying here whatever the height (0 = only up high, 1 = white ground), so a snow biome is white by biome and
## not only by altitude. Rock cliffs stay bare.
@export_range(0.0, 1.0, 0.01) var snow_cover := 0.0
## Metres this biome lowers the ground where it weighs (0 = none), so a marsh holds standing water. It changes the
## land heights (a different map from the same seed), so only set it on biomes you mean to sink.
@export_range(0.0, 10.0, 0.1, "or_greater", "suffix:m") var ground_dip := 0.0

@export_group("Trees")
## Thin the trees out in places.
@export var clearings := true
## Tree rules. Keep their chances adding up to 1 or less.
@export var trees: Array[LFPropRule] = []

@export_group("Ground cover")
## Plant rules. Keep their chances adding up to 1 or less.
@export var plants: Array[LFPropRule] = []
## Share of the 8 m cells with a rock (0 = none; the map's rock density setting scales it)...
@export_range(0.0, 1.0, 0.001) var rock_chance := 0.3
## ... and how strongly small rocks win (higher = more pebbles, lower = more boulders; 1 = an even mix).
@export var rock_size_bias := 2.4
## How often fallen logs appear (0 = none).
@export_range(0.0, 1.0, 0.001) var log_chance := 0.0
## Extra chance (added to a base chance) that a log grows mushrooms here. 0 = the base chance only.
@export var log_mushroom_bonus := 0.0

@export_group("Roamers")
## The creatures that roam here: ids of your own, picked by weight. Lowland Forge draws none; ask
## LFTerrainGenerator.roamers_at / roll_roamer and map the id to your creature. Does not change the terrain.
@export var roamers: Array[LFRoamer] = []

@export_group("Forage")
## How good a home this is for berry bushes (0..1, 0 = none). Dense forest cuts it by up to 70%.
@export_range(0.0, 1.0, 0.01) var berry_habitat := 0.0
## How good a home this is for mushroom patches (0..1; 0 = none, apart from the damp low ground, see Dryness).
@export_range(0.0, 1.0, 0.01) var mushroom_habitat := 0.0
## How much this biome dries out the damp ground near water (0 to 1).
@export_range(0.0, 1.0, 0.01) var dryness := 0.0


## This biome's climate score at temperature `t` and moisture `m` (both -1..1).
func score(t: float, m: float) -> float:
	return t * likes_heat + m * likes_wet + commonness


## The stock biomes, in the order of LFTerrainGenerator.Biome: Meadow, Pine Forest, Birch Woods, Old Growth.
static func defaults() -> Array[LFBiomeDef]:
	var K := LFPropMeshes.Kind
	var meadow := _make("Meadow", 0.0, -1.6, -0.3, Color(0.50, 0.70, 0.26))
	meadow.clearings = false
	meadow.trees = [LFPropRule.make(K.BROAD, 0.035, {"scale": 0.8}), LFPropRule.make(K.BIRCH, 0.025)]
	meadow.plants = [LFPropRule.make(K.GRASS, 0.5, {"river_bonus": true}), LFPropRule.make(K.FLOWER, 0.3, {"patchy": true}),
			LFPropRule.make(K.BUSH, 0.04)]
	meadow.rock_chance = 0.3
	meadow.berry_habitat = 0.55
	meadow.mushroom_habitat = 0.02
	meadow.dryness = 0.5
	meadow.roamers = [LFRoamer.make(&"rabbit", 3.0), LFRoamer.make(&"deer", 2.0), LFRoamer.make(&"fox", 0.8), LFRoamer.make(&"crow", 1.0, {"day_only": true}), LFRoamer.make(&"owl", 0.6, {"night_only": true}), LFRoamer.make(&"boar", 0.4, {"rare": true})]
	var pine := _make("Pine Forest", -1.6, 0.0, -0.2, Color(0.20, 0.38, 0.19))
	pine.surface = &"forest"
	pine.trees = [LFPropRule.make(K.PINE, 0.8, {"scale": 1.1}), LFPropRule.make(K.BIRCH, 0.03, {"from_top": true})]
	pine.plants = [LFPropRule.make(K.FERN, 0.25, {"river_bonus": true}), LFPropRule.make(K.GRASS, 0.1, {"river_bonus": true}),
			LFPropRule.make(K.BUSH, 0.03)]
	pine.rock_chance = 0.15
	pine.log_chance = 0.05
	pine.berry_habitat = 0.03
	pine.mushroom_habitat = 0.12
	pine.roamers = [LFRoamer.make(&"deer", 2.0), LFRoamer.make(&"boar", 1.2), LFRoamer.make(&"wolf", 1.0, {"night_only": true}), LFRoamer.make(&"owl", 1.0, {"night_only": true}), LFRoamer.make(&"fox", 0.8), LFRoamer.make(&"bear", 0.3, {"rare": true})]
	var birch := _make("Birch Woods", 0.0, 0.0, 0.0, Color(0.58, 0.74, 0.32))
	birch.dense_surface = &"forest"
	birch.trees = [LFPropRule.make(K.BIRCH, 0.5), LFPropRule.make(K.PINE, 0.05), LFPropRule.make(K.BROAD, 0.02, {"from_top": true})]
	birch.plants = [LFPropRule.make(K.GRASS, 0.3, {"river_bonus": true}), LFPropRule.make(K.FLOWER, 0.2, {"patchy": true}),
			LFPropRule.make(K.BUSH, 0.05), LFPropRule.make(K.FERN, 0.05, {"river_bonus": true})]
	birch.rock_chance = 0.1
	birch.log_chance = 0.012
	birch.berry_habitat = 1.0
	birch.mushroom_habitat = 0.12
	birch.roamers = [LFRoamer.make(&"deer", 2.5), LFRoamer.make(&"rabbit", 1.5), LFRoamer.make(&"fox", 1.0), LFRoamer.make(&"crow", 1.0, {"day_only": true}), LFRoamer.make(&"owl", 0.8, {"night_only": true}), LFRoamer.make(&"wolf", 0.4, {"night_only": true, "rare": true})]
	var old := _make("Old Growth", 0.8, 1.4, -0.3, Color(0.16, 0.30, 0.15))
	old.surface = &"forest"
	old.trees = [LFPropRule.make(K.BROAD, 0.2, {"scale_min": 1.3, "scale_max": 1.9})]
	old.plants = [LFPropRule.make(K.FERN, 0.25, {"river_bonus": true}), LFPropRule.make(K.BUSH, 0.04),
			LFPropRule.make(K.GRASS, 0.05, {"river_bonus": true})]
	old.rock_chance = 0.45
	old.rock_size_bias = 1.4
	old.log_chance = 0.21
	old.log_mushroom_bonus = 0.3
	old.berry_habitat = 0.08
	old.mushroom_habitat = 1.0
	old.roamers = [LFRoamer.make(&"boar", 1.5), LFRoamer.make(&"deer", 1.0), LFRoamer.make(&"bear", 0.6), LFRoamer.make(&"wolf", 1.0, {"night_only": true}), LFRoamer.make(&"owl", 1.2, {"night_only": true}), LFRoamer.make(&"bat", 0.8, {"night_only": true})]
	return [meadow, pine, birch, old]


static func _make(n: String, heat: float, wet: float, common: float, col: Color) -> LFBiomeDef:
	var b := LFBiomeDef.new()
	b.name = n
	b.likes_heat = heat
	b.likes_wet = wet
	b.commonness = common
	b.ground_color = col
	return b
