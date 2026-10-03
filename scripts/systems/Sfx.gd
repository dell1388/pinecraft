extends Node

## Autoload. Every sound in the game, made here from scratch rather than read
## from files: a few lines of arithmetic each (a thunk, a clink, a crash, an
## engine note) turned into samples once, at start-up. A first pass - good
## enough to play with, easy to swap for recorded sounds later.
##
## play() is fire-and-forget, at a spot in the world or flat (the interface);
## loop() gives a looping player to hang on something, like an engine. The
## music is a gentle loop built on a worker thread, so start-up does not wait.

const RATE := 22050
const POOL := 20

var _sounds: Dictionary = {}          ## name -> AudioStreamWAV
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _next3d: int = 0
var _next2d: int = 0
var _music: AudioStreamPlayer
var _music_thread: Thread

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_all()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 90.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
		var q := AudioStreamPlayer.new()
		add_child(q)
		_pool2d.append(q)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	Settings.changed.connect(func(_k): _apply_volume())
	# Headless (tests, a dedicated host) there is nothing to hear.
	if DisplayServer.get_name() != "headless":
		_music_thread = Thread.new()
		_music_thread.start(_build_music)

func _exit_tree() -> void:
	if _music_thread != null and _music_thread.is_started():
		_music_thread.wait_to_finish()

