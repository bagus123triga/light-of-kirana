extends Node3D

## LIGHT OF KIRANA — main v6 (LowLand Forge).
## Dunia = map hasil bake LowLand Forge (res://maps/lf_map/map.tscn):
## Classic Island 512 m, seed 1234, 1 tile, 13524 props (pohon, batu, rumput).
## Langit tetap shader stylized prosedural + siklus hari (scripts/sky.gd).
## Kamera terbang (scripts/fly_camera.gd), mulai di titik spawn map.
## Mode test: `godot --headless --path . -- --world-test`
## nge-print `WORLD_TEST PASS` kalau map ke-load + spawn ketemu.

const SkyScript := preload("res://scripts/sky.gd")
const FlyCameraScript := preload("res://scripts/fly_camera.gd")
const AmbienceScript := preload("res://scripts/ambience.gd")
const LandmarksScript := preload("res://scripts/landmarks.gd")
const MAP_PATH := "res://maps/lf_map/map.tscn"
const TILES_JSON_PATH := "res://maps/lf_map/tiles.json"


func _ready() -> void:
	# Dunia: instance map hasil bake.
	var map_scene: PackedScene = load(MAP_PATH)
	var map_instance := map_scene.instantiate()
	map_instance.name = "LFMap"
	add_child(map_instance)
	# Landmark (desa, kincir, menara, gua, kuil kristal, jembatan, gerbang).
	var landmarks := Node3D.new()
	landmarks.name = "Landmarks"
	landmarks.set_script(LandmarksScript)
	add_child(landmarks)
	# Langit stylized + siklus hari.
	var sky := Node3D.new()
	sky.name = "Sky"
	sky.set_script(SkyScript)
	add_child(sky)
	# Kamera terbang, mulai di spawn.
	var camera := Camera3D.new()
	camera.name = "FlyCamera"
	camera.set_script(FlyCameraScript)
	add_child(camera)
	var spawn_pos := _spawn_position()
	if spawn_pos != Vector3.ZERO:
		camera.position = spawn_pos + Vector3(0.0, 9.0, 12.0)
	# Ambience (angin).
	var ambience := Node.new()
	ambience.name = "Ambience"
	ambience.set_script(AmbienceScript)
	add_child(ambience)
	if "--world-test" in OS.get_cmdline_user_args():
		_run_world_test()


func _spawn_position() -> Vector3:
	if not FileAccess.file_exists(TILES_JSON_PATH):
		return Vector3.ZERO
	var json_text := FileAccess.get_file_as_string(TILES_JSON_PATH)
	var data: Dictionary = JSON.parse_string(json_text)
	if data.is_empty() or not data.has("spawn"):
		return Vector3.ZERO
	var spawn: Dictionary = data["spawn"]
	var pos: Array = spawn.get("position", [])
	if pos.size() < 3:
		return Vector3.ZERO
	return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))


func _run_world_test() -> void:
	var failures: Array[String] = []
	# 1. Map ke-load.
	var map_node := get_node_or_null("LFMap")
	if map_node == null:
		failures.append("map: node LFMap tidak ada")
	# 2. tiles.json kebaca + spawn ada.
	var spawn_pos := _spawn_position()
	if spawn_pos == Vector3.ZERO:
		failures.append("spawn: tiles.json tidak kebaca / spawn kosong")
	# 3. Spawn marker (group "spawn") ada di scene.
	var spawn_marker := get_tree().get_first_node_in_group("spawn")
	if spawn_marker == null:
		failures.append("spawn: marker group 'spawn' tidak ketemu")
	# 4. Terrain (group "terrain") ada.
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain == null:
		failures.append("terrain: group 'terrain' tidak ketemu")
	# 5. Pohon (group "tree") ada.
	var tree := get_tree().get_first_node_in_group("tree")
	if tree == null:
		failures.append("tree: group 'tree' tidak ketemu")
	# 6. Air (group "water") ada.
	var water := get_tree().get_first_node_in_group("water")
	if water == null:
		failures.append("water: group 'water' tidak ketemu")
	# 7. Langit = ShaderMaterial (prosedural).
	var sky := get_node_or_null("Sky")
	if sky == null or sky._env == null or not (sky._env.environment.sky.sky_material is ShaderMaterial):
		failures.append("langit: bukan ShaderMaterial")
	# 8. Kabut mati.
	if sky != null and sky._env != null and sky._env.environment.fog_enabled:
		failures.append("kabut: masih nyala (mau mati)")
	if failures.is_empty():
		print("WORLD_TEST PASS")
		print("MAP: Classic Island 512m seed 1234, spawn=" + str(spawn_pos))
	else:
		print("WORLD_TEST FAIL")
		for f in failures:
			print("  - " + f)
	get_tree().quit()
