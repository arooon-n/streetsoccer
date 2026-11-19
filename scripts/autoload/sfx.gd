extends Node
## Procedurally synthesised audio: crowd ambience, cheers, whistle, ball sounds, UI.

const RATE := 22050

var streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _crowd: AudioStreamPlayer
var _cheer: AudioStreamPlayer
var _excite := 0.0
var _excite_target := 0.0
var _crowd_on := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_crowd = AudioStreamPlayer.new()
	add_child(_crowd)
	_cheer = AudioStreamPlayer.new()
	add_child(_cheer)
	_build_small()
	_task = WorkerThreadPool.add_task(_build_crowd_bg)


var _task := -1


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


var _crowd_lock := Mutex.new()


func _build_crowd_bg() -> void:
	ensure_crowd()


## Short sounds are built at startup; the long crowd beds are built on demand.
func _build_small() -> void:
	streams.kick = _wav(_kick(0.16, 1.0))
	streams.kick_soft = _wav(_kick(0.11, 0.55))
	streams.whistle = _wav(_whistle(0.35))
	streams.whistle_long = _wav(_whistle(1.1))
	streams.post = _wav(_post())
	streams.net = _wav(_net())
	streams.bounce = _wav(_kick(0.07, 0.25))
	streams.catch = _wav(_catch())
	streams.tap = _wav(_blip(1250.0, 0.045, 0.5))
	streams.back = _wav(_blip(780.0, 0.05, 0.45))
	streams.coin = _wav(_coin())
	streams.tackle = _wav(_thud())


func ensure_crowd() -> void:
	_crowd_lock.lock()
	if not streams.has("crowd"):
		var rng_backup := _rng
		_rng = RandomNumberGenerator.new()
		_rng.seed = 77
		var c := _wav(_crowd_bed(5.0, 260.0, 1700.0, 0.22), true)
		var ch := _wav(_cheer_burst(4.2))
		var oo := _wav(_ooh(1.8))
		_rng = rng_backup
		streams.cheer = ch
		streams.ooh = oo
		streams.crowd = c
	_crowd_lock.unlock()


func play(name: String, vol := 1.0, pitch := 1.0, bus_vol_key := "sfx_vol") -> void:
	if not streams.has(name):
		return
	var v: float = vol * float(Game.settings.get(bus_vol_key, 0.9))
	if v <= 0.001:
		return
	for p in _pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = linear_to_db(v)
			p.pitch_scale = pitch
			p.play()
			return


func ui(name := "tap") -> void:
	play(name, 0.8, 1.0, "ui_vol")


func kick(power: float) -> void:
	play("kick" if power > 0.45 else "kick_soft", clamp(0.35 + power * 0.7, 0.2, 1.0), _rng.randf_range(0.92, 1.08))


func start_crowd() -> void:
	ensure_crowd()
	_crowd.stream = streams.crowd
	_crowd.volume_db = linear_to_db(0.0001)
	_crowd.play()
	_crowd_on = true


func stop_crowd() -> void:
	_crowd_on = false
	_crowd.stop()
	_cheer.stop()


func set_excitement(x: float) -> void:
	_excite_target = clamp(x, 0.0, 1.0)


func goal_roar() -> void:
	ensure_crowd()
	_cheer.stream = streams.cheer
	_cheer.volume_db = linear_to_db(max(0.0001, 1.1 * float(Game.settings.crowd_vol)))
	_cheer.play()


func near_miss() -> void:
	ensure_crowd()
	play("ooh", 0.9, _rng.randf_range(0.95, 1.05), "crowd_vol")


func _process(delta: float) -> void:
	if not _crowd_on:
		return
	_excite = move_toward(_excite, _excite_target, delta * 0.5)
	var v: float = (0.28 + 0.5 * _excite) * float(Game.settings.crowd_vol)
	_crowd.volume_db = linear_to_db(max(0.0001, v))
	_crowd.pitch_scale = 1.0 + _excite * 0.06


