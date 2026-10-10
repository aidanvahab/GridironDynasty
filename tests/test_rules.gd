extends TestCase
## Rules engine: downs, distance, scoring, possession, clock, overtime.

func _engine(ql: float = 900.0, playoff: bool = false) -> RulesEngine:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var e := RulesEngine.new(ql, 1.0, playoff, rng)
	e.start_game(GameState.HOME)
	e.apply_kickoff(0, true, false)
	return e

func _run(e: RulesEngine, gain: float, oob := false, t := 5.0) -> Array:
	return e.apply_scrimmage(PlayResult.make(PlayResult.Kind.RUN, gain, t, oob))

func test_kickoff_touchback_gives_receiver_first_and_ten_at_30() -> void:
	var e := _engine()
	eq(e.state.possession, GameState.HOME)
	eq(e.state.ball_on, 30.0)
	eq(e.state.down, 1)
	eq(e.state.yards_to_go(), 10.0)
	eq(e.describe_down(), "1st & 10")

func test_first_down_requires_full_distance() -> void:
	var e := _engine()
	_run(e, 9.9)
	eq(e.state.down, 2, "9.9 yards is not a first down")
	near(e.state.yards_to_go(), 0.1, 0.001)
	var ev := _run(e, 0.1)
	check(has_event(ev, "first_down"))
	eq(e.state.down, 1)
	near(e.state.first_down_line, 50.0, 0.001)

func test_downs_advance_and_turnover_on_downs() -> void:
	var e := _engine()
	_run(e, 2)
	_run(e, 2)
	_run(e, 2)
	eq(e.state.down, 4)
	var ev := _run(e, 1)
	check(has_event(ev, "turnover_on_downs"))
	eq(e.state.possession, GameState.AWAY)
	near(e.state.ball_on, 100.0 - 37.0, 0.001, "defense takes over at the spot")
	eq(e.state.down, 1)

func test_incomplete_pass_keeps_spot_and_stops_clock() -> void:
	var e := _engine()
	var clock_before := e.state.clock
	e.pre_snap()
	e.apply_scrimmage(PlayResult.make(PlayResult.Kind.PASS_INCOMPLETE, 12.0, 4.0))
	eq(e.state.ball_on, 30.0)
	eq(e.state.down, 2)
	eq(e.state.yards_to_go(), 10.0)
	near(e.state.clock, clock_before - 4.0, 0.001)
	check(not e.state.clock_running)

func test_inbounds_run_keeps_clock_running_and_runoff_applies() -> void:
	var e := _engine()
	_run(e, 4.0, false, 5.0)
	check(e.state.clock_running)
	var c := e.state.clock
	e.pre_snap(RulesEngine.Tempo.NORMAL)
	near(e.state.clock, c - RulesEngine.TEMPO_SECONDS[RulesEngine.Tempo.NORMAL], 0.001)
	_run(e, 4.0, true, 5.0)
	check(not e.state.clock_running, "out of bounds stops the clock")
	c = e.state.clock
	e.pre_snap()
	near(e.state.clock, c, 0.001, "no runoff after a stopped clock")

func test_timeout_prevents_runoff() -> void:
	var e := _engine()
	_run(e, 3.0)
	check(e.call_timeout(GameState.HOME))
	eq(e.state.timeouts[GameState.HOME], 2)
	var c := e.state.clock
	e.pre_snap()
	near(e.state.clock, c, 0.001)

func test_rushing_touchdown_then_try_then_kickoff() -> void:
	var e := _engine()
	var ev := _run(e, 75.0)
	check(has_event(ev, "score"))
	eq(e.state.score[GameState.HOME], 6)
	eq(e.state.phase, GameState.Phase.TRY)
	ev = e.apply_try("kick", true)
	eq(e.state.score[GameState.HOME], 7)
	eq(e.state.phase, GameState.Phase.KICKOFF)
	eq(e.state.kicking_side, GameState.HOME)
	e.apply_kickoff(27.0, false, false)
	eq(e.state.possession, GameState.AWAY)
	eq(e.state.ball_on, 27.0)

func test_no_touchdown_short_of_goal_line() -> void:
	var e := _engine()
	_run(e, 69.9)
	eq(e.state.score[GameState.HOME], 0)
	eq(e.state.phase, GameState.Phase.SCRIMMAGE)
	check(e.state.is_goal_to_go(), "inside the 10 after first down is goal to go")
	eq(e.describe_down(), "1st & Goal")

func test_two_point_conversion() -> void:
	var e := _engine()
	_run(e, 70.0)
	e.apply_try("two", true)
	eq(e.state.score[GameState.HOME], 8)