## Plays a sound once: at `at` (a Vector3) in the world, or flat when null.
func play(sound: StringName, at: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStreamWAV = _sounds.get(sound)
	if stream == null or DisplayServer.get_name() == "headless":
		return
	var vol := volume_db + _db(&"sfx_volume")
	pitch *= randf_range(0.94, 1.06)
	if at is Vector3:
		var p := _pool3d[_next3d]
		_next3d = (_next3d + 1) % POOL
		p.stream = stream
		p.global_position = at
		p.volume_db = vol
		p.pitch_scale = pitch
		p.play()
	else:
		var q := _pool2d[_next2d]
		_next2d = (_next2d + 1) % POOL
		q.stream = stream
		q.volume_db = vol
		q.pitch_scale = pitch
		q.play()

## A looping player of `sound`, to add as a child of whatever makes it.
## Starts silent; the owner sets its volume and pitch as it goes.
func loop(sound: StringName) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds.get(sound)
	p.unit_size = 8.0
	p.max_distance = 70.0
	p.volume_db = -80.0
	p.autoplay = DisplayServer.get_name() != "headless"
	return p

## The effects volume setting, in decibels (for things that set their own).
func sfx_db() -> float:
	return _db(&"sfx_volume")

func _db(key: StringName) -> float:
	var v := clampf(float(Settings.value(key)), 0.0, 1.0)
	return -80.0 if v <= 0.001 else linear_to_db(v)

func _apply_volume() -> void:
	if _music != null:
		_music.volume_db = _db(&"music_volume") + 2.0

# --- Making the sounds ------------------------------------------------------------

func _make_all() -> void:
	_sounds[&"chop"] = _wav(_synth(0.22, _chop))
	_sounds[&"fall"] = _wav(_synth(1.6, _fall, true))
	_sounds[&"clink"] = _wav(_synth(0.35, _clink))
	_sounds[&"crack"] = _wav(_synth(0.5, _crack, true))
	_sounds[&"pickup"] = _wav(_synth(0.09, _pickup))
	_sounds[&"drop"] = _wav(_synth(0.25, _drop, true))
	_sounds[&"whoosh"] = _wav(_synth(0.3, _whoosh, true))
	_sounds[&"cash"] = _wav(_synth(0.7, _cash))
	_sounds[&"place"] = _wav(_synth(0.18, _place))
	_sounds[&"remove"] = _wav(_synth(0.25, _remove, true))
	_sounds[&"step"] = _wav(_synth(0.07, _step, true))
	_sounds[&"click"] = _wav(_synth(0.04, _click))
	# Loops: whole numbers of cycles, so they go round without a click.
	_sounds[&"engine"] = _wav(_synth(0.5, _engine, true), true)
	# Each vehicle's own voice: [base Hz, harmonic weights, thump, lope Hz,
	# lope depth, noise, rasp]. Every rate a whole number of cycles in 0.5 s.
	for voice in ENGINE_VOICES:
		var v: Array = ENGINE_VOICES[voice]
		_sounds[StringName("engine_" + String(voice))] = _wav(_synth(0.5, func(t: float, n: float) -> float:
			return _voice(t, n, v), true), true)
	_sounds[&"hum"] = _wav(_synth(1.0, _hum, true), true)
	_sounds[&"grind"] = _wav(_synth(0.6, _grind, true))
	_sounds[&"boom"] = _wav(_synth(1.8, _boom, true))
	_sounds[&"squish"] = _wav(_synth(0.45, _squish, true))
	_sounds[&"thud"] = _wav(_synth(0.35, _thud, true))
	_sounds[&"fuse"] = _wav(_synth(0.5, _fuse), true)

## A stick of TNT going off: a hard crack, a deep thump, a rolling rumble.
static func _boom(t: float, n: float) -> float:
	var crack := n * exp(-t * 30.0) * 1.0
	var thump := sin(TAU * lerpf(70.0, 32.0, clampf(t / 0.4, 0.0, 1.0)) * t) * exp(-t * 5.0) * 0.9
	var rumble := n * exp(-t * 2.2) * 0.45 * (0.7 + 0.3 * sin(TAU * 9.0 * t))
	return clampf(crack + thump + rumble, -1.0, 1.0)

## A body hitting the ground: a dull, heavy whump.
static func _thud(t: float, n: float) -> float:
	return sin(TAU * lerpf(95.0, 45.0, t / 0.35) * t) * exp(-t * 14.0) * 0.9 + n * exp(-t * 40.0) * 0.35

## Something soft going through the crusher.
static func _squish(t: float, n: float) -> float:
	var wet := n * exp(-t * 9.0) * (0.5 + 0.5 * sin(TAU * 23.0 * t))
	return wet * 0.7 + sin(TAU * lerpf(140.0, 60.0, t / 0.45) * t) * exp(-t * 7.0) * 0.5

## A lit fuse fizzing (a loop).
static func _fuse(t: float, n: float) -> float:
	return n * (0.25 + 0.1 * sin(TAU * 30.0 * t))

## An axe biting wood: a knock and a short dull thud under it.
static func _chop(t: float, n: float) -> float:
	var knock := n * exp(-t * 60.0) * 0.8
	var body := sin(TAU * lerpf(190.0, 120.0, t / 0.22) * t) * exp(-t * 18.0)
	return (knock + body) * 0.7

## A tree coming down: a creak, then a long heavy crash.
static func _fall(t: float, n: float) -> float:
	var creak := sin(TAU * lerpf(260.0, 70.0, clampf(t / 0.5, 0.0, 1.0)) * t) * exp(-t * 4.0) * (0.4 if t < 0.5 else 0.0)
	var hit := smoothstep(0.35, 0.45, t)
	var after := maxf(t - 0.45, 0.0)
	return creak + n * hit * exp(-after * 3.0) * 0.5 + sin(TAU * 45.0 * t) * hit * exp(-after * 4.0) * 0.7

## A hammer on rock: bright, ringing, gone quickly.
static func _clink(t: float, n: float) -> float:
	var ring := (sin(TAU * 1240.0 * t) + 0.7 * sin(TAU * 1873.0 * t) + 0.45 * sin(TAU * 2711.0 * t)) * exp(-t * 16.0)
	return ring * 0.35 + n * exp(-t * 90.0) * 0.5

## Rock splitting.
static func _crack(t: float, n: float) -> float:
	return n * exp(-t * 12.0) * 0.8 + sin(TAU * 80.0 * t) * exp(-t * 10.0) * 0.5

static func _pickup(t: float, _n: float) -> float:
	return sin(TAU * lerpf(320.0, 620.0, t / 0.09) * t) * exp(-t * 20.0) * 0.5

static func _drop(t: float, n: float) -> float:
	return sin(TAU * 85.0 * t) * exp(-t * 20.0) * 0.8 + n * exp(-t * 50.0) * 0.3

static func _whoosh(t: float, n: float) -> float:
	return n * sin(PI * t / 0.3) * 0.45

## The till: two bells.
static func _cash(t: float, _n: float) -> float:
	var a := sin(TAU * 1318.5 * t) * exp(-t * 6.0)
	var b := sin(TAU * 1760.0 * t) * exp(-maxf(t - 0.12, 0.0) * 6.0) * (1.0 if t > 0.12 else 0.0)
	return (a + b) * 0.3

## Building: a wooden knock down, a scrape up.
static func _place(t: float, n: float) -> float:
	return sin(TAU * 150.0 * t) * exp(-t * 25.0) * 0.7 + n * exp(-t * 80.0) * 0.4

static func _remove(t: float, n: float) -> float:
	return n * exp(-t * 14.0) * 0.4 + sin(TAU * lerpf(300.0, 150.0, t / 0.25) * t) * exp(-t * 12.0) * 0.4

## A footstep on grass.
static func _step(t: float, n: float) -> float:
	return n * exp(-t * 60.0) * 0.35

static func _click(t: float, _n: float) -> float:
	return sin(TAU * 900.0 * t) * exp(-t * 90.0) * 0.4

## A diesel at idle: a deep, round rumble - a low fundamental with soft
## harmonics, each cylinder's firing a smooth thump rather than a click, a
## slow lope, and a rumble of low noise under it. Every rate divides the loop
## (0.5 s) into whole cycles, so it goes round without a seam.
static func _engine(t: float, n: float) -> float:
	var f := 32.0
	var tone := sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.0 * t + 0.3) + 0.16 * sin(TAU * f * 3.0 * t + 0.9)
	var phase := fposmod(t * f * 2.0, 1.0) - 0.5
	var thump := exp(-phase * phase / 0.018)
	var lope := 0.85 + 0.15 * sin(TAU * 8.0 * t)
	return (tone * 0.42 + thump * 0.3) * lope + n * 0.12

