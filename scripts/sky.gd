extends Node3D

## LIGHT OF KIRANA — langit + siklus hari (minta Bagus 2026-11-09).
## Pagi, siang, sore, malam otomatis (1 hari = 10 menit). Matahari, bulan,
## bintang, awan — semuanya pakai TEKSTUR asli (bukan asal bikin):
## - Matahari: foto NASA SDO (public domain) -> sun.png
## - Bulan: foto NASA FullMoon2010 (public domain) -> moon.png
## - Bintang: foto langit malam CC0 (Wikimedia) -> stars.jpg
## - Awan: foto awan cumulus CC0 (Wikimedia), langit biru di-key -> cloud.png
## Langit (gradien) tetap ProceduralSkyMaterial; kabut + cahaya ikut waktu.
## Jarak pandang diatur kabut (VIEW_DISTANCE).

const DAY_LENGTH := 600.0  # detik untuk 1 hari penuh (10 menit)
const SKY_RADIUS := 400.0  # radius kubah bintang
const BODY_DISTANCE := 350.0  # jarak matahari/bulan dari kamera
const VIEW_DISTANCE := 200.0  # jarak pandang (kabut tipis, bukan tembok putih)
const CLOUD_COUNT := 10

var time_of_day := 8.0  # jam, 0..24. Mulai pagi.

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun_light: DirectionalLight3D
var _sun_sprite: Sprite3D
var _moon_sprite: Sprite3D
var _star_dome: MeshInstance3D
var _star_mat: ShaderMaterial
var _clouds: Array[Sprite3D] = []
var _camera: Camera3D

# Keyframe langit: [jam, sky_top, sky_horizon, ground_horizon,
#   ambient_color, ambient_energy, sun_color, sun_energy,
#   fog_color, bintang (0..1)]
const KEYS := [
	[0.0, Color(0.015, 0.02, 0.06), Color(0.04, 0.05, 0.10), Color(0.03, 0.03, 0.05), Color(0.10, 0.12, 0.20), 0.25, Color(0.0, 0.0, 0.0), 0.0, Color(0.03, 0.04, 0.08), 1.0],
	[5.0, Color(0.03, 0.04, 0.10), Color(0.10, 0.10, 0.18), Color(0.05, 0.05, 0.08), Color(0.14, 0.16, 0.24), 0.3, Color(0.0, 0.0, 0.0), 0.0, Color(0.06, 0.07, 0.12), 1.0],
	[6.5, Color(0.25, 0.35, 0.60), Color(0.95, 0.55, 0.35), Color(0.45, 0.40, 0.35), Color(0.55, 0.50, 0.55), 0.45, Color(1.0, 0.55, 0.25), 0.7, Color(0.80, 0.55, 0.45), 0.25],
	[9.0, Color(0.22, 0.48, 0.95), Color(0.68, 0.82, 0.98), Color(0.65, 0.75, 0.85), Color(0.70, 0.78, 0.92), 0.6, Color(1.0, 0.95, 0.85), 1.1, Color(0.72, 0.82, 0.95), 0.0],
	[12.0, Color(0.18, 0.45, 0.98), Color(0.68, 0.82, 0.98), Color(0.65, 0.75, 0.85), Color(0.70, 0.78, 0.92), 0.65, Color(1.0, 0.98, 0.90), 1.3, Color(0.72, 0.82, 0.95), 0.0],
	[15.0, Color(0.20, 0.47, 0.96), Color(0.70, 0.82, 0.98), Color(0.68, 0.76, 0.85), Color(0.70, 0.78, 0.92), 0.6, Color(1.0, 0.95, 0.80), 1.2, Color(0.72, 0.82, 0.95), 0.0],
	[17.5, Color(0.35, 0.50, 0.80), Color(0.95, 0.70, 0.45), Color(0.70, 0.60, 0.50), Color(0.70, 0.68, 0.75), 0.5, Color(1.0, 0.70, 0.35), 0.9, Color(0.85, 0.70, 0.55), 0.0],
	[18.5, Color(0.15, 0.18, 0.40), Color(0.90, 0.45, 0.25), Color(0.35, 0.28, 0.30), Color(0.45, 0.40, 0.55), 0.35, Color(1.0, 0.45, 0.20), 0.4, Color(0.60, 0.40, 0.35), 0.35],
	[20.0, Color(0.03, 0.04, 0.10), Color(0.08, 0.08, 0.16), Color(0.04, 0.04, 0.07), Color(0.14, 0.16, 0.24), 0.3, Color(0.0, 0.0, 0.0), 0.0, Color(0.05, 0.06, 0.10), 1.0],
	[24.0, Color(0.015, 0.02, 0.06), Color(0.04, 0.05, 0.10), Color(0.03, 0.03, 0.05), Color(0.10, 0.12, 0.20), 0.25, Color(0.0, 0.0, 0.0), 0.0, Color(0.03, 0.04, 0.08), 1.0],
]


