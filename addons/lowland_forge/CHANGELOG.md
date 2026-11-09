# Lowland Forge Map Baker: changelog

Newest first. **Changes what you bake** marks a change that gives a different result from the same seed and
settings, or different files in the output folder: maps you have already baked are not touched until you
bake them again.

## 2.1.0
**Faster and lighter**
- Bakes use every CPU core: a 1 km tile in about 3 s (was 12), and the editor stays usable while it bakes.
- About 4x fewer draw calls: props are drawn in 256 m batches (*Prop Batch Size*).
- Heightmap export and map image: about 3x faster (a 2 x 2 km heightmap in 19 s, was 56), in the background
  with a progress bar and Cancel.
- Big maps save without loading every tile; lighter water by river mouths.

**New**
- Fell trees and mine rocks in your game: `LFBakedProps` removes the one a ray hit.
- Trees sway and water moves with no extra node (add `LFEnvironment` to drive wind and weather).
- Grown tiles stay part of the map after you set *Add West / East ...* back to 0.
- **Rim Pass** (Map group, with the Mountains boundary): rivers leave the valley through a gorge they cut in the
  mountain rim and run off the map's edge (a river from past the edge comes in through one). Off (the default)
  keeps every map as it was.
- **Your own prop meshes** (*Params > Props > Prop Swaps*): swap any built-in tree, rock or plant for your own
  meshes, sized with *Mesh Scale*. They stand where the built-in ones would; empty (the default) keeps every
  map as it was.
- Two new map presets, *Great Mountains* and *Deep Valleys* (tall ranges, broad valleys), and the *valleys* landform.
- **Relief Variation** (Height > Relief Variation): `relief_variation` (0..1) makes some regions flat lowland and
  others up to twice as rugged, over regions `relief_size` metres across. 0 (the default) keeps every map as it was.
- Biomes have their own looks: *Rock Tint*, *Grass Tint*, *Beach*, *Snow*, *Snow Cover* and *Ground Dip* per biome,
  and prop rules can ask for *Near Water*. The biome presets use them.
- *Snow Takes Over* (above the snow line the snow biomes cover everything, no forest patches) and *Spawn Search*
  (how far to look for a dry spawn).
- Code: override `LFTerrainGenerator.biome_allowed(i, x, z)` to place biomes by area.
- **Biome Regions** (Biomes > Biome Regions): split the land into wedges round the centre, each with its own
  biomes and soft borders. Empty (the default) keeps every map as it was.
- Each biome lists its **Roamers** (generic animal ids, night-only, rare) for your game to spawn from;
  `LFTerrainGenerator.roamers_at(x, z, night)`. They don't change the map.
- `LFFogPatch`: a local patch of fog that thickens as the camera goes in.
- Code: `max_step(x, z, radius)` (how flat), `roads.overlaps(x, z, radius)`, roads marked open at runtime.
- Snow pines: the snow is part of each branch now, so it sways with it (it used to slide over it).

**Breaking** (only when you re-bake; the same seed gives the same land)
- Props moved to `props/` scenes. Code that finds them by node path: set *Prop Batch Size* to 128 m for the
  old layout.
- Shader globals are now `lf_wind`, `lf_weather`...: your own shaders that read the old names, switch, or set
  `LFEnvironment.publish_old_names = true`.
- `tiles.json` has new fields; maps from 2.0 are still recognised when you grow them.
- The biome presets look different (rock and grass tints, beaches, snow): set `LFBiomePresets.legacy = true`
  for the old look. The land itself is unchanged.
- Roads you plan from code end at the shore (none out in the water; bridges need dry banks): `LFTerrainRoads.keep_wet_ends = true`
  gives the old roads.

Includes 2.0.1 (faster sampling, same output), which was never uploaded on its own. Details: `docs/GUIDE.md`.

## 2.0.1
- Faster: baking, the preview and placing the sites sample the land with less work (rivers, coast, roads),
  about a third quicker by rivers, and roads and shore villages are planned with fewer samples. **Nothing changes in what you bake:** the same seed and settings give the
  same map and the same files, bit for bit.

## 2.0.0

### Upgrading from 1.1.0
**Changes what you bake** (every map): the same seed and settings give another map than 1.1.0 (rivers,
lakes, snow). Maps you have already baked are not touched until you bake them again; to keep one as it is,
don't re-bake it (or keep 1.1.0 for it). When you do re-bake:
- **Rivers:** the web of rivers every map used to get is gone. *River Count* is now exactly how many rivers
  you get (0 = none). Set it to the number you want.
