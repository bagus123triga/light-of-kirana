extends StaticBody3D
class_name KiranaTree

## Pohon yang bisa ditebang: 3 tebasan -> roboh -> kayu -> tunggul -> tumbuh lagi.
## Root = StaticBody3D (tabrakan batang). Visual ada di Pivot agar bisa
## dijatuhkan dengan rotasi tanpa memindah tabrakan.

const MAX_HP := 3
const REGROW_SECONDS := 60.0

var hp := MAX_HP
var fallen := false

var _pivot: Node3D
var _collision: CollisionShape3D
var _fall_tween: Tween
var _shake_tween: Tween
var _regrow_timer := 0.0


func _ready() -> void:
	_pivot = $Pivot
	_collision = $CollisionShape3D


func chop(from_position: Vector3) -> void:
	if fallen:
		return
	hp -= 1
	_play_chop_sound()
	if hp > 0:
		_shake()
	else:
		_fall(from_position)


func _shake() -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_pivot.rotation = Vector3.ZERO
	_shake_tween = create_tween()
	_shake_tween.tween_property(_pivot, "rotation:z", 0.06, 0.07)
	_shake_tween.tween_property(_pivot, "rotation:z", -0.05, 0.09)
	_shake_tween.tween_property(_pivot, "rotation:z", 0.0, 0.08)


func _fall(from_position: Vector3) -> void:
	fallen = true
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_pivot.rotation = Vector3.ZERO
	_collision.set_deferred("disabled", true)
	_play_fall_sound()
	# Jatuh menjauhi pemain: sumbu putar = horizontal, tegak lurus arah jatuh.
	var fall_dir := (global_position - from_position)
	fall_dir.y = 0.0
	if fall_dir.length() < 0.01:
		fall_dir = Vector3.FORWARD
	fall_dir = fall_dir.normalized()
	# Putar pivot 90 derajat menjauhi pemain (lihat rotation di bawah).
	if _fall_tween and _fall_tween.is_valid():
		_fall_tween.kill()
	_fall_tween = create_tween()
	_fall_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Tween rotasi via basis: pakai rotation dengan sumbu lokal yang sudah
	# diputar menghadap arah jatuh (pivot diputar dulu di sumbu Y).
	_pivot.rotation.y = atan2(fall_dir.x, fall_dir.z)
	_fall_tween.tween_property(_pivot, "rotation:x", deg_to_rad(86.0), 0.7)
	_fall_tween.tween_callback(_spawn_logs)
	_regrow_timer = REGROW_SECONDS


func _spawn_logs() -> void:
	# 3 kayu kecil di dekat pangkal, menghilang sendiri setelah 8 detik.
	for i in 3:
		var log := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.14
		mesh.bottom_radius = 0.14
		mesh.height = 0.9
		log.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.38, 0.20)
		mat.roughness = 1.0
		log.material_override = mat
		log.rotation_degrees = Vector3(90.0, 0.0, randf() * 180.0)
		log.position = Vector3(randf_range(-0.8, 0.8), 0.18, randf_range(-0.8, 0.8))
		add_child(log)
		var tw := create_tween()
		tw.tween_interval(8.0)
		tw.tween_callback(log.queue_free)


func _process(delta: float) -> void:
	if fallen and _regrow_timer > 0.0:
		_regrow_timer -= delta
		if _regrow_timer <= 0.0:
			_regrow()


func _regrow() -> void:
	hp = MAX_HP
	fallen = false
	_pivot.rotation = Vector3.ZERO
	_collision.set_deferred("disabled", false)


func _play_chop_sound() -> void:
	var ambience := get_tree().get_first_node_in_group("ambience")
	if ambience and ambience.has_method("play_chop"):
		ambience.play_chop()


func _play_fall_sound() -> void:
	var ambience := get_tree().get_first_node_in_group("ambience")
	if ambience and ambience.has_method("play_fall"):
		ambience.play_fall()
