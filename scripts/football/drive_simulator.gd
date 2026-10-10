class_name DriveSimulator
extends RefCounted
## Play-by-play statistical simulation. Each simulated down is converted into a
## PlayResult and applied through the shared RulesEngine, so simulated drives
## obey exactly the same rules, clock and scoring as live play.

var rules: RulesEngine
var league: League
var teams: Array = [] ## [home Team, away Team]
var ratings: Array = [{}, {}]
var rng: RandomNumberGenerator
var stats: StatsRecorder
## Additive rating adjustment applied to each side's offense / defense.
var off_adj: Array[float] = [0.0, 0.0]
var def_adj: Array[float] = [0.0, 0.0]
var lineups: Array = [{}, {}]
var turnover_mult: Array[float] = [1.0, 1.0]
var base: Dictionary = {}

func _init(p_rules: RulesEngine, p_league: League, home: Team, away: Team, p_rng: RandomNumberGenerator, p_stats: StatsRecorder) -> void:
	rules = p_rules
	league = p_league
	teams = [home, away]
	rng = p_rng
	stats = p_stats
	base = league.rating_baseline()
	for side in 2:
		ratings[side] = league.team_ratings(teams[side])
		lineups[side] = _lineup(teams[side])
	# Home-field advantage, boosted by stadium facilities.
	var hf := 1.2 + (float(home.facilities.get("stadium", 1)) - 1.0) * 0.4
	off_adj[0] += hf
	def_adj[0] += hf

func _lineup(t: Team) -> Dictionary:
	var lu := {}
	for pos in Team.STARTERS:
		lu[pos] = league.starters(t, pos, Team.STARTERS[pos])
	return lu

## Difficulty: the CPU side (opposite the user) gets `bonus` on offense and defense.
func apply_difficulty(user_side: int, bonus: float, cpu_turnover_mult: float = 1.0) -> void:
	if user_side < 0:
		return
	var cpu := 1 - user_side
	off_adj[cpu] += bonus
	def_adj[cpu] += bonus * 0.5
	turnover_mult[user_side] = 1.0
	turnover_mult[cpu] = cpu_turnover_mult

# ------------------------------------------------------------------ helpers

func _pick(side: int, pos: String, idx: int = -1) -> Player:
	var arr: Array = lineups[side].get(pos, [])
	if arr.is_empty():
		return null
	if idx < 0:
		return arr[rng.randi_range(0, arr.size() - 1)]
	return arr[mini(idx, arr.size() - 1)]

func _pid(p: Player) -> String:
	return p.id if p != null else ""

func _name(p: Player) -> String:
	return p.short_name() if p != null else "Player"

func _weighted_target(side: int) -> Player:
	var wr: Array = lineups[side].get("WR", [])
	var opts: Array = []
	var weights: Array = []
	for i in wr.size():
		opts.append(wr[i])
		weights.append([0.30, 0.24, 0.16][mini(i, 2)] * (wr[i].effective("route") + wr[i].effective("catching")) / 140.0)
	var te: Player = _pick(side, "TE", 0)
	if te != null:
		opts.append(te)
		weights.append(0.17)
	var rb: Player = _pick(side, "RB", 0)
	if rb != null:
		opts.append(rb)
		weights.append(0.13)
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in opts.size():
		r -= weights[i]
		if r <= 0.0:
			return opts[i]
	return opts[0] if not opts.is_empty() else null

func _tackler(def_side: int, deep: bool) -> Player:
	var r := rng.randf()
	if deep:
		return _pick(def_side, "S") if r < 0.5 else _pick(def_side, "CB")
	if r < 0.45:
		return _pick(def_side, "LB")
	if r < 0.7:
		return _pick(def_side, "DL")
	if r < 0.87:
		return _pick(def_side, "S")
	return _pick(def_side, "CB")

## Offense rating relative to the league average (0 = average).
func off_rating(side: int, key: String) -> float:
	return float(ratings[side][key]) - float(base.get(key, 0.0)) + off_adj[side]

