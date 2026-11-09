extends Node3D

## LIGHT OF KIRANA — main v5 (REBUILD DARI 0).
## Entry point: bangun World + Sky + FlyCamera + Ambience.
## Mode test: `godot --headless --path . -- --world-test`
## nge-print `WORLD_TEST PASS` kalau semua cek lulus, atau FAIL + alasannya.
## Cek: chunk rumput, jumlah rumput, laut (barat), pegunungan (utara),
## danau, jalanan tanah, langit shader, kabut mati, kuil ada.

const WorldScript := preload("res://scripts/world.gd")
const SkyScript := preload("res://scripts/sky.gd")
const FlyCameraScript := preload("res://scripts/fly_camera.gd")
const AmbienceScript := preload("res://scripts/ambience.gd")


func _ready() -> void:
	var world := Node3D.new()
	world.name = "World"
	world.set_script(WorldScript)
	add_child(world)
	var sky := Node3D.new()
	sky.name = "Sky"
	sky.set_script(SkyScript)
	add_child(sky)
	var camera := Camera3D.new()
	camera.name = "FlyCamera"
	camera.set_script(FlyCameraScript)
	add_child(camera)
	var ambience := Node.new()
	ambience.name = "Ambience"
	ambience.set_script(AmbienceScript)
	add_child(ambience)
	if "--world-test" in OS.get_cmdline_user_args():
		_run_world_test()


func _run_world_test() -> void:
	var world := get_node("World")
	var sky := get_node("Sky")
	var failures: Array[String] = []
	# 1. Chunk rumput: 6x6 = 36 chunk.
	var chunk_count: int = world._grass_chunks.size()
	if chunk_count != 36:
		failures.append("chunk rumput=%d (mau 36)" % chunk_count)
	# 2. Jumlah rumput total >= 100000 (target 350k).
	var total_grass := 0
	for c in world._grass_chunks:
		var node: MultiMeshInstance3D = c["node"]
		total_grass += node.multimesh.instance_count
	if total_grass < 100000:
		failures.append("rumput total=%d (mau >=100000)" % total_grass)
	# 3. Laut (barat, x=-170): tanah di bawah air.
	if world.get_height(-170.0, 0.0) > WorldScript.WATER_LEVEL:
		failures.append("laut: get_height(-170,0)=%.2f (mau < %.2f)" % [world.get_height(-170.0, 0.0), WorldScript.WATER_LEVEL])
	# 4. Pegunungan (utara, z=-185): tinggi.
	if world.get_height(0.0, -185.0) < 15.0:
		failures.append("gunung: get_height(0,-185)=%.2f (mau >=15)" % world.get_height(0.0, -185.0))
	# 5. Danau (60,35): di bawah air.
	if world.get_height(60.0, 35.0) > WorldScript.WATER_LEVEL:
		failures.append("danau: get_height(60,35)=%.2f (mau < %.2f)" % [world.get_height(60.0, 35.0), WorldScript.WATER_LEVEL])
	# 6. Dataran tengah (spawn) datar.
	if absf(world.get_height(0.0, 0.0)) > 1.5:
		failures.append("spawn: get_height(0,0)=%.2f (mau |h|<=1.5)" % world.get_height(0.0, 0.0))
	# 7. Jalanan tanah: titik di jalan = DIRT.
	if world.get_ground_type(20.0, 12.0) != WorldScript.GroundType.DIRT:
		failures.append("jalan danau: get_ground_type(20,12) bukan DIRT")
	if world.get_ground_type(-90.0, 8.0) != WorldScript.GroundType.DIRT:
		failures.append("jalan pantai: get_ground_type(-90,8) bukan DIRT")
	# 8. Langit = ShaderMaterial (prosedural, bukan foto).
	var env: WorldEnvironment = sky._env
	if env == null or not (env.environment.sky.sky_material is ShaderMaterial):
		failures.append("langit: bukan ShaderMaterial")
	# 9. Kabut mati.
	if env != null and env.environment.fog_enabled:
		failures.append("kabut: masih nyala (mau mati)")
	# 10. Kuil ada.
	if get_node_or_null("World/Shrine") == null:
		failures.append("kuil: node Shrine tidak ada")
	# 11. Ground type sampling (statistik).
	var rumput := 0
	var tanah := 0
	var batu := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 400:
		var x := rng.randf_range(-190.0, 190.0)
		var z := rng.randf_range(-190.0, 190.0)
		match world.get_ground_type(x, z):
			WorldScript.GroundType.GRASS:
				rumput += 1
			WorldScript.GroundType.DIRT:
				tanah += 1
			WorldScript.GroundType.ROCK:
				batu += 1
	if rumput < 200:
		failures.append("rumput sample=%d/400 (mau >=200)" % rumput)
	if failures.is_empty():
		print("WORLD_TEST PASS")
		print("GROUND: rumput=%d tanah=%d batu=%d" % [rumput, tanah, batu])
		print("GRASS: chunks=%d total=%d" % [chunk_count, total_grass])
	else:
		print("WORLD_TEST FAIL")
		for f in failures:
			print("  - " + f)
	get_tree().quit()
