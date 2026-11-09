@tool
class_name LFMapParams
extends Resource
## The settings that shape the land: island, height, rivers and ground colours. Hand one to
## LFTerrainGenerator (`gen.params = p` before setup) or save it as a `.tres` preset. Every default is the
## stock world (the LFTerrainGenerator constants of the same name), so `LFMapParams.new()` changes nothing.
## Read once at setup: changing a value afterwards needs a new setup.

@export_group("World")
## Radius (m) round the spawn that should reach every biome.
@export var start_radius := LFTerrainGenerator.START_RADIUS
## How far (m) from the start region's centre the spawn search looks for a flat, dry spot. A map with
## mountains all through its start region may need more than the default.
@export_range(60.0, 3000.0, 6.0, "or_greater", "suffix:m") var spawn_search := 240.0

## What stops the land: nothing (it runs on past the map), the sea (an island) or a rim of mountains.
enum Boundary { OPEN, ISLAND, MOUNTAINS }

@export_group("Boundary")
## Open: land runs off every edge. Island: sea all round. Mountains: a valley ringed by mountains.
@export var boundary := Boundary.ISLAND
## Same as boundary == ISLAND (true sets it; false sets OPEN if it was the island). Kept for code and for
## presets saved before boundary existed.
var island: bool:
	get:
		return boundary == Boundary.ISLAND
	set(v):
		if v:
			boundary = Boundary.ISLAND
		elif boundary == Boundary.ISLAND:
			boundary = Boundary.OPEN
@export_subgroup("Mountain Rim")
## Size of the valley inside the rim (m). The Map Baker sets it to the map's size.
@export var boundary_size := Vector2(2048.0, 2048.0)
## How high the mountain rim stands (m). Mountains boundary only.
@export_range(20.0, 300.0, 1.0, "or_greater", "suffix:m") var rim_height := 140.0
## How wide the mountain rim is (m). Mountains boundary only.
@export_range(50.0, 1000.0, 10.0, "or_greater", "suffix:m") var rim_width := 300.0
## Rivers leave the valley through a pass they cut in the rim, out past the map's edge (off: they end in a lake
## inside it). Mountains boundary only.
@export var rim_pass := false
## How wide a river's pass is across the rim's top (m); its floor is a fifth of that.
@export_range(60.0, 1000.0, 10.0, "or_greater", "suffix:m") var rim_pass_width := 320.0
@export_subgroup("Island Shape")
## Island radius (m). The Map Baker sets it to fit the map.
@export var island_radius := LFTerrainGenerator.ISLAND_R
## How many bulges the coastline has (one entry per wave).
@export var island_lobes: Array[int] = [2, 3, 5]
## How deep each wave of bulges is (share of the radius). Keep the total under 1.
@export var island_lobe_amp: Array[float] = [0.10, 0.06, 0.04]
## How ragged the coastline is (m).
@export var coast_noise := LFTerrainGenerator.COAST_NOISE_AMP
@export_subgroup("Island Coast")
## How far inland the land starts dropping to the sea (m).
@export var coast_band := LFTerrainGenerator.COAST_BAND
## How far out the sea floor drops to full depth (m).
@export var coast_shelf := LFTerrainGenerator.COAST_SHELF
## Height of the open sea floor (m).
@export var sea_floor := LFTerrainGenerator.SEA_FLOOR

