extends Node

## Suara dunia — dibuat prosedural dari noise (tanpa file download, repo
## tetap kecil). Angin & air ASLI-nya memang noise yang difilter, jadi
## sintesis yang dibentuk dengan benar terdengar dekat dengan aslinya.
## Pola sintesis AudioStreamWAV yang sama dipakai di hero-game (bunyi "duk").
## Rekaman CC0 asli bisa menggantikan stream ini kapan pun (lihat Agent.md).

const MIX_RATE := 16000

var wind_strength := 0.35

var _wind_player: AudioStreamPlayer
var _water_player: AudioStreamPlayer3D
var _pool: Array = []
var _pool_idx := 0
var _footsteps := {}
var _chop_stream: AudioStreamWAV
var _fall_stream: AudioStreamWAV
var _splash_stream: AudioStreamWAV
var _chirp_streams: Array = []
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
	_wind_player.stream = _make_wind_loop()
	_wind_player.volume_db = -18.0
	add_child(_wind_player)
	_wind_player.play()
	_water_player = AudioStreamPlayer3D.new()
	_water_player.stream = _make_water_loop()
	_water_player.volume_db = -14.0
	_water_player.max_distance = 40.0
	_water_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_water_player.unit_size = 6.0
	add_child(_water_player)
	_water_player.play()
	_footsteps[0] = _make_footstep(0) # rumput
	_footsteps[1] = _make_footstep(1) # tanah
	_footsteps[2] = _make_footstep(2) # batu
	_chop_stream = _make_chop()
	_fall_stream = _make_fall()
	_splash_stream = _make_splash()
	for i in 3:
		_chirp_streams.append(_make_chirp(2800.0 + i * 400.0))


func _process(delta: float) -> void:
	# Volume angin mengikuti kekuatan angin (nilai yang sama dengan rumput).
	var target := lerpf(-24.0, -10.0, clampf(wind_strength / 0.7, 0.0, 1.0))
	_wind_player.volume_db = lerpf(_wind_player.volume_db, target, delta * 0.5)
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = _rng.randf_range(8.0, 20.0)
		_play_one_shot(_chirp_streams[_rng.randi_range(0, 2)], -22.0, _rng.randf_range(0.9, 1.15))


func set_wind(strength: float) -> void:
	wind_strength = strength


func set_water_position(pos: Vector3) -> void:
	_water_player.position = pos


func play_footstep(ground_type: int) -> void:
	var stream: AudioStreamWAV = _footsteps.get(ground_type, _footsteps[0])
	_play_one_shot(stream, -12.0, _rng.randf_range(0.92, 1.08))


func play_chop() -> void:
	_play_one_shot(_chop_stream, -8.0, _rng.randf_range(0.95, 1.05))


func play_fall() -> void:
	_play_one_shot(_fall_stream, -8.0, 1.0)


func play_splash() -> void:
	_play_one_shot(_splash_stream, -10.0, _rng.randf_range(0.95, 1.05))


func _play_one_shot(stream: AudioStreamWAV, volume_db: float, pitch: float) -> void:
	var p: AudioStreamPlayer = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


# --- Sintesis ---

func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _normalize(samples: PackedFloat32Array, peak: float) -> void:
	var m := 0.001
	for s in samples:
		m = maxf(m, absf(s))
	for i in samples.size():
		samples[i] = samples[i] / m * peak


func _crossfade_loop(samples: PackedFloat32Array) -> void:
	# Samarkan sambungan loop: 0.5 detik terakhir dibaur ke arah awal.
	var fade := MIX_RATE / 2
	var n := samples.size()
	for i in fade:
		var t := float(i) / float(fade)
		samples[n - fade + i] = samples[n - fade + i] * (1.0 - t) + samples[i] * t


func _brown_noise(seconds: float, leak: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var white := _rng.randf_range(-1.0, 1.0)
		last = (last + 0.02 * white) * leak
		out[i] = last * 3.0
	return out


func _lowpass(samples: PackedFloat32Array, alpha: float) -> void:
	var last := 0.0
	for i in samples.size():
		last = last + alpha * (samples[i] - last)
		samples[i] = last


func _make_wind_loop() -> AudioStreamWAV:
	# Angin = brown noise yang bergerak pelan (LFO) + desah naik-turun.
	var s := _brown_noise(6.0, 0.998)
	_lowpass(s, 0.25)
	for i in s.size():
		var t := float(i) / MIX_RATE
		var lfo := 0.75 + 0.25 * sin(t * 0.9) + 0.15 * sin(t * 2.3 + 1.0)
		s[i] = s[i] * lfo
	_normalize(s, 0.7)
	_crossfade_loop(s)
	return _to_wav(s, true)


func _make_water_loop() -> AudioStreamWAV:
	# Air = noise lembut + gemericik acak (ping pendek) + LFO pelan.
	var s := _brown_noise(5.0, 0.996)
	_lowpass(s, 0.5)
	for i in s.size():
		var t := float(i) / MIX_RATE
		s[i] = s[i] * (0.8 + 0.2 * sin(t * 1.7))
	# 12 tetes acak di dalam loop.
	for k in 12:
		var start := _rng.randi_range(0, s.size() - 800)
		var freq := _rng.randf_range(900.0, 2200.0)
		for j in 500:
			var t := float(j) / MIX_RATE
			var env := exp(-t * 30.0)
			s[start + j] += sin(TAU * freq * t) * env * 0.15
	_normalize(s, 0.65)
	_crossfade_loop(s)
	return _to_wav(s, true)


func _make_footstep(kind: int) -> AudioStreamWAV:
	var n := int(0.16 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * (28.0 if kind != 2 else 55.0))
		var noise := _rng.randf_range(-1.0, 1.0) * env
		var thump := 0.0
		if kind == 1:
			thump = sin(TAU * 85.0 * t) * env * 0.8
		elif kind == 2:
			thump = sin(TAU * 180.0 * t) * env * 0.5
		s[i] = noise * (0.5 if kind == 0 else 0.8) + thump
	_lowpass(s, 0.18 if kind == 0 else 0.35)
	_normalize(s, 0.8)
	return _to_wav(s, false)


func _make_chop() -> AudioStreamWAV:
	var n := int(0.14 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 45.0)
		var click := _rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.7
		s[i] = sin(TAU * 150.0 * t) * env + click
	_normalize(s, 0.85)
	return _to_wav(s, false)


func _make_fall() -> AudioStreamWAV:
	var n := int(0.9 * MIX_RATE)
	var s := _brown_noise(0.9, 0.996)
	_lowpass(s, 0.3)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(1.0, t * 20.0) * exp(-t * 3.5)
		s[i] = s[i] * env + sin(TAU * 52.0 * t) * env * 0.35
	_normalize(s, 0.85)
	return _to_wav(s, false)


func _make_splash() -> AudioStreamWAV:
	var n := int(0.45 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 8.0)
		s[i] = _rng.randf_range(-1.0, 1.0) * env
	_lowpass(s, 0.45)
	_normalize(s, 0.8)
	return _to_wav(s, false)


func _make_chirp(base_freq: float) -> AudioStreamWAV:
	var n := int(0.3 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		# 3 suku kata: naik-turun cepat.
		var syllable := int(t / 0.1) % 2 == 0
		var freq := base_freq + 1200.0 * sin(t * 40.0) if syllable else base_freq * 0.8
		phase += TAU * freq / MIX_RATE
		var env := 0.6 + 0.4 * sin(t * 60.0)
		s[i] = sin(phase) * env * 0.5
	_normalize(s, 0.5)
	return _to_wav(s, false)
