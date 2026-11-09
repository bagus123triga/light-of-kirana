class_name LFEnvironment
extends Node
## The wind and weather the addon's shaders react to (trees and plants sway, water chops, rain rings the
## water, foliage looks wet), published as global shader uniforms. Add one to the scene and drive it with
## set_wind / set_weather (from your own weather system, a time-of-day script, or nothing: the defaults are
## a light breeze on a dry day).
##
## Each frame it publishes (every name starts lf_, so none clashes with a project's own globals):
##   lf_wind       = (dir.x, dir.z, strength 0..1, gustiness 0..1)
##   lf_weather    = (cloud 0..1, rain 0..1, wetness 0..1, fog 0..1)
##   lf_wind_phase = (gust travel m, sway phase rad, 0, 0): accumulated, so changing wind never makes grass jump
##   lf_water_wave / lf_water_dir: accumulated wave state (LFWaterWaves), so the water never shakes
## The player-driven uniforms (lf_player_pos, lf_player_vel, lf_player_trail_*, lf_fx_time) are registered here
## too and set at runtime by LFFoliageInteraction, if the game uses it (grass and leaves bend round the
## player); left alone they stay at rest. Without an LFEnvironment the shaders sway and wave on the clock in
## the default breeze (a baked map animates on its own); add one to change the wind or the weather.

const GUST_SPEED_BASE := 1.0     # m/s gust travel at zero wind
const GUST_SPEED_WIND := 9.0     # extra at full wind
const SWAY_FREQ_BASE := 1.2      # rad/s
const SWAY_FREQ_WIND := 3.5

## The last LFEnvironment that entered the tree (null if none).
static var current: LFEnvironment

var wind_dir := Vector2(1, 0)
var wind_strength := 0.3
var gustiness := 0.2
var cloud_cover := 0.0
var rain := 0.0
var wetness := 0.0
var fog := 0.0
var water_waves := LFWaterWaves.new()

var _gust_travel := 0.0
var _sway_phase := 0.0

static var _registered := false
## Also publish the names from before Lowland Forge 0.13 / Map Baker 2.1 (wind, weather, wind_phase,
## water_wave, water_dir), for your own shaders that read them. Off: those names are left to your project.
static var publish_old_names := false
static var _old_added := {}


## Registers every global uniform the addon's shaders read (once; skips any the project already defines in
## Project Settings > Shader Globals). Call before creating a material that uses them; the addon's own
## code does.
static func register_globals() -> void:
	if _registered:   # (global_shader_parameter_get_list() is editor-only, so a static flag tracks this)
		return
	_registered = true
	for g: Array in globals():
		_add(g[0], g[1], g[3])


## Every global uniform the addon's shaders read: [name, RenderingServer type, Project Settings type name,
## default]. The editor plugin writes them to Project Settings so baked scenes (no scripts) render right.
static func globals() -> Array:
	var vec4 := RenderingServer.GLOBAL_VAR_TYPE_VEC4
	var out: Array = [
		[&"lf_wind", vec4, "vec4", Vector4(1, 0, 0.3, 0.2)],
		[&"lf_weather", vec4, "vec4", Vector4.ZERO],
		[&"lf_wind_phase", vec4, "vec4", Vector4.ZERO],
		[&"lf_water_wave", vec4, "vec4", Vector4.ZERO],
		[&"lf_water_dir", vec4, "vec4", Vector4(0.0, 0.0, 1.0, 0.0)],
		[&"lf_player_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC3, "vec3", Vector3.ZERO],
		[&"lf_player_vel", RenderingServer.GLOBAL_VAR_TYPE_VEC3, "vec3", Vector3.ZERO],
		[&"lf_fx_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, "float", 0.0],
	]
	for i in 4:
		out.append([StringName("lf_player_trail_%d" % i), vec4, "vec4", Vector4(0, 0, 0, -1000)])
	return out


static func _add(n: StringName, type: int, value: Variant) -> void:
	if ProjectSettings.has_setting("shader_globals/" + n):
		return
	RenderingServer.global_shader_parameter_add(n, type, value)


func _init() -> void:
	register_globals()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func set_wind(dir: Vector2, strength: float, gust: float) -> void:
	wind_dir = dir
	wind_strength = strength
	gustiness = gust


func set_weather(cloud: float, rain_amount: float, wet: float, fog_amount: float) -> void:
	cloud_cover = cloud
	rain = rain_amount
	wetness = wet
	fog = fog_amount


## Same value as the `wind_phase` uniform, for CPU copies of the shader sway (a bird on a branch).
func get_wind_phase() -> Vector4:
	return Vector4(fposmod(_gust_travel, 20000.0), _sway_phase, 0.0, 0.0)


func _process(delta: float) -> void:
	step(delta)


## Advances the wind and wave accumulators by `delta` seconds and publishes every uniform.
func step(delta: float) -> void:
	_gust_travel += (GUST_SPEED_BASE + GUST_SPEED_WIND * wind_strength) * delta
	_sway_phase = fposmod(_sway_phase + (SWAY_FREQ_BASE + SWAY_FREQ_WIND * wind_strength) * delta, TAU * 50.0)
	water_waves.step(delta, wind_dir, wind_strength, gustiness)
	var values := {&"lf_wind": Vector4(wind_dir.x, wind_dir.y, wind_strength, gustiness),
			&"lf_weather": Vector4(cloud_cover, rain, wetness, fog), &"lf_wind_phase": get_wind_phase(),
			&"lf_water_wave": water_waves.wave_uniform(), &"lf_water_dir": water_waves.dir_uniform()}
	for n: StringName in values:
		RenderingServer.global_shader_parameter_set(n, values[n])
		if publish_old_names:
			var old := StringName(String(n).trim_prefix("lf_"))
			if not _old_added.has(old):
				_old_added[old] = true
				_add(old, RenderingServer.GLOBAL_VAR_TYPE_VEC4, values[n])
			RenderingServer.global_shader_parameter_set(old, values[n])
