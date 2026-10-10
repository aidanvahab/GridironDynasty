class_name KickModel
extends RefCounted
## Statistical kicking outcomes used for simulated kicks and as the fallback
## model for kickoffs/punts presented visually.

## Field-goal distance in yards for a snap from `ball_on` (offense frame).
static func fg_distance(ball_on: float) -> float:
	return (100.0 - ball_on) + RulesEngine.FG_SNAP_DEPTH + 10.0

static func max_range(k_power: float) -> float:
	return 44.0 + k_power * 0.16

static func fg_probability(distance: float, k_power: float, k_acc: float) -> float:
	var p := 0.99
	if distance > 25.0:
		p -= (distance - 25.0) * 0.0135 * (1.55 - k_acc / 110.0)
	var mr := max_range(k_power)
	if distance > mr:
		p -= (distance - mr) * 0.16
	return clampf(p, 0.0, 0.99)

static func xp_probability(k_acc: float) -> float:
	return clampf(0.92 + k_acc * 0.0008, 0.0, 0.995)

## Returns {receiver_ball_on, touchback, return_td, elapsed, kick_yards, return_yards}
static func kickoff(rng: RandomNumberGenerator, k_power: float, returner_speed: float, coverage: float, free_kick: bool = false) -> Dictionary:
	var kick_from := 20.0 if free_kick else 35.0
	var dist := 58.0 + (k_power - 70.0) * 0.25 + rng.randfn(0.0, 5.0)
	if free_kick:
		dist -= 8.0
	var land := kick_from + dist ## kicking-team frame
	if land >= 100.0 and rng.randf() < 0.85:
		return {"receiver_ball_on": RulesEngine.KICKOFF_TOUCHBACK, "touchback": true, "return_td": false, "elapsed": 0.0, "kick_yards": dist, "return_yards": 0.0}
	var catch_spot := clampf(100.0 - land, -5.0, 30.0) ## receiving frame
	var ret := 22.0 + (returner_speed - coverage) * 0.25 + rng.randfn(0.0, 6.0)
	if rng.randf() < 0.05:
		ret += rng.randf_range(15.0, 40.0)
	ret = maxf(ret, 4.0)
	var spot := catch_spot + ret
	var td := rng.randf() < 0.004 + maxf(0.0, (returner_speed - coverage)) * 0.0003
	if td:
		spot = 100.0
	return {"receiver_ball_on": clampf(spot, 1.0, 99.0), "touchback": false, "return_td": td, "elapsed": clampf(ret / 6.0 + 3.0, 4.0, 12.0), "kick_yards": dist, "return_yards": ret}

## Returns {receiver_ball_on, touchback, return_td, elapsed, gross, return_yards, fair_catch}
static func punt(rng: RandomNumberGenerator, ball_on: float, k_power: float, returner_speed: float, coverage: float) -> Dictionary:
	var gross := 36.0 + k_power * 0.12 + rng.randfn(0.0, 5.5)
	var land := ball_on + gross
	if land >= 100.0:
		if rng.randf() < 0.7:
			return {"receiver_ball_on": RulesEngine.PUNT_TOUCHBACK, "touchback": true, "return_td": false, "elapsed": 6.0, "gross": gross, "return_yards": 0.0, "fair_catch": false}
		land = rng.randf_range(92.0, 98.0)
	var fair := rng.randf() < 0.32 or land > 88.0
	var ret := 0.0
	if not fair:
		ret = maxf(0.0, 7.0 + (returner_speed - coverage) * 0.2 + rng.randfn(0.0, 5.0))
		if rng.randf() < 0.04:
			ret += rng.randf_range(10.0, 35.0)
	var spot := (100.0 - land) + ret
	var td := not fair and rng.randf() < 0.003
	return {"receiver_ball_on": clampf(spot, 1.0, 99.0), "touchback": false, "return_td": td, "elapsed": 7.0 + ret / 6.0, "gross": gross, "return_yards": ret, "fair_catch": fair}
