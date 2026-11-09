extends Node3D
## The Map Baker from code, no Inspector: put this script on a Node3D in an empty scene and run it (F6).
## The first run bakes a 2 x 2 tile island to `map_dir` (a few seconds), later runs load it; then the tiles
## stream round a capsule you walk with the arrow keys / WASD. Everything here is plain API: copy what you need.

## Emitted once the player stands on loaded ground.
signal ready_to_play

## Where the map is baked. user:// works in an exported game too; res:// only in the editor.
@export var map_dir := "user://maps/code_example"
## The seed of the baked map. Same seed (with the same settings) = the same map. Only used when it bakes.
@export var map_seed := 1234
## Bake again even if map_dir already holds a map.
@export var rebake := false

var player: CharacterBody3D
var _cam: Camera3D


func _ready() -> void:
	if rebake or not FileAccess.file_exists(map_dir + "/tiles.json"):
		var info := bake_map()
		if info["error"] != OK:
			push_error("bake failed: %s" % error_string(info["error"]))
			return
	_add_light()
	_add_player()
	await start_level()
	ready_to_play.emit()


## Bakes the map: a preset, a few changed params, the tile grid and where it goes.
func bake_map() -> Dictionary:
	var baker := LFMapBaker.new()
	baker.auto_preview = false   # no preview outside the editor
	baker.map_seed = map_seed
	baker.params = LFMapPresets.make("Classic Island")
	baker.params.lake_count = 2
	baker.params.river_count = 2
	baker.tile_size = 512
	baker.tiles_x = 2
	baker.tiles_z = 2
	baker.props = LFTileBaker.Props.ALL
	baker.output_dir = map_dir
	var info := baker.bake()   # {"error", "tiles", "props", "ms"}
	baker.free()
	return info


## Streams the tiles round the player, puts the player on the spawn and hooks up the water.
func start_level() -> void:
	var streamer := LFTileStreamer.new()
	streamer.name = "LFTileStreamer"
	streamer.map_dir = map_dir
	streamer.target = player
	streamer.load_distance = 600.0
	add_child(streamer)
	await $LFTileStreamer.load_around($LFTileStreamer.spawn_position())
	player.global_position = $LFTileStreamer.spawn_position() + Vector3.UP
	# The same, from the Spawn marker in the loaded tile:
	var spawn := get_tree().get_first_node_in_group("spawn") as Node3D
	player.global_position = spawn.global_position + Vector3.UP
	for area in get_tree().get_nodes_in_group("water"):
		area.body_entered.connect(_on_enter_water)
		area.body_exited.connect(_on_leave_water)
	# Tiles loaded later bring their own water areas.
	streamer.tile_loaded.connect(func(_x: int, _z: int, tile: Node3D) -> void:
		for area in tile.find_children("WaterArea*", "Area3D", true, false):
			area.body_entered.connect(_on_enter_water)
			area.body_exited.connect(_on_leave_water))


## What the camera looks at: "Chop" on a tree within 6 m.
func look_prompt() -> String:
	var from := _cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - _cam.global_basis.z * 6.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.is_in_group("tree"):
		show_prompt("Chop")
		return "Chop"
	return ""


## Fells the tree the camera looks at, if any (LFBakedProps): it stops drawing and its collision goes.
func chop() -> bool:
	var from := _cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - _cam.global_basis.z * 6.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return false
	var prop := LFBakedProps.find(hit.collider, hit.position)
	if not prop.is_empty() and prop.group == &"tree":
		LFBakedProps.remove(prop)
		return true
	return false


func show_prompt(text: String) -> void:
	print(text)


func _on_enter_water(body: Node3D) -> void:
	if body is StaticBody3D:
		return   # the land and props, noticed once as a tile loads
	if body == player:
		print("in the water")


func _on_leave_water(body: Node3D) -> void:
	if body == player:
		print("out of the water")


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	player.velocity.x = input.x * 6.0
	player.velocity.z = input.y * 6.0
	player.velocity.y = 0.0 if player.is_on_floor() else player.velocity.y - 9.8 * delta
	player.move_and_slide()


func _add_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	player.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	player.add_child(mesh)
	_cam = Camera3D.new()
	_cam.far = 3000.0
	_cam.position = Vector3(0, 4, 9)
	_cam.rotation_degrees.x = -15.0
	player.add_child(_cam)
	add_child(player)


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
