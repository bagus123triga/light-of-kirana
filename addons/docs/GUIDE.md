# Lowland Forge Map Baker: guide

Everything the baker does, setting by setting. Hover any setting in the Inspector for a short tip; code is
in `API.md` (next to this file).

## Make a map
1. Add an **LFMapBaker** node to any 3D scene and select it (or **Project > Tools > New Lowland Forge map**:
   a new scene in `res://maps/` with the baker, a sun and a sky, opened for you). The Inspector shows everything:
   - **Map Seed:** same seed + same settings = the same map, bit for bit. **New Seed** rolls a new one.
   - **Preset** and **Apply preset:** a ready-made map to start from: *Classic Island*, *Highland Island*
     (two snow-capped peaks), *Mountain Valley* (a rim of mountains, peaks inside), *Great Mountains* (tall ranges), *Deep Valleys* (broad valleys), *Rolling Plains* (open
     country), *Deep Forest*, *Badlands* (desert and ash, red-rock mesas ringed by cliff bands, gorges) and *Frozen Isle*. It replaces
     Params (Ctrl+Z undoes it) and keeps your seed and map size; then change anything. To keep your own,
     save Params as a `.tres` (the Inspector's resource menu > Save As).
   - **Params** (an `LFMapParams` resource): height and hills, landforms (terraces, gorges), rivers, biomes,
     prop density, ground colours, and the **Boundary**: *Island* (the default) gives a coast and sea,
     *Mountains* a rim of mountains standing on the map's edge, *Open* endless land with neither. *Rim
     Height* (also in the Map group when the Boundary is Mountains) and *Rim Width* shape the rim. *Rim Pass*
     (also in the Map group) lets the rivers out: each cuts a gorge through the rim (*Rim Pass Width* m across
     its top) and runs off the map's edge, and a river from past the edge comes in through one; off (the
     default), they end in a lake inside the valley. Radius and coast lobes shape the
     island. Save it as a `.tres` to keep a preset.
     **Mountains** (*Mountain Height* and *Mountain Count* in the Map group; all of it in *Params > Height >
     Mountains*): *Height* is how far they rise above the hills (0 = none; try 60 to 120). *Count* 0 gives
     ranges (*Cover*: how much of the land), a number gives that many separate mountains with flat land
     between (on a small map they get smaller so they fit; if some still don't, the bake says so in the Output panel). *Size* is a mountain's width, *Flats* adds shelves and flat tops. Mountains are cold: their
     slopes and peaks take the coldest biome you have ticked, so tick Frozen Highlands for snow caps and snow
     pines; without a snow biome there is no snow on them. On an island they ease down before the beach.
     **Cliffs** (*Params > Ground > Cliffs*): mountainsides are built of rock layers. The hard layers stand as
     cliff bands with a ledge on top; the soft ones between lie back as scree slopes. *Cliffs* sets how much of
     the mountains gets bands (0 = smooth slopes), *Layer Min/Max* how thick a layer is, *Hard Share* how many
     layers stand as cliffs, *Dip* how much they tilt, *Talus Slope* how steep the scree lies. Rock slabs stand
     in the bands and boulders lie on the scree below them (*Cliff Rocks*: how many, 0 = none; *Cliff Rock
     Size*); they are solid, in the `rock` group. The rock is coloured by layer (*Rock Strata*: how strongly),
     the scree with *Scree Color*, and the slabs take *Rock Color*. None by rivers, lakes, roads or sites.
     **Relief Variation** (*Params > Height > Relief Variation*): 0 keeps the hills the same everywhere; up to 1
     some regions turn flat lowland and others up to twice as rugged. *Relief Size* is how big those regions are.
   - **Lakes and rivers** (*Lake Count*, *Natural Lakes*, *River Count*; more in *Params*, under *Lakes*
     and *Rivers*): a new map has one lake and one river. *Lake Count* sets how many lakes; each sits at the
     height of the land round it, so a lake in the hills stays up there. *River Count* sets how many rivers
     (0 = none): each starts high up (a mountain, the island's high ground or a lake), flows downhill
     through the lakes in its path and on to the sea, or off the map's edge. Where the land drops steeply
     it falls in waterfalls (a cascade down a mountain), and a river that runs into a lower one falls into
     it (*Params > Rivers > Waterfalls* turns them off: rapids instead). *Natural Lakes* adds a lake
     wherever the land dips below sea level; rivers run through the big ones.
   - **Biomes On:** tick the biomes you want: Meadow, Pine Forest, Birch Woods, Old Growth (on at first),
     Desert, Palm Coast, Frozen Highlands, Ash Barrens and Drowned Marsh. One ticked makes a single-biome map;
     with several, each takes the climate it suits (hot and dry, cold, wet...). Bigger maps show more of them;
     *Params > Climate Freq* sets how big each biome region is (lower = bigger). Frozen Highlands only
     covers high ground (its *Only Above*), unless it is the only biome ticked. Each biome has its own look
     (open it in *Params > Biomes*): *Rock Tint*, *Grass Tint*, *Beach*, *Snow*, *Snow Cover*, *Ground Dip*.
     `LFBiomePresets.legacy = true` (from code) gives the presets' looks of 2.0.
   - **Biome Regions:** *Params > Biome Regions* (empty at first) splits the land into wedges round the map's
     centre, each with its own list of allowed biomes by name (empty = all), an optional central disc and a soft
     *Blend* border: a meadow quarter, a pine quarter, a desert quarter. From code, `generator.region_at(x, z)`
     says which wedge a point is in. Each biome also lists *Roamers* (ids such as `deer` or `owl`, with night-only
     and rare flags) for your game to read with `roamers_at` / `roll_roamer`; they never change the map.
   - **Snow Line:** where snow starts, as a share of the land's height: 0 = the lowlands, 1 = only the
     highest peak (0.5 at first). Above it the heights are snow; it follows the mountains as they really
     stand, so any mountain height gets snow. *Params > Snow Takes Over*: above the line the snow biomes cover everything (no forest patches among the snow). A biome's *Min Height* keeps it above a set height as well.
   - **Map:** tile size (steps of 128 m, default 1024 m) and how many tiles across and down. *Boundary*
     picks Open, Island or Mountains; the island and the mountain rim are always fitted to the map. Up to 16 x 16 tiles, but mind the disk: a baked 1 km tile with every prop is about 25 MB.
   - **Work on One Tile:** tick *One Tile* and pick the tile (*x* = column, *y* = row, from 0 at the
     north-west corner, as in `tile_<x>_<z>.tscn`; the preview labels every tile). The preview then shows that
     tile in detail with its trees and the rest of the map coarse round it, and **Bake** writes only that
     tile, keeping the others already in the folder. The way to work on a big map one piece at a time.
   - **Grow Map:** need more land after you've baked and edited? Set *Add West / East / North / South* to
     the tiles to add round the map, tick *New Tiles Only* and press **Bake**: only the new tiles are baked,
     and the tiles already in the folder (with your edits) aren't touched. The land doesn't change and the
     map doesn't move: the new tiles carry on the land you have (more land on an Open map, sea round an
     Island, the rim's mountains on a Mountains map), numbered on from the old ones, below 0 to the west and
     north (`tile_-1_0.tscn`). Keep the seed, *Params* and *Tiles X / Z* as they were (they make the land:
     with *New Tiles Only* the bake stops if they changed). The preview marks the tiles already baked *kept*.
     Once baked, the new tiles are part of the map: you can set *Add West ...* back to 0 and every later bake
     (a whole bake, or one tile) keeps them. To drop a tile, delete its `tile_<x>_<z>.tscn`. Grow Map suits
     *Open* maps best: round an *Island* the new tiles are sea, round *Mountains* they are the rim's mountains.
   - **Props:** *All*, *Large* (trees, rocks and logs, no ground cover) or *None* (bare terrain), and
     *Prop Density* (0 = none, 1 = normal, 2 = about twice as many), *Prop Draw Distance* (how far away trees, rocks and logs stop drawing in the baked map, fading out; default 800 m, 0 = always; grass and flowers stop at 120 m), and *Prop Batch Size*: props are drawn and collide in batches this big (default 256 m: a quarter of the draw calls of 128 m; *128 m* bakes them inside each block, as Map Baker 2.0 did).
   - **Preview:** *Auto Preview*, detail, *Preview Props*, *Preview Props Limit*, and the *Refresh preview* and
     *Cancel preview* buttons (see step 2).
   - **Collision:** collision on or off, *Edge Walls* (invisible walls round an open or mountain-rim map, so
     a player can't walk off it; on by default), *Water Areas* (on by default: see *Using the map in your
     game*), and the physics layers of the land, the props, the edge walls and the water, so a bake lands on
     your game's layers with no fixing up after. Everything is on layer 1 at first, as a new player is.
   - **Bake:** the folder (default `res://maps/map`), *Bake Threads* (0, the default: every CPU core but one)
     and *Flowing Rivers* (**experimental**, off at first:
     rivers are still water like the lakes; on: moving streaks show the current, in the preview too), with
     the *Bake* and *Cancel bake* buttons. For a finished game, bring your own river water: a shader on
     the `RiverFlow` meshes (each vertex's colour holds the flow: `rg` = direction x speed as `0.5 + 0.5 * v`,
     `b` = opacity, `a` = 1 by the bank), or your own water over the river, using
     `LFTerrainGenerator.river_flow_dir(x, z)` (downstream) and `water_level_at(x, z)` from `make_generator()`.
   - **Heightmap Export:** its resolution and the *Export heightmap* button (see below).
2. The viewport shows a low-detail preview of the whole map, with its trees, rocks and logs, redrawn a moment
   after you change anything (a note in the view's top-left corner says so: bake, then open a tile scene
   to see full detail; thin rivers can look broken in the preview only). It is built in the background, so the editor stays usable, and the 3D toolbar
   shows how far it is. Ground cover isn't shown in the preview. A big map with every tree takes a while
   (about 10 seconds for 3 x 3 km); if it takes long, a tip pops up once with the ways to make it quicker:
   *Work on One Tile*, *Preview > Preview Props* off, *Preview Props Limit* (leave props out of previews
   bigger than that many km²; 0, the default, shows them all) or *Auto Preview* off. To stop a preview while
   it builds, press *Cancel* next to its bar (or *Cancel preview*); the last preview stays until the next
   change or *Refresh preview*.
3. Press **Bake**. A 1 km x 1 km tile with every prop takes about 3 seconds on a 12-thread PC (about 7 with *Bake Threads* 1; a 2 x 2 km Highland Island with every biome about 25). If the folder already holds a baked map, it asks
   before baking over it (and names any tile you saved since the last bake, and any tile it would delete): a bake rewrites its tiles, and
   hand edits in them are lost. Bake to a new folder to keep them, or use *Grow Map*. The 3D toolbar shows a progress bar with
   *Cancel* (or press *Cancel bake* in the Inspector). The map is built on background threads and saved a piece at a time, so the editor stays usable (a little slower until it's done); the bake goes on while you look at another scene tab, and stops only if you close the map's scene.

## What a bake writes
- `map.tscn`: the whole map (every tile). Open it, or instance it in your level.
- `tile_<x>_<z>.tscn`: one scene per tile. Every tile carries its own offset, so a tile added at (0, 0, 0)
  sits in its place. The tile with the start point has a `Spawn` marker. Load tiles one at a time (a loading screen per tile) and they meet without a seam.
  `tiles.json` lists them.
  A big map (say 10 x 10 tiles) is 100 tile scenes: load the ones near the player and free the rest;
  `map.tscn` is only an overview that instances them all.
- `map_edge.tscn`: what lies round the whole map: the invisible walls (*Edge Walls*) and, round an island,
  the sea out to the horizon. `map.tscn` has it; if you load tiles one at a time, add it to your level once.
- `blocks/`: the 128 m pieces tiles are made of: terrain mesh (with two coarser levels of detail Godot
  switches to far away, and its colours in a small texture), height-field collision (`TerrainBody`), water
  and its `WaterArea`, river surface.
- `props/`: the props, a scene per *Prop Batch Size* square (`props_<x>_<z>.scn`, a `Props_<x>_<z>` node in
  the tile): MultiMeshes, one per prop type, and one collision shape each for the batch's trees, rocks and
  logs (`TreeBody`, `RockBody`, `LogBody`). With *Prop Batch Size* 128 m they are in the blocks instead.
- `tiles.json`: the map's tiles, its grid, seed, land key and the generator version that made it (a later
  bake checks them before adding tiles), and the spawn.
- `shared/`: meshes and materials every block uses, and `shared/props/`: a scene per prop (`pine_0.tscn`,
  `rock_2.tscn`, ...) with its mesh and collision. Drag them into a map to place props by hand. They're
  written whatever *Props* is set to, so you can bake bare terrain and dress it yourself.

Re-baking overwrites the output folder, and a full bake removes the pieces an earlier bake left there (a *Work on One Tile* bake keeps the other tiles). Bake to a new folder to keep hand edits, and use *Grow Map*
with *New Tiles Only* to add tiles to a map you've edited.

## Using the map in your game
- **Where the player starts:** the `Spawn` marker, on dry, gentle ground near the middle of the map
  (`tiles.json` says which tile has it). It sits on the ground: lift your player by half its height.
  ```gdscript
  var spawn := get_tree().get_first_node_in_group("spawn") as Node3D
  player.global_position = spawn.global_position + Vector3.UP
  ```
- **What did I hit?** Every baked body is in a group: `terrain`, `tree`, `rock`, `log`, `edge_wall`. Use it
  for footstep sounds, "press E to chop" only on trees, rocks to mine, or a ray that should only land on the
  ground:
  ```gdscript
  var hit := get_world_3d().direct_space_state.intersect_ray(query)
  if hit and hit.collider.is_in_group("tree"):
      show_prompt("Chop")
  ```
  The prop scenes in `shared/props/` are in the same groups.
- **Fell a tree, mine a rock:** `LFBakedProps` names the single prop a ray hit, and removes it (it stops
  drawing and its collision goes):
  ```gdscript
  var prop := LFBakedProps.find(hit.collider, hit.position)
  if not prop.is_empty() and prop.group == &"tree":
      LFBakedProps.remove(prop)
  ```
  That changes the loaded tile only, not the files: keep the cut trees' `prop.position` in your save data and
  remove them again when their tile loads (`LFBakedProps.find_near(tile, position)`).
- **Water:** each block with water has a `WaterArea` (group `water`) from the bottom up to the surface, and
  so has the sea round an island. Connect its signals to know when something goes in or comes out (swim,
  splash, drown, put out a torch, float a boat); its `water_level` meta is the surface height. A block
  with water up in the hills has an area per water level (`WaterArea`, `WaterArea2`... in 0.5 m steps: a
  highland lake, a river falling from it), each with its own `water_level`:
  ```gdscript
  for area in get_tree().get_nodes_in_group("water"):
      area.body_entered.connect(_on_enter_water)
      area.body_exited.connect(_on_leave_water)
  ```
  The water areas notice the layers in *Collision > Water Mask* (layer 1 at first, where a player starts).
  The land and trees are on layer 1 too, so they are reported once as a tile loads: skip them.
  ```gdscript
  func _on_enter_water(body: Node3D) -> void:
  	if body is StaticBody3D:
  		return   # the land and props, noticed once as a tile loads
  ```
- **Waterfalls:** each is a `Waterfall` mesh in the group `waterfall`, with metas `top`, `bottom` (water
  levels) and `width`: hang a looping sound or spray on them:
  ```gdscript
  for fall in get_tree().get_nodes_in_group("waterfall"):
      var sound := AudioStreamPlayer3D.new()
      fall.add_child(sound)
  ```
- **Physics layers:** set them in *Collision* before baking (say, edge walls only on the player's layer, so
  arrows and the camera pass through). Every bake, and every tile you add later, comes out the same.
- **Big maps: load tiles as the player moves.** Instead of `map.tscn`, add an **LFTileStreamer** node to
  your level at (0, 0, 0), set *Map Dir* to the bake folder and *Target* to your player. It loads the tiles
  within *Load Distance* (default 1200 m) on background threads and frees those further than that plus
  *Unload Margin*, and adds `map_edge.tscn` once. For a loading screen at the start:
  ```gdscript
  await $LFTileStreamer.load_around($LFTileStreamer.spawn_position())
  player.global_position = $LFTileStreamer.spawn_position() + Vector3.UP
  ```
  Its `tile_loaded(x, z, tile)` and `tile_unloaded(x, z)` signals let you hook up each tile's water areas
  or spawn things in it. A tile's nodes are freed with it, so keep what must last (pickups taken, trees cut)
  in your own save data.

## Placing your own things on the land
Select one or more nodes (houses, props, anything 3D) and use the **Ground** menu in the 3D viewport's
toolbar: **Drop selection to ground** puts each node's origin on the land below it; **Drop and align to
slope** also tilts it so its up follows the ground. Both can be undone (Ctrl+Z).
- With an **LFMapBaker** in the scene, the nodes land where the baked ground will be, even on the preview
  (which has no collision), so you can lay a level out before you bake.
- Without one (say you instanced `map.tscn` in your level) they land on the first collider below them, so
  bake with collision on. Godot's own *Transform > Snap Object to Floor* (Page Down) works there too.

## Map image (a minimap)
**Map Image > Export map image** writes `map_image.png`: the whole map seen from above, north up, lit from
the north-west, with its water, rivers and start point (a white dot). Pixel (0, 0) is the map's north-west
corner, so a point at `(x, z)` in the baked map (centred on the origin) is at pixel
`((x / map_width + 0.5) * px, (z / map_width + 0.5) * px)`. Use it as a minimap or a map screen. *Map Image
Overlay* swaps the colours to check one thing: each biome in its own colour, the slope (green flat, yellow
steep, red cliff) or the height.

## Heightmap export (Terrain3D and other tools)
**Export Heightmap** writes `heightmap_height.exr` (heights in metres), `heightmap_height.r16`,
`heightmap_color.png` and `heightmap_heightmap.json` (sizes, metres per pixel, height range), and on a map with
lakes or rivers up in the hills `heightmap_water.exr` (the water's level at each pixel: water wherever it is
above the height). In Terrain3D's importer: height = the `.exr`, colour = the `.png`,
scale 1, offset 0, vertex spacing = the step you exported at. The json's `origin_x` / `origin_z` are the
north-west corner in the generator's world space (what `make_generator()` samples), not the baked map's
(centred on the origin). The baked map's (0, 0) is the generator's
`b.map_origin(g) + Vector2(b.tiles_x, b.tiles_z) * b.tile_size * 0.5` (`g := b.make_generator()`). HTerrain, Blender and World Machine read them
too.

## Good to know
- Every setting the baker doesn't show itself is inside **Params**: click the `LFMapParams` value next to
  *Params* to open it. Its settings are grouped as World, Boundary (Mountain Rim, Island Shape, Island Coast),
  Height (Hills, Ridges, Relief Variation, Detail, Landforms, Mountains), Rivers (Layout, Channel), Biomes, Props and Ground
  (Colours, Beach, Rock and Snow).
- Props are MultiMeshes: fast to draw, but you can't click a single tree in the editor. To place or remove
  props by hand, bake with *Props: None* (or *Large*) and drag scenes in from `shared/props/`; in the game,
  `LFBakedProps` removes one.
- **Your own trees, rocks and plants:** in *Params > Props > Prop Swaps*, add an entry, create a new `LFPropSwap`
  in it, pick the built-in *Kind* and add your *Meshes*. An `.obj` drops straight in. A `.glb` or `.gltf` is a
  scene, not a mesh: double-click it in the FileSystem dock, select its mesh in *Advanced Import Settings*, tick
  *Save to File*, press *Reimport*, then use the saved file (a model of several parts needs joining first). The
  origin goes at the foot, +Y up. *Mesh Scale* sizes them: a built-in tree is about 10 m tall, a rock 0.5 to 3 m
  across. They appear where that kind would stand, in the preview and the bake, with its collision and felling;
  *Collide Radius* sets the collider of trees and rocks. They keep their own materials, so they don't sway
  unless yours does. Changing swaps counts as a different map: re-bake it rather than growing it.
- **Local fog:** `LFFogPatch` is a patch of denser fog at a place, thickening as the camera goes in.
- **Wind and water need no script:** baked trees sway and the water moves on their own, in a light breeze.
  To change the wind or the weather (rain, wetness), add an `LFEnvironment` node to your level and call its
  `set_wind(dir, strength, gust)` / `set_weather(cloud, rain, wet, fog)`. The shaders read global uniforms
  the plugin adds to *Project Settings > Shader Globals*, all named `lf_...` (`lf_wind`, `lf_weather`,
  `lf_wind_phase`, `lf_water_wave`, `lf_water_dir`, `lf_player_*`, `lf_fx_time`), so they don't clash with
  your own.
- **Heightmap export and the map image** run in the background on all CPU cores, with a progress bar and *Cancel* in the 3D toolbar (a 2 x 2 km heightmap at 1 m takes about 20 seconds on a 12-thread CPU, a third of before). The editor stays usable; a cancelled export writes nothing. Scripts call `export_heightmap()` / `export_map_image()`, which return when done, or `start_export_heightmap()` / `start_export_map_image()` for the background run.
- The baked materials use the shaders in `addons/lowland_forge/shaders/`, so keep the addon in your project.
- Water is a flat surface (a `Water` mesh per block) over the land that dips below the water level; rivers and lakes are channels it fills, so they are still water
  unless you bake with *Flowing Rivers* (a `RiverFlow` mesh per block, which you can also delete by hand). Where a side of the map is open sea (an island), the sea and
  its floor go on for 6 km (a `SeaRing` node in `map_edge.tscn`), so the island sits in sea to the horizon; delete
  that node if you don't want it. On open land the terrain is cut off at the map edge; with a mountain
  rim the crest is the map's edge, and rivers end as dry ravines up the rim. Both get invisible walls at the
  map's edge (*Edge Walls*), so nothing walks or falls off it.
- Everything (meshes, colours, shaders) is made in code by the addon. There are no third-party assets.
