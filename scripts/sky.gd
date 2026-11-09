extends Node3D

## LIGHT OF KIRANA — langit v5 (REBUILD DARI 0).
## Langit stylized prosedural (shaders/sky.gdshader): gradasi siang/sore/malam
## + matahari disc+halo + bulan sabit + awan noise + bintang Voronoi.
## Tanpa foto (minta Bagus 2026-11-09: "jangan nempel gambar asli ke game").
## Sky.gd cuma nyetir pencahayaan dunia (ambient + matahari) lewat keyframe
## + muter DirectionalLight3D. Siklus hari 600 detik, mulai 08:00.

const DAY_LENGTH := 600.0
const START_HOUR := 8.0
const SUN_TILT_Z := -0.35  # busur matahari condong ke depan kamera default

# Keyframe pencahayaan [jam, ambient, warna matahari, energi matahari].
const KEYFRAMES: Array = [
	[0.0, Color(0.05, 0.06, 0.12), Color(0.65, 0.75, 1.0), 0.12],
	[5.0, Color(0.08, 0.09, 0.16), Color(0.8, 0.7, 0.9), 0.15],
	[6.0, Color(0.25, 0.2, 0.25), Color(1.0, 0.6, 0.4), 0.5],
	[8.0, Color(0.5, 0.55, 0.7), Color(1.0, 0.9, 0.75), 1.0],
	[12.0, Color(0.6, 0.65, 0.8), Color(1.0, 0.95, 0.85), 1.3],
	[16.0, Color(0.5, 0.55, 0.7), Color(1.0, 0.9, 0.75), 1.0],
	[18.0, Color(0.3, 0.22, 0.28), Color(1.0, 0.55, 0.35), 0.6],
	[19.0, Color(0.1, 0.1, 0.18), Color(0.7, 0.7, 0.9), 0.2],
	[20.0, Color(0.05, 0.06, 0.12), Color(0.65, 0.75, 1.0), 0.12],
	[24.0, Color(0.05, 0.06, 0.12), Color(0.65, 0.75, 1.0), 0.12],
]

var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _sky_mat: ShaderMaterial
var _time := 0.0


func _ready() -> void:
	# Langit prosedural (shader).
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky.gdshader")
	_sky_mat.set_shader_parameter("sun_size", 0.08)
	_sky_mat.set_shader_parameter("sun_glow", 0.35)
	_sky_mat.set_shader_parameter("moon_size", 0.06)
	_sky_mat.set_shader_parameter("moon_crescent_offset", 0.35)
	_sky_mat.set_shader_parameter("clouds_speed", 0.015)
	_sky_mat.set_shader_parameter("clouds_scale", 0.35)
	_sky_mat.set_shader_parameter("clouds_cutoff", 0.55)
	_sky_mat.set_shader_parameter("clouds_fuzziness", 0.25)
	_sky_mat.set_shader_parameter("clouds_texture", _make_noise_texture(11, 0.015))
	_sky_mat.set_shader_parameter("clouds_distort_texture", _make_noise_texture(22, 0.03))
	_sky_mat.set_shader_parameter("clouds_noise_texture", _make_noise_texture(33, 0.06))
	_sky_mat.set_shader_parameter("stars_texture", _make_star_texture(44, 0.12))
	# WorldEnvironment.
	_env = WorldEnvironment.new()
	_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = false  # kabut dihapus total (minta Bagus); culling rumput yang gantiin
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.environment = env
	add_child(_env)
	# Matahari.
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	add_child(_sun)
	_time = START_HOUR / 24.0 * DAY_LENGTH
	_apply_lighting()


func _process(delta: float) -> void:
	_time = fmod(_time + delta, DAY_LENGTH)
	_apply_lighting()


func _hour() -> float:
	return fmod(_time / DAY_LENGTH * 24.0, 24.0)


func _make_noise_texture(seed: int, freq: float) -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.seed = seed
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = freq
	tex.noise = fnl
	return tex


func _make_star_texture(seed: int, freq: float) -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.seed = seed
	fnl.noise_type = FastNoiseLite.TYPE_CELLULAR
	fnl.frequency = freq
	tex.noise = fnl
	return tex


func _apply_lighting() -> void:
	var h := _hour()
	# Sudut matahari: 0 jam = tengah malam (di bawah), 12 jam = tengah hari.
	var sun_angle := (h / 24.0) * TAU - PI * 0.5
	var sun_dir := Vector3(cos(sun_angle), sin(sun_angle), SUN_TILT_Z).normalized()
	_sun.rotation = Quaternion(Vector3.FORWARD, sun_dir).get_euler()
	# Keyframe pencahayaan (lerp antar keyframe terdekat).
	var k0: Array = KEYFRAMES[0]
	var k1: Array = KEYFRAMES[KEYFRAMES.size() - 1]
	for i in KEYFRAMES.size() - 1:
		if h >= float(KEYFRAMES[i][0]) and h < float(KEYFRAMES[i + 1][0]):
			k0 = KEYFRAMES[i]
			k1 = KEYFRAMES[i + 1]
			break
	var t := 0.0
	var span: float = float(k1[0]) - float(k0[0])
	if span > 0.0:
		t = clampf((h - float(k0[0])) / span, 0.0, 1.0)
	var ambient: Color = (k0[1] as Color).lerp(k1[1] as Color, t)
	var sun_color: Color = (k0[2] as Color).lerp(k1[2] as Color, t)
	var sun_energy: float = lerpf(float(k0[3]), float(k1[3]), t)
	_env.environment.ambient_light_color = ambient
	_env.environment.ambient_light_energy = 1.0
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	# Shader langit ngikutin arah matahari lewat LIGHT0_DIRECTION (otomatis).
