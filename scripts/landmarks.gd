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

# [path model, posisi x, posisi z, rotasi Y (derajat), skala]
const LANDMARKS: Array = [
	# --- Desa (tengah, dekat spawn) ---
	["buildings/red/building_home_A_red.gltf", -32.0, 22.0, 15.0, 1.0],
	["buildings/red/building_home_B_red.gltf", -14.0, 32.0, -30.0, 1.0],
	["buildings/red/building_home_A_red.gltf", 2.0, 18.0, 90.0, 1.0],
	["buildings/red/building_home_B_red.gltf", 12.0, 30.0, 160.0, 1.0],
	["buildings/red/building_market_red.gltf", -12.0, 8.0, 0.0, 1.0],
	["buildings/red/building_well_red.gltf", -20.0, 16.0, 0.0, 1.0],
	["buildings/red/building_blacksmith_red.gltf", -38.0, 8.0, 45.0, 1.0],
	["buildings/red/building_tavern_red.gltf", 6.0, 2.0, -60.0, 1.0],
	["decoration/props/flag_blue.gltf", -12.0, 12.0, 0.0, 1.0],
	["decoration/props/barrel.gltf", -16.0, 14.0, 0.0, 1.0],
	["decoration/props/crate_A_small.gltf", -10.0, 14.0, 20.0, 1.0],
	# --- Kincir angin (bukit timur desa) ---
	["buildings/red/building_windmill_red.gltf", 60.0, -12.0, 30.0, 1.0],
	# --- Menara reruntuhan (bukit utara) ---
	["buildings/red/building_tower_A_red.gltf", -45.0, -105.0, 0.0, 1.0],
	["buildings/red/building_tower_B_red.gltf", -30.0, -95.0, 40.0, 1.0],
	# --- Tambang = pintu gua (barat, area batu) ---
	["buildings/red/building_mine_red.gltf", -145.0, -35.0, 90.0, 1.0],
	# --- Gerbang reruntuhan kuno (timur) ---
	["buildings/neutral/wall_straight_gate.gltf", 125.0, 45.0, -90.0, 1.0],
	["buildings/neutral/wall_straight_gate.gltf", 125.0, 55.0, -90.0, 1.0],
	# --- Jembatan (di atas sungai, sungai mengalir utara-selatan di tengah) ---
	["buildings/neutral/building_bridge_A.gltf", 0.0, -45.0, 90.0, 1.0],
	["buildings/neutral/building_bridge_B.gltf", 8.0, 65.0, 90.0, 1.0],
	# --- Kuil kristal (barat daya, dekat danau) ---
	["CRYSTAL_Cluster", -85.0, 95.0, 0.0, 2.0],
	["CRYSTAL_Small", -80.0, 100.0, 0.0, 1.0],
	["CRYSTAL_Small", -90.0, 100.0, 0.0, 1.0],
	["CRYSTAL_Base", -85.0, 90.0, 0.0, 1.5],
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
		Vector3(x, 120.0, z), Vector3(x, -10.0, z)
	)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return -100.0
	return (hit["position"] as Vector3).y
