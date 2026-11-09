extends Node3D

## LIGHT OF KIRANA — landmark ala peta referensi Bagus (2026-11-09).
## Gambar referensi: desa + kincir angin + gua + menara reruntuhan + kuil kristal
## + dermaga + reruntuhan kuno + gunung salju + air terjun + sungai + jembatan.
## SEMUA model DICARI (bukan dibuat sendiri, minta Bagus):
## - KayKit Medieval Hexagon Pack (CC0, gratis): rumah, kincir, pasar, menara,
##   tambang (gua), sumur, jembatan, gerbang, bendera, tong/peti.
## - Polygonal Mind CC0 (GitHub): kristal (Crystal_Cluster, Small_01, Base).
## Penempatan: raycast ke bawah dari y=120 biar nempel tanah (bukan ngambang).
## Posisi (x, z) diperkirakan dari map_image.png (pulau 512 m, spawn -18,10).

const KAYKIT := "res://assets/models/kaykit"
const CRYSTAL := "res://assets/models/crystal"

# Posisi buat map Highland Island seed 2026 (spawn baru 136,6,102).
# Danau di (44..104, -6..124), sungai timur mengalir utara->danau->laut selatan.
# Gunung salju di barat laut, tebing di sekelilingnya, dataran hijau di timur.
# [path model, posisi x, posisi z, rotasi Y (derajat), skala]
const LANDMARKS: Array = [
	# --- Desa (timur danau, dekat spawn; danau/sungai sampai x~125, jadi geser ke timur) ---
	["buildings/red/building_home_A_red.gltf", 150.0, 125.0, 15.0, 1.0],
	["buildings/red/building_home_B_red.gltf", 165.0, 135.0, -30.0, 1.0],
	["buildings/red/building_home_A_red.gltf", 175.0, 115.0, 90.0, 1.0],
	["buildings/red/building_home_B_red.gltf", 180.0, 130.0, 160.0, 1.0],
	["buildings/red/building_market_red.gltf", 160.0, 110.0, 0.0, 1.0],
	["buildings/red/building_well_red.gltf", 155.0, 120.0, 0.0, 1.0],
	["buildings/red/building_blacksmith_red.gltf", 170.0, 145.0, 45.0, 1.0],
	["buildings/red/building_tavern_red.gltf", 175.0, 100.0, -60.0, 1.0],
	["decoration/props/flag_blue.gltf", 160.0, 118.0, 0.0, 1.0],
	["decoration/props/barrel.gltf", 158.0, 125.0, 0.0, 1.0],
	["decoration/props/crate_A_small.gltf", 165.0, 125.0, 20.0, 1.0],
	# --- Kincir angin (utara desa, di bukit) ---
	["buildings/red/building_windmill_red.gltf", 160.0, 70.0, 30.0, 1.0],
	# --- Menara reruntuhan (kaki gunung, selatan salju) ---
	["buildings/red/building_tower_A_red.gltf", 0.0, -10.0, 0.0, 1.0],
	["buildings/red/building_tower_B_red.gltf", 20.0, -20.0, 40.0, 1.0],
	# --- Tambang = pintu gua (tebing barat) ---
	["buildings/red/building_mine_red.gltf", -55.0, 25.0, 90.0, 1.0],
	# --- Gerbang reruntuhan kuno (timur jauh) ---
	["buildings/neutral/wall_straight_gate.gltf", 195.0, 35.0, -90.0, 1.0],
	["buildings/neutral/wall_straight_gate.gltf", 195.0, 45.0, -90.0, 1.0],
	# --- Jembatan (di atas sungai) ---
	["buildings/neutral/building_bridge_A.gltf", 150.0, -30.0, 90.0, 1.0],
	["buildings/neutral/building_bridge_B.gltf", 110.0, 175.0, 90.0, 1.0],
	# --- Kuil kristal (barat sungai selatan danau) ---
	["CRYSTAL_Cluster", 30.0, 180.0, 0.0, 2.0],
	["CRYSTAL_Small", 25.0, 185.0, 0.0, 1.0],
	["CRYSTAL_Small", 35.0, 185.0, 0.0, 1.0],
	["CRYSTAL_Base", 30.0, 175.0, 0.0, 1.5],
]


func _ready() -> void:
	# Tunggu 1 frame biar collision map ke-load, baru raycast.
	await get_tree().process_frame
	await get_tree().process_frame
	var placed := 0
	var failed: Array[String] = []
	for lm in LANDMARKS:
		var path: String = lm[0]
		var x: float = lm[1]
		var z: float = lm[2]
		var rot_y: float = lm[3]
		var scale: float = lm[4]
		var scene: PackedScene
		if path.begins_with("CRYSTAL"):
			var fname := ""
			match path:
				"CRYSTAL_Cluster":
					fname = "Crystal_Cluster.glb"
				"CRYSTAL_Small":
					fname = "Crystal_Small_01.glb"
				"CRYSTAL_Base":
					fname = "Crystal_Base.glb"
			scene = load(CRYSTAL + "/" + fname)
		else:
			scene = load(KAYKIT + "/" + path)
		if scene == null:
			failed.append(path)
			continue
		var y := _ground_height(x, z)
		if y < -50.0:
			failed.append("%s di (%d,%d): tanah tidak ketemu" % [path, int(x), int(z)])
			continue
		if y < 0.5:
			failed.append("%s di (%d,%d): di air (y=%.1f), dilewati" % [path, int(x), int(z), y])
			continue
		var node := scene.instantiate()
		node.position = Vector3(x, y, z)
		node.rotation_degrees.y = rot_y
		node.scale = Vector3.ONE * scale
		add_child(node)
		placed += 1
	print("LANDMARKS: placed=%d failed=%d" % [placed, failed.size()])
	for f in failed:
		print("  - " + f)


func _ground_height(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 400.0, z), Vector3(x, -10.0, z)
	)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return -100.0
	return (hit["position"] as Vector3).y