# ================= synthesis =================
func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _kick(dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 55.0 + 95.0 * exp(-t * 40.0)
		ph += TAU * f / RATE
		var body := sin(ph) * exp(-t * 22.0)
		var click := (_rng.randf() * 2.0 - 1.0) * exp(-t * 400.0) * 0.6
		s[i] = (body * 0.9 + click) * amp
	return s


func _thud() -> PackedFloat32Array:
	var n := int(0.18 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf() * 2.0 - 1.0 - lp) * 0.08
		s[i] = (lp * 2.2 + sin(TAU * 70.0 * t) * 0.5) * exp(-t * 25.0)
	return s


func _whistle(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var trill := 0.5 + 0.5 * sin(TAU * 28.0 * t)
		var f := 2850.0 + 90.0 * sin(TAU * 28.0 * t)
		ph += TAU * f / RATE
		var env: float = min(1.0, t / 0.02) * min(1.0, (dur - t) / 0.05)
		var breath := (_rng.randf() * 2.0 - 1.0) * 0.08
		s[i] = (sin(ph) * (0.55 + 0.45 * trill) * 0.5 + breath) * env
	return s


func _post() -> PackedFloat32Array:
	var n := int(0.9 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var freqs := [523.0, 1346.0, 2211.0, 3177.0, 4120.0]
	var decs := [5.0, 7.0, 9.0, 12.0, 16.0]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t) * exp(-t * decs[k]) / (k + 1.5)
		v += (_rng.randf() * 2.0 - 1.0) * exp(-t * 300.0) * 0.5
		s[i] = v * 0.9
	return s


func _net() -> PackedFloat32Array:
	var n := int(0.55 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := _rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.35
		lp2 += (lp - lp2) * 0.05
		s[i] = (lp - lp2) * 1.6 * min(1.0, t / 0.01) * exp(-t * 7.0)
	return s


func _catch() -> PackedFloat32Array:
	var n := int(0.15 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 180.0 * t) * 0.7 + (_rng.randf() * 2.0 - 1.0) * 0.5 * exp(-t * 120.0)) * exp(-t * 30.0)
	return s


func _blip(f: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * f * t) * exp(-t * 60.0) * amp * min(1.0, t / 0.002)
	return s


func _coin() -> PackedFloat32Array:
	var a := _blip(1568.0, 0.07, 0.45)
	var b := _blip(2093.0, 0.16, 0.45)
	var s := PackedFloat32Array()
	s.append_array(a)
	s.append_array(b)
	return s


## Band-limited noise with slow swells: a stadium murmur. Crossfaded for a seamless loop.
func _crowd_bed(dur: float, lo: float, hi: float, amp: float) -> PackedFloat32Array:
	var fade := int(0.6 * RATE)
	var n := int(dur * RATE)
	var total := n + fade
	var raw := PackedFloat32Array()
	raw.resize(total)
	var a_hi := 1.0 - exp(-TAU * hi / RATE)
	var a_lo := 1.0 - exp(-TAU * lo / RATE)
	var l1 := 0.0
	var l2 := 0.0
	var mods := []
	for k in 6:
		mods.append([_rng.randf_range(0.15, 1.6), _rng.randf() * TAU, _rng.randf_range(0.05, 0.18)])
	for i in total:
		var t := float(i) / RATE
		var w := _rng.randf() * 2.0 - 1.0
		l1 += (w - l1) * a_hi
		l2 += (l1 - l2) * a_lo
		var m := 0.75
		for md in mods:
			m += sin(TAU * md[0] * t + md[1]) * md[2]
		# occasional distant shouts
		var shout := 0.0
		var ph := fmod(t * 0.37, 1.0)
		if ph < 0.05:
			shout = sin(TAU * (420.0 + 80.0 * sin(t)) * t) * sin(PI * ph / 0.05) * 0.12
		raw[i] = ((l1 - l2) * 2.4 * m + shout) * amp * 3.0
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[i]
	for i in fade:
		var k := float(i) / fade
		s[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	return s


func _cheer_burst(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	var a_hi := 1.0 - exp(-TAU * 3200.0 / RATE)
	var a_lo := 1.0 - exp(-TAU * 380.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var w := _rng.randf() * 2.0 - 1.0
		l1 += (w - l1) * a_hi
		l2 += (l1 - l2) * a_lo
		var env: float = min(1.0, t / 0.35) * (1.0 if t < dur - 1.6 else max(0.0, (dur - t) / 1.6))
		var voices := 0.0
		for k in 4:
			var f := 300.0 + k * 120.0 + 40.0 * sin(t * (1.3 + k))
			voices += sin(TAU * f * t + k) * 0.03
		s[i] = ((l1 - l2) * 2.8 * (0.9 + 0.1 * sin(t * 9.0)) + voices) * env * 0.85
	return s


func _ooh(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var cut := 900.0 - 400.0 * (t / dur)
		var a_hi := 1.0 - exp(-TAU * cut / RATE)
		var w := _rng.randf() * 2.0 - 1.0
		l1 += (w - l1) * a_hi
		l2 += (l1 - l2) * 0.02
		var env = sin(PI * clamp(t / dur, 0.0, 1.0))
		var tone := sin(TAU * (240.0 - 60.0 * t / dur) * t) * 0.08
		s[i] = ((l1 - l2) * 2.2 + tone) * env * 0.8
	return s
