@tool
class_name LFRoamer
extends Resource
## One kind of creature that roams a biome: an id of your own choosing (&"deer", &"owl") and how likely it is.
## Lowland Forge draws no animals; it only says which ids belong where (LFBiomeDef.roamers,
## LFTerrainGenerator.roamers_at / roll_roamer) and your game maps an id to its own creature. Roamers never
## change the terrain, so editing them does not re-bake a map.

## What your game calls this creature. Any name; the stock biomes use plain ones (deer, wolf, owl ...).
@export var id: StringName = &""
## How common it is here compared with the biome's other roamers (the weights are relative).
@export_range(0.0, 20.0, 0.01, "or_greater") var weight := 1.0
## Only comes out at night (owls, bats, wolves).
@export var night_only := false
## Only seen by day (crows, butterflies).
@export var day_only := false
## A rare sight: roamers_at(include_rare = false) leaves it out, so a game can keep it for special moments.
@export var rare := false


## A new roamer. `options` may hold "night_only", "day_only" and "rare" (bool).
static func make(roamer_id: StringName, roamer_weight := 1.0, options := {}) -> LFRoamer:
	var r := LFRoamer.new()
	r.id = roamer_id
	r.weight = roamer_weight
	r.night_only = bool(options.get("night_only", false))
	r.day_only = bool(options.get("day_only", false))
	r.rare = bool(options.get("rare", false))
	return r
