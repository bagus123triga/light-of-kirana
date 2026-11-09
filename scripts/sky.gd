extends Node3D

## LIGHT OF KIRANA — langit + siklus hari (minta Bagus 2026-11-09).
## Pagi, siang, sore, malam otomatis (1 hari = 10 menit).
## Langit = SATU shader stylized (shaders/sky.gdshader), ikut referensi
## "Stylized Sky Shader With Clouds" (godotshaders.com): gradien
## siang/senja/malam + horizon glow + matahari (disc + halo) + bulan sabit
## + awan noise + bintang Voronoi — semuanya prosedural, TANPA foto
## (foto asli kelihatan "nempel" ke game, minta Bagus).
## Awan & bintang pakai NoiseTexture2D yang dibuat di kode, bukan file.
## Arah matahari dibaca shader dari LIGHT0_DIRECTION (cahaya yang diputar
## di sini mengikuti jam). KABUT DIHAPUS TOTAL (minta Bagus) — gantinya
## culling: rumput di belakang jarak pandang tidak di-render (world.gd).

const DAY_LENGTH := 600.0  # detik untuk 1 hari penuh (10 menit)

var time_of_day := 8.0  # jam, 0..24. Mulai pagi.

var _env: Environment
var _sky_mat: ShaderMaterial
var _sun_light: DirectionalLight3D

# Keyframe cahaya dunia (ambient + warna/energi matahari) per jam:
# [jam, ambient_color, ambient_energy, sun_color, sun_energy]
const KEYS := [
	[0.0, Color(0.10, 0.12, 0.20), 0.25, Color(0.0, 0.0, 0.0), 0.0],
	[5.0, Color(0.14, 0.16, 0.24), 0.3, Color(0.0, 0.0, 0.0), 0.0],
	[6.5, Color(0.55, 0.50, 0.55), 0.45, Color(1.0, 0.55, 0.25), 0.7],
	[9.0, Color(0.70, 0.78, 0.92), 0.6, Color(1.0, 0.95, 0.85), 1.1],
	[12.0, Color(0.70, 0.78, 0.92), 0.65, Color(1.0, 0.98, 0.90), 1.3],
	[15.0, Color(0.70, 0.78, 0.92), 0.6, Color(1.0, 0.95, 0.80), 1.2],
	[17.5, Color(0.70, 0.68, 0.75), 0.5, Color(1.0, 0.70, 0.35), 0.9],
	[18.5, Color(0.45, 0.40, 0.55), 0.35, Color(1.0, 0.45, 0.20), 0.4],
	[20.0, Color(0.14, 0.16, 0.24), 0.3, Color(0.0, 0.0, 0.0), 0.0],
	[24.0, Color(0.10, 0.12, 0.20), 0.25, Color(0.0, 0.0, 0.0), 0.0],
]


func _ready() -> void:
	_create_environment()
	_create_sun_light()
	_update_sky(0.0)


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH * 24.0, 24.0)
	_update_sky(delta)


func set_time_of_day(hour: float) -> void:
	time_of_day = fmod(hour, 24.0)
	_update_sky(0.0)


# --- Lingkungan (langit shader + cahaya ambient, TANPA kabut) ---

func _make_noise_tex(noise_type: int, frequency: float, seed: int) -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.noise_type = noise_type
	fnl.frequency = frequency
	fnl.seed = seed
	tex.noise = fnl
	return tex


func _create_environment() -> void:
	var world_env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky.gdshader")
	# Awan: 3 lapis noise (dasar + distorsi + detail) — dibuat di kode.
	_sky_mat.set_shader_parameter("clouds_texture", _make_noise_tex(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.015, 11))
	_sky_mat.set_shader_parameter("clouds_distort_texture", _make_noise_tex(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 22))
	_sky_mat.set_shader_parameter("clouds_noise_texture", _make_noise_tex(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 33))
	# Bintang: Voronoi (titik-titik acak alami).
	_sky_mat.set_shader_parameter("stars_texture", _make_noise_tex(FastNoiseLite.TYPE_CELLULAR, 0.12, 44))
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.glow_enabled = true
	_env.glow_intensity = 0.2
	# Kabut DIHAPUS (minta Bagus) — gantinya culling jarak pandang di world.gd.
	_env.fog_enabled = false
	world_env.environment = _env
	add_child(world_env)


func _create_sun_light() -> void:
	_sun_light = DirectionalLight3D.new()
	_sun_light.shadow_enabled = true
	# Bayangan cuma di sekitar kamera (hemat GPU) — bukan seluruh world.
	_sun_light.directional_shadow_max_distance = 60.0
	add_child(_sun_light)


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


func _update_sky(_delta: float) -> void:
	var k := _sample_keys(time_of_day)
	var ambient_color: Color = k[0]
	var ambient_energy: float = k[1]
	var sun_color: Color = k[2]
	var sun_energy: float = k[3]

	_env.ambient_light_color = ambient_color
	_env.ambient_light_energy = ambient_energy

	# Matahari: terbit 06:00, tenggelam 18:00. Bulan: kebalikannya.
	# Miring ke -z (utara, ke arah depan kamera) biar matahari lebih
	# gampang kelihatan dari pandangan awal.
	var sun_angle := (time_of_day - 6.0) / 12.0 * PI
	var sun_dir := Vector3(cos(sun_angle), sin(sun_angle), -0.35).normalized()
	var moon_dir := Vector3(cos(sun_angle + PI), sin(sun_angle + PI), -0.35).normalized()

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