## Defense rating relative to the league average (0 = average).
func def_rating(side: int, key: String) -> float:
	return float(ratings[side][key]) - float(base.get(key, 0.0)) + def_adj[side]

# ------------------------------------------------------------------ decisions

func _score_diff(side: int) -> int:
	return rules.state.score[side] - rules.state.score[1 - side]

func _late(sec: float) -> bool:
	var s := rules.state
	return (s.quarter == 4 or s.is_overtime()) and s.clock <= sec

func _half_ending(sec: float) -> bool:
	var s := rules.state
	return (s.quarter == 2 or s.quarter == 4) and s.clock <= sec

## Returns "run", "pass", "fg", "punt", "kneel" or "spike".
func choose_call(side: int) -> String:
	var s := rules.state
	var diff := _score_diff(side)
	var togo := s.yards_to_go()
	var fg_dist := KickModel.fg_distance(s.ball_on)
	var k_power: float = ratings[side]["k_power"]
	var in_range := fg_dist <= KickModel.max_range(k_power) - 2.0
	# Victory formation when the clock can be run out.
	if s.quarter == 4 and diff > 0 and s.clock <= float(5 - s.down) * 38.0 * rules.runoff_scale + 4.0:
		return "kneel"
	# Last-second field goal.
	if _half_ending(8.0) and in_range and (s.quarter == 2 or diff >= -3):
		return "fg"
	if s.down == 4:
		var desperate := _late(240.0) and diff < 0
		if in_range and not (desperate and diff < -3):
			if togo <= 1.0 and s.ball_on >= 60.0 and diff <= 0 and rng.randf() < 0.35:
				pass
			else:
				return "fg"
		if desperate or (togo <= 1.0 and s.ball_on >= 45.0) or (togo <= 2.0 and s.ball_on >= 65.0 and rng.randf() < 0.5):
			return "pass" if togo > 3.0 else ("run" if rng.randf() < 0.55 else "pass")
		return "punt"
	var style: String = teams[side].offense_style
	var pass_p: float = {"pass": 0.62, "balanced": 0.55, "run": 0.45}.get(style, 0.55)
	if s.down == 3 and togo >= 6.0:
		pass_p += 0.3
	elif s.down >= 2 and togo <= 2.0:
		pass_p -= 0.2
	if _late(300.0) and diff < 0:
		pass_p += 0.25
	if _late(360.0) and diff > 0:
		pass_p -= 0.25
	if s.ball_on >= 95.0:
		pass_p -= 0.15
	return "pass" if rng.randf() < clampf(pass_p, 0.1, 0.92) else "run"

func choose_tempo(side: int) -> int:
	var diff := _score_diff(side)
	if _half_ending(120.0) and (diff <= 0 or rules.state.quarter == 2):
		return RulesEngine.Tempo.HURRY
	if rules.state.quarter == 4 and diff > 0:
		return RulesEngine.Tempo.CHEW
	return RulesEngine.Tempo.NORMAL

# ------------------------------------------------------------------ plays

## Simulates one scrimmage play for the side in possession. Returns a text line.
func simulate_play() -> Dictionary:
	var s := rules.state
	var off := s.possession
	var dfn := 1 - off
	var call := choose_call(off)
	var line := ""
	var events: Array = []
	if call == "fg":
		return simulate_field_goal()
	if call == "punt":
		return simulate_punt()
	events.append_array(rules.pre_snap(choose_tempo(off)))
	if s.phase != GameState.Phase.SCRIMMAGE:
		return {"text": "", "events": events, "call": call}
	var r: PlayResult
	var qb := _pick(off, "QB", 0)
	if call == "kneel":
		r = PlayResult.make(PlayResult.Kind.KNEEL, -1.0, 2.0)
		line = "%s kneels" % _name(qb)
	elif call == "pass":
		r = _sim_pass(off, dfn)
		line = r.description
	else:
		r = _sim_run(off, dfn)
		line = r.description
	record_play(off, dfn, r)
	events.append_array(rules.apply_scrimmage(r))
	return {"text": line, "events": events, "call": call, "result": r}