func test_interception_changes_possession_at_spot() -> void:
	var e := _engine()
	var r := PlayResult.make(PlayResult.Kind.INTERCEPTION, 20.0, 4.0)
	r.return_yards = 5.0
	var ev := e.apply_scrimmage(r)
	check(has_event(ev, "turnover"))
	eq(e.state.possession, GameState.AWAY)
	near(e.state.ball_on, 100.0 - 50.0 + 5.0, 0.001)
	eq(e.state.team_stats[GameState.HOME]["turnovers"], 1)

func test_interception_in_endzone_is_touchback() -> void:
	var e := _engine()
	_run(e, 50.0) # ball on opp 20
	var r := PlayResult.make(PlayResult.Kind.INTERCEPTION, 25.0, 4.0) # picked 5 yards deep
	e.apply_scrimmage(r)
	eq(e.state.possession, GameState.AWAY)
	eq(e.state.ball_on, RulesEngine.TURNOVER_TOUCHBACK)

func test_pick_six() -> void:
	var e := _engine()
	var r := PlayResult.make(PlayResult.Kind.INTERCEPTION, 10.0, 6.0)
	r.return_yards = 70.0
	e.apply_scrimmage(r)
	eq(e.state.score[GameState.AWAY], 6)
	eq(e.state.phase, GameState.Phase.TRY)
	eq(e.state.try_side, GameState.AWAY)

func test_safety() -> void:
	var e := _engine()
	e.state.ball_on = 3.0
	var ev := e.apply_scrimmage(PlayResult.make(PlayResult.Kind.SACK, -5.0, 3.0))
	check(has_event(ev, "score"))
	eq(e.state.score[GameState.AWAY], 2)
	eq(e.state.phase, GameState.Phase.KICKOFF)
	eq(e.state.kicking_side, GameState.HOME)
	check(e.state.free_kick)

func test_field_goal_made_and_missed() -> void:
	var e := _engine()
	_run(e, 45.0) # opp 25
	e.apply_field_goal(true)
	eq(e.state.score[GameState.HOME], 3)
	eq(e.state.phase, GameState.Phase.KICKOFF)
	e.apply_kickoff(25.0, false, false)
	# Away now has ball at its 25. Move to home 30 and miss.
	_run(e, 45.0)
	e.apply_field_goal(false)
	eq(e.state.possession, GameState.HOME)
	near(e.state.ball_on, 100.0 - (70.0 - RulesEngine.FG_SNAP_DEPTH), 0.001, "missed FG: spot of kick")

func test_missed_short_fg_uses_twenty() -> void:
	var e := _engine()
	_run(e, 62.0) # opp 8
	_run(e, 0.0)
	e.apply_field_goal(false)
	eq(e.state.possession, GameState.AWAY)
	eq(e.state.ball_on, 20.0)

func test_punt_and_touchback() -> void:
	var e := _engine()
	e.apply_punt(18.0, false, false)
	eq(e.state.possession, GameState.AWAY)
	eq(e.state.ball_on, 18.0)
	e.apply_punt(0.0, true, false)
	eq(e.state.possession, GameState.HOME)
	eq(e.state.ball_on, 20.0)

func test_quarter_end_switches_direction_and_keeps_drive() -> void:
	var e := _engine(60.0)
	var dir_before := e.state.offense_dir()
	_run(e, 3.0, false, 59.0)
	_run(e, 3.0, false, 5.0)
	eq(e.state.quarter, 2)
	eq(e.state.clock, 60.0)
	eq(e.state.down, 3, "drive continues into the next quarter")
	eq(e.state.offense_dir(), -dir_before)

func test_no_extra_play_after_period_expires() -> void:
	var e := _engine(30.0)
	_run(e, 3.0, false, 10.0)
	e.pre_snap(RulesEngine.Tempo.CHEW) # capped to leave 1 second
	near(e.state.clock, 1.0, 0.001)
	eq(e.state.quarter, 1)
	_run(e, 3.0, false, 4.0)
	eq(e.state.quarter, 2, "the play that expires the clock ends the quarter")

func test_halftime_kickoff_by_opening_receiver() -> void:
	var e := _engine(60.0)
	e.state.quarter = 2
	e.state.two_minute_warning_given = true
	_run(e, 2.0, false, 61.0)
	eq(e.state.quarter, 3)
	eq(e.state.phase, GameState.Phase.KICKOFF)
	eq(e.state.kicking_side, GameState.HOME, "home received first, so kicks second half")
	eq(e.state.timeouts[0], 3)

func test_two_minute_warning_stops_clock() -> void:
	var e := _engine()
	e.state.quarter = 4
	e.state.clock = 125.0
	var ev := _run(e, 3.0, false, 6.0)
	check(has_event(ev, "two_minute_warning"))
	check(not e.state.clock_running)
	near(e.state.clock, 119.0, 0.001)