@export_group("Height")
@export_subgroup("Hills")
## Average land height (m). The sea is at 0, so lower floods more land.
@export var base_height := 3.0
## Height of the rolling hills (m). 0 = flat.
@export var hills_height := 10.0
## Size of the hills: lower = broader.
@export var hills_freq := 0.0045
@export_subgroup("Ridges")
## Height of ridged bands of high ground (m). 0 = none.
@export var ridge_height := 18.0
## Spacing of the ridges: lower = further apart.
@export var ridge_freq := 0.0028
## Size of the areas with ridges: lower = bigger.
@export var ridge_mask_freq := 0.0016
@export_subgroup("Relief Variation")
## How much the hills and ridges change from region to region: 0 = the same everywhere, 1 = some regions flat
## lowland (no hills) and others twice as rugged. Gives snow, cliffs and long views on more maps.
@export_range(0.0, 1.0, 0.01) var relief_variation := 0.0
## How big those regions are (m): the distance over which the land goes from flat to rugged.
@export_range(200.0, 6000.0, 10.0, "or_greater", "suffix:m") var relief_size := 1500.0
@export_subgroup("Detail")
## Small bumps (m). 0 = smooth.
@export var detail_height := 1.2
## Size of the small bumps: higher = finer.
@export var detail_freq := 0.035
@export_subgroup("Landforms")
## Extra landforms such as cliffs (LFTerraceLayer) or gorges (LFGorgeLayer).
@export var landforms: Array[LFHeightLayer] = []
@export_subgroup("Mountains")
## How high mountains rise (m). 0 = no mountains. Snow needs a snow biome.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m") var mountain_height := 0.0
## 0: mountain ranges. 1 or more: that many separate peaks.
@export_range(0, 32, 1, "or_greater") var mountain_count := 0
## Width of a mountain (m).
@export_range(100.0, 2000.0, 10.0, "or_greater", "suffix:m") var mountain_size := 400.0
## How much land the ranges cover (0 to 1). Mountain Count 0 only.
@export_range(0.0, 1.0, 0.01) var mountain_cover := 0.4
## Flat shelves on the slopes: 0 = smooth, 1 = steps you can build on.
@export_range(0.0, 1.0, 0.01) var mountain_flats := 0.5
## Mountains, lakes and rivers go within this distance of the centre (m). The Map Baker sets it.
@export_range(100.0, 10000.0, 10.0, "or_greater", "suffix:m") var mountain_area := 1200.0
## How steeply a mountain may rise from an island's coast (rise over run). Mountains are kept under this
## ramp instead of being cut off by the coast, so they do not end in a wall. Island only.
@export_range(0.1, 2.0, 0.01) var mountain_foot_slope := 0.55

@export_group("Lakes")
## Also put lakes wherever the land dips below sea level.
@export var natural_lakes := true
## How many lakes. Lakes need room, so a small map may get fewer.
@export_range(0, 32, 1, "or_greater") var lake_count := 0
## Rough width of a lake (m).
@export_range(40.0, 1000.0, 10.0, "or_greater", "suffix:m") var lake_size := 240.0
## Width of the first lake (m), to make one big lake. 0 = same as the others.
@export_range(0.0, 3000.0, 10.0, "or_greater", "suffix:m") var big_lake := 0.0
## Share of lakes on mountain slopes (0 to 1). Needs Mountain Count above 0.
@export_range(0.0, 1.0, 0.05) var highland_lakes := 0.4

@export_group("Rivers")
## How many rivers. Each flows from high ground through the lakes in its path to the sea.
@export_range(0, 16, 1, "or_greater") var river_count := 1
## Where a river drops steeply, its water falls in waterfalls (off: it runs down in rapids).
@export var waterfalls := true
@export_subgroup("Layout")
## How much a river winds (m).
@export var river_warp_amp := LFTerrainGenerator.RIVER_WARP_AMP
## Length of the creek and full-river stretches: lower = longer.
@export var river_mask_freq := LFTerrainGenerator.RIVER_MASK_FREQ
## Higher = more creek, less full river.
@export var river_mask_on := LFTerrainGenerator.RIVER_MASK_ON
@export_subgroup("Channel")
## Steepness of the river banks: higher = steeper, rocky banks.
@export_range(0.1, 2.0, 0.01) var river_bank_slope := 0.35
## Depth of the river bed (m).
@export var river_bed := LFTerrainGenerator.RIVER_BED
## Half the width of the river bed (m).
@export var river_core := LFTerrainGenerator.RIVER_CORE
## Distance from the river's middle to the top of the bank (m).
@export var river_bank_end := LFTerrainGenerator.RIVER_BANK_END
## Height of the land beside the bank (m).
@export var river_bank_h := LFTerrainGenerator.RIVER_BANK_H
## Half the width of the valley round a river (m).
@export var river_valley := LFTerrainGenerator.RIVER_VALLEY
## Distance from the river's middle to the water's edge (m).
@export var river_water_edge := LFTerrainGenerator.RIVER_WATER_EDGE
## How far from a river still counts as near it (m), for river sounds.
@export var river_near := LFTerrainGenerator.RIVER_NEAR

@export_group("Biomes")
## The biomes. Untick one to leave it out.
@export var biomes: Array[LFBiomeDef] = LFBiomeDef.defaults()
## Where snow starts: 0 = the lowlands, 1 = only the highest peak. For biomes with Only Above.
@export_range(0.0, 1.0, 0.05) var snow_line := 0.5
## Above the snow line the high biomes (Only Above) take over completely: forests and meadows don't grow in
## patches among the snow. Off: the climate still mixes them in (the stock look).
@export var snow_takes_over := false
## How sharp biome borders are: higher = harder edges.
@export var biome_blend := 5.0
## Size of the biome regions: lower = bigger.
@export var climate_freq := 0.0022
## Splits the land into wedges round the map's centre, each with its own allowed biomes (empty = the climate
## decides everywhere, as before). Read a point's wedge with LFTerrainGenerator.region_at.
@export var biome_regions: LFBiomeRegions = null