func _sim_pass(off: int, dfn: int) -> PlayResult:
	var s := rules.state
	var qb := _pick(off, "QB", 0)
	var qbv := off_rating(off, "qb")
	var recv := off_rating(off, "recv")
	var ol := off_rating(off, "ol")
	var pr := def_rating(dfn, "pass_rush")
	var cov := def_rating(dfn, "coverage")
	var t := rng.randf_range(5.0, 8.0)
	var p_sack := clampf(0.065 + (pr - ol) * 0.004, 0.025, 0.15)
	if rng.randf() < p_sack:
		var sacker := _pick(dfn, "DL") if rng.randf() < 0.75 else _pick(dfn, "LB")
		var loss := -rng.randf_range(3.0, 10.0)
		var r := PlayResult.make(PlayResult.Kind.SACK, loss, rng.randf_range(3.0, 5.0))
		r.credit = {"passer": _pid(qb), "sacker": _pid(sacker)}
		r.description = "%s sacked by %s for %d" % [_name(qb), _name(sacker), int(round(loss))]
		if rng.randf() < 0.07 * turnover_mult[off]:
			r.kind = PlayResult.Kind.FUMBLE_LOST
			r.credit["fumbler"] = _pid(qb)
			r.credit["recoverer"] = _pid(_pick(dfn, "DL"))
			r.description += " — FUMBLE, recovered by the defense"
		return r
	var togo := s.yards_to_go()
	var depth_roll := rng.randf()
	var deep_p := 0.14 + (0.1 if togo > 12.0 else 0.0) + (0.1 if _late(120.0) and _score_diff(off) < 0 else 0.0)
	var med_p := 0.36
	var depth := 0 ## 0 short, 1 medium, 2 deep
	if depth_roll < deep_p:
		depth = 2
	elif depth_roll < deep_p + med_p:
		depth = 1
	var air: float = [rng.randf_range(1.0, 8.0), rng.randf_range(9.0, 18.0), rng.randf_range(19.0, 45.0)][depth]
	air = minf(air, 100.0 - s.ball_on + 2.0)
	var comp: float = 0.62 + qbv * 0.007 + (recv - cov) * 0.005 + [0.1, -0.07, -0.29][depth]
	var p_int: float = (0.021 + (cov - qbv) * 0.0012 + [0.0, 0.008, 0.025][depth]) * turnover_mult[off]
	var target := _weighted_target(off)
	if rng.randf() < clampf(p_int, 0.005, 0.08):
		var who := _pick(dfn, "CB") if rng.randf() < 0.6 else _pick(dfn, "S")
		var r := PlayResult.make(PlayResult.Kind.INTERCEPTION, air, t)
		r.return_yards = maxf(0.0, rng.randfn(8.0, 9.0))
		if rng.randf() < 0.05:
			r.return_yards = 100.0
		r.credit = {"passer": _pid(qb), "interceptor": _pid(who), "target": _pid(target)}
		r.description = "%s pass INTERCEPTED by %s" % [_name(qb), _name(who)]
		return r
	if rng.randf() < clampf(comp, 0.2, 0.9):
		var yac := maxf(0.0, rng.randfn([3.0, 2.5, 4.0][depth], 2.5))
		if rng.randf() < 0.035:
			yac += rng.randf_range(10.0, 45.0)
		var gain := minf(air + yac, 100.0 - s.ball_on + 5.0)
		var oob := rng.randf() < (0.35 if _half_ending(120.0) else 0.14)
		var r := PlayResult.make(PlayResult.Kind.PASS_COMPLETE, gain, t, oob)
		r.air_yards = air
		var tk := _tackler(dfn, depth == 2)
		r.credit = {"passer": _pid(qb), "receiver": _pid(target), "tackler": _pid(tk)}
		var where: String = ["short", "", "deep"][depth]
		r.description = "%s pass %s to %s for %d" % [_name(qb), where, _name(target), int(round(gain))]
		if s.ball_on + gain >= 100.0:
			r.description += " — TOUCHDOWN"
		elif rng.randf() < 0.012 * turnover_mult[off]:
			r.kind = PlayResult.Kind.FUMBLE_LOST
			r.credit["fumbler"] = _pid(target)
			r.credit["recoverer"] = _pid(tk)
			r.description += " — FUMBLE recovered by %s" % _name(tk)
		return r
	var r := PlayResult.make(PlayResult.Kind.PASS_INCOMPLETE, air, rng.randf_range(4.0, 6.0))
	r.credit = {"passer": _pid(qb), "target": _pid(target)}
	r.description = "%s pass incomplete, intended for %s" % [_name(qb), _name(target)]
	return r

