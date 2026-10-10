extends TestCase
## Franchise systems: schedule, standings, season, playoffs, offseason,
## contracts, cap, draft, progression, trades, persistence.

func _league(seed: int = 21, games: int = 14) -> League:
	return League.create_new({"coach": "T", "team_id": "IWF", "settings": {"season_games": games}}, seed)

func _check_invariants(lg: League, label: String) -> void:
	var owner := {}
	for t in lg.teams.values():
		for pid in t.roster:
			check(lg.players.has(pid), "%s: rostered player exists" % label)
			check(not owner.has(pid), "%s: %s owned twice" % [label, pid])
			owner[pid] = t.id
			check(lg.players[pid].team_id == t.id, "%s: team_id matches roster" % label)
	for pid in lg.free_agents:
		check(not owner.has(pid), "%s: free agent also rostered" % label)

func test_schedule_is_valid() -> void:
	for games in [10, 14, 15]:
		var lg := _league(3, games)
		eq(lg.schedule.size(), games, "weeks")
		var pairs := {}
		var counts := {}
		var home := {}
		for wk in lg.schedule:
			var seen := {}
			for g in wk:
				check(g["home"] != g["away"], "no self games")
				check(not seen.has(g["home"]) and not seen.has(g["away"]), "team plays once per week")
				seen[g["home"]] = true
				seen[g["away"]] = true
				var key: String = g["home"] + g["away"] if g["home"] < g["away"] else g["away"] + g["home"]
				check(not pairs.has(key), "matchup not repeated")
				pairs[key] = true
				counts[g["home"]] = counts.get(g["home"], 0) + 1
				counts[g["away"]] = counts.get(g["away"], 0) + 1
				home[g["home"]] = home.get(g["home"], 0) + 1
			eq(seen.size(), 16, "all teams play each week")
		for tid in lg.teams:
			eq(counts[tid], games, "%s plays %d games" % [tid, games])
			check(absi(int(home.get(tid, 0)) - games / 2) <= 2, "%s home games balanced" % tid)

func test_standings_tiebreakers() -> void:
	var lg := _league()
	var a: Team = lg.teams["IWF"]
	var b: Team = lg.teams["HBG"]
	a.record = {"w": 5, "l": 2, "t": 0, "pf": 150, "pa": 100}
	b.record = {"w": 5, "l": 2, "t": 0, "pf": 170, "pa": 100}
	var s := Season.sort_teams(lg, [a, b])
	eq(s[0].id, "HBG", "point differential breaks the tie")
	b.record["w"] = 4
	b.record["l"] = 3
	s = Season.sort_teams(lg, [a, b])
	eq(s[0].id, "IWF", "better record wins")

func test_apply_result_is_idempotent() -> void:
	var lg := _league()
	var g: Dictionary = lg.schedule[0][0]
	check(Season.apply_result(lg, g, 21, 14, false))
	check(not Season.apply_result(lg, g, 21, 14, false), "second application rejected")
	var h: Team = lg.teams[g["home"]]
	eq(h.record["w"], 1)
	eq(h.record["pf"], 21)

func test_full_season_playoffs_and_champion() -> void:
	var lg := _league(8, 10)
	var guard := 0
	while lg.phase != League.Phase.OFFSEASON and guard < 40:
		guard += 1
		var ug := Season.user_game(lg)
		if not ug.is_empty():
			Season.sim_user_game(lg, ug)
		Season.advance(lg)
	eq(lg.phase, League.Phase.OFFSEASON, "season reached the offseason")
	var total_w := 0
	var total_l := 0
	for t in lg.teams.values():
		total_w += int(t.record["w"])
		total_l += int(t.record["l"])
		eq(int(t.record["w"]) + int(t.record["l"]) + int(t.record["t"]), 10, "%s played every game" % t.id)
	eq(total_w, total_l, "wins equal losses league-wide")
	check(lg.playoffs.get("champion", "") != "", "a champion was crowned")
	eq(lg.playoffs["games"].size(), 7, "8-team bracket has 7 games")
	eq(lg.history["champions"].size(), 1)
	check(lg.history["awards"].size() == 1 and lg.history["awards"][0]["list"].size() >= 6, "awards handed out")
	# Seeds: division winners rank in the top two of each conference.
	for c in ["0", "1"]:
		eq(lg.playoffs["seeds"][c].size(), 4)
	_check_invariants(lg, "after season")

