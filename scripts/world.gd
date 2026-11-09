extends Node3D

## LIGHT OF KIRANA — dunia v1.
## Tanah berbukit dari heightmap + noise (tanpa addon), dicat per-vertex:
## rumput / tanah gundul / batu (lereng curam). Danau + air shader stylized.
## Rumput MultiMesh + shader angin. Pohon bisa ditebang. Bebatuan.
## Cahaya: 1 matahari + langit + kabut (GL Compatibility).

enum GroundType { GRASS, DIRT, ROCK }

const WORLD_SIZE := 64.0
const SUBDIV := 64
const LAKE_CENTER := Vector2(14.0, 12.0)
const LAKE_RADIUS := 9.0
const WATER_LEVEL := -0.25
const GRASS_COUNT := 30000
const TREE_COUNT := 24
const BOULDER_COUNT := 14

var trees: Array = []
var grass_material: ShaderMaterial
var wind_strength := 0.35

var _height_noise := FastNoiseLite.new()
var _dirt_noise := FastNoiseLite.new()
var _ambience: Node


func _ready() -> void:
	_height_noise.seed = 1234
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.035
	_height_noise.fractal_octaves = 4
	_dirt_noise.seed = 777
	_dirt_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dirt_noise.frequency = 0.08
	_dirt_noise.fractal_octaves = 3
	_ambience = get_tree().get_first_node_in_group("ambience")
	_create_environment()
	_create_terrain()
	_create_water()
	_create_grass()
	_create_trees()
	_create_boulders()


func _process(delta: float) -> void:
	# SATU nilai angin untuk semuanya: goyangan rumput (shader) + volume
	# suara angin. Angin TIDAK terus-menerus — kadang reda total (0),
	# kadang berhembus kencang (1). Dua sinus berperiode beda biar
	# polanya tidak berulang monoton.
	var t := Time.get_ticks_msec() / 1000.0
	var g := sin(t * 0.10) * 0.6 + sin(t * 0.023 + 1.7) * 0.4
	wind_strength = clampf(g, 0.0, 1.0)
	if grass_material:
		grass_material.set_shader_parameter("wind_amount", wind_strength)
	if _ambience and _ambience.has_method("set_wind"):
		_ambience.set_wind(wind_strength)


func set_interaction_position(p: Vector3) -> void:
	# Kamera (mode kamera saja) mendorong rumput saat lewat — interaksi
	# player_position dari shader gameidea.
	if grass_material:
		grass_material.set_shader_parameter("player_position", p)


# --- Tinggi & jenis tanah (satu rumus dipakai mesh, rumput, pohon, pemain) ---

func get_height(x: float, z: float) -> float:
	var h := _height_noise.get_noise_2d(x, z) * 3.0
	var d := Vector2(x, z).distance_to(LAKE_CENTER)
	if d < LAKE_RADIUS:
		var f := smoothstep(0.0, 1.0, d / LAKE_RADIUS)
		h = lerpf(-1.6, h, f)
	# Ratakan area spawn pemain (0, 6).
	var ds := Vector2(x, z).distance_to(Vector2(0.0, 6.0))
	if ds < 4.0:
		h = lerpf(0.0, h, smoothstep(0.0, 1.0, ds / 4.0))
	return h


func get_ground_type(x: float, z: float) -> int:
	var e := 0.6
	var slope := absf(get_height(x + e, z) - get_height(x - e, z)) / (2.0 * e)
	slope = maxf(slope, absf(get_height(x, z + e) - get_height(x, z - e)) / (2.0 * e))
	if slope > 0.42:
		return GroundType.ROCK
	if _dirt_noise.get_noise_2d(x, z) > 0.25:
		return GroundType.DIRT
	return GroundType.GRASS


func _ground_color(x: float, z: float) -> Color:
	match get_ground_type(x, z):
		GroundType.ROCK:
			return Color(0.36, 0.34, 0.33)
		GroundType.DIRT:
			return Color(0.45, 0.33, 0.20)
		_:
			var v := 0.9 + 0.2 * _dirt_noise.get_noise_2d(x * 0.5, z * 0.5)
			return Color(0.30 * v, 0.48 * v, 0.20 * v)


# --- Langit, matahari, kabut ---

func _create_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.60, 0.90)
	sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_bottom_color = Color(0.25, 0.30, 0.25)
	sky_mat.ground_horizon_color = Color(0.70, 0.78, 0.85)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.80, 0.92)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.83, 0.92)
	env.fog_density = 0.004
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


# --- Tanah ---

