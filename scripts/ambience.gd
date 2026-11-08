extends Node

## Suara dunia — REKAMAN ASLI dari Mixkit (lisensi gratis Mixkit, boleh
## dipakai di proyek/game), bukan sintesis. File di res://assets/audio/:
## wind (Wind blowing ambience, 62 dtk), water (Water flowing ambience
## loop, 51 dtk), birds (Morning birds, potongan 30 dtk), step_grass
## (Grass step), step_dirt (Footsteps in the forest ground — 1 langkah
## 0.7 dtk dipotong dari loop), step_rock (Footsteps on stones loop —
## 1 langkah 0.7 dtk dipotong dari loop), chop (Wood hard hit), fall
## (Tree branch brake), splash (Water splash).
## Langkah tanah/batu tidak ada versi 1-langkah di Mixkit, jadi dipotong
## dari loop langkah kaki — kalau terdengar aneh, ganti sumbernya.

var wind_strength := 0.35

var _wind_player: AudioStreamPlayer
var _water_player: AudioStreamPlayer3D
var _pool: Array = []
var _pool_idx := 0
var _footsteps := {}
var _chop_stream: AudioStreamOggVorbis
var _fall_stream: AudioStreamOggVorbis
var _splash_stream: AudioStreamOggVorbis
var _birds_stream: AudioStreamOggVorbis
var _bird_timer := 8.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("ambience")
	_rng.seed = 4242
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _loop_stream("res://assets/audio/wind.ogg")
	_wind_player.volume_db = -18.0
	add_child(_wind_player)
	_wind_player.play()
	_water_player = AudioStreamPlayer3D.new()
	_water_player.stream = _loop_stream("res://assets/audio/water.ogg")
	_water_player.volume_db = -14.0
	_water_player.max_distance = 40.0
	_water_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_water_player.unit_size = 6.0
	add_child(_water_player)
	_water_player.play()
	_footsteps[0] = load("res://assets/audio/step_grass.ogg") # rumput
	_footsteps[1] = load("res://assets/audio/step_dirt.ogg") # tanah
	_footsteps[2] = load("res://assets/audio/step_rock.ogg") # batu
	_chop_stream = load("res://assets/audio/chop.ogg")
	_fall_stream = load("res://assets/audio/fall.ogg")
	_splash_stream = load("res://assets/audio/splash.ogg")
	_birds_stream = load("res://assets/audio/birds.ogg")


func _loop_stream(path: String) -> AudioStreamOggVorbis:
	var stream: AudioStreamOggVorbis = load(path)
	stream.loop = true
	return stream


func _process(delta: float) -> void:
	# Volume angin mengikuti kekuatan angin (nilai yang sama dengan rumput).
	var target := lerpf(-24.0, -10.0, clampf(wind_strength / 0.7, 0.0, 1.0))
	_wind_player.volume_db = lerpf(_wind_player.volume_db, target, delta * 0.5)
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = _rng.randf_range(20.0, 40.0)
		_play_one_shot(_birds_stream, -22.0, _rng.randf_range(0.95, 1.05))


func set_wind(strength: float) -> void:
	wind_strength = strength


func set_water_position(pos: Vector3) -> void:
	_water_player.position = pos


func play_footstep(ground_type: int) -> void:
	var stream: AudioStreamOggVorbis = _footsteps.get(ground_type, _footsteps[0])
	_play_one_shot(stream, -12.0, _rng.randf_range(0.92, 1.08))


func play_chop() -> void:
	_play_one_shot(_chop_stream, -8.0, _rng.randf_range(0.95, 1.05))


func play_fall() -> void:
	_play_one_shot(_fall_stream, -8.0, 1.0)


func play_splash() -> void:
	_play_one_shot(_splash_stream, -10.0, _rng.randf_range(0.95, 1.05))


func _play_one_shot(stream: AudioStreamOggVorbis, volume_db: float, pitch: float) -> void:
	var p: AudioStreamPlayer = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