func _ready() -> void:
	_create_environment()
	_create_sun_light()
	_create_bodies()
	_create_star_dome()
	_create_clouds()
	_update_sky(0.0)


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH * 24.0, 24.0)
	_update_sky(delta)


func set_time_of_day(hour: float) -> void:
	time_of_day = fmod(hour, 24.0)
	_update_sky(0.0)


func get_camera() -> Camera3D:
	if _camera == null:
		_camera = get_tree().get_first_node_in_group("fly_camera") as Camera3D
	return _camera


func _cam_pos() -> Vector3:
	var cam := get_camera()
	if cam:
		return cam.global_position
	return Vector3.ZERO


# --- Lingkungan (langit, kabut, cahaya ambient) ---

func _create_environment() -> void:
	var world_env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sun_angle_max = 30.0
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.glow_enabled = true
	_env.glow_intensity = 0.2
	_env.fog_enabled = true
	# Kabut TIPIS ala Zelda (bukan tembok putih): di VIEW_DISTANCE baru
	# ~60% tertutup, di jarak dekat cuma haze ringan. Dulu 1.9/VIEW_DISTANCE
	# (=0.021) terlalu over — terrain dekat pun sudah putih semua.
	_env.fog_density = 0.9 / VIEW_DISTANCE
	world_env.environment = _env
	add_child(world_env)


func _create_sun_light() -> void:
	_sun_light = DirectionalLight3D.new()
	_sun_light.shadow_enabled = true
	# Bayangan cuma di sekitar kamera (hemat GPU) — bukan seluruh world.
	_sun_light.directional_shadow_max_distance = 60.0
	add_child(_sun_light)


# --- Matahari & bulan (billboard bertekstur, ikut kamera) ---

func _make_body_sprite(tex_path: String, size: float) -> Sprite3D:
	var s := Sprite3D.new()
	var tex := load(tex_path)
	s.texture = tex
	s.pixel_size = size / 512.0
	s.shaded = false
	s.double_sided = false
	# Tanpa kabut: benda langit harus tetap kelihatan dari jauh.
	# PENTING: material_override HARUS membawa albedo_texture + billboard
	# juga — kalau tidak, sprite jadi kotak putih polos (tekstur + alpha
	# hilang) dan tidak menghadap kamera. Itu yang bikin awan kotak.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	s.material_override = mat
	add_child(s)
	return s


func _create_bodies() -> void:
	_sun_sprite = _make_body_sprite("res://assets/textures/sun.png", 80.0)
	_moon_sprite = _make_body_sprite("res://assets/textures/moon.png", 48.0)


# --- Bintang (kubah bertekstur, cuma bintangnya yang kelihatan) ---

func _create_star_dome() -> void:
	_star_mat = ShaderMaterial.new()
	_star_mat.shader = load("res://shaders/stars.gdshader")
	_star_mat.set_shader_parameter("star_tex", load("res://assets/textures/stars.jpg"))
	_star_mat.set_shader_parameter("star_brightness", 0.0)
	var sphere := SphereMesh.new()
	sphere.radius = SKY_RADIUS
	sphere.height = SKY_RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_star_dome = MeshInstance3D.new()
	_star_dome.name = "StarDome"
	_star_dome.mesh = sphere
	_star_dome.material_override = _star_mat
	_star_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_star_dome)


# --- Awan (billboard bertekstur, hanyut pelan ikut angin) ---

func _create_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tex := load("res://assets/textures/cloud.png")
	for i in CLOUD_COUNT:
		var s := Sprite3D.new()
		s.texture = tex
		# Awan besar (15-40 m) — pixel_size dari lebar tekstur 512 px.
		var w := rng.randf_range(15.0, 40.0)
		s.pixel_size = w / 512.0
		s.shaded = false
		s.modulate = Color(1, 1, 1, rng.randf_range(0.65, 0.9))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_fog = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = tex
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		s.material_override = mat
		# Posisi acak di sekitar origin; _update_sky yang menempelkan ke kamera.
		s.position = Vector3(rng.randf_range(-180.0, 180.0), rng.randf_range(65.0, 110.0), rng.randf_range(-180.0, 180.0))
		s.set_meta("drift", rng.randf_range(0.5, 1.5))
		add_child(s)
		_clouds.append(s)


# --- Update per frame ---