const ENGINE_VOICES := {
	# Big diesels: slow, deep, a heavy knock on every firing.
	&"big_diesel": [26.0, [1.0, 0.55, 0.2, 0.08], 0.38, 6.0, 0.12, 0.14, 0.0],
	# The loader and crane: diesel with a hydraulic whine over it.
	&"plant": [30.0, [1.0, 0.45, 0.2, 0.1], 0.3, 4.0, 0.1, 0.12, 0.06],
	# A pickup's V8: a lumpy burble.
	&"v8": [40.0, [1.0, 0.6, 0.3, 0.12], 0.26, 8.0, 0.3, 0.1, 0.0],
	# The hauler: a mid-size diesel.
	&"diesel": [34.0, [1.0, 0.5, 0.18, 0.06], 0.3, 6.0, 0.14, 0.12, 0.0],
	# The buggy: a raspy flat-four.
	&"flat4": [56.0, [1.0, 0.45, 0.35, 0.2], 0.2, 10.0, 0.12, 0.16, 0.18],
	# The quad: a single-cylinder thumper.
	&"thumper": [44.0, [1.0, 0.3, 0.15, 0.05], 0.5, 22.0, 0.25, 0.14, 0.08],
	# The dirt bike: a buzzy two-stroke.
	&"two_stroke": [90.0, [1.0, 0.7, 0.5, 0.35], 0.12, 12.0, 0.08, 0.1, 0.3],
}

