@tool
class_name LFPropRule
extends Resource
## One kind of prop a biome grows, and how often (LFBiomeDef.trees / plants). Each placement cell rolls once:
## rules take turns along the roll from 0 up (`chance` each), so the chances of a list add up; a rule
## `from_top` takes its share from 1 down instead (trees: the odd stray tree a clearing does not thin out).

## The prop's mesh (LFPropMeshes builds them). Trees use the tree kinds, plants the ground-cover kinds.
@export var kind := LFPropMeshes.Kind.GRASS
## Share of the cells this prop takes (0..1; 0 = never). The map's tree / cover density settings scale it.
@export_range(0.0, 1.0, 0.001) var chance := 0.1
## Trees only: take the share from the top of the roll, unaffected by clearings (forest density). Ignored for plants.
@export var from_top := false
## Trees: size (1 = normal). Ignored when Scale Max is above 0.
@export var scale := 1.0
## Trees: smallest random size, used with Scale Max.
@export var scale_min := 0.0
## Trees: the largest rolled size (0 = off: always Scale).
@export var scale_max := 0.0
## Plants: more of it on river banks (low ground beside a river). Ignored for trees.
@export var river_bonus := false
## Plants: grows in patches, thick in some places and sparse in others (flowers). Ignored for trees.
@export var patchy := false
## Only within this many metres of open water (sea, lake or river; 0 = anywhere): reeds at a shore, palms on a
## coast, an oasis. Costs a few ground probes per candidate, so keep it for the few rules that need it.
@export_range(0.0, 200.0, 0.5, "or_greater", "suffix:m") var near_water := 0.0


static func make(k: LFPropMeshes.Kind, c: float, flags := {}) -> LFPropRule:
	var r := LFPropRule.new()
	r.kind = k
	r.chance = c
	for key: String in flags:
		r.set(key, flags[key])
	return r
