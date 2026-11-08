extends Node3D

# LIGHT OF KIRANA — main: rakit dunia + kamera terbang + suara.
# Mode kamera saja, tanpa pemain (minta Bagus 2026-11-09).
# Jalankan tes dunia headless: godot --headless --path . -- --world-test

const WorldScript := preload("res://scripts/world.gd")
const FlyCameraScript := preload("res://scripts/fly_camera.gd")
const AmbienceScript := preload("res://scripts/ambience.gd")

var _world: Node3D
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
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "LIGHT OF KIRANA — mode kamera | Joystick/WASD gerak, NAIK/TURUN, CEPAT, drag kanan lihat-lihat"
	label.position = Vector2(16, 16)
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
		if _world.trees.size() < 10:
			failures.append("pohon kurang: %d" % _world.trees.size())
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
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var counts := [0, 0, 0]
		for i in 400:
			var x := rng.randf_range(-30.0, 30.0)
			var z := rng.randf_range(-30.0, 30.0)
			counts[_world.get_ground_type(x, z)] += 1
		print("GROUND: rumput=%d tanah=%d batu=%d" % counts)
		if float(counts[2]) / 400.0 > 0.25:
			failures.append("batu kebanyakan: %d/400" % counts[2])
		if float(counts[0]) / 400.0 < 0.4:
			failures.append("rumput kesedikit: %d/400" % counts[0])
		# Tebang satu pohon sampai roboh (logika pohon tetap hidup, walau
		# tanpa pemain yang menebang).
		var tree = _world.trees[0]
		tree.chop(Vector3(0.0, 9.0, 20.0))
		tree.chop(Vector3(0.0, 9.0, 20.0))
		tree.chop(Vector3(0.0, 9.0, 20.0))
		if not tree.fallen:
			failures.append("pohon tidak roboh setelah 3 tebasan")
		# Kamera terbang: ada, aktif, dan bisa gerak.
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