@export_group("Props")
## How many props: 0 = none, 1 = normal, 2 = about twice as many.
@export_range(0.0, 3.0, 0.05) var prop_density := 1.0
## How many trees and logs.
@export_range(0.0, 3.0, 0.05) var tree_density := 1.0
## How many rocks.
@export_range(0.0, 3.0, 0.05) var rock_density := 1.0
## How much grass, flowers, bushes and mushrooms.
@export_range(0.0, 3.0, 0.05) var ground_cover_density := 1.0
## Your own meshes in place of built-in prop kinds (each entry one kind). Empty: the built-in looks.
@export var prop_swaps: Array[LFPropSwap] = []

@export_group("Ground")
@export_subgroup("Colours")
## Beaches and river sand.
@export var sand_color := LFTerrainGenerator.SAND
## Wet ground and river banks.
@export var mud_color := LFTerrainGenerator.MUD
## Cliffs, steep slopes and high ground.
@export var rock_color := LFTerrainGenerator.ROCK
## Snow on the heights.
@export var snow_color := LFTerrainGenerator.SNOW
## Loose stone (scree) on the steep ground below cliff bands (with cliffs on).
@export var scree_color := LFTerrainGenerator.SCREE
@export_subgroup("Beach")
## Sand starts this high above the water (m).
@export var beach_top := 1.5
## All sand below this height above the water (m).
@export var beach_full := 0.3
@export_subgroup("Rock and Snow")
## Slopes steeper than this start to turn to rock (1 = flat, lower = steeper).
@export var rock_slope_start := 0.9
## Slopes steeper than this are all rock.
@export var rock_slope_full := 0.72
## Ground starts turning to rock at this height (m).
@export var rock_height_start := 17.0
## All rock above this height (m).
@export var rock_height_full := 25.0
## Snow starts at this height (m), with a snow biome.
@export var snow_height_start := 26.0
## All snow above this height (m).
@export var snow_height_full := 30.0
## Rock gets bands of lighter and darker stone (0 = flat colour, 1 = strong bands), so a cliff reads as layers
## of rock instead of one grey sheet. With cliffs on, one band per rock layer.
@export_range(0.0, 1.0, 0.01) var rock_strata := 0.5
## Height of one band of rock (m) where cliffs is 0 (else the rock layers set the bands).
@export_range(0.5, 12.0, 0.1, "suffix:m") var rock_strata_height := 3.0
## Steep faces turn darker, and snow slides off them (0 = off, 1 = strong); ledges facing up stay light.
@export_range(0.0, 1.0, 0.01) var cliff_shade := 0.4
## Places above this height (m) are Rocky Highlands; the spawn avoids them.
@export var highland_height := 24.0
@export_subgroup("Cliffs")
## Cliff bands on steep mountainsides (0 = smooth slopes, 1 = on every steep slope): hard rock layers stand as
## steep risers with a shelf on top, the soft layers between lie back as scree slopes. Only on the mountains, and
## not by a river.
@export_range(0.0, 1.0, 0.01) var cliffs := 0.6
## Thinnest rock layer (m). Under about 4 m the 2 m mesh can't show a band cleanly.
@export_range(2.0, 40.0, 0.5, "suffix:m") var cliff_layer_min := 5.0
## Thickest rock layer (m).
@export_range(2.0, 60.0, 0.5, "suffix:m") var cliff_layer_max := 14.0
## Share of the hard layers that stand as cliffs (the rest of the slope stays smooth).
@export_range(0.0, 1.0, 0.01) var cliff_hard_share := 0.6
## How much the rock layers tilt (m per m), so bands climb across a mountainside instead of running level.
@export_range(0.0, 0.3, 0.005) var cliff_dip := 0.06
## Slope of the scree below a cliff band (m per m; 0.8 is about 39 degrees), where the mountainside allows.
@export_range(0.3, 1.5, 0.01) var talus_slope := 0.8
## Rock slabs standing in the cliff bands (0 = none, 1 = most of a band's face, more = denser): faces of rock
## with a broken outline, which the 2 m ground mesh can't draw. They collide.
@export_range(0.0, 2.0, 0.05) var cliff_rocks := 1.0
## Size of those slabs (1 = 6-10 m wide; their height comes from the rock layer they stand in).
@export_range(0.4, 2.5, 0.05) var cliff_rock_size := 1.0