func test_two_minute_warning_caps_runoff() -> void:
	var e := _engine()
	e.state.quarter = 2
	e.state.clock = 140.0
	_run(e, 3.0, false, 1.0)
	var ev := e.pre_snap(RulesEngine.Tempo.CHEW)
	check(has_event(ev, "two_minute_warning"))
	near(e.state.clock, 120.0, 0.001)

func test_game_over_regulation_and_no_further_plays() -> void:
	var e := _engine(60.0)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [14, 10]
	var ev := _run(e, 3.0, false, 61.0)
	check(has_event(ev, "game_over"))
	eq(e.state.phase, GameState.Phase.GAME_OVER)
	eq(e.state.winner, 0)
	check(not e.can_snap())
	var ev2 := e.apply_field_goal(true)
	eq(ev2.size(), 0, "no plays after the game ends")
	eq(e.state.score[0], 14)

func test_tie_goes_to_overtime_and_receiver_td_wins() -> void:
	var e := _engine(60.0)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [10, 10]
	var ev := _run(e, 3.0, false, 61.0)
	check(has_event(ev, "overtime"))
	eq(e.state.quarter, 5)
	eq(e.state.phase, GameState.Phase.KICKOFF)
	var receiver := e.state.ot_receiver
	e.apply_kickoff(25.0, false, false)
	eq(e.state.possession, receiver)
	ev = _run(e, 80.0)
	check(has_event(ev, "game_over"))
	eq(e.state.winner, receiver)

func test_overtime_fg_gives_other_team_a_chance() -> void:
	var e := _engine(60.0)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [10, 10]
	_run(e, 3.0, false, 61.0)
	var r := e.state.ot_receiver
	var k := GameState.other(r)
	e.apply_kickoff(25.0, false, false)
	_run(e, 50.0)
	e.apply_field_goal(true)
	check(not e.state.is_over(), "FG on first possession does not end OT")
	e.apply_kickoff(25.0, false, false)
	eq(e.state.possession, k)
	var ev := e.apply_punt(20.0, false, false)
	check(has_event(ev, "game_over"), "kicker failed to answer")
	eq(e.state.winner, r)

func test_overtime_fg_answered_then_sudden_death() -> void:
	var e := _engine(60.0)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [3, 3]
	_run(e, 3.0, false, 61.0)
	var r := e.state.ot_receiver
	var k := GameState.other(r)
	e.apply_kickoff(25.0, false, false)
	_run(e, 50.0)
	e.apply_field_goal(true)
	e.apply_kickoff(25.0, false, false)
	_run(e, 50.0)
	e.apply_field_goal(true)
	check(not e.state.is_over())
	e.apply_kickoff(25.0, false, false)
	eq(e.state.possession, r)
	_run(e, 50.0)
	var ev := e.apply_field_goal(true)
	check(has_event(ev, "game_over"), "sudden death")
	eq(e.state.winner, r)
	check(k != r)

func test_regular_season_overtime_can_tie() -> void:
	var e := _engine(60.0)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [7, 7]
	_run(e, 3.0, false, 61.0)
	e.apply_kickoff(25.0, false, false)
	_run(e, 3.0, false, 200.0)
	eq(e.state.phase, GameState.Phase.GAME_OVER)
	eq(e.state.winner, 2)

func test_playoff_overtime_continues() -> void:
	var e := _engine(60.0, true)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [7, 7]
	_run(e, 3.0, false, 61.0)
	e.apply_kickoff(25.0, false, false)
	_run(e, 3.0, false, 200.0)
	eq(e.state.quarter, 6)
	check(not e.state.is_over())

func test_kneel_burns_clock() -> void:
	var e := _engine(120.0)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [21, 14]
	e.apply_scrimmage(PlayResult.make(PlayResult.Kind.KNEEL, -1.0, 2.0))
	near(e.state.clock, 120.0 - 2.0 - RulesEngine.TEMPO_SECONDS[RulesEngine.Tempo.CHEW], 0.001)

func test_run_out_clock_ends_game() -> void:
	var e := _engine(120.0)
	e.state.quarter = 4
	e.state.two_minute_warning_given = true
	e.state.score = [21, 14]
	var ev := e.run_out_clock()
	check(has_event(ev, "game_over"))

func test_stats_track_yards_and_conversions() -> void:
	var e := _engine()
	_run(e, 4)
	_run(e, 3)
	_run(e, 5) # 3rd down conversion
	var ts: Dictionary = e.state.team_stats[GameState.HOME]
	eq(ts["third_att"], 1)
	eq(ts["third_conv"], 1)
	eq(ts["first_downs"], 1)
	near(ts["rush_yards"], 12.0, 0.001)

func test_clock_format() -> void:
	eq(RulesEngine.format_clock(125.0), "2:05")
	eq(RulesEngine.format_clock(0.2), "0:01")
	eq(RulesEngine.format_clock(0.0), "0:00")
