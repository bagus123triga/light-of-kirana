extends Node3D

## LIGHT OF KIRANA — dunia v5 (REBUILD DARI 0, minta Bagus 2026-11-09:
## "rebuild world map dari 0, clean dulu repo, yang bagus kayak Zelda/Genshin").
## Open world 384 m: laut di barat (pantai), pegunungan di utara, padang
## rumput di tengah, hutan di timur, danau + jalanan tanah.
## Ditulis bersih dari nol (skill GodotPrompter: procedural-generation +
## gdscript-patterns): RNG ber-seed, FastNoiseLite, type hint di mana-mana.
## Langit = shader stylized (shaders/sky.gdshader, prosedural, tanpa foto).
## Rumput MultiMesh per chunk + dicull di belakang jarak pandang (pengganti kabut).
## Tanpa pohon & batu (minta Bagus 2026-11-09).

enum GroundType { GRASS, DIRT, ROCK }

const WORLD_SIZE := 384.0
const SUBDIV := 192  # grid 2 m (193x193 vertex, ringan buat tablet)
const WATER_LEVEL := -0.25
const SEA_X := -150.0  # barat (x < -150) = laut
const MOUNTAIN_Z := -150.0  # utara (z < -150) = pegunungan
const LAKE_CENTER := Vector2(60.0, 35.0)
const LAKE_RADIUS := 12.0
const FOREST_X := 90.0  # timur (x > 90) = hutan (rumput lebih rapat + gelap)
const GRASS_CHUNKS := 6  # 6x6 = 36 chunk, tiap chunk 64 m
const VIEW_DISTANCE := 150.0  # rumput di belakang ini tidak di-render

# Bukit (dataran datar, bukit cuma di tempat tertentu).
# [tengah, jari-jari, tinggi]. Jauh dari spawn (0,0) + danau (60,35).
const HILLS: Array = [
	[Vector2(-70.0, -60.0), 28.0, 12.0],
	[Vector2(70.0, -70.0), 32.0, 15.0],
	[Vector2(-80.0, 70.0), 24.0, 9.0],
	[Vector2(80.0, 80.0), 30.0, 11.0],
	[Vector2(0.0, -100.0), 26.0, 10.0],
	[Vector2(-120.0, 0.0), 22.0, 8.0],
]

# Jalanan tanah coklat (bukan bercak ngacak). Tiap jalan = polyline.
# Semua berangkat dari spawn (0,0).
const PATHS: Array = [
	[Vector2(0.0, 0.0), Vector2(20.0, 12.0), Vector2(40.0, 24.0), Vector2(52.0, 31.0)],  # spawn -> danau
	[Vector2(0.0, 0.0), Vector2(-40.0, 5.0), Vector2(-90.0, 8.0), Vector2(-140.0, 5.0)],  # spawn -> pantai barat
	[Vector2(0.0, 0.0), Vector2(30.0, -5.0), Vector2(70.0, -8.0), Vector2(100.0, -5.0)],  # spawn -> hutan timur
	[Vector2(0.0, 0.0), Vector2(-5.0, -30.0), Vector2(-8.0, -70.0), Vector2(-5.0, -110.0)],  # spawn -> pegunungan utara
]
const PATH_HALF_WIDTH := 2.0

var grass_material: ShaderMaterial
var terrain_material: ShaderMaterial
var wind_strength := 0.35

var _height_noise := FastNoiseLite.new()
var _dirt_noise := FastNoiseLite.new()
var _ambience: Node
var _grass_chunks: Array[Dictionary] = []

# Cache tinggi tanah (grid 193x193). get_height() baca dari grid (bilinear)
# biar pembuatan terrain + rumput + collision tidak ngulang noise berkali-kali.
# Tanpa ini, world test headless jalan >8 menit (GDScript lambat hitung noise).
var _height_grid := PackedFloat32Array()
var _grid_step := 0.0


func _ready() -> void:
	_height_noise.seed = 1234
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.012
	_height_noise.fractal_octaves = 3
	_dirt_noise.seed = 777
	_dirt_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dirt_noise.frequency = 0.5
	_ambience = get_node_or_null("Ambience")
	_build_height_grid()
	_create_terrain()
	_create_water()
	_create_grass()
	_create_shrine()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var g := sin(t * 0.10) * 0.6 + sin(t * 0.023 + 1.7) * 0.4
	wind_strength = clampf(g, 0.0, 1.0)
	if grass_material:
		grass_material.set_shader_parameter("wind_amount", wind_strength)
	if _ambience and _ambience.has_method("set_wind"):
		_ambience.set_wind(wind_strength)
	_update_grass_culling()