func _sim_run(off: int, dfn: int) -> PlayResult:
	var s := rules.state
	var qb_run := rng.randf() < clampf(0.06 + off_rating(off, "qb_mobility") * 0.006, 0.02, 0.18)
	var runner := _pick(off, "QB", 0) if qb_run else _pick(off, "RB", 0)
	var rbv := off_rating(off, "rb")
	var ol := off_rating(off, "ol")
	var rd := def_rating(dfn, "run_def")
	var mean := 3.6 + ((rbv + ol) * 0.5 - rd) * 0.09
	var gain := rng.randfn(mean, 3.2)
	if rng.randf() < 0.05:
		gain += rng.randf_range(6.0, 40.0)
	if rng.randf() < 0.12:
		gain = -rng.randf_range(0.0, 3.0)
	if s.ball_on >= 97.0:
		gain = minf(gain, rng.randf_range(-1.0, 4.0))
	gain = clampf(gain, -6.0, 100.0 - s.ball_on + 5.0)
	var oob := rng.randf() < 0.07
	var r := PlayResult.make(PlayResult.Kind.RUN, gain, rng.randf_range(4.5, 7.5), oob)
	var tk := _tackler(dfn, gain > 15.0)
	r.credit = {"rusher": _pid(runner), "tackler": _pid(tk)}
	r.description = "%s runs for %d" % [_name(runner), int(round(gain))]
	if s.ball_on + gain >= 100.0:
		r.description += " — TOUCHDOWN"
	elif rng.randf() < 0.011 * turnover_mult[off]:
		r.kind = PlayResult.Kind.FUMBLE_LOST
		r.credit["fumbler"] = _pid(runner)
		r.credit["recoverer"] = _pid(tk)
		r.description += " — FUMBLE recovered by %s" % _name(tk)
	return r

func simulate_field_goal() -> Dictionary:
	var s := rules.state
	var off := s.possession
	var k := _pick(off, "K", 0)
	var dist := KickModel.fg_distance(s.ball_on)
	var p := KickModel.fg_probability(dist, ratings[off]["k_power"], ratings[off]["k_acc"])
	var made := rng.randf() < p
	stats.add(_pid(k), "fg_att", 1.0, off)
	if made:
		stats.add(_pid(k), "fg_made", 1.0, off)
	var ev := rules.apply_field_goal(made, 5.0)
	return {"text": "%s %d-yard field goal is %s" % [_name(k), int(round(dist)), "GOOD" if made else "NO GOOD"], "events": ev, "call": "fg", "made": made, "distance": dist}

func simulate_punt() -> Dictionary:
	var s := rules.state
	var off := s.possession
	var k := _pick(off, "K", 0)
	var res := KickModel.punt(rng, s.ball_on, ratings[off]["k_power"], _returner_speed(1 - off), 70.0)
	stats.add(_pid(k), "punts", 1.0, off)
	stats.add(_pid(k), "punt_yds", res["gross"], off)
	var ev := rules.apply_punt(res["receiver_ball_on"], res["touchback"], res["return_td"], res["elapsed"])
	var txt := "%s punts %d yards" % [_name(k), int(round(res["gross"]))]
	if res["touchback"]:
		txt += ", touchback"
	elif res["fair_catch"]:
		txt += ", fair catch"
	else:
		txt += ", returned %d" % int(round(res["return_yards"]))
	return {"text": txt, "events": ev, "call": "punt", "punt": res}

