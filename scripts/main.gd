extends Node3D

# LIGHT OF KIRANA — main: rakit dunia + pemain + suara.
# Jalankan tes dunia headless: godot --headless --path . -- --world-test

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player_controller.gd")
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
	var player := CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.position = Vector3(0.0, 1.0, 6.0)
	player.world = _world
	player.ambience = ambience
	add_child(player)
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "LIGHT OF KIRANA — dunia v1 | WASD gerak, Space lompat, F tebas pohon, V/TERBANG mode terbang (joystick gerak, NAIK/TURUN, drag kanan lihat-lihat)"
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
		# Tebang satu pohon sampai roboh.
		var tree = _world.trees[0]
		tree.chop(Vector3(0.0, 1.0, 6.0))
		tree.chop(Vector3(0.0, 1.0, 6.0))
		tree.chop(Vector3(0.0, 1.0, 6.0))
		if not tree.fallen:
			failures.append("pohon tidak roboh setelah 3 tebasan")
		# Mode terbang: nyala, kamera terbang jadi aktif, lalu balik lagi.
		var player := get_tree().get_first_node_in_group("player")
		if player == null:
			failures.append("pemain null")
		else:
			player.set_fly_mode(true)
			if not player.fly_mode:
				failures.append("mode terbang tidak nyala")
			if player._fly_cam == null or not player._fly_cam.current:
				failures.append("kamera terbang tidak aktif")
			player.set_fly_mode(false)
			if player.fly_mode:
				failures.append("mode terbang tidak mati")
		# Pemain harus sudah mendarat di tanah (validasi tabrakan heightmap).
		if player:
			var ground_h: float = _world.get_height(player.global_position.x, player.global_position.z)
			if absf(player.global_position.y - ground_h) > 0.6:
				failures.append("pemain tidak mendarat: y=%f tanah=%f" % [player.global_position.y, ground_h])
	var ambience := get_tree().get_first_node_in_group("ambience")
	if ambience == null:
		failures.append("ambience null")
	if failures.is_empty():
		print("WORLD_TEST PASS")
		get_tree().quit(0)
	else:
		print("WORLD_TEST FAIL: " + ", ".join(failures))
		get_tree().quit(1)