func _create_terrain() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var heights := PackedFloat32Array()
	var half := WORLD_SIZE * 0.5
	var step := WORLD_SIZE / SUBDIV
	for j in SUBDIV + 1:
		for i in SUBDIV + 1:
			var x := -half + i * step
			var z := -half + j * step
			var h := get_height(x, z)
			verts.append(Vector3(x, h, z))
			normals.append(Vector3.UP)
			colors.append(_ground_color(x, z))
			heights.append(h)
	for j in SUBDIV:
		for i in SUBDIV:
			var a := j * (SUBDIV + 1) + i
			var b := a + 1
			var c := a + SUBDIV + 1
			var d := c + 1
			# Urutan segitiga [a,b,c, b,d,c] — generate_normals() memberi
			# normal ke ATAS untuk urutan ini; [a,c,b] terbalik (normal
			# ke bawah, tanah cuma kena ambient → putih di tablet).
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Normal yang benar (bukan UP mentah) — penting buat cahaya lereng.
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	mesh = st.commit()
	var body := StaticBody3D.new()
	body.name = "Terrain"
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	var shape := HeightMapShape3D.new()
	shape.map_width = SUBDIV + 1
	shape.map_depth = SUBDIV + 1
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	# HeightMapShape3D berpusat di origin dengan jarak sampel 1 m — sama
	# dengan grid mesh (64 m / 64 subdivisi), jadi tanpa offset.
	body.add_child(collision)


# --- Danau (air dari godotlearning.com, CC0) ---

func _create_water() -> void:
	# Shader + material + normal map dari paket CC0 godotlearning
	# "Stylized Water" (res://water/). Plane 20 m, verteks tiap 0.25 m
	# (subdivide 80) — sesuai petunjuk halaman itu. Node jangan di-rotate
	# atau di-scale, ukur lewat PlaneMesh.
	var plane := PlaneMesh.new()
	plane.size = Vector2(LAKE_RADIUS * 2.0 + 2.0, LAKE_RADIUS * 2.0 + 2.0)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.position = Vector3(LAKE_CENTER.x, WATER_LEVEL, LAKE_CENTER.y)
	water.material_override = load("res://water/water_material.tres")
	add_child(water)


# --- Rumput (hanya di tanah berumput, bukan tanah gundul / batu) ---

func _blade_mesh() -> ArrayMesh:
	# 2 quad menyilang. Shader repo TIDAK punya discard/taper, jadi
	# bentuk runcingnya dari GEOMETRI: 3 baris, lebar menyempit ke ujung
	# (0.12 → 0.08 → 0.03). Bilah tetap LURUS — barisnya buat lancip,
	# bukan buat melengkung (minta Bagus: lurus aja).
	# Ukuran direvisi 2026-11-09: 0.06 x 0.6 kekecilan + ketinggian,
	# jadi dilebarin & dipendekin (0.12 x 0.4).
	# UV.y = 0 di ujung, 1 di pangkal (syarat repo: displacement
	# affect = 1.0 - UV.y, ujung paling kena angin).
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rows := [0.0, 0.2, 0.4]
	var row_half_w := [0.06, 0.04, 0.015]
	var row_uv := [1.0, 0.5, 0.0]
	var quads := [
		[Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)],
		[Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0)],
	]
	var base := 0
	for q in quads:
		var left_dir: Vector3 = q[0]
		var right_dir: Vector3 = q[1]
		var up := Vector3(0.0, 1.0, 0.0)
		for r in rows.size():
			verts.append(left_dir * row_half_w[r] + up * rows[r])
			verts.append(right_dir * row_half_w[r] + up * rows[r])
			uvs.append(Vector2(0.0, row_uv[r]))
			uvs.append(Vector2(1.0, row_uv[r]))
		for r in rows.size() - 1:
			var b0 := base + r * 2
			indices.append_array([b0, b0 + 1, b0 + 3, b0, b0 + 3, b0 + 2])
		base += rows.size() * 2
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _create_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var blade := _blade_mesh()
	grass_material = ShaderMaterial.new()
	grass_material.shader = load("res://shaders/grass_wind.gdshader")
	# Tekstur noise shader gameidea: NoiseTexture2D (dibuat di kode, karena
	# artikelnya juga membuatnya di editor, bukan dari file).
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.05
	noise_tex.noise = fnl
	grass_material.set_shader_parameter("wind_noise", noise_tex)
	# Nilai angin repo dilunakkan biar bilah tegak lurus & cuma
	# bergoyang pelan (minta Bagus: angin kekencengan, bilah lurus).
	# wind_strength repo = 1.0, wind_vertical_strength repo = 0.5.
	grass_material.set_shader_parameter("wind_strength", 0.35)
	grass_material.set_shader_parameter("wind_vertical_strength", 0.05)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.use_custom_data = true
	multimesh.mesh = blade
	multimesh.instance_count = GRASS_COUNT
	var placed := 0
	var guard := 0
	var half := WORLD_SIZE * 0.5 - 2.0
	while placed < GRASS_COUNT and guard < GRASS_COUNT * 20:
		guard += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
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
		# Warna rumput NGIKUT warna tanah di bawahnya (minta Bagus):
		# INSTANCE_CUSTOM.rgb = warna tanah titik itu, .a = variasi acak.
		var gc := _ground_color(x, z)
		multimesh.set_instance_custom_data(placed, Color(gc.r, gc.g, gc.b, rng.randf()))
		placed += 1
	multimesh.instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = multimesh
	mmi.material_override = grass_material
	# Rumput tidak melempar bayangan — bayangan tongkat yang panjang
	# bikin helai kelihatan makin kaku, dan hemat GPU.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# --- Pohon ---

