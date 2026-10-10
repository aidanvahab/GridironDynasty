class_name PassMath
extends RefCounted
## Deterministic projectile math for passes and kicks (units: yards, seconds).

const GRAVITY := 10.72 ## 9.8 m/s^2 expressed in yd/s^2
const CATCH_HEIGHT := 1.35

## Launch velocity reaching `to` from `from` at speed `speed`, using the flatter
## (low) solution. If out of range the ball is thrown at the max-range angle and
## lands short. Returns {velocity, time, reachable}.
static func solve(from: Vector3, to: Vector3, speed: float, lob: bool = false) -> Dictionary:
	var delta := to - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var d := flat.length()
	var dir := flat.normalized() if d > 0.001 else Vector3.FORWARD
	var dy := delta.y
	var v2 := speed * speed
	var g := GRAVITY
	var disc := v2 * v2 - g * (g * d * d + 2.0 * dy * v2)
	if d < 0.01:
		return {"velocity": Vector3(0, speed * 0.3, 0), "time": 0.2, "reachable": true}
	if disc < 0.0:
		var ang := PI / 4.0
		var vel := dir * (speed * cos(ang)) + Vector3.UP * (speed * sin(ang))
		return {"velocity": vel, "time": flight_time(from.y, vel.y, to.y), "reachable": false}
	var root := sqrt(disc)
	var tan_t := (v2 + root) / (g * d) if lob else (v2 - root) / (g * d)
	var theta := atan(tan_t)
	var vel := dir * (speed * cos(theta)) + Vector3.UP * (speed * sin(theta))
	return {"velocity": vel, "time": d / (speed * cos(theta)), "reachable": true}

## Time for a projectile launched at height y0 with vertical speed vy to come
## down to height y1.
static func flight_time(y0: float, vy: float, y1: float) -> float:
	var g := GRAVITY
	var disc := vy * vy + 2.0 * g * (y0 - y1)
	if disc < 0.0:
		return vy / g
	return (vy + sqrt(disc)) / g

static func position_at(from: Vector3, vel: Vector3, t: float) -> Vector3:
	return from + vel * t + Vector3.DOWN * (0.5 * GRAVITY * t * t)

## Peak height of the arc.
static func apex(from: Vector3, vel: Vector3) -> float:
	if vel.y <= 0.0:
		return from.y
	return from.y + vel.y * vel.y / (2.0 * GRAVITY)

## Passing speed (yd/s) for a charge level 0..1 and the passer's arm.
static func throw_speed(power: float, arm: float) -> float:
	var vmax := 21.0 + arm * 0.12 ## 27 .. 33 yd/s
	return lerpf(13.0, vmax, clampf(power, 0.0, 1.0))

## Charge level that produces a comfortable, catchable arc for distance d.
static func ideal_power(d: float, arm: float) -> float:
	var desired := clampf(12.0 + d * 0.42, 14.0, 21.0 + arm * 0.12)
	var vmax := 21.0 + arm * 0.12
	return clampf((desired - 13.0) / (vmax - 13.0), 0.0, 1.0)

## Standard deviation (yards) of the throw's landing error.
static func error_sigma(dist: float, accuracy: float, pressure: float, moving: float, power: float, assist: int) -> float:
	var base := 0.28 + (99.0 - accuracy) * 0.012 ## 0.28 .. 1.0
	var s := base * (0.35 + dist / 22.0)
	s *= 1.0 + pressure * 0.9
	s *= 1.0 + moving * 0.45
	s *= 1.0 + maxf(0.0, power - 0.85) * 1.6
	if assist >= 2:
		s *= 0.55
	elif assist == 1:
		s *= 0.85
	return s