- **Removed settings** (*Params > Rivers*): *Rivers*, *River Freq*, *River Warp Freq*, *River Soft Edges*,
  *River Channel Only*. A saved Params `.tres` that sets them still loads (Godot skips those keys with a
  warning); re-save it to drop them. A script that sets them must stop.
- A script that finds the water area by the exact name `WaterArea`: a block with water up in the hills now
  has one per water level (`WaterArea2`...). Use the `water` group or `find_children("WaterArea*")`.
- Maps and Params you saved keep their own settings (lakes, natural lakes, biomes): only new maps and the
  presets get the new defaults below.

### Rivers and lakes
- **A new map has one lake and one river:** the river springs on the island's high ground, runs through the
  lake and on to the sea. *Natural Lakes* starts off. The Classic Island preset is the same.
- **Rivers start high and run through the lakes:** each river springs on a mountain (*Mountain Count*), the
  island's high ground or a lake, and runs downhill through up to three lakes in its path (natural lakes
  too) to the sea, or off the map's edge. Its water falls along its course, with rapids where the land
  drops. A river that reaches another river's lake joins it there.
- **Waterfalls:** where a river drops steeply it falls (cascades of falls down a mountain's face, a gorge
  below each), and a river running into a lower river falls into it. Each is a `Waterfall` mesh with
  streaming water and foam at its foot, in the group `waterfall` (metas `top`, `bottom`, `width`) for
  your sound. *Params > Rivers > Waterfalls* turns them off.
- **Where rivers meet** the banks curve into each other and the current turns from one into the other.
- **Flowing Rivers is experimental** (off at first): thinner streaks that run with the current and stop at a
  lake or the sea, and it now shows in the preview. The guide says how to use your own river water.
- **Lakes at their own height:** a lake lies at the height of the land round it, so a lake up in the hills
  holds its water up there, with its own beach. Shores have bays and points. **Big Lake** makes the first
  lake wider; **Highland Lakes** puts a share of them on the mountains' slopes.
- **River mouths meet the sea at its level** (no stair of water at the mouth).
- Water above the sea is everywhere water is: the Water meshes, the `WaterArea`s (one per level, 0.5 m
  steps, each with its `water_level` meta), sand round it, no props in it, roads bridge it, the map image
  and the preview show it, and the heightmap export adds `heightmap_water.exr`.

### Snow only up high
- **Frozen Highlands** (and any biome with the new *Only Above*) only covers ground above the snow line,
  so snow no longer lies in patches beside the pines. Highland Island and Mountain Valley get snow on their
  heights only; Frozen Isle keeps snow down to the shore; a map with only a snow biome is all snow.
- **Snow Line** (new, in the Map group): where snow starts, from the lowlands (0) to the highest peak (1).
  It follows the land as it really stands, so mountains on a small island get snow too.
- Lakes and rivers no longer flatten a mountain's summit: a highland lake keeps its shore off the top, and
  a river goes round a peak to the next lake. Rivers that cross join instead of one standing over the other.

### Mountains with cliffs
- **Cliff bands and scree:** mountainsides are built of rock layers. Hard layers stand as cliff bands with a
  ledge on top, soft ones lie back as scree slopes (*Params > Ground > Cliffs*: *Cliffs* 0 = smooth slopes,
  layer thickness, how many layers stand as cliffs, their tilt, the scree's slope). Never by rivers or on
  lake sides, and they never move the water.
- **Rock slabs and boulders:** chunky slabs of layered rock stand in the cliff bands and boulders lie on the
  scree below them. They are solid (in the `rock` group) and show in the preview. *Cliff Rocks* sets how
  many (0 = none), *Cliff Rock Size* how big; the slabs take *Rock Color*.
- **Rock colours:** rock is coloured by its layer (*Rock Strata*), the scree with *Scree Color*, steep faces
  darker with the snow sliding off them (*Cliff Shade*). One colour per 2 m square on steep ground: no green
  and grey checkerboard on narrow ledges. The map image and heightmap export follow.
- **Badlands** now has red-rock mesas ringed by cliff bands. **Highland Island** and **Frozen Isle** get two
  mountains on every seed (on some seeds they had none), Highland Island's with rounder snowy peaks.
- **No more sheer walls or spikes** on mountains beside rivers and lakes.

### Better
- **Short, plain tooltips** on every setting (hover it in the Inspector).
- **Re-baking the same map changes no files:** every scene comes out byte for byte the same, so a map kept
  in version control only shows the tiles you really changed. (The first bake with 2.0.0 rewrites the
  hidden node ids inside each scene once; nothing you see changes.)
- **The spawn point is never in a lake**, even on a tiny map.

### Fixed
- **LFTileStreamer no longer loads a tile twice now and then** ("Another resource is loaded from path ...",
  sometimes followed by a MultiMesh error): it loads one tile at a time on a background thread. Tiles come in
  one after another instead of all at once; `load_around` still returns when the start area is in.

### Docs
- **A short `README.md`** (install, quick start) and the docs in **`docs/`**: `GUIDE.md` (every setting,
  Grow Map, what a bake writes, using the map in your game) and `API.md` (from code).

### New for scripts
- `LFMapBaker.water_level_at(p)`: the water's surface over a point (like `ground_at`): a lake or river up
  in the hills has its own level.
- **`docs/API.md`**: the baker from code (bake, params, One Tile, Grow Map, heightmap and map image, the ground
  before baking, streaming), every snippet checked by the package's own tests.
- **`examples/bake_from_code.gd`**: bakes a map and streams it round a player you walk, no Inspector set-up
  (put it on a Node3D in an empty scene and run it).
- `LFTerrainGenerator.find_water(from, dir, reach)`: the first open water (lake, sea or river) along a
  direction; `water_level_at(x, z)`: the water's surface there (lakes and rivers in the hills sit above
  the sea).

