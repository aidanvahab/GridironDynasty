extends Node
## Audio: pooled one-shot effects, layered crowd ambience that tracks game
## intensity, and music with cross-fades. Missing files are reported once and
## then ignored, so a bad asset never spams errors.

const SFX_DIR := "res://assets/audio/"
const POOL_SIZE := 14

var _cache: Dictionary = {}
var _missing: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _crowd_base: AudioStreamPlayer
var _crowd_hype: AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: String = ""
var _crowd_target := 0.0
var _crowd_level := 0.0
var _crowd_on := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_crowd_base = _looping_player("Crowd")
	_crowd_hype = _looping_player("Crowd")
	_music_a = _looping_player("Music")
	_music_b = _looping_player("Music")

func _looping_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p

func _stream(sound_name: String, loop: bool = false) -> AudioStream:
	var key := sound_name + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	if _missing.has(sound_name):
		return null
	var path := SFX_DIR + sound_name + ".ogg"
	if not ResourceLoader.exists(path):
		_missing[sound_name] = true
		push_warning("Audio asset missing: %s" % path)
		return null
	var s: AudioStream = load(path)
	if loop and s is AudioStreamOggVorbis:
		s = s.duplicate()
		(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s

## Plays a one-shot effect. `volume` is linear 0..1.
func play(sound_name: String, volume: float = 1.0, pitch_jitter: float = 0.05, bus: String = "SFX") -> void:
	var s := _stream(sound_name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stop()
	p.stream = s
	p.bus = bus
	p.volume_db = linear_to_db(clampf(volume, 0.001, 1.5))
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

func ui(kind: String) -> void:
	play("ui_" + kind, 1.0, 0.02)

# ---------------------------------------------------------------- crowd

func crowd_start(level: float = 0.35) -> void:
	_crowd_on = true
	_crowd_target = level
	if not _crowd_base.playing:
		_crowd_base.stream = _stream("crowd_loop", true)
		_crowd_hype.stream = _stream("crowd_excited", true)
		if _crowd_base.stream != null:
			_crowd_base.play()
		if _crowd_hype.stream != null:
			_crowd_hype.play()

func crowd_stop() -> void:
	_crowd_on = false
	_crowd_target = 0.0

## Sustained crowd intensity 0..1.
func crowd_level(level: float) -> void:
	_crowd_target = clampf(level, 0.0, 1.0)

## Momentary reaction: "roar", "cheer", "groan".
func crowd_react(kind: String, volume: float = 1.0) -> void:
	play("crowd_" + kind, volume, 0.03, "Crowd")

func _process(delta: float) -> void:
	_crowd_level = move_toward(_crowd_level, _crowd_target if _crowd_on else 0.0, delta * 0.6)
	if _crowd_base.playing:
		_crowd_base.volume_db = linear_to_db(maxf(0.0001, (0.35 + _crowd_level * 0.4) * (1.0 if _crowd_on or _crowd_level > 0.01 else 0.0)))
		_crowd_hype.volume_db = linear_to_db(maxf(0.0001, clampf((_crowd_level - 0.35) * 1.4, 0.0, 1.0) * 0.8))
		if not _crowd_on and _crowd_level <= 0.01:
			_crowd_base.stop()
			_crowd_hype.stop()

# ---------------------------------------------------------------- music

func music(track: String, fade: float = 1.2) -> void:
	if track == _music_current:
		return
	_music_current = track
	var incoming := _music_b if _music_a.playing else _music_a
	var outgoing := _music_a if incoming == _music_b else _music_b
	var tw := create_tween().set_parallel(true)
	if track != "":
		var s := _stream(track, true)
		if s != null:
			incoming.stream = s
			incoming.volume_db = -40.0
			incoming.play()
			tw.tween_property(incoming, "volume_db", -6.0, fade)
	if outgoing.playing:
		tw.tween_property(outgoing, "volume_db", -60.0, fade)
		tw.chain().tween_callback(outgoing.stop)

func stop_music(fade: float = 1.0) -> void:
	music("", fade)