func _returner_speed(side: int) -> float:
	var cb := _pick(side, "CB", 2)
	return cb.effective("speed") if cb != null else 70.0

## Kickoff by rules.state.kicking_side. Returns the kick dictionary + events.
func simulate_kickoff() -> Dictionary:
	var s := rules.state
	var kick := s.kicking_side
	var res := KickModel.kickoff(rng, ratings[kick]["k_power"], _returner_speed(1 - kick), 70.0 + def_adj[kick], s.free_kick)
	var ev := rules.apply_kickoff(res["receiver_ball_on"], res["touchback"], res["return_td"], res["elapsed"])
	res["events"] = ev
	return res

## AI try decision: "kick" or "two".
func choose_try(side: int) -> String:
	var diff := _score_diff(side) ## already includes the six points
	if rules.state.quarter >= 4 and diff in [-2, 1, -5, -10]:
		return "two"
	return "kick"

func simulate_try() -> Dictionary:
	var side := rules.state.try_side
	var kind := choose_try(side)
	var success := false
	var k := _pick(side, "K", 0)
	if kind == "kick":
		success = rng.randf() < KickModel.xp_probability(ratings[side]["k_acc"])
		stats.add(_pid(k), "xp_att", 1.0, side)
		if success:
			stats.add(_pid(k), "xp_made", 1.0, side)
	else:
		var edge := (off_rating(side, "offense") - def_rating(1 - side, "defense")) * 0.01
		success = rng.randf() < clampf(0.47 + edge, 0.3, 0.65)
	var ev := rules.apply_try(kind, success)
	return {"kind": kind, "success": success, "events": ev}

# ------------------------------------------------------------------ stats

## Credits a play's statistics. Must be called before the play is applied
## (it reads the pre-snap line of scrimmage).
func record_play(off: int, dfn: int, r: PlayResult) -> void:
	var c := r.credit
	var s := rules.state
	var gain := minf(r.gain, 100.0 - s.ball_on)
	var td := s.ball_on + r.gain >= 100.0
	match r.kind:
		PlayResult.Kind.PASS_COMPLETE:
			stats.add(c.get("passer", ""), "pass_att", 1, off)
			stats.add(c.get("passer", ""), "pass_cmp", 1, off)
			stats.add(c.get("passer", ""), "pass_yds", gain, off)
			stats.add(c.get("receiver", ""), "rec", 1, off)
			stats.add(c.get("receiver", ""), "targets", 1, off)
			stats.add(c.get("receiver", ""), "rec_yds", gain, off)
			if td:
				stats.add(c.get("passer", ""), "pass_td", 1, off)
				stats.add(c.get("receiver", ""), "rec_td", 1, off)
			else:
				stats.add(c.get("tackler", ""), "tackles", 1, dfn)
		PlayResult.Kind.PASS_INCOMPLETE:
			stats.add(c.get("passer", ""), "pass_att", 1, off)
			stats.add(c.get("target", ""), "targets", 1, off)
		PlayResult.Kind.INTERCEPTION:
			stats.add(c.get("passer", ""), "pass_att", 1, off)
			stats.add(c.get("passer", ""), "int_thrown", 1, off)
			stats.add(c.get("interceptor", ""), "def_int", 1, dfn)
		PlayResult.Kind.SACK:
			stats.add(c.get("passer", ""), "sacked", 1, off)
			stats.add(c.get("sacker", ""), "sacks", 1, dfn)
			stats.add(c.get("sacker", ""), "tackles", 1, dfn)
		PlayResult.Kind.RUN:
			stats.add(c.get("rusher", ""), "rush_att", 1, off)
			stats.add(c.get("rusher", ""), "rush_yds", gain, off)
			if td:
				stats.add(c.get("rusher", ""), "rush_td", 1, off)
			else:
				stats.add(c.get("tackler", ""), "tackles", 1, dfn)
		PlayResult.Kind.FUMBLE_LOST:
			if c.has("rusher"):
				stats.add(c.get("rusher", ""), "rush_att", 1, off)
				stats.add(c.get("rusher", ""), "rush_yds", gain, off)
			if c.has("receiver"):
				stats.add(c.get("passer", ""), "pass_att", 1, off)
				stats.add(c.get("passer", ""), "pass_cmp", 1, off)
				stats.add(c.get("passer", ""), "pass_yds", gain, off)
				stats.add(c.get("receiver", ""), "rec", 1, off)
				stats.add(c.get("receiver", ""), "rec_yds", gain, off)
			stats.add(c.get("fumbler", ""), "fumbles", 1, off)
			stats.add(c.get("recoverer", ""), "ff", 1, dfn)

