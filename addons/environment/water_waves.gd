class_name LFWaterWaves
extends RefCounted
## Accumulated wave state for water.gdshader, so wind changes never make the water "vibrate".
##
## The shader used to compute its wave phase as TIME * speed(wind) and its swell direction straight
## from the wind uniform. TIME is large (up to an hour), so while a weather blend changed the wind
## strength the phase raced (t * d(speed)/dt), and while the wind turned, dot(world_pos, dir)
## swept by hundreds of radians far from the origin. Both read as the lake shaking.
##
## Now the phases are integrated here (phase += speed * delta, continuous whatever the wind does)
## and the swell direction never rotates: a new direction fades in over BLEND_TIME while the old
## wave set fades out. LFEnvironment owns one, steps it every frame and publishes:
##   water_wave = (swell phase rad, lapping phase, fleck drift x, fleck drift z)
##   water_dir  = (old swell angle, new swell angle, blend 0..1, 0)    angles in rad, world XZ

## Swell phase speed in rad/s: SWELL_BASE + SWELL_WIND * strength (matches the old shader).
const SWELL_BASE := 0.8
const SWELL_WIND := 1.6
## Lapping-line cycles per second at shore: LAP_BASE + LAP_WIND * strength + LAP_GUST * gust.
const LAP_BASE := 0.10
const LAP_WIND := 0.16
const LAP_GUST := 0.05
## Foam fleck drift, m/s along the wind.
const FLECK_DRIFT := 0.6
## The swell direction only follows the wind once it has turned this far (rad) ...
const TURN_THRESHOLD := 0.12
## ... and then cross-fades to the new direction over this many seconds.
const BLEND_TIME := 6.0
## The swell's three sines run at phase x1, x1.25 and x1.6, all periodic over 40 pi.
const SWELL_WRAP := 40.0 * PI * 8.0

var swell_phase := 0.0
var lap_phase := 0.0
var fleck := Vector2.ZERO
var dir_from := 0.0
var dir_to := 0.0
var blend := 1.0
var _started := false


## Advances the accumulators by `delta` s under the given wind (dir normalised XZ, strength and
## gust 0..1). Every output changes by at most speed * delta, so it is continuous in time.
func step(delta: float, wind_dir: Vector2, strength: float, gust: float) -> void:
	var ws := clampf(strength, 0.0, 1.0)
	var ang := atan2(wind_dir.y, wind_dir.x) if wind_dir.length() > 0.01 else dir_to
	if not _started:
		_started = true
		dir_from = ang
		dir_to = ang
		blend = 1.0
	swell_phase = fposmod(swell_phase + (SWELL_BASE + SWELL_WIND * ws) * delta, SWELL_WRAP)
	lap_phase = fposmod(lap_phase + (LAP_BASE + LAP_WIND * ws + LAP_GUST * clampf(gust, 0.0, 1.0)) * delta, 1000.0)
	fleck += wind_dir * FLECK_DRIFT * delta
	if absf(fleck.x) > 4096.0 or absf(fleck.y) > 4096.0:
		fleck = Vector2(fposmod(fleck.x, 4096.0), fposmod(fleck.y, 4096.0))
	if blend < 1.0:
		blend = minf(1.0, blend + delta / BLEND_TIME)
	elif absf(angle_difference(dir_to, ang)) > TURN_THRESHOLD:
		dir_from = dir_to
		dir_to = ang
		blend = 0.0


func wave_uniform() -> Vector4:
	return Vector4(swell_phase, lap_phase, fleck.x, fleck.y)


func dir_uniform() -> Vector4:
	return Vector4(dir_from, dir_to, blend, 0.0)
