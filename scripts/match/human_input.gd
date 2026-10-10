class_name HumanInput
extends PlayInput
## Keyboard + mouse + gamepad control for live play.
## Keyboard: WASD move, Shift sprint, Space snap/juke, C dive, 1-5 target,
## LMB hold/release throw, Q cancel, E throw away.
## Gamepad: left stick move, RT sprint, A snap/juke, B dive; hold a receiver
## button (A/B/X/Y/RB) to charge and release to throw; right stick fine-aims.

var _was_charging := false
var _pad_target := -1
var _blocked := true ## ignore throw buttons held over from before the snap
const PAD_TARGETS := ["pad_target_1", "pad_target_2", "pad_target_3", "pad_target_4", "pad_target_5"]
const TRACKED := ["snap", "juke", "dive", "cancel_target", "throw_away", "throw", "target_1", "target_2", "target_3", "target_4", "target_5", "pad_target_1", "pad_target_2", "pad_target_3", "pad_target_4", "pad_target_5"]

## Presses/releases queued from input events since the last poll, so quick
## taps are never lost between physics ticks at low frame rates.
var _pressed_q := {}
var _released_q := {}

func push_event(e: InputEvent) -> void:
	for a in TRACKED:
		if e.is_action_pressed(a, false):
			_pressed_q[a] = true
		elif e.is_action_released(a):
			_released_q[a] = true

func _just(a: String) -> bool:
	return _pressed_q.has(a) or Input.is_action_just_pressed(a)

func poll(play: Node, _dt: float) -> void:
	clear()
	var v := Input.get_vector("move_left", "move_right", "move_back", "move_forward", 0.2)
	move = v
	any_move = v.length() > 0.2
	sprint = Input.is_action_pressed("sprint")
	snap = _just("snap")
	juke = _just("juke")
	dive = _just("dive")
	cancel = _just("cancel_target")
	throw_away = _just("throw_away")
	for i in 5:
		if _just("target_%d" % (i + 1)):
			target = i
	# Gamepad receiver buttons: hold to charge, release to throw.
	var pad_held := -1
	for i in PAD_TARGETS.size():
		if Input.is_action_pressed(PAD_TARGETS[i]):
			pad_held = i
		if _just(PAD_TARGETS[i]):
			target = i
	var mouse_charge := Input.is_action_pressed("throw")
	var held := mouse_charge or pad_held >= 0
	var live: bool = play.get("stage") == LivePlay.Stage.LIVE
	if not live:
		_blocked = true
	elif _blocked and not held:
		_blocked = false
	if _blocked:
		held = false
		if live:
			target = -1
	if pad_held >= 0:
		_pad_target = pad_held
	charging = held
	release = _was_charging and not held
	_was_charging = held
	_pressed_q.clear()
	_released_q.clear()
	aim_nudge = Input.get_vector("aim_left", "aim_right", "aim_back", "aim_forward", 0.25)
	var cam: Camera3D = play.get("camera")
	if cam != null and Settings.last_input_was_mouse:
		var mp := play.get_viewport().get_mouse_position()
		var from := cam.project_ray_origin(mp)
		var dir := cam.project_ray_normal(mp)
		if dir.y < -0.01:
			var tt := (PassMath.CATCH_HEIGHT - from.y) / dir.y
			if tt > 0.0:
				aim_world = from + dir * tt
				aim_world.y = 0.0
				has_aim = true