static func _voice(t: float, n: float, v: Array) -> float:
	var f: float = v[0]
	var h: Array = v[1]
	var tone := 0.0
	for k in h.size():
		tone += float(h[k]) * sin(TAU * f * float(k + 1) * t + float(k) * 0.4)
	var phase := fposmod(t * f, 1.0) - 0.5
	var thump := exp(-phase * phase / 0.02) * float(v[2])
	var lope := 1.0 - float(v[4]) + float(v[4]) * sin(TAU * float(v[3]) * t)
	var rasp := float(v[6]) * (fposmod(t * f * 4.0, 1.0) * 2.0 - 1.0)
	return (tone * 0.3 + thump + rasp) * lope + n * float(v[5])

## A machine running.
static func _hum(t: float, n: float) -> float:
	return sin(TAU * 100.0 * t) * 0.35 + sin(TAU * 200.0 * t) * 0.15 + sin(TAU * 300.0 * t) * 0.06 + n * 0.04

## A machine at work on something.
static func _grind(t: float, n: float) -> float:
	return (n * 0.5 + sin(TAU * 420.0 * t) * 0.2) * sin(PI * t / 0.6)

## Samples of a sound `seconds` long: `f(t, noise)` gives each one. With
## `lowpass`, the noise is softened (thuds and rumbles rather than hiss).
func _synth(seconds: float, f: Callable, lowpass: bool = false) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = n
	var soft := 0.0
	for i in n:
		var noise := rng.randf_range(-1.0, 1.0)
		if lowpass:
			soft = lerpf(soft, noise, 0.12)
			noise = soft * 2.5
		out[i] = f.call(float(i) / RATE, noise)
	return out

func _wav(samples: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	# Loud ones are brought down under clipping rather than cut off at it.
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	if peak > 0.85:
		var k := 0.85 / peak
		for i in samples.size():
			samples[i] *= k
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

# --- Music --------------------------------------------------------------------------

## A slow, warm loop: soft chords under a picked pentatonic tune, 16 bars.
## Built off the main thread; it starts playing when it is ready.
func _build_music() -> void:
	var bpm := 84.0
	var beat := 60.0 / bpm
	var bars := 16
	var seconds := beat * 4.0 * float(bars)
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# I - vi - IV - V in C, a bar each, round four times.
	var chords := [[261.63, 329.63, 392.0], [220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [196.0, 246.94, 293.66]]
	var scale := [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# The tune: a note on most eighths, wandering the scale.
	var notes: Array = []
	var step := 3
	for i in bars * 8:
		if rng.randf() < 0.7:
			step = clampi(step + rng.randi_range(-2, 2), 0, scale.size() - 1)
			notes.append([float(i) * beat * 0.5, scale[step]])
	for i in n:
		var t := float(i) / RATE
		var bar := int(t / (beat * 4.0)) % 4
		var chord: Array = chords[bar]
		var in_bar := fmod(t, beat * 4.0)
		var swell := smoothstep(0.0, 0.6, in_bar) * (1.0 - smoothstep(beat * 4.0 - 0.3, beat * 4.0, in_bar))
		var pad := 0.0
		for fz in chord:
			pad += sin(TAU * float(fz) * 0.5 * t) + 0.3 * sin(TAU * float(fz) * t)
		out[i] = pad * 0.045 * (0.4 + 0.6 * swell)
	for note in notes:
		var start := int(float(note[0]) * RATE)
		var f := float(note[1])
		var length := int(0.9 * RATE)
		for k in length:
			var j := start + k
			if j >= n:
				break
			var tt := float(k) / RATE
			out[j] += (sin(TAU * f * tt) + 0.25 * sin(TAU * f * 2.0 * tt)) * exp(-tt * 5.0) * 0.12
	var stream := _wav(out, true)
	call_deferred("_start_music", stream)

func _start_music(stream: AudioStreamWAV) -> void:
	_music.stream = stream
	_apply_volume()
	_music.play()
