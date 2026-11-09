extends Node3D

# LIGHT OF KIRANA — main: rakit dunia + kamera terbang + suara.
# Mode kamera saja, tanpa pemain (minta Bagus 2026-11-09).
# Jalankan tes dunia headless: godot --headless --path . -- --world-test

const WorldScript := preload("res://scripts/world.gd")
const FlyCameraScript := preload("res://scripts/fly_camera.gd")
const AmbienceScript := preload("res://scripts/ambience.gd")
const SkyScript := preload("res://scripts/sky.gd")

var _world: Node3D
var _sky: Node3D
var _test_mode := false
var _test_frames := 0


func _ready() -> void:
	_test_mode = "--world-test" in OS.get_cmdline_user_args()
	var ambience := Node.new()
	ambience.set_script(AmbienceScript)
	add_child(ambience)
	_world = Node3D.new()
	_world.set_script(WorldScript)
	add_child(_world)
	ambience.set_water_position(Vector3(14.0, 0.0, 12.0))
	var cam := Camera3D.new()
	cam.set_script(FlyCameraScript)
	cam.world = _world
	add_child(cam)
	# Langit + siklus hari (matahari/bulan/bintang/awan bertekstur).
	_sky = Node3D.new()
	_sky.set_script(SkyScript)
	add_child(_sky)
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "LIGHT OF KIRANA — mode kamera | Joystick/WASD gerak, NAIK/TURUN, CEPAT, drag kanan lihat-lihat"
	label.position = Vector2(16, 16)
	var label_bg := StyleBoxFlat.new()
	label_bg.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	label_bg.content_margin_left = 8.0
	label_bg.content_margin_right = 8.0
	label_bg.content_margin_top = 4.0
	label_bg.content_margin_bottom = 4.0
	label.add_theme_stylebox_override("normal", label_bg)
	layer.add_child(label)


func _process(_delta: float) -> void:
	if not _test_mode:
		return
	_test_frames += 1
	if _test_frames == 60:
		_run_world_test()


func _run_world_test() -> void:
	var failures := []
	if _world == null:
		failures.append("world null")
	else:
		var grass := _world.get_node_or_null("Grass")
		if grass == null or grass.multimesh.instance_count < 1000:
			failures.append("rumput kurang/tidak ada")
		if _world.get_node_or_null("Water") == null:
			failures.append("air tidak ada")
		if _world.get_node_or_null("Terrain") == null:
			failures.append("tanah tidak ada")
		var h: float = _world.get_height(0.0, 6.0)
		if absf(h) > 0.6:
			failures.append("spawn tidak rata: h=%f" % h)
		if _world.get_ground_type(0.0, 6.0) < 0 or _world.get_ground_type(0.0, 6.0) > 2:
			failures.append("jenis tanah invalid")
		# Sebaran warna tanah: batu jangan mendominasi bukit (dugaan
		# "atas putih" — batu abu-abu di mana-mana), rumput harus dominan.
		# World kini 256 m, jadi sampel di ±120 (bukan ±60).
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var counts := [0, 0, 0]
		for i in 400:
			var x := rng.randf_range(-120.0, 120.0)
			var z := rng.randf_range(-120.0, 120.0)
			counts[_world.get_ground_type(x, z)] += 1
		print("GROUND: rumput=%d tanah=%d batu=%d" % counts)
		if float(counts[2]) / 400.0 > 0.25:
			failures.append("batu kebanyakan: %d/400" % counts[2])
		if float(counts[0]) / 400.0 < 0.4:
			failures.append("rumput kesedikit: %d/400" % counts[0])
		# Danau bertepi berombak: jari-jari di dua sudut harus beda jelas
		# (tidak ada garis lurus di tepi).
		var r0: float = _world._lake_radius_at(0.0)
		var r1: float = _world._lake_radius_at(PI * 0.5)
		if absf(r0 - r1) < 1.0:
			failures.append("tepi danau kurang berombak: r0=%f r1=%f" % [r0, r1])
		# Terrain bertekstur: material shader + 3 tekstur terpasang.
		if _world.terrain_material == null:
			failures.append("material terrain null")
		elif _world.terrain_material.get_shader_parameter("grass_tex") == null:
			failures.append("tekstur rumput terrain tidak terpasang")
		# World 256 m (bukan 128): ujung world masih ada tanah, bukan void.
		if absf(_world.get_height(-120.0, -120.0)) > 6.0:
			failures.append("ujung world terlalu curam")
		# Rumput: world 4x luas, jumlah helai harus naik (150k).
		if grass == null or grass.multimesh.instance_count < 80000:
			failures.append("rumput terlalu sedikit untuk world 256 m")
		# Langit + siklus hari: node ada, matahari/bulan/bintang/awan ada,
		# waktu berjalan (siang->sore->malam).
		if _sky == null:
			failures.append("langit null")
		else:
			var t0: float = _sky.time_of_day
			_sky.set_time_of_day(12.0)
			if absf(_sky.time_of_day - 12.0) > 0.01:
				failures.append("set waktu gagal")
			_sky.set_time_of_day(t0)
			if _sky.get_node_or_null("StarDome") == null:
				failures.append("kubah bintang tidak ada")
			var sun_found := false
			var moon_found := false
			for child in _sky.get_children():
				if child is Sprite3D and child.texture != null:
					if child.texture.resource_path.ends_with("sun.png"):
						sun_found = true
					if child.texture.resource_path.ends_with("moon.png"):
						moon_found = true
			if not sun_found:
				failures.append("matahari tidak ada")
			if not moon_found:
				failures.append("bulan tidak ada")
		var cam := get_tree().get_first_node_in_group("fly_camera")
		if cam == null:
			failures.append("kamera terbang null")
		elif not cam.current:
			failures.append("kamera terbang tidak aktif")
	var ambience := get_tree().get_first_node_in_group("ambience")
	if ambience == null:
		failures.append("ambience null")
	if failures.is_empty():
		print("WORLD_TEST PASS")
		get_tree().quit(0)
	else:
		print("WORLD_TEST FAIL: " + ", ".join(failures))
		get_tree().quit(1)
