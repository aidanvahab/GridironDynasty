class_name BroadcastCamera
extends Camera3D
## Third-person broadcast camera. Each mode computes a desired eye position and
## look target; both are critically damped toward their targets so motion is
## smooth, with a small dead zone to avoid jitter.

enum Mode { PRESNAP, LIVE, KICK, WIDE, ORBIT, REPLAY, CELEBRATE, FIXED }

var mode: Mode = Mode.ORBIT
var play: LivePlay
var dir: int = 1
var anchor := Vector3.ZERO ## ball spot for presnap / kicks
var kick_target := Vector3.ZERO
var tracked: Node3D ## kick ball / replay focus
var follow_rate: float = 4.0
var assist: bool = true
var shake_amount: float = 0.0
var shake_enabled: bool = true
var orbit_angle: float = 0.0
var orbit_radius: float = 95.0
var orbit_height: float = 38.0
var replay_angle: int = 0
var _eye := Vector3(0, 30, 60)
var _look := Vector3.ZERO
var _eye_vel := Vector3.ZERO
var _look_vel := Vector3.ZERO

func _ready() -> void:
	fov = 52.0
	near = 0.2
	far = 900.0
	current = true

func snap_to_target() -> void:
	var d := _desired()
	_eye = d[0]
	_look = d[1]
	_eye_vel = Vector3.ZERO
	_look_vel = Vector3.ZERO
	_apply(0.0)

func set_mode(m: Mode, instant: bool = false) -> void:
	mode = m
	if instant:
		snap_to_target()

func add_shake(amount: float) -> void:
	if shake_enabled:
		shake_amount = maxf(shake_amount, amount)

func _fwd() -> Vector3:
	return FieldCoords.forward(dir)

func _desired() -> Array:
	var fwd := _fwd()
	var up := Vector3.UP
	match mode:
		Mode.PRESNAP:
			var base := Vector3(anchor.x, 0, anchor.z * 0.55)
			return [base - fwd * 12.5 + up * 7.8, base + fwd * 11.0 + up * 0.5]
		Mode.LIVE, Mode.CELEBRATE:
			return _live_framing()
		Mode.KICK:
			var b := tracked.global_position if tracked != null else anchor
			var eye := anchor - fwd * 9.0 + up * 3.6
			var look := kick_target.lerp(b, 0.35) + up * 2.0
			if tracked != null and tracked.global_position.distance_to(anchor) > 6.0:
				eye = eye.lerp(b - fwd * 12.0 + up * 4.0, 0.5)
			return [eye, look]
		Mode.WIDE:
			var c := Vector3(anchor.x * 0.8, 0, 0)
			return [c + Vector3(0, 30, 58), c + Vector3(0, 0, -4)]
		Mode.ORBIT:
			var e := Vector3(cos(orbit_angle) * orbit_radius, orbit_height, sin(orbit_angle) * orbit_radius * 0.75)
			return [e, Vector3(0, 2, 0)]
		Mode.REPLAY:
			var f := tracked.global_position if tracked != null else anchor
			match replay_angle % 3:
				0: # sideline
					return [Vector3(f.x, 7.0, f.z + (22.0 if f.z < 8.0 else -22.0)), f + up]
				1: # end zone
					return [f + fwd * 24.0 + up * 6.0, f + up]
				_: # sky cam
					return [f - fwd * 6.0 + up * 22.0, f]
		_:
			return [_eye, _look]

func _live_framing() -> Array:
	var fwd := _fwd()
	var up := Vector3.UP
	if play == null:
		return [_eye, _look]
	var c: FieldAgent = play.ball.carrier as FieldAgent
	var ball_pos := play.ball.global_position
	var focus := Vector3(ball_pos.x, 0, ball_pos.z)
	var look_ahead := 8.0
	var back := 11.0
	var height := 7.0
	if play.ball.state == Football.State.FLIGHT and play.thrown:
		var land: Vector3 = play.pass_land
		focus = Vector3(ball_pos.x, 0, ball_pos.z).lerp(land, 0.45)
		back = 12.5
		height = 8.0
		look_ahead = 2.0
	elif c != null:
		focus = c.flat_pos()
		if c == play.qb and not play.thrown and not play.ran_past_los and not play.handed_off:
			# Pocket: frame the quarterback and the field in front of him.
			var tgt: FieldAgent = play.receivers[play.target_idx] if play.target_idx >= 0 else null
			var ahead := focus + fwd * 9.0
			if tgt != null:
				ahead = ahead.lerp(tgt.flat_pos(), 0.3)
			return [focus - fwd * 10.5 + up * 7.2 + Vector3(0, 0, -focus.z * 0.25), ahead + up * 0.5]
		if assist:
			focus += Vector3(c.vel.x, 0, c.vel.z) * 0.3
		if c.unit == FieldAgent.Unit.DEFENSE:
			look_ahead = -6.0
	var eye := focus - fwd * back + up * height
	eye.z = lerpf(eye.z, focus.z, 0.75)
	var look := focus + fwd * look_ahead + up * 0.6
	if mode == Mode.CELEBRATE:
		eye = focus - fwd * 7.0 + up * 3.5 + Vector3(0, 0, 3.0)
		look = focus + up * 1.2
	return [eye, look]

func _process(delta: float) -> void:
	_apply(delta)

func _apply(delta: float) -> void:
	if delta > 0.0:
		var d := _desired()
		var rate := follow_rate * float(Settings.get_value("camera_sensitivity")) if Settings.has_method("get_value") else follow_rate
		if mode == Mode.ORBIT:
			orbit_angle += delta * 0.05
			rate = 1.5
		if mode == Mode.REPLAY:
			rate = 3.0
		_eye = _damp(_eye, d[0], delta, rate, true)
		_look = _damp(_look, d[1], delta, rate * 1.4, false)
	var eye := _eye
	if eye.y < 1.6:
		eye.y = 1.6
	if shake_amount > 0.0:
		eye += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake_amount * 0.25
		shake_amount = maxf(0.0, shake_amount - delta * 2.5)
	global_position = eye
	if eye.distance_to(_look) > 0.01:
		look_at(_look, Vector3.UP)

func _damp(cur: Vector3, target: Vector3, dt: float, rate: float, is_eye: bool) -> Vector3:
	# Dead zone: ignore tiny target changes to keep the frame calm.
	var diff := target - cur
	if diff.length() < 0.03:
		return cur
	var k := 1.0 - exp(-rate * dt)
	return cur + diff * k