func _make_tree() -> KiranaTree:
	var tree := KiranaTree.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 2.0
	collision.shape = shape
	collision.position.y = 1.0
	tree.add_child(collision)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	tree.add_child(pivot)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.35
	trunk_mesh.height = 2.2
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.42, 0.28, 0.15)
	trunk_mat.roughness = 1.0
	trunk.material_override = trunk_mat
	pivot.add_child(trunk)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.16, 0.42, 0.14)
	leaf_mat.roughness = 1.0
	for pos in [Vector3(0.0, 2.9, 0.0), Vector3(0.45, 3.6, 0.2), Vector3(-0.4, 3.5, -0.25)]:
		var leaf := MeshInstance3D.new()
		var leaf_mesh := SphereMesh.new()
		leaf_mesh.radius = 1.25 if pos.y < 3.0 else 0.9
		leaf_mesh.height = leaf_mesh.radius * 2.0
		leaf.mesh = leaf_mesh
		leaf.position = pos
		leaf.material_override = leaf_mat
		pivot.add_child(leaf)
	var stump := MeshInstance3D.new()
	var stump_mesh := CylinderMesh.new()
	stump_mesh.top_radius = 0.3
	stump_mesh.bottom_radius = 0.34
	stump_mesh.height = 0.4
	stump.mesh = stump_mesh
	stump.position.y = 0.2
	var stump_mat := StandardMaterial3D.new()
	stump_mat.albedo_color = Color(0.5, 0.36, 0.2)
	stump_mat.roughness = 1.0
	stump.material_override = stump_mat
	tree.add_child(stump)
	return tree


func _create_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var placed := 0
	var guard := 0
	var half := WORLD_SIZE * 0.5 - 3.0
	while placed < TREE_COUNT and guard < TREE_COUNT * 40:
		guard += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if get_ground_type(x, z) != GroundType.GRASS:
			continue
		if Vector2(x, z).distance_to(Vector2(0.0, 6.0)) < 4.0:
			continue
		var ok := true
		for other in trees:
			if Vector2(x, z).distance_to(Vector2(other.position.x, other.position.z)) < 3.0:
				ok = false
				break
		if not ok:
			continue
		var tree := _make_tree()
		tree.position = Vector3(x, get_height(x, z), z)
		add_child(tree)
		trees.append(tree)
		placed += 1


# --- Bebatuan ---

func _create_boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.42, 0.40, 0.39)
	rock_mat.roughness = 0.95
	var placed := 0
	var guard := 0
	var half := WORLD_SIZE * 0.5 - 3.0
	while placed < BOULDER_COUNT and guard < BOULDER_COUNT * 30:
		guard += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if get_height(x, z) < WATER_LEVEL + 0.1:
			continue
		if Vector2(x, z).distance_to(Vector2(0.0, 6.0)) < 4.0:
			continue
		var scale := rng.randf_range(0.6, 2.2)
		var body := StaticBody3D.new()
		body.position = Vector3(x, get_height(x, z) + scale * 0.25, z)
		body.rotation.y = rng.randf() * TAU
		add_child(body)
		var mesh_instance := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 12
		mesh.rings = 8
		mesh_instance.mesh = mesh
		mesh_instance.scale = Vector3(scale, scale * 0.7, scale * rng.randf_range(0.8, 1.2))
		mesh_instance.material_override = rock_mat
		body.add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.0
		collision.shape = shape
		collision.scale = mesh_instance.scale
		body.add_child(collision)
		placed += 1