# ------------------------------------------------------------------ drives

## Simulates until the side in possession changes, a score happens, the half
## ends or the game ends. Returns a drive summary.
func simulate_drive() -> Dictionary:
	var s := rules.state
	var side := s.possession
	var start_ball := s.ball_on
	var start_clock := s.clock
	var start_q := s.quarter
	var log: Array = []
	var plays := 0
	var result := ""
	var guard := 0
	while s.phase == GameState.Phase.SCRIMMAGE and s.possession == side and guard < 40:
		guard += 1
		var ball_before := s.ball_on
		var q_before := s.quarter
		var out := simulate_play()
		plays += 1
		if out["text"] != "":
			log.append({"text": out["text"], "q": q_before, "ball_on": ball_before})
		for e in out["events"]:
			match e["type"]:
				"score":
					result = {"touchdown": "Touchdown", "field_goal": "Field Goal", "safety": "Safety", "defensive_td": "Defensive TD"}.get(e["kind"], "Score")
				"turnover":
					result = "Interception" if e["kind"] == "INTERCEPTION" else "Fumble"
				"turnover_on_downs":
					result = "Turnover on Downs"
				"fg_missed":
					result = "Missed FG"
				"punt":
					result = "Punt"
				"halftime":
					if result == "":
						result = "End of Half"
				"game_over":
					if result == "":
						result = "End of Game"
		if result != "" and result != "End of Half":
			break
		if s.quarter != q_before and (q_before == 2 or q_before >= 4):
			break
	var elapsed := start_clock - s.clock if s.quarter == start_q else start_clock + (rules.quarter_length - s.clock)
	var yards := 0.0
	if s.possession == side and s.phase == GameState.Phase.SCRIMMAGE:
		yards = s.ball_on - start_ball
	elif result == "Touchdown":
		yards = 100.0 - start_ball
	else:
		for entry in rules.state.play_log.slice(-plays):
			if entry["side"] == side and entry["kind"] in ["RUN", "PASS_COMPLETE", "SACK"]:
				yards += minf(entry["gain"], 100.0 - entry["ball_on"])
	return {"side": side, "plays": plays, "yards": yards, "start": start_ball, "result": result if result != "" else "End of Quarter", "time": maxf(elapsed, 0.0), "log": log}

## Simulates an entire game (CPU vs CPU). Returns the final GameState.
func simulate_game(receiving_side: int = -1) -> GameState:
	if receiving_side < 0:
		receiving_side = rng.randi_range(0, 1)
	rules.start_game(receiving_side)
	var guard := 0
	while not rules.state.is_over() and guard < 600:
		guard += 1
		match rules.state.phase:
			GameState.Phase.KICKOFF:
				simulate_kickoff()
			GameState.Phase.TRY:
				simulate_try()
			GameState.Phase.SCRIMMAGE:
				simulate_drive()
	return rules.state
