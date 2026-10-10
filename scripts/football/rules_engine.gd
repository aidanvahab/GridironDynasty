class_name RulesEngine
extends RefCounted
## Centralized, testable football rules. Every change to down, distance,
## score, clock or possession — whether from live play or the drive
## simulator — goes through this class. See docs/RULES.md for the rule set.
##
## Every apply_* method returns an Array of event dictionaries
## ({"type": String, ...}) the presentation layer can react to.

const KICKOFF_TOUCHBACK := 30.0
const PUNT_TOUCHBACK := 20.0
const TURNOVER_TOUCHBACK := 20.0
const TRY_KICK_SPOT := 85.0 ## extra point snapped from the 15
const TRY_TWO_SPOT := 98.0 ## two-point try from the 2
const FG_SNAP_DEPTH := 7.0 ## holder spot behind the line of scrimmage
const TWO_MINUTES := 120.0

enum Tempo { HURRY, NORMAL, CHEW }
const TEMPO_SECONDS := {Tempo.HURRY: 12.0, Tempo.NORMAL: 26.0, Tempo.CHEW: 38.0}

var state: GameState
var quarter_length: float = 900.0
var ot_length: float = 600.0
## Scales between-play runoff so shorter game lengths keep a natural number of plays.
var runoff_scale: float = 1.0
var playoff: bool = false ## playoff games cannot end in a tie
var rng: RandomNumberGenerator

func _init(p_quarter_length: float = 900.0, p_runoff_scale: float = 1.0, p_playoff: bool = false, p_rng: RandomNumberGenerator = null) -> void:
	quarter_length = p_quarter_length
	ot_length = minf(600.0, p_quarter_length)
	runoff_scale = p_runoff_scale
	playoff = p_playoff
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	state = GameState.new()
	state.clock = quarter_length

# ---------------------------------------------------------------- setup

## Coin toss result: the receiving side gets the opening kickoff.
func start_game(receiving_side: int) -> Array:
	state.phase = GameState.Phase.KICKOFF
	state.quarter = 1
	state.clock = quarter_length
	state.opening_receiver = receiving_side
	state.kicking_side = GameState.other(receiving_side)
	state.home_dir = 1
	state.timeouts = [3, 3]
	return [{"type": "kickoff_pending", "kicking": state.kicking_side}]

# ---------------------------------------------------------------- queries

func can_snap() -> bool:
	return state.phase == GameState.Phase.SCRIMMAGE

func describe_down() -> String:
	if state.phase == GameState.Phase.TRY:
		return "TRY"
	if state.phase != GameState.Phase.SCRIMMAGE:
		return ""
	var ord: String = ["", "1st", "2nd", "3rd", "4th"][state.down]
	if state.is_goal_to_go():
		return "%s & Goal" % ord
	var togo := state.yards_to_go()
	if togo < 1.0:
		return "%s & Inches" % ord
	return "%s & %d" % [ord, int(ceil(togo - 0.01))]