func test_offseason_to_next_season_and_draft() -> void:
	var lg := _league(9, 10)
	var guard := 0
	while lg.phase != League.Phase.OFFSEASON and guard < 40:
		guard += 1
		var ug := Season.user_game(lg)
		if not ug.is_empty():
			Season.sim_user_game(lg, ug)
		Season.advance(lg)
	var year := lg.year
	var qb_age: int = lg.players["p1"].age if lg.players.has("p1") else 0
	FranchiseOps.advance_offseason(lg) # review -> resign
	eq(lg.offseason_stage, "resign")
	var exp := Contracts.expiring_for(lg, lg.user_team())
	FranchiseOps.advance_offseason(lg) # resign -> draft
	eq(lg.offseason_stage, "draft")
	for pid in exp:
		check(lg.players[pid].team_id != lg.user_team_id, "unsigned expiring players left")
	eq(Draft.on_clock(lg), lg.user_team_id, "draft simulated up to the user's pick")
	var before := lg.user_team().roster.size()
	var pick := Draft.ai_choice(lg, lg.user_team_id)
	eq(Draft.make_pick(lg, lg.user_team_id, pick), "")
	eq(lg.user_team().roster.size(), before + 1)
	eq(lg.players[pick].team_id, lg.user_team_id)
	FranchiseOps.advance_offseason(lg) # draft -> FA (finishes draft)
	check(lg.draft_state["done"])
	eq(lg.draft_state["picks"].size(), Draft.ROUNDS * 16, "five full rounds")
	FranchiseOps.advance_offseason(lg) # FA -> camp (progression)
	eq(lg.offseason_stage, "camp")
	# Trim user roster to legal size before the season.
	var ut := lg.user_team()
	var guard2 := 0
	while ut.roster.size() > Team.ROSTER_MAX and guard2 < 20:
		guard2 += 1
		var worst := Contracts._worst_value(lg, ut)
		Contracts.release(lg, ut, worst, true)
	Contracts.ensure_legal(lg, ut)
	FranchiseOps.advance_offseason(lg) # camp -> new season
	eq(lg.year, year + 1)
	eq(lg.phase, League.Phase.REGULAR)
	eq(lg.week, 0)
	eq(lg.schedule.size(), 10)
	for t in lg.teams.values():
		eq(int(t.record["w"]), 0)
		check(t.roster.size() <= Team.ROSTER_MAX and t.roster.size() >= Team.ROSTER_MIN, "%s legal roster (%d)" % [t.id, t.roster.size()])
	_check_invariants(lg, "new season")

func test_cap_and_roster_limits() -> void:
	var lg := _league()
	var ut := lg.user_team()
	var fa: Player = lg.players[lg.free_agents[0]]
	var err := Contracts.sign_player(lg, ut, fa, 500.0, 2)
	check(err.contains("cap"), "cap blocks a huge contract: " + err)
	# Fill the roster to the max, then one more must fail.
	var guard := 0
	while ut.roster.size() < Team.ROSTER_MAX and guard < 20:
		guard += 1
		var p: Player = lg.players[lg.free_agents[0]]
		Contracts.sign_player(lg, ut, p, 0.6, 1, true)
	var extra: Player = lg.players[lg.free_agents[0]]
	check(Contracts.sign_player(lg, ut, extra, 0.6, 1) != "", "roster max enforced")
	# Cannot release below positional minimums.
	var ks: Array = lg.players_at(ut, "K")
	check(Contracts.release(lg, ut, ks[0]) != "", "cannot release the only kicker")

func test_contract_expiration() -> void:
	var lg := _league()
	var ut := lg.user_team()
	var p: Player = lg.players[ut.roster[0]]
	p.years = 1
	Contracts.tick_contracts(lg)
	check(Contracts.expiring_for(lg, ut).has(p.id), "1-year deal expires")
	var res := Contracts.negotiate(lg, ut, p, Contracts.asking(lg, ut, p)["salary"] * 1.1, 2)
	check(res["accepted"], "fair offer accepted: " + str(res["message"]))
	eq(p.years, 2)
	check(not Contracts.expiring_for(lg, ut).has(p.id))

func test_negotiation_lowball_rejected() -> void:
	var lg := _league()
	var fa: Player = lg.players[lg.free_agents[0]]
	var ut := lg.user_team()
	var res := Contracts.negotiate(lg, ut, fa, 0.1, 3)
	check(not res["accepted"])
	eq(fa.team_id, "", "still a free agent")

func test_progression_young_improve_old_decline() -> void:
	var lg := _league(30)
	var rng := RandomNumberGenerator.new()
	var young := PlayerGenerator.create(rng, "y", "WR", 60, 21)
	young.potential = 85
	var old := PlayerGenerator.create(rng, "o", "WR", 80, 34)
	old.potential = 80
	lg.players["y"] = young
	lg.players["o"] = old
	var y0 := young.overall()
	var o0 := old.overall()
	for i in 3:
		Progression.offseason(lg)
	check(young.overall() > y0 + 3, "young player develops (%d -> %d)" % [y0, young.overall()])
	check(old.overall() < o0, "veteran declines (%d -> %d)" % [o0, old.overall()])
	check(young.overall() <= young.potential, "never exceeds potential")

func test_trade_validation_and_execution() -> void:
	var lg := _league()
	var ut := lg.user_team()
	var cpu: Team = lg.teams["HBG"]
	var my_wr: Player = lg.players_at(ut, "WR")[0]
	var their_wr: Player = lg.players_at(cpu, "WR")[4]
	var ev := Trades.evaluate(lg, ut, cpu, [my_wr.id], [their_wr.id])
	check(ev.has("accepted"))
	var err := Trades.execute(lg, ut, cpu, [my_wr.id], [their_wr.id])
	eq(err, "")
	eq(my_wr.team_id, "HBG")
	eq(their_wr.team_id, "IWF")
	_check_invariants(lg, "after trade")
	var k: Player = lg.players_at(ut, "K")[0]
	check(Trades.validate(lg, ut, cpu, [k.id], [lg.players_at(cpu, "WR")[0].id]) != "", "cannot trade away the only kicker")

