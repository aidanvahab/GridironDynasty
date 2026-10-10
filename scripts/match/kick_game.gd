class_name KickGame
extends Node3D
## Field goal / extra point mini-game. Aim with A/D (or the stick), press once
## to start the power meter and again to lock it. Kicker power sets range,
## accuracy sets the random hook/slice, and wind drifts the ball in flight.
## The kick is a real projectile checked against the goal plane.

signal finished(made: bool, info: Dictionary)

enum Stage { AIM, POWER, FLIGHT, DONE }

const ELEVATION := deg_to_rad(37.0)
const MAX_AIM := deg_to_rad(14.0)

var stage: Stage = Stage.DONE ## idle until setup()
var kicker: FieldAgent
var ball: Football
var dir: int = 1
var spot := Vector3.ZERO ## ball placement (world)
var distance: float = 30.0 ## kick distance to the goal posts
var wind := Vector2.ZERO ## world x/z acceleration in yd/s^2
var wind_mph: float = 0.0
var aim: float = 0.0 ## radians, + = toward offense right
var meter: float = 0.0
var meter_dir: float = 1.0
var power: float = 0.0
var k_power: float = 70.0
var k_acc: float = 70.0
var is_xp: bool = false
var auto_plan: Dictionary = {} ## for tests/bots: {"aim": rad, "power": 0..1}
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _crossed := false
var _result_sent := false
var _vel := Vector3.ZERO

func setup(p_kicker: FieldAgent, p_ball: Football, p_dir: int, kick_ball_on: float, lateral: float, p_wind_mph: float, wind_angle: float, xp: bool) -> void:
	kicker = p_kicker
	ball = p_ball
	dir = p_dir
	is_xp = xp
	spot = FieldCoords.to_world(kick_ball_on, FieldCoords.hash_lateral(lateral), dir)
	distance = (100.0 - kick_ball_on) + 10.0
	k_power = kicker.player.effective("kick_power")
	k_acc = kicker.player.effective("kick_acc")
	wind_mph = p_wind_mph
	wind = Vector2(cos(wind_angle), sin(wind_angle)) * p_wind_mph * 0.03
	stage = Stage.AIM
	meter = 0.0
	power = 0.0
	aim = 0.0
	_t = 0.0
	_crossed = false
	_result_sent = false
	kicker.reset_for_play(spot - FieldCoords.forward(dir) * 2.2 + FieldCoords.offense_right(dir) * -1.0, FieldCoords.forward(dir))
	kicker.rig.set_pose(PlayerRig.Pose.IDLE)
	ball.state = Football.State.DEAD
	ball.global_position = spot + Vector3(0, 0.15, 0)
	ball.mesh_root.basis = Basis.looking_at(Vector3.UP, FieldCoords.forward(dir))
	ball.visible = true

func max_velocity() -> float:
	return 18.0 + k_power * 0.12

## Distance reachable at full power (to crossbar height), for the HUD.
func max_range() -> float:
	var v := max_velocity()
	return v * v * sin(2.0 * ELEVATION) / PassMath.GRAVITY * 0.92

func goal_center() -> Vector3:
	return Vector3(float(dir) * 60.0, 0, 0)

## Aim angle (offense frame, + = right) that points straight between the uprights.
func ideal_aim() -> float:
	var to := goal_center() - spot
	return atan2(to.dot(FieldCoords.offense_right(dir)), to.dot(FieldCoords.forward(dir)))

func _physics_process(dt: float) -> void:
	if kicker == null:
		return
	_t += dt
	match stage:
		Stage.AIM, Stage.POWER:
			_handle_input(dt)
			kicker.rig.animate(dt)
		Stage.FLIGHT:
			_vel.y -= PassMath.GRAVITY * dt
			_vel.x += wind.x * dt
			_vel.z += wind.y * dt
			var prev := ball.global_position
			ball.global_position += _vel * dt
			ball.spin_angle += 12.0 * dt
			ball.mesh_root.basis = Basis.looking_at(_vel.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, ball.spin_angle)
			kicker.rig.animate(dt)
			_check_goal(prev, ball.global_position)
			if ball.global_position.y <= 0.12 and not _result_sent:
				_finish(false, "short")
			if _t > 8.0 and not _result_sent:
				_finish(false, "short")
		Stage.DONE:
			kicker.rig.animate(dt)

func _handle_input(dt: float) -> void:
	var press := false
	var steer := 0.0
	if not auto_plan.is_empty():
		if stage == Stage.AIM and _t > 0.6:
			aim = float(auto_plan.get("aim", ideal_aim()))
			press = true
		elif stage == Stage.POWER and meter >= float(auto_plan.get("power", 0.85)):
			press = true
	else:
		steer = Input.get_axis("kick_left", "kick_right")
		press = Input.is_action_just_pressed("kick_power")
	if stage == Stage.AIM:
		aim = clampf(aim + steer * dt * 0.45, -MAX_AIM, MAX_AIM)
		if press:
			stage = Stage.POWER
			meter = 0.0
			meter_dir = 1.0
	elif stage == Stage.POWER:
		meter += meter_dir * dt * 1.05
		if meter >= 1.0:
			meter = 1.0
			meter_dir = -1.0
		if meter <= 0.0 and meter_dir < 0.0:
			# Missed the window: weak, short kick.
			_kick(0.25)
			return
		if press:
			_kick(meter)

func _kick(p: float) -> void:
	power = p
	stage = Stage.FLIGHT
	_t = 0.0
	kicker.rig.set_pose(PlayerRig.Pose.KICK)
	# Accuracy: inaccurate kickers and over-swinging push the ball off line.
	var sigma := 0.012 + (99.0 - k_acc) * 0.0011 + maxf(0.0, p - 0.92) * 0.12
	var hook := rng.randfn(0.0, sigma)
	var yaw := aim + hook
	var fwd := FieldCoords.forward(dir)
	# Rotating by -yaw turns the forward vector toward the offense's right.
	var horiz := fwd.rotated(Vector3.UP, -yaw)
	var v := max_velocity() * clampf(p, 0.05, 1.0)
	_vel = horiz * v * cos(ELEVATION) + Vector3.UP * v * sin(ELEVATION)
	ball.state = Football.State.DEAD
	ball.visible = true
	Audio.play("kick", 1.0)

func _check_goal(prev: Vector3, cur: Vector3) -> void:
	var plane_x := float(dir) * 60.0
	if _crossed:
		return
	if (prev.x - plane_x) * (cur.x - plane_x) <= 0.0 and prev.x != cur.x:
		_crossed = true
		var k := (plane_x - prev.x) / (cur.x - prev.x)
		var hit := prev.lerp(cur, k)
		var half := FieldCoords.GOAL_POST_WIDTH * 0.5
		var made := absf(hit.z) < half and hit.y > FieldCoords.CROSSBAR_HEIGHT
		var why := "good"
		if not made:
			if hit.y <= FieldCoords.CROSSBAR_HEIGHT:
				why = "short"
			elif hit.z * float(dir) > 0.0:
				why = "wide_right"
			else:
				why = "wide_left"
		_finish(made, why)

func _finish(made: bool, why: String) -> void:
	if _result_sent:
		return
	_result_sent = true
	stage = Stage.DONE
	finished.emit(made, {"reason": why, "distance": distance, "power": power})