## 1.1.0

### Upgrading from 1.0.0
Nothing you have baked changes until you bake it again. When you do:
- A script that looks for `PropBody` by name: test the groups instead (`collider.is_in_group("tree")`,
  `"rock"`, `"log"`) or the new names `TreeBody`, `RockBody`, `LogBody`.
- Loading tiles one at a time on an island map: add `map_edge.tscn` to your level once, at (0, 0, 0), to keep
  the sea out to the horizon (it used to be in the edge tiles).
- A script of yours that used `LFWorld`, `LFTerrainChunk`, `LFPropChanges`, `LFFoliageInteraction` or
  `LFFxUtil` from 1.0.0: those classes are no longer in the download (baked maps never used them).

### New: ready for your game
- **A spawn point:** a `Spawn` marker (group `spawn`) on dry, gentle ground near the middle of the map, in the
  tile it falls in; `tiles.json` says which. `get_tree().get_first_node_in_group("spawn")` finds it.
- **Tell trees from rocks:** prop collision is one body per kind in each block, `TreeBody`, `RockBody` and
  `LogBody`, and every baked body is in a group: `terrain`, `tree`, `rock`, `log`, `edge_wall`. A ray or a
  footstep can tell what it hit: chop prompts, footstep sounds, mining. The prop scenes in `shared/props/` are
  in the same groups.
  **Changes what you bake:** `PropBody` is gone.
- **Water you can swim in** (*Collision > Water Areas*, on by default): a `WaterArea` (Area3D, group `water`)
  over each block's lakes, rivers and sea, and over the sea round an island, from the bottom up to the
  surface. `body_entered` / `body_exited` tell you when something goes in or comes out; its `water_level`
  meta is the surface height.
  **Changes what you bake:** wet blocks get a `WaterArea`; untick *Water Areas* to leave it out.
- **Physics layers** (*Collision*): the layers of the land, the props, the edge walls and the water, and what
  the water notices, set before you bake. Every bake, and every tile you add later, comes out the same.
- **Invisible walls at the map's edge** (*Collision > Edge Walls*, on by default): an open or mountain-rim
  map gets an `EdgeWall` body along its outer sides, so a player can't walk up the rim and off the map, or
  off the cut edge of open land. An island has none (it ends in sea). Needs collision.

### New: grow a map you've already edited
- **Grow Map:** set *Add West / East / North / South*, tick *New Tiles Only* and Bake. Only the new tiles are
  baked; the tiles in the folder, with your edits, are not touched, and the land and the map's position
  don't change. New tiles carry the land on (more land, the island's sea or the rim's mountains) and are
  numbered on from the old ones (`tile_-1_0.tscn` to the west). The bake stops, without writing anything,
  if the folder holds another map (other seed, Params or Tiles X / Z).
- **`map_edge.tscn`:** what lies round the whole map (the edge walls, and the sea out to the horizon round
  an island), in its own scene so a grown map's edge can move. `map.tscn` includes it.
  **Changes what you bake:** the `SeaRing` node moves from the edge tiles into `map_edge.tscn`.