func test_scouting_report_brackets_estimate() -> void:
	var lg := _league()
	Draft.generate_class(lg)
	Draft.start(lg)
	var ut := lg.user_team()
	var p: Player = lg.players[lg.prospects[0]]
	var r := Draft.report(lg, p, ut)
	check(r["low"] <= r["high"])
	eq(Draft.scout(lg, ut, p), "")
	var r2 := Draft.report(lg, p, ut)
	check(absi(int(r2["est"]) - p.overall()) <= absi(int(r["est"]) - p.overall()) + 1, "scouting sharpens the estimate")

func test_save_load_roundtrip() -> void:
	var lg := _league(44, 10)
	for w in 3:
		var ug := Season.user_game(lg)
		if not ug.is_empty():
			Season.sim_user_game(lg, ug)
		Season.advance(lg)
	var d := lg.to_dict()
	var text := JSON.stringify(d)
	var back: Dictionary = JSON.parse_string(text)
	var lg2 := League.from_dict(back)
	check(lg2 != null, "reloaded")
	eq(lg2.year, lg.year)
	eq(lg2.week, lg.week)
	eq(lg2.players.size(), lg.players.size())
	eq(lg2.user_team().full_name(), lg.user_team().full_name())
	eq(lg2.user_team().record_string(), lg.user_team().record_string())
	var any_pid: String = lg.user_team().roster[0]
	eq(lg2.players[any_pid].overall(), lg.players[any_pid].overall())
	eq(lg2.players[any_pid].stat("gp"), lg.players[any_pid].stat("gp"))
	eq(lg2.schedule[0][0]["hs"], lg.schedule[0][0]["hs"])
	eq(lg2.repair(), 0, "no repairs needed on a clean save")
	_check_invariants(lg2, "reloaded")

func test_repair_fixes_duplicate_ownership() -> void:
	var lg := _league()
	var a: Team = lg.teams["IWF"]
	var b: Team = lg.teams["HBG"]
	b.roster.append(a.roster[0])
	lg.free_agents.append(a.roster[1])
	var fixes := lg.repair()
	check(fixes >= 2)
	_check_invariants(lg, "repaired")

func test_save_manager_atomic_and_backup() -> void:
	var lg := _league(51, 10)
	var sm: Node = Engine.get_main_loop().root.get_node("SaveManager")
	var real_dir: String = sm.dir
	sm.dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(sm.dir)
	var slot := 2
	sm.delete_slot(slot)
	check(sm.save_league(lg, slot), "first save")
	lg.week = 5
	check(sm.save_league(lg, slot), "second save")
	check(FileAccess.file_exists(sm.backup_path(slot)), "backup kept")
	# Corrupt the main file: loading falls back to the backup.
	var f := FileAccess.open(sm.slot_path(slot), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var back: League = sm.load_league(slot)
	check(back != null, "recovered from backup")
	check(sm.last_error.contains("backup"))
	sm.delete_slot(slot)
	check(not sm.has_save(slot))
	sm.dir = real_dir

func test_multi_season_stability() -> void:
	var lg := _league(77, 10)
	for season in 3:
		var guard := 0
		while lg.phase != League.Phase.OFFSEASON and guard < 40:
			guard += 1
			var ug := Season.user_game(lg)
			if not ug.is_empty():
				Season.sim_user_game(lg, ug)
			Season.advance(lg)
		var g2 := 0
		while lg.phase == League.Phase.OFFSEASON and g2 < 10:
			g2 += 1
			if lg.offseason_stage == "draft":
				Draft.sim_to_user(lg)
				while Draft.on_clock(lg) == lg.user_team_id:
					Draft.auto_pick_user(lg)
					Draft.sim_to_user(lg)
			if lg.offseason_stage == "camp":
				var ut := lg.user_team()
				var gg := 0
				while ut.roster.size() > Team.ROSTER_MAX and gg < 30:
					gg += 1
					Contracts.release(lg, ut, Contracts._worst_value(lg, ut), true)
				Contracts.ensure_legal(lg, ut)
			FranchiseOps.advance_offseason(lg)
		_check_invariants(lg, "season %d" % season)
		for t in lg.teams.values():
			for pos in Team.MIN_AT:
				check(lg.position_count(t, pos) >= int(Team.MIN_AT[pos]), "%s has %s" % [t.id, pos])
	eq(lg.history["champions"].size(), 3)
	eq(lg.history["user_seasons"].size(), 3)
	check(lg.players.size() < 1200, "player pool stays bounded (%d)" % lg.players.size())
	print("        players after 3 seasons: %d, hall: %d" % [lg.players.size(), lg.history["hall"].size()])
