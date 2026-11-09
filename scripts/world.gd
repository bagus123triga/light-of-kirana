extends Node3D

## LIGHT OF KIRANA — dunia v1.
## Tanah berbukit dari heightmap + noise (tanpa addon), bertekstur CC0
## Poly Haven (rumput / tanah gundul / batu lereng curam, mask per-vertex).
## Danau bertepi berombak (tanpa garis lurus) + air shader stylized.
## Rumput MultiMesh + shader angin. Tanpa pohon & batu (minta Bagus 2026-11-09).
## Cahaya: 1 matahari + langit + kabut (GL Compatibility).

enum GroundType { GRASS, DIRT, ROCK }

const WORLD_SIZE := 64.0
const SUBDIV := 64
const LAKE_CENTER := Vector2(14.0, 12.0)
const LAKE_RADIUS := 9.0
const WATER_LEVEL := -0.25
const GRASS_COUNT := 60000

var grass_material: ShaderMaterial
var terrain_material: ShaderMaterial
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

# Jari-jari danau berubah-ubah menurut sudut (2 sinus, periode beda) —
# tepinya berombak organik, tidak ada garis lurus (minta Bagus 2026-11-09).
# Rentang ~6–12 m. Kontinu di sudut 0/2π (sinus kelipatan bulat).
func _lake_radius_at(angle: float) -> float:
	return LAKE_RADIUS + 2.0 * sin(angle * 2.0 + 0.7) + 1.0 * sin(angle * 5.0 + 2.0)


func get_height(x: float, z: float) -> float:
	var h := _height_noise.get_noise_2d(x, z) * 3.0
	var rel := Vector2(x, z) - LAKE_CENTER
	var d := rel.length()
	var r := _lake_radius_at(atan2(rel.y, rel.x))
	if d < r:
		var f := smoothstep(0.0, 1.0, d / r)
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


# Mask jenis tanah untuk shader terrain (r=tanah gundul, g=rumput, b=batu).
# Dipakai sebagai COLOR vertex terrain; _ground_color dipakai warna bilah rumput.
func _ground_mask(x: float, z: float) -> Color:
	match get_ground_type(x, z):
		GroundType.ROCK:
			return Color(0.0, 0.0, 1.0)
		GroundType.DIRT:
			return Color(1.0, 0.0, 0.0)
		_:
			return Color(0.0, 1.0, 0.0)


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
			colors.append(_ground_mask(x, z))
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
	# Material shader bertekstur (bukan warna vertex polos): sampling
	# tekstur CC0 Poly Haven per jenis tanah, mask dari COLOR vertex.
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	terrain_material.set_shader_parameter("grass_tex", load("res://assets/textures/leafy_grass_diff_1k.jpg"))
	terrain_material.set_shader_parameter("dirt_tex", load("res://assets/textures/dirt_floor_diff_1k.jpg"))
	terrain_material.set_shader_parameter("rock_tex", load("res://assets/textures/rock_face_diff_1k.jpg"))
	mesh_instance.material_override = terrain_material
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
	# "Stylized Water" (res://water/). BUKAN plane kotak lagi — mesh cakram
	# kustom (grid polar: 20 ring x 64 segmen) yang tepinya mengikuti jari-jari
	# danau yang berombak (radius * 1.1 + 0.5, masuk ke bawah tanah) — jadi
	# tidak ada garis lurus di tepi danau (minta Bagus 2026-11-09).
	# Ring rapat (jarak ~0.6 m) supaya gelombang vertex shader tetap kelihatan.
	var rings := 20
	var segs := 64
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Titik tengah.
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	tangents.append_array([1.0, 0.0, 0.0, 1.0])
	uvs.append(Vector2.ZERO)
	for ring in rings:
		var f := float(ring + 1) / float(rings)
		for s in segs:
			var angle := TAU * float(s) / float(segs)
			var r := _lake_radius_at(angle) * 1.1 + 0.5
			var rr := r * f
			verts.append(Vector3(cos(angle) * rr, 0.0, sin(angle) * rr))
			normals.append(Vector3.UP)
			tangents.append_array([1.0, 0.0, 0.0, 1.0])
			uvs.append(Vector2(cos(angle) * rr, sin(angle) * rr) / 8.0)
	# Kipas tengah (pusat -> ring 1).
	for s in segs:
		indices.append_array([0, 1 + s, 1 + (s + 1) % segs])
	# Quad antar ring.
	for ring in rings - 1:
		var base0 := 1 + ring * segs
		var base1 := 1 + (ring + 1) * segs
		for s in segs:
			var s1 := (s + 1) % segs
			indices.append_array([base0 + s, base1 + s, base1 + s1, base0 + s, base1 + s1, base0 + s1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var disc := ArrayMesh.new()
	disc.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = disc
	water.position = Vector3(LAKE_CENTER.x, WATER_LEVEL, LAKE_CENTER.y)
	water.material_override = load("res://water/water_material.tres")
	add_child(water)


# --- Rumput (hanya di tanah berumput, bukan tanah gundul / batu) ---

func _blade_mesh() -> ArrayMesh:
	# 2 quad menyilang — shader gameidea mengharapkan quad penuh: UV.x
	# 0..1 selebar bilah, UV.y = 0 di ujung, 1 di pangkal, biar discard-nya
	# membentuk bilah yang meruncing. LURUS saja, tanpa segmen lengkung
	# (minta Bagus 2026-11-09: "lurus aja nggak usah 3 shape").
	# Bilah TIPIS (lebar 0.06, tinggi 0.5) biar runcing.
	# Direvisi 2026-11-09: 0.6 dipendekin dikit jadi 0.5 (minta Bagus).
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half_w := 0.03
	var quads := [
		[Vector3(-half_w, 0.0, 0.0), Vector3(half_w, 0.0, 0.0)],
		[Vector3(0.0, 0.0, -half_w), Vector3(0.0, 0.0, half_w)],
	]
	var base := 0
	for q in quads:
		var bl: Vector3 = q[0]
		var br: Vector3 = q[1]
		# Kiri-bawah, kanan-bawah, kanan-atas (ujung), kiri-atas (ujung).
		verts.append_array([bl, br, br + Vector3(0.0, 0.5, 0.0), bl + Vector3(0.0, 0.5, 0.0)])
		uvs.append_array([Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)])
		indices.append_array([base + 0, base + 1, base + 2, base + 0, base + 2, base + 3])
		base += 4
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
	# Angin dilunakkan biar bilah tegak lurus & cuma bergoyang pelan
	# (minta Bagus: angin kekencengan, bilah harus lurus).
	grass_material.set_shader_parameter("blade_bend", 0.05)
	grass_material.set_shader_parameter("gust_strength", 0.3)
	grass_material.set_shader_parameter("still_sway_strength", 0.06)
	# Bilah lebih runcing: lebar discard 70% (bawah tidak terlalu besar).
	grass_material.set_shader_parameter("blade_width", 0.7)
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