### New: lakes and rivers by number
- **Lake Count**, **Natural Lakes** and **River Count** (Map group, and *Params > Lakes / Rivers*): say how
  many lakes and rivers you want. Counted rivers spring at the mountains and run to the sea or into a lake.
  All off by default: maps you made before come out the same.

### New: a map image
- **Map Image > Export map image:** a top-down picture of the whole map for a minimap or a map screen,
  with overlays to check the biomes, the slope or the height.

### New: stream big maps
- **LFTileStreamer:** a node that loads the baked tiles near your player on background threads and frees
  the far ones, so a 10 x 10 km map plays without loading 100 tiles at once. See *Using the map in your
  game*.

### New: in the editor
- **Map presets:** pick *Preset* (Classic Island, Highland Island, Mountain Valley, Rolling Plains, Deep
  Forest, Badlands, Frozen Isle) and press *Apply preset* for a ready-made map to start from (undoable).
- **Asks before baking over a map:** pressing Bake when the folder already holds one asks first, and names
  the tiles you saved since the last bake (the ones you likely edited by hand).
- **Project > Tools > New Lowland Forge map:** a new scene with the baker, a sun and a sky, ready to bake.
- **A node icon** for LFMapBaker, and a tooltip on every Inspector setting.

### Better
- **Maps half the size on disk, and lighter to draw:** a baked 1 km tile with every prop went from about
  52 MB to about 25 MB. The terrain mesh shares its corners (6 times fewer vertices) and keeps the same
  flat-shaded, faceted look (each triangle's colour is in a small texture per block, drawn by the new
  `terrain_baked.gdshader`). Far away, Godot switches each block to a coarser level of detail (4 m and 8 m),
  with a skirt along its edges so no gaps show between blocks.
  **Changes what you bake:** the terrain's colours are no longer vertex colours (each block's `Terrain` has
  its own material with the colour texture), and prop collision shapes have 6 sides instead of 8.
- **Trees, rocks and logs fade out at a distance** you set: *Props > Prop Draw Distance* (default 800 m;
  0 = always drawn, as in 1.0.0). Ground cover still stops at 120 m.
  **Changes what you bake:** set it to 0 to draw them at any distance as before.
- **Smaller download:** the zip no longer carries the full Lowland Forge addon's runtime streaming code
  (`LFWorld`, `LFTerrainChunk`, `LFPropChanges`, `LFFoliageInteraction`, `LFFxUtil`), which the Map Baker
  never used. They no longer clutter the *Add Node* dialog.
  **Breaking (code only):** see *Upgrading* above.

### Fixed
- **Heightmap export on a huge map** no longer tries to write an image too big to hold: past 16385 pixels a
  side it exports at a coarser step that fits, says so, and writes the step it used in the `.json`.
- **No more cliffs beside rivers:** land far from a river could be cut flat down to the river banks, leaving
  sheer rock walls (and long grey streaks across open maps). The land now eases down only near the water.
  **Changes what you bake:** maps with rivers come out different near them. To bake a 1.0.0 map again
  exactly, untick *Params > Rivers > River Channel Only*.
- **No more sea slab past the map's edge:** water used to be a flat plane under each whole tile, which
  showed as a blue slab under the map's edge seen from outside, or under a tile loaded on its own. Water is
  now a `Water` mesh per block over just the land that dips below the water level (lakes, rivers, sea).
  **Changes what you bake:** the tile's `Water` node is gone; each wet block has its own.
- **Mountain Count works on small maps:** on a map of 1 to 2 km, counted mountains could find no room and
  silently not appear (0 of 3 on a 1 km map). Peaks now get smaller to fit, and if some still can't, the
  bake prints a warning saying how many were placed.
  **Changes what you bake:** maps with a *Mountain Count* of 1 or more where peaks were missing now have them.
- **Re-baking cleans the folder:** a full bake now removes the blocks and tiles an earlier bake left in the
  output folder (a different seed or a smaller map used to leave the old pieces behind, doubling the
  folder). A *Work on One Tile* bake still keeps the other tiles. Cancelling a re-bake warns that the folder
  is a mix of two bakes until you bake again.
- **Your Params presets stay as you saved them:** assigning a `.tres` preset to the baker no longer adds the
  biome presets to it (which could change a preset other scenes share).

### Docs
- A new *Using the map in your game* section (spawn, groups, water, layers, with code), and *Grow Map*.
- How big a bake is on disk (about 25 MB per 1 km tile), that the bake runs a piece at a time on the main
  thread (the editor stays usable, but slower), and when *Rim Height* shows.

## 1.0.0
First release.
