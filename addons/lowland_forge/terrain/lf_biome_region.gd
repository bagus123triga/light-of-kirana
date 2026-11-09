@tool
class_name LFBiomeRegion
extends Resource
## One wedge of LFBiomeRegions (or its central disc): which biomes may grow there.

## Names of the biomes (LFBiomeDef.name) that grow here. Empty = every biome, as the climate says.
@export var biomes := PackedStringArray()
## How much the listed biomes are favoured against the climate (1 = as it says, 2 = twice the weight, below 1 =
## fainter). Does nothing while Biomes is empty.
@export_range(0.0, 10.0, 0.05, "or_greater") var favour := 1.0
## How much the biomes NOT listed still grow here (0 = never, 1 = as the climate says). Does nothing while Biomes
## is empty.
@export_range(0.0, 1.0, 0.01) var others := 0.0