static func format_clock(seconds: float) -> String:
	var s := int(ceil(maxf(seconds, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]

func quarter_label() -> String:
	if state.quarter <= 4:
		return "Q%d" % state.quarter
	return "OT" if state.quarter == 5 else "OT%d" % (state.quarter - 4)

# ---------------------------------------------------------------- clock

## Clock that runs between the previous play and the next snap.
## Applied when the offense snaps. Capped so the offense can always get the
## snap off before the period expires, and stopped by the two-minute warning.
func pre_snap(tempo: int = Tempo.NORMAL) -> Array:
	var events: Array = []
	assert(state.phase == GameState.Phase.SCRIMMAGE)
	if state.clock_running:
		var runoff: float = TEMPO_SECONDS[tempo] * runoff_scale
		runoff = minf(runoff, maxf(state.clock - 1.0, 0.0))
		_consume(runoff, events, true)
	state.clock_running = false
	return events

## Explicitly let the clock run out (e.g. victory formation). Ends the period.
func run_out_clock() -> Array:
	var events: Array = []
	if state.phase != GameState.Phase.SCRIMMAGE:
		return events
	_add_top(state.possession, state.clock)
	state.clock = 0.0
	_after_play(events)
	return events

func call_timeout(side: int) -> bool:
	if state.phase != GameState.Phase.SCRIMMAGE and state.phase != GameState.Phase.TRY:
		return false
	if state.timeouts[side] <= 0:
		return false
	state.timeouts[side] -= 1
	state.clock_running = false
	return true

func _consume(seconds: float, events: Array, is_runoff: bool) -> void:
	if seconds <= 0.0:
		return
	var before := state.clock
	var after := maxf(before - seconds, 0.0)
	var warn_quarter := state.quarter == 2 or state.quarter == 4
	if warn_quarter and not state.two_minute_warning_given and before > TWO_MINUTES and after <= TWO_MINUTES:
		state.two_minute_warning_given = true
		if is_runoff:
			after = TWO_MINUTES
		state.clock_running = false
		events.append({"type": "two_minute_warning"})
	_add_top(state.possession, before - after)
	state.clock = after

func _add_top(side: int, seconds: float) -> void:
	state.team_stats[side]["top"] += seconds

# ---------------------------------------------------------------- scrimmage

func apply_scrimmage(r: PlayResult) -> Array:
	var events: Array = []
	assert(state.phase == GameState.Phase.SCRIMMAGE, "apply_scrimmage outside scrimmage phase")
	if state.phase != GameState.Phase.SCRIMMAGE:
		return events
	var off := state.possession
	var ts: Dictionary = state.team_stats[off]
	var los := state.ball_on
	var down_before := state.down
	ts["plays"] += 1
	if down_before == 3:
		ts["third_att"] += 1
	elif down_before == 4:
		ts["fourth_att"] += 1

	var two_min_before := state.two_minute_warning_given
	_consume(r.elapsed, events, false)
	var warning_now := state.two_minute_warning_given and not two_min_before
	state.play_log.append({"q": state.quarter, "side": off, "kind": r.kind_name(), "gain": r.gain, "down": down_before, "ball_on": los, "desc": r.description})

	match r.kind:
		PlayResult.Kind.PASS_INCOMPLETE, PlayResult.Kind.SPIKE:
			state.clock_running = false
			_advance_down(los, events)
		PlayResult.Kind.INTERCEPTION, PlayResult.Kind.FUMBLE_LOST:
			ts["turnovers"] += 1
			var spot := los + r.gain
			if r.kind == PlayResult.Kind.FUMBLE_LOST:
				_credit_yards(off, r, minf(r.gain, 100.0 - los))
			events.append({"type": "turnover", "kind": r.kind_name(), "side": off})
			_turnover(spot, r.return_yards, events)
		_:
			var end_spot := los + r.gain
			_credit_yards(off, r, minf(r.gain, 100.0 - los))
			if r.kind == PlayResult.Kind.SACK:
				ts["sacks_allowed"] += 1
			if end_spot >= 100.0:
				_touchdown(off, events, r)
			elif end_spot <= 0.0:
				_safety(off, events)
			else:
				state.clock_running = not r.out_of_bounds
				_advance_down(end_spot, events)
	if warning_now:
		state.clock_running = false
	if r.kind == PlayResult.Kind.KNEEL and state.phase == GameState.Phase.SCRIMMAGE and state.clock > 0.0:
		# Victory formation: the clock keeps running through the huddle.
		_consume(TEMPO_SECONDS[Tempo.CHEW] * runoff_scale, events, true)
	_after_play(events)
	return events

func _credit_yards(side: int, r: PlayResult, yards: float) -> void:
	var ts: Dictionary = state.team_stats[side]
	ts["total_yards"] += yards
	if r.kind == PlayResult.Kind.PASS_COMPLETE or r.kind == PlayResult.Kind.SACK:
		ts["pass_yards"] += yards
	elif r.kind == PlayResult.Kind.RUN or r.kind == PlayResult.Kind.FUMBLE_LOST:
		ts["rush_yards"] += yards

func _advance_down(new_spot: float, events: Array) -> void:
	var off := state.possession
	state.ball_on = clampf(new_spot, 0.5, 99.5)
	if state.ball_on >= state.first_down_line - 0.0001:
		if state.down == 3:
			state.team_stats[off]["third_conv"] += 1
		elif state.down == 4:
			state.team_stats[off]["fourth_conv"] += 1
		state.team_stats[off]["first_downs"] += 1
		_set_first_down()
		events.append({"type": "first_down"})
		return
	if state.down >= 4:
		events.append({"type": "turnover_on_downs", "side": off})
		_change_possession(FieldCoords.flip(state.ball_on), events)
		return
	state.down += 1

func _set_first_down() -> void:
	state.down = 1
	state.first_down_line = minf(state.ball_on + 10.0, 100.0)

func _change_possession(new_ball_on_for_new_offense: float, events: Array) -> void:
	state.possession = GameState.other(state.possession)
	state.ball_on = clampf(new_ball_on_for_new_offense, 0.5, 99.5)
	state.drive_count[state.possession] += 1
	_set_first_down()
	state.clock_running = false
	state.phase = GameState.Phase.SCRIMMAGE
	events.append({"type": "possession_change", "side": state.possession})
	if state.is_overtime():
		state.ot_poss_index += 1
		_check_ot_end(events)

func _turnover(spot_offense_frame: float, return_yards: float, events: Array) -> void:
	var def_side := state.defense()
	var spot_def := FieldCoords.flip(spot_offense_frame) + return_yards
	if spot_def >= 100.0:
		# Returned for a touchdown.
		state.possession = def_side
		state.drive_count[def_side] += 1
		if state.is_overtime():
			state.ot_poss_index += 1
		_touchdown(def_side, events, null, true)
		return
	if spot_def <= 0.0:
		events.append({"type": "touchback"})
		spot_def = TURNOVER_TOUCHBACK
	_change_possession(spot_def, events)

# ---------------------------------------------------------------- scoring

func _score(side: int, points: int, kind: String, events: Array) -> void:
	state.score[side] += points
	state.last_score = {"side": side, "kind": kind, "points": points}
	state.scoring_log.append({"q": state.quarter, "clock": state.clock, "side": side, "kind": kind, "points": points, "score": state.score.duplicate()})
	events.append({"type": "score", "side": side, "kind": kind, "points": points})

func _touchdown(side: int, events: Array, _r: PlayResult = null, defensive: bool = false) -> void:
	state.team_stats[side]["td"] += 1
	_score(side, 6, "defensive_td" if defensive else "touchdown", events)
	state.clock_running = false
	_check_ot_end(events)
	if state.phase == GameState.Phase.GAME_OVER:
		return
	state.phase = GameState.Phase.TRY
	state.try_side = side
	state.possession = side
	state.down = 1
	state.ball_on = TRY_KICK_SPOT
	state.first_down_line = 100.0

func _safety(offense_side: int, events: Array) -> void:
	var scorer := GameState.other(offense_side)
	_score(scorer, 2, "safety", events)
	state.clock_running = false
	_check_ot_end(events)
	if state.phase == GameState.Phase.GAME_OVER:
		return
	state.phase = GameState.Phase.KICKOFF
	state.kicking_side = offense_side
	state.free_kick = true

## kind: "kick" or "two"
func apply_try(kind: String, success: bool) -> Array:
	var events: Array = []
	if state.phase != GameState.Phase.TRY:
		return events
	var side := state.try_side
	if success:
		_score(side, 1 if kind == "kick" else 2, "xp" if kind == "kick" else "two_point", events)
	else:
		events.append({"type": "try_failed", "kind": kind, "side": side})
	state.phase = GameState.Phase.KICKOFF
	state.kicking_side = side
	state.free_kick = false
	_after_play(events)
	return events

func apply_field_goal(made: bool, elapsed: float = 5.0) -> Array:
	var events: Array = []
	if state.phase != GameState.Phase.SCRIMMAGE:
		return events
	var off := state.possession
	var ts: Dictionary = state.team_stats[off]
	ts["fg_att"] += 1
	ts["plays"] += 1
	_consume(elapsed, events, false)
	var kick_spot := state.ball_on - FG_SNAP_DEPTH
	if made:
		ts["fg_made"] += 1
		_score(off, 3, "field_goal", events)
		state.clock_running = false
		_check_ot_end(events)
		if state.phase != GameState.Phase.GAME_OVER:
			state.phase = GameState.Phase.KICKOFF
			state.kicking_side = off
			state.free_kick = false
	else:
		events.append({"type": "fg_missed", "side": off})
		var new_spot := maxf(FieldCoords.flip(kick_spot), TURNOVER_TOUCHBACK)
		_change_possession(new_spot, events)
	_after_play(events)
	return events

## receiver_ball_on: where the receiving team takes over, in its own frame.
func apply_punt(receiver_ball_on: float, touchback: bool, return_td: bool, elapsed: float = 8.0) -> Array:
	var events: Array = []
	if state.phase != GameState.Phase.SCRIMMAGE:
		return events
	var off := state.possession
	state.team_stats[off]["punts"] += 1
	state.team_stats[off]["plays"] += 1
	_consume(elapsed, events, false)
	events.append({"type": "punt", "side": off})
	if return_td:
		var recv := GameState.other(off)
		state.possession = recv
		state.drive_count[recv] += 1
		if state.is_overtime():
			state.ot_poss_index += 1
		_touchdown(recv, events, null, true)
	else:
		var spot := PUNT_TOUCHBACK if touchback else receiver_ball_on
		_change_possession(spot, events)
	_after_play(events)
	return events

## receiver_ball_on: where the receiving team takes over, in its own frame.
func apply_kickoff(receiver_ball_on: float, touchback: bool, return_td: bool, elapsed: float = 6.0) -> Array:
	var events: Array = []
	if state.phase != GameState.Phase.KICKOFF:
		return events
	var recv := GameState.other(state.kicking_side)
	state.possession = state.kicking_side
	state.free_kick = false
	if not touchback:
		_consume(elapsed, events, false)
	if return_td:
		state.possession = recv
		state.drive_count[recv] += 1
		if state.is_overtime():
			state.ot_poss_index += 1
		_touchdown(recv, events, null, false)
	else:
		var spot := KICKOFF_TOUCHBACK if touchback else receiver_ball_on
		_change_possession(spot, events)
	_after_play(events)
	return events

# ---------------------------------------------------------------- periods

func _after_play(events: Array) -> void:
	if state.phase == GameState.Phase.GAME_OVER:
		return
	if state.clock <= 0.0 and state.phase != GameState.Phase.TRY:
		_end_period(events)

func _end_period(events: Array) -> void:
	var q := state.quarter
	state.clock_running = false
	if q == 1 or q == 3:
		state.quarter += 1
		state.clock = quarter_length
		state.home_dir = -state.home_dir
		events.append({"type": "quarter_end", "quarter": q})
	elif q == 2:
		events.append({"type": "halftime"})
		state.quarter = 3
		state.clock = quarter_length
		state.home_dir = -state.home_dir
		state.timeouts = [3, 3]
		state.two_minute_warning_given = false
		state.phase = GameState.Phase.KICKOFF
		state.kicking_side = state.opening_receiver
		state.free_kick = false
	else:
		if state.score[0] != state.score[1]:
			_finish(events)
		elif q == 4 or playoff:
			_start_overtime(events)
		else:
			_finish(events)

func _start_overtime(events: Array) -> void:
	var first_ot := state.quarter == 4
	state.quarter += 1
	state.clock = ot_length
	state.timeouts = [2, 2]
	state.two_minute_warning_given = true
	if first_ot:
		var receiver := rng.randi_range(0, 1)
		state.ot_receiver = receiver
		state.ot_poss_index = 0
		state.phase = GameState.Phase.KICKOFF
		state.kicking_side = GameState.other(receiver)
		state.free_kick = false
	events.append({"type": "overtime", "period": state.quarter - 4, "receiver": state.ot_receiver})

func _check_ot_end(events: Array) -> void:
	if not state.is_overtime() or state.phase == GameState.Phase.GAME_OVER:
		return
	if state.score[0] == state.score[1]:
		return
	var leader := 0 if state.score[0] > state.score[1] else 1
	var kicker := GameState.other(state.ot_receiver)
	var ends := false
	if state.ot_poss_index >= 3:
		ends = true
	elif state.ot_poss_index == 2:
		ends = leader == kicker
	elif state.ot_poss_index <= 1:
		if leader == kicker:
			ends = true
		else:
			var ls := state.last_score
			ends = ls.get("side", -1) == state.ot_receiver and ls.get("kind", "") == "touchdown"
	if ends:
		_finish(events)

func _finish(events: Array) -> void:
	state.phase = GameState.Phase.GAME_OVER
	state.clock_running = false
	if state.score[0] > state.score[1]:
		state.winner = 0
	elif state.score[1] > state.score[0]:
		state.winner = 1
	else:
		state.winner = 2
	events.append({"type": "game_over", "winner": state.winner})