func _sample_keys(t: float) -> Array:
	# Cari 2 keyframe yang mengapit t, lalu interpolasi.
	var prev: Array = KEYS[0]
	var next: Array = KEYS[KEYS.size() - 1]
	for k in KEYS:
		if k[0] <= t:
			prev = k
		if k[0] >= t:
			next = k
			break
	var span: float = next[0] - prev[0]
	var f := 0.0
	if span > 0.001:
		f = (t - prev[0]) / span
	var out := []
	for i in range(1, prev.size()):
		var a = prev[i]
		var b = next[i]
		if a is Color:
			out.append(a.lerp(b, f))
		else:
			out.append(lerpf(float(a), float(b), f))
	return out


func _update_sky(delta: float) -> void:
	var k := _sample_keys(time_of_day)
	var sky_top: Color = k[0]
	var sky_horizon: Color = k[1]
	var ground_horizon: Color = k[2]
	var ambient_color: Color = k[3]
	var ambient_energy: float = k[4]
	var sun_color: Color = k[5]
	var sun_energy: float = k[6]
	var fog_color: Color = k[7]
	var stars: float = k[8]

	_sky_mat.sky_top_color = sky_top
	_sky_mat.sky_horizon_color = sky_horizon
	_sky_mat.ground_bottom_color = ground_horizon.darkened(0.4)
	_sky_mat.ground_horizon_color = ground_horizon
	_env.ambient_light_color = ambient_color
	_env.ambient_light_energy = ambient_energy
	_env.fog_light_color = fog_color

	# Matahari: terbit 06:00, tenggelam 18:00. Bulan: kebalikannya.
	# Miring ke -z (utara, ke arah depan kamera) biar matahari lebih
	# gampang kelihatan dari pandangan awal; di Indonesia (belahan selatan)
	# matahari memang sering di utara saat tengah hari.
	var sun_angle := (time_of_day - 6.0) / 12.0 * PI
	var sun_dir := Vector3(cos(sun_angle), sin(sun_angle), -0.35).normalized()
	var moon_angle := sun_angle + PI
	var moon_dir := Vector3(cos(moon_angle), sin(moon_angle), -0.35).normalized()

	# Cahaya matahari (arah + warna + intensitas ikut waktu).
	# Siang: cahaya matahari. Malam: cahaya bulan (redup, kebiruan).
	# look_at cuma dipanggil untuk benda yang lagi di atas horizon —
	# kalau arahnya sejajar sumbu Y, look_at bisa gagal.
	if sun_energy > 0.01:
		_sun_light.light_color = sun_color
		_sun_light.light_energy = sun_energy
		_sun_light.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	else:
		_sun_light.light_color = Color(0.65, 0.75, 1.0)
		_sun_light.light_energy = 0.12
		_sun_light.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)

	var cam_pos := _cam_pos()

	# Matahari & bulan: tempel di kamera, searah sudutnya, redup di horizon.
	var sun_up := clampf(sun_dir.y * 3.0, 0.0, 1.0)
	_sun_sprite.position = cam_pos + sun_dir * BODY_DISTANCE
	_sun_sprite.modulate = Color(1, 1, 1, sun_up)
	_sun_sprite.visible = sun_up > 0.01
	var moon_up := clampf(moon_dir.y * 3.0, 0.0, 1.0)
	_moon_sprite.position = cam_pos + moon_dir * BODY_DISTANCE
	_moon_sprite.modulate = Color(1, 1, 1, moon_up)
	_moon_sprite.visible = moon_up > 0.01

	# Bintang: kubah ikut kamera, terangnya ikut malam.
	_star_dome.position = cam_pos
	_star_mat.set_shader_parameter("star_brightness", stars)

	# Awan: hanyut pelan searah angin, melingkar di sekitar kamera.
	# Siang putih, malam gelap kebiruan (biar tidak menyala di malam hari).
	var day_f := clampf(sun_energy, 0.0, 1.0)
	var cloud_tint := Color(0.25, 0.30, 0.45).lerp(Color.WHITE, day_f)
	for c in _clouds:
		var drift: float = c.get_meta("drift")
		c.position.x += drift * delta
		# Jaga awan tetap di sekitar kamera (bungkus di radius 200 m).
		var rel := c.position - Vector3(cam_pos.x, 0.0, cam_pos.z)
		if rel.x > 200.0:
			c.position.x -= 400.0
		elif rel.x < -200.0:
			c.position.x += 400.0
		if rel.z > 200.0:
			c.position.z -= 400.0
		elif rel.z < -200.0:
			c.position.z += 400.0
		var m := c.modulate
		m.r = cloud_tint.r
		m.g = cloud_tint.g
		m.b = cloud_tint.b
		c.modulate = m