func _update_grass_culling() -> void:
	var cam := get_tree().get_first_node_in_group("fly_camera") as Camera3D
	if cam == null or _grass_chunks.is_empty():
		return
	var cp := cam.global_position
	var chunk_half_diag := (WORLD_SIZE / GRASS_CHUNKS) * 0.7071
	for c in _grass_chunks:
		var center: Vector3 = c["center"]
		var node: MultiMeshInstance3D = c["node"]
		var d := Vector2(cp.x - center.x, cp.z - center.z).length()
		node.visible = d < VIEW_DISTANCE + chunk_half_diag


# --- Tinggi tanah ---

func _build_height_grid() -> void:
	_grid_step = WORLD_SIZE / SUBDIV
	var half := WORLD_SIZE * 0.5
	_height_grid.resize((SUBDIV + 1) * (SUBDIV + 1))
	for j in SUBDIV + 1:
		for i in SUBDIV + 1:
			_height_grid[j * (SUBDIV + 1) + i] = _compute_height_raw(-half + i * _grid_step, -half + j * _grid_step)


# Tinggi tanah dari grid (bilinear). Cepat; dipakai terrain/rumput/collision/test.
func get_height(x: float, z: float) -> float:
	if _height_grid.is_empty():
		return _compute_height_raw(x, z)
	var half := WORLD_SIZE * 0.5
	var gx := clampf((x + half) / _grid_step, 0.0, float(SUBDIV) - 0.001)
	var gz := clampf((z + half) / _grid_step, 0.0, float(SUBDIV) - 0.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - float(i)
	var fz := gz - float(j)
	var w := SUBDIV + 1
	var h00: float = _height_grid[j * w + i]
	var h10: float = _height_grid[j * w + i + 1]
	var h01: float = _height_grid[(j + 1) * w + i]
	var h11: float = _height_grid[(j + 1) * w + i + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func _lake_radius_at(angle: float) -> float:
	return LAKE_RADIUS + 2.0 * sin(angle * 2.0 + 0.7) + 1.0 * sin(angle * 5.0 + 2.0)


func _compute_height_raw(x: float, z: float) -> float:
	# Dataran bergelombang halus (bukan bukit di mana-mana).
	var h := _height_noise.get_noise_2d(x, z) * 1.5
	# Laut (barat): turun halus ke -4 m di bawah air.
	if x < SEA_X:
		var f := smoothstep(0.0, 1.0, clampf((SEA_X - x) / 40.0, 0.0, 1.0))
		h = lerpf(h, -4.0, f)
	# Pegunungan (utara): naik halus ke +25 m.
	if z < MOUNTAIN_Z:
		var f := smoothstep(0.0, 1.0, clampf((MOUNTAIN_Z - z) / 40.0, 0.0, 1.0))
		h = lerpf(h, 25.0, f)
	# Bukit: gundukan cosinus halus di titik HILLS.
	for hill in HILLS:
		var center: Vector2 = hill[0]
		var radius: float = hill[1]
		var height: float = hill[2]
		var d := Vector2(x, z).distance_to(center)
		if d < radius:
			var m := 0.5 + 0.5 * cos(PI * clampf(d / radius, 0.0, 1.0))
			h += height * m
	# Danau (cekungan bertepi berombak).
	var rel := Vector2(x, z) - LAKE_CENTER
	var d := rel.length()
	var r := _lake_radius_at(atan2(rel.y, rel.x))
	if d < r:
		var f := smoothstep(0.0, 1.0, d / r)
		h = lerpf(-1.6, h, f)
	# Ratakan area spawn (0, 0).
	var ds := Vector2(x, z).distance_to(Vector2.ZERO)
	if ds < 5.0:
		h = lerpf(0.0, h, smoothstep(0.0, 1.0, ds / 5.0))
	return h


# --- Jenis tanah ---

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _dist_to_paths(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for path in PATHS:
		for i in path.size() - 1:
			var d := _dist_to_segment(p, path[i], path[i + 1])
			if d < best:
				best = d
	return best


func get_ground_type(x: float, z: float) -> int:
	var e := 0.6
	var slope := absf(get_height(x + e, z) - get_height(x - e, z)) / (2.0 * e)
	slope = maxf(slope, absf(get_height(x, z + e) - get_height(x, z - e)) / (2.0 * e))
	if slope > 0.42:
		return GroundType.ROCK
	if _dist_to_paths(x, z) < PATH_HALF_WIDTH:
		return GroundType.DIRT
	return GroundType.GRASS


func is_forest(x: float, z: float) -> bool:
	return x > FOREST_X and get_height(x, z) > WATER_LEVEL + 0.5


# Warna tanah: hijau (rumput) / coklat (tanah gundul) / abu-abu (batu).
# Dipakai shader terrain (mask) + warna bilah rumput (INSTANCE_CUSTOM).
func _ground_color(x: float, z: float) -> Color:
	var t := get_ground_type(x, z)
	match t:
		GroundType.DIRT:
			return Color(0.45, 0.33, 0.20)
		GroundType.ROCK:
			return Color(0.42, 0.42, 0.44)
		_:
			var v := _dirt_noise.get_noise_2d(x * 0.5, z * 0.5) * 0.5 + 0.5
			var g := Color(0.28, 0.48, 0.18).lerp(Color(0.45, 0.62, 0.25), v)
			if is_forest(x, z):
				g = g * Color(0.75, 0.9, 0.7)
			return g


# Mask per-vertex buat shader terrain (1,0,0)=tanah, (0,1,0)=rumput, (0,0,1)=batu.
func _ground_mask(x: float, z: float) -> Color:
	var t := get_ground_type(x, z)
	match t:
		GroundType.DIRT:
			return Color(1, 0, 0)
		GroundType.ROCK:
			return Color(0, 0, 1)
		_:
			return Color(0, 1, 0)


# --- Terrain ---

func _create_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := WORLD_SIZE / SUBDIV
	var half := WORLD_SIZE * 0.5
	for j in SUBDIV:
		for i in SUBDIV:
			var x0 := -half + i * step
			var z0 := -half + j * step
			var x1 := x0 + step
			var z1 := z0 + step
			# [a,b,c] (bukan [a,c,b]) biar normal menghadap ATAS.
			var a := Vector3(x0, get_height(x0, z0), z0)
			var b := Vector3(x1, get_height(x1, z0), z0)
			var c := Vector3(x1, get_height(x1, z1), z1)
			var d := Vector3(x0, get_height(x0, z1), z1)
			st.set_uv(Vector2(x0, z0) * 0.33)
			st.set_color(_ground_mask(x0, z0))
			st.add_vertex(a)
			st.set_uv(Vector2(x1, z0) * 0.33)
			st.set_color(_ground_mask(x1, z0))
			st.add_vertex(b)
			st.set_uv(Vector2(x1, z1) * 0.33)
			st.set_color(_ground_mask(x1, z1))
			st.add_vertex(c)
			st.set_uv(Vector2(x0, z0) * 0.33)
			st.set_color(_ground_mask(x0, z0))
			st.add_vertex(a)
			st.set_uv(Vector2(x1, z1) * 0.33)
			st.set_color(_ground_mask(x1, z1))
			st.add_vertex(c)
			st.set_uv(Vector2(x0, z1) * 0.33)
			st.set_color(_ground_mask(x0, z1))
			st.add_vertex(d)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	terrain_material.set_shader_parameter("grass_tex", load("res://assets/textures/grass004_diff_1k.jpg"))
	terrain_material.set_shader_parameter("dirt_tex", load("res://assets/textures/dirt_floor_diff_1k.jpg"))
	terrain_material.set_shader_parameter("rock_tex", load("res://assets/textures/rock_face_diff_1k.jpg"))
	mi.material_override = terrain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Collision (HeightMapShape3D).
	var col := StaticBody3D.new()
	col.name = "TerrainCollision"
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	var data := PackedFloat32Array()
	data.resize((SUBDIV + 1) * (SUBDIV + 1))
	for j in SUBDIV + 1:
		for i in SUBDIV + 1:
			data[j * (SUBDIV + 1) + i] = get_height(-half + i * step, -half + j * step)
	hm.map_width = SUBDIV + 1
	hm.map_depth = SUBDIV + 1
	hm.map_data = data
	shape.shape = hm
	col.add_child(shape)
	add_child(col)


# --- Air (satu bidang besar: laut barat + danau) ---

func _create_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(768.0, 768.0)
	plane.subdivide_width = 24
	plane.subdivide_depth = 24
	water.mesh = plane
	water.position = Vector3(0.0, WATER_LEVEL, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://water/stylized_water.gdshader")
	water.material_override = mat
	add_child(water)


# --- Rumput (MultiMesh per chunk, dicull) ---

func _blade_mesh() -> ArrayMesh:
	# Bilah rumput: 2 quad menyilang (8 vertex), 1 segmen, lurus.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.06
	var h := 0.5
	# Quad 1 (sejajar X).
	st.add_vertex(Vector3(-w, 0, 0))
	st.add_vertex(Vector3(w, 0, 0))
	st.add_vertex(Vector3(w, h, 0))
	st.add_vertex(Vector3(-w, 0, 0))
	st.add_vertex(Vector3(w, h, 0))
	st.add_vertex(Vector3(-w, h, 0))
	# Quad 2 (sejajar Z).
	st.add_vertex(Vector3(0, 0, -w))
	st.add_vertex(Vector3(0, 0, w))
	st.add_vertex(Vector3(0, h, w))
	st.add_vertex(Vector3(0, 0, -w))
	st.add_vertex(Vector3(0, h, w))
	st.add_vertex(Vector3(0, h, -w))
	var mesh := st.commit()
	return mesh


func _create_grass() -> void:
	# Penempatan grid + jitter (BUKAN rejection sampling). Rejection sampling
	# 350k bilah di GDScript jalan >90 detik (timeout headless); grid 0.8 m
	# cuma butuh 1 cek per titik, jadi cepat + merata.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var blade := _blade_mesh()
	grass_material = ShaderMaterial.new()
	grass_material.shader = load("res://shaders/grass_wind.gdshader")
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.05
	noise_tex.noise = fnl
	grass_material.set_shader_parameter("wind_noise", noise_tex)
	grass_material.set_shader_parameter("blade_bend", 0.05)
	grass_material.set_shader_parameter("gust_strength", 0.3)
	grass_material.set_shader_parameter("still_sway_strength", 0.06)
	grass_material.set_shader_parameter("blade_width", 0.7)
	var spacing := 0.8
	var chunk_size := WORLD_SIZE / GRASS_CHUNKS
	var half := WORLD_SIZE * 0.5
	var per_side := int(chunk_size / spacing)
	var max_per_chunk := per_side * per_side
	for cj in GRASS_CHUNKS:
		for ci in GRASS_CHUNKS:
			var x0 := -half + ci * chunk_size
			var z0 := -half + cj * chunk_size
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = false
			multimesh.use_custom_data = true
			multimesh.mesh = blade
			multimesh.instance_count = max_per_chunk
			var placed := 0
			for gz in per_side:
				for gx in per_side:
					var x := x0 + (float(gx) + 0.5) * spacing + rng.randf_range(-0.3, 0.3)
					var z := z0 + (float(gz) + 0.5) * spacing + rng.randf_range(-0.3, 0.3)
					if get_ground_type(x, z) != GroundType.GRASS:
						continue
					var y := get_height(x, z)
					if y < WATER_LEVEL + 0.05:
						continue
					var t := Transform3D(
						Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)),
						Vector3(x, y, z)
					)
					multimesh.set_instance_transform(placed, t)
					var gc := _ground_color(x, z)
					multimesh.set_instance_custom_data(placed, Color(gc.r, gc.g, gc.b, rng.randf()))
					placed += 1
			multimesh.instance_count = placed
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Grass_%d_%d" % [ci, cj]
			mmi.multimesh = multimesh
			mmi.material_override = grass_material
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			_grass_chunks.append({
				"node": mmi,
				"center": Vector3(x0 + chunk_size * 0.5, 0.0, z0 + chunk_size * 0.5),
			})


# --- Kuil kecil di bukit (landmark ala Zelda) ---

func _create_shrine() -> void:
	var shrine := Node3D.new()
	shrine.name = "Shrine"
	var hx := -40.0
	var hz := -80.0
	var hy := get_height(hx, hz)
	shrine.position = Vector3(hx, hy, hz)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.62, 0.60, 0.55)
	stone.roughness = 0.9
	# Alas batu.
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(6.0, 0.6, 6.0)
	base.mesh = base_mesh
	base.position = Vector3(0, 0.3, 0)
	base.material_override = stone
	shrine.add_child(base)
	# 4 pilar.
	for px in [-2.0, 2.0]:
		for pz in [-2.0, 2.0]:
			var pillar := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.35
			pm.bottom_radius = 0.4
			pm.height = 3.0
			pillar.mesh = pm
			pillar.position = Vector3(px, 2.1, pz)
			pillar.material_override = stone
			shrine.add_child(pillar)
	# Atap.
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(6.5, 0.4, 6.5)
	roof.mesh = rm
	roof.position = Vector3(0, 3.8, 0)
	roof.material_override = stone
	shrine.add_child(roof)
	add_child(shrine)
