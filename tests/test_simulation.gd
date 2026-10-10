extends TestCase

func _league(seed: int = 42) -> League:
	return League.create_new({"coach": "Test", "team_id": "IWF"}, seed)

func test_league_generation_is_valid() -> void:
	var lg := _league()
	eq(lg.teams.size(), 16)
	var seen := {}
	for t in lg.teams.values():
		check(t.roster.size() >= Team.ROSTER_MIN and t.roster.size() <= Team.ROSTER_MAX, "%s roster size %d" % [t.id, t.roster.size()])
		for pos in Team.MIN_AT:
			check(lg.position_count(t, pos) >= Team.MIN_AT[pos], "%s has enough %s" % [t.id, pos])
		check(lg.payroll(t) <= League.SALARY_CAP, "%s under cap" % t.id)
		var nums := {}
		for pid in t.roster:
			check(not seen.has(pid), "player on two rosters")
			seen[pid] = true
			var p: Player = lg.players[pid]
			eq(p.team_id, t.id)
			check(not nums.has(p.number), "%s duplicate jersey number %d" % [t.id, p.number])
			nums[p.number] = true
	check(lg.user_team().is_user)
	check(lg.free_agents.size() > 10)

func test_generation_is_deterministic() -> void:
	var a := _league(9)
	var b := _league(9)
	var pa: Player = a.players["p1"]
	var pb: Player = b.players["p1"]
	eq(pa.full_name(), pb.full_name())
	eq(pa.overall(), pb.overall())

func test_position_strengths_differ() -> void:
	var lg := _league()
	var wr_block := 0.0
	var ol_block := 0.0
	var nwr := 0
	var nol := 0
	for p in lg.players.values():
		if p.pos == "WR":
			wr_block += p.a("blocking"); nwr += 1
		elif p.pos == "OL":
			ol_block += p.a("blocking"); nol += 1
	check(ol_block / nol > wr_block / nwr + 20.0, "linemen block better than receivers")

func test_simulated_games_are_sane() -> void:
	var lg := _league(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var total_pts := 0
	var games := 120
	var ties := 0
	for g in games:
		var home: Team = lg.teams[lg.team_order[g % 16]]
		var away: Team = lg.teams[lg.team_order[(g + 5) % 16]]
		var rules := RulesEngine.new(900.0, 1.0, false, rng)
		var stats := StatsRecorder.new()
		var sim := DriveSimulator.new(rules, lg, home, away, rng, stats)
		var st := sim.simulate_game()
		check(st.is_over(), "game finished")
		total_pts += st.score[0] + st.score[1]
		if st.winner == 2:
			ties += 1
		# Scoring log reproduces the final score.
		var tally := [0, 0]
		for s in st.scoring_log:
			tally[s["side"]] += s["points"]
		eq(tally[0], st.score[0], "home tally")
		eq(tally[1], st.score[1], "away tally")
		check(st.quarter >= 4)
	var avg := float(total_pts) / games / 2.0
	print("        avg points per team: %.1f, ties: %d" % [avg, ties])
	check(avg > 12.0 and avg < 34.0, "average points per team %.1f in a believable range" % avg)

func test_drive_respects_possession() -> void:
	var lg := _league(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var rules := RulesEngine.new(900.0, 1.0, false, rng)
	var sim := DriveSimulator.new(rules, lg, lg.teams["IWF"], lg.teams["HBG"], rng, StatsRecorder.new())
	rules.start_game(GameState.AWAY)
	sim.simulate_kickoff()
	eq(rules.state.possession, GameState.AWAY)
	var d := sim.simulate_drive()
	eq(d["side"], GameState.AWAY)
	check(d["plays"] >= 1)
	check(rules.state.possession != GameState.AWAY or rules.state.phase != GameState.Phase.SCRIMMAGE or rules.state.quarter > 1, "drive ended in a change of state")

func test_cpu_kneels_to_protect_lead() -> void:
	var lg := _league(3)
	var rng := RandomNumberGenerator.new()
	var rules := RulesEngine.new(900.0, 1.0, false, rng)
	var sim := DriveSimulator.new(rules, lg, lg.teams["IWF"], lg.teams["HBG"], rng, StatsRecorder.new())
	rules.start_game(GameState.HOME)
	rules.apply_kickoff(0, true, false)
	rules.state.quarter = 4
	rules.state.clock = 70.0
	rules.state.two_minute_warning_given = true
	rules.state.score = [17, 10]
	eq(sim.choose_call(GameState.HOME), "kneel")

func test_fourth_down_decisions() -> void:
	var lg := _league(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var rules := RulesEngine.new(900.0, 1.0, false, rng)
	var sim := DriveSimulator.new(rules, lg, lg.teams["IWF"], lg.teams["HBG"], rng, StatsRecorder.new())
	rules.start_game(GameState.HOME)
	rules.apply_kickoff(0, true, false)
	rules.state.down = 4
	rules.state.ball_on = 25.0
	rules.state.first_down_line = 33.0
	eq(sim.choose_call(GameState.HOME), "punt", "4th & 8 at own 25 punts")
	rules.state.ball_on = 75.0
	rules.state.first_down_line = 83.0
	eq(sim.choose_call(GameState.HOME), "fg", "4th & 8 at opp 25 kicks")
