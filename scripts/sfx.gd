class_name Sfx
## All audio is synthesised procedurally at runtime, so there are no third-party
## audio files and no licensing concerns. Streams are cached.

static var _cache := {}


static func get_stream(n: String) -> AudioStreamWAV:
	if _cache.has(n):
		return _cache[n]
	var s: AudioStreamWAV = null
	match n:
		"engine": s = _engine()
		"siren": s = _siren()
		"click": s = _burst(0.05, 22050, 900.0, 0.35, 60.0)
		"shot": s = _burst(0.22, 22050, 0.0, 0.8, 14.0)
		"step": s = _burst(0.08, 16000, 0.0, 0.25, 40.0)
		"crash": s = _burst(0.35, 22050, 0.0, 0.9, 7.0)
		"punch": s = _burst(0.12, 16000, 140.0, 0.7, 25.0)
		"horn": s = _tone(0.4, 16000, [392.0, 494.0], 0.3, true)
		"pickup": s = _tone(0.25, 16000, [880.0, 1320.0], 0.3, false)
		"ambient": s = _noise_loop(3.0, 8000, 0.05, 0.12)
		"rain": s = _noise_loop(2.0, 11025, 0.35, 0.5)
		"music": s = _music()
	_cache[n] = s
	return s


static func _make(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _engine() -> AudioStreamWAV:
	var rate := 22050
	var n := 2205                      # 0.1 s; 40 Hz base => 4 whole cycles (seamless loop)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / rate
		var v := 0.0
		for k in range(1, 7):
			v += sin(TAU * 40.0 * k * t) / float(k)
		s[i] = v * 0.28
	return _make(s, rate, true)


static func _siren() -> AudioStreamWAV:
	var rate := 16000
	var half := rate / 2
	var s := PackedFloat32Array()
	s.resize(rate)
	for i in range(rate):
		var t := float(i) / rate
		var f := 760.0 if i < half else 960.0
		s[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * 0.3
	return _make(s, rate, true)


static func _burst(dur: float, rate: int, tone: float, vol: float, decay: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / rate
		var env := exp(-decay * t)
		var v := rng.randf_range(-1.0, 1.0)
		if tone > 0.0:
			v = v * 0.3 + sin(TAU * tone * t)
		s[i] = v * env * vol
	return _make(s, rate, false)


static func _tone(dur: float, rate: int, freqs: Array, vol: float, hold: bool) -> AudioStreamWAV:
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / rate
		var env := 1.0 if hold else exp(-8.0 * t)
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t)
		s[i] = v / freqs.size() * env * vol
	return _make(s, rate, false)


static func _noise_loop(dur: float, rate: int, lo_vol: float, hi_vol: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in range(n):
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.25)
		s[i] = lp * lerpf(lo_vol, hi_vol, 0.5 + 0.5 * sin(TAU * float(i) / n))
	return _make(s, rate, true)


static func _music() -> AudioStreamWAV:
	# Original slow ambient pad: four chords, 3 s each, 6 kHz mono.
	var rate := 6000
	var chords := [[110.0, 164.8, 220.0], [98.0, 146.8, 196.0], [87.3, 130.8, 174.6], [98.0, 146.8, 196.0]]
	var n := rate * 12
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / rate
		var ch: Array = chords[int(t / 3.0) % 4]
		var local := fmod(t, 3.0)
		var env := minf(local / 0.8, 1.0) * minf((3.0 - local) / 0.8, 1.0)
		var v := 0.0
		for f in ch:
			v += sin(TAU * float(f) * t)
		s[i] = v / 3.0 * env * 0.35
	return _make(s, rate, true)


static func play3d(parent: Node, n: String, pos: Vector3, vol_db := 0.0) -> void:
	var st := get_stream(n)
	if st == null or parent == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = vol_db
	p.unit_size = 12.0
	p.max_distance = 90.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
