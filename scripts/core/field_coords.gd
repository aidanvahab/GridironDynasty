class_name FieldCoords
## Canonical field coordinate system. 1 world unit = 1 yard.
##
## World axes: +X runs along the length of the field, +Y is up, +Z runs across.
## Goal lines sit at x = -50 and x = +50, end lines at x = -60 / +60,
## sidelines at z = -HALF_WIDTH / +HALF_WIDTH.
##
## Gameplay positions are expressed in the *offense frame*:
##   ball_on  -> yards from the offense's own goal line (0 = own goal line,
##               100 = opponent goal line, >100 inside opponent end zone)
##   lateral  -> yards to the quarterback's right (+) / left (-)
## `dir` is +1 when the offense drives toward +X and -1 when toward -X.
## All conversions go through this file so movement, camera and rules agree.

const FIELD_LENGTH := 100.0
const ENDZONE_DEPTH := 10.0
const FIELD_WIDTH := 53.3333
const HALF_WIDTH := 26.6667
const HASH_OFFSET := 3.083 ## distance of the hash marks from the field center
const GOAL_POST_WIDTH := 6.167 ## 18'6" between uprights
const CROSSBAR_HEIGHT := 3.333 ## 10 ft
const UPRIGHT_HEIGHT := 11.67

static func world_x(ball_on: float, dir: int) -> float:
	return float(dir) * (ball_on - 50.0)

static func ball_on_from_world_x(x: float, dir: int) -> float:
	return x * float(dir) + 50.0

static func world_z(lateral: float, dir: int) -> float:
	return lateral * float(dir)

static func lateral_from_world_z(z: float, dir: int) -> float:
	return z * float(dir)

static func to_world(ball_on: float, lateral: float, dir: int, y: float = 0.0) -> Vector3:
	return Vector3(world_x(ball_on, dir), y, world_z(lateral, dir))

static func to_field(p: Vector3, dir: int) -> Vector2:
	## Returns Vector2(ball_on, lateral) in the offense frame.
	return Vector2(ball_on_from_world_x(p.x, dir), lateral_from_world_z(p.z, dir))

static func forward(dir: int) -> Vector3:
	return Vector3(float(dir), 0.0, 0.0)

static func offense_right(dir: int) -> Vector3:
	return Vector3(0.0, 0.0, float(dir))

static func is_in_bounds(p: Vector3) -> bool:
	return absf(p.z) <= HALF_WIDTH and absf(p.x) <= 50.0 + ENDZONE_DEPTH

static func in_opponent_endzone(ball_on: float) -> bool:
	return ball_on >= 100.0

static func in_own_endzone(ball_on: float) -> bool:
	return ball_on <= 0.0

static func flip(ball_on: float) -> float:
	## Converts a spot between the two possession frames.
	return 100.0 - ball_on

static func clamp_spot(ball_on: float) -> float:
	return clampf(ball_on, 0.0, 100.0)

static func yard_line_number(ball_on: float) -> int:
	## The painted yard line nearest the spot (0..50).
	var b := clampf(ball_on, 0.0, 100.0)
	return int(round(b if b <= 50.0 else 100.0 - b))

static func describe_spot(ball_on: float, own_abbr: String, opp_abbr: String) -> String:
	var n := yard_line_number(ball_on)
	if n == 50:
		return "50"
	if ball_on < 50.0:
		return "%s %d" % [own_abbr, n]
	return "%s %d" % [opp_abbr, n]

static func hash_lateral(lateral: float) -> float:
	## Spot the ball between the hashes (snaps are never taken outside them).
	return clampf(lateral, -HASH_OFFSET, HASH_OFFSET)
