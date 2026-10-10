class_name Season
extends RefCounted
## Schedule, standings, results, week advancement and playoffs.
## All functions are static and operate on a League.

const PLAYOFF_ROUNDS := ["Conference Semifinals", "Conference Championships"]

# ================================================================= schedule

## Round-robin (circle method): every round is a perfect matching, so no team
## plays twice in a week and no matchup repeats within the season.
static func generate_schedule(lg: League) -> void:
	var ids: Array = lg.team_order.duplicate()
	_shuffle(lg.rng, ids)
	var n := ids.size()
	var rounds: Array = []
	var fixed: String = ids[0]
	var rot: Array = ids.slice(1)
	for r in n - 1:
		var lineup: Array = [fixed] + rot
		var games: Array = []
		for i in n / 2:
			var a: String = lineup[i]
			var b: String = lineup[n - 1 - i]
			# Alternate home field by round and slot so home games balance out.
			if (r + i) % 2 == 0:
				games.append([a, b])
			else:
				games.append([b, a])
		rounds.append(games)
		rot.push_front(rot.pop_back())
	_shuffle(lg.rng, rounds)
	var weeks: int = clampi(int(lg.settings.get("season_games", 14)), 4, n - 1)
	rounds = rounds.slice(0, weeks)
	# Balance home games: flip a matchup whenever its home team has 2+ more
	# home games than the visitor.
	var homes := {}
	for rd in rounds:
		for pair in rd:
			homes[pair[0]] = homes.get(pair[0], 0) + 1
	for _pass in 30:
		var changed := false
		for rd in rounds:
			for pair in rd:
				if int(homes.get(pair[0], 0)) - int(homes.get(pair[1], 0)) >= 2:
					homes[pair[0]] -= 1
					homes[pair[1]] = homes.get(pair[1], 0) + 1
					var tmp: String = pair[0]
					pair[0] = pair[1]
					pair[1] = tmp
					changed = true
		if not changed:
			break
	lg.schedule = []
	for w in weeks:
		var wk: Array = []
		for gi in rounds[w].size():
			var pair: Array = rounds[w][gi]
			wk.append({
				"id": "%d-%d-%d" % [lg.year, w, gi], "week": w, "home": pair[0], "away": pair[1],
				"played": false, "hs": 0, "as": 0, "ot": false, "playoff": false,
			})
		lg.schedule.append(wk)

static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

static func season_weeks(lg: League) -> int:
	return lg.schedule.size()

static func week_games(lg: League, w: int) -> Array:
	if w < 0 or w >= lg.schedule.size():
		return []
	return lg.schedule[w]

static func team_games(lg: League, tid: String) -> Array:
	var out: Array = []
	for wk in lg.schedule:
		for g in wk:
			if g["home"] == tid or g["away"] == tid:
				out.append(g)
	for g in lg.playoffs.get("games", []):
		if g["home"] == tid or g["away"] == tid:
			out.append(g)
	return out

## The user's next unplayed game (regular season or playoffs), or {}.
static func user_game(lg: League) -> Dictionary:
	if lg.phase == League.Phase.REGULAR:
		for g in week_games(lg, lg.week):
			if (g["home"] == lg.user_team_id or g["away"] == lg.user_team_id) and not g["played"]:
				return g
	elif lg.phase == League.Phase.PLAYOFFS:
		for g in current_playoff_games(lg):
			if (g["home"] == lg.user_team_id or g["away"] == lg.user_team_id) and not g["played"]:
				return g
	return {}

static func find_game(lg: League, game_id: String) -> Dictionary:
	for wk in lg.schedule:
		for g in wk:
			if g["id"] == game_id:
				return g
	for g in lg.playoffs.get("games", []):
		if g["id"] == game_id:
			return g
	return {}

# ================================================================= standings

static func sort_teams(lg: League, arr: Array) -> Array:
	var out := arr.duplicate()
	out.sort_custom(func(a: Team, b: Team) -> bool: return _ahead(lg, a, b))
	return out

static func _ahead(lg: League, a: Team, b: Team) -> bool:
	var pa := a.win_pct()
	var pb := b.win_pct()
	if absf(pa - pb) > 0.0001:
		return pa > pb
	var h2h := head_to_head(lg, a.id, b.id)
	if h2h != 0:
		return h2h > 0
	var da := int(a.record.get("pf", 0)) - int(a.record.get("pa", 0))
	var db := int(b.record.get("pf", 0)) - int(b.record.get("pa", 0))
	if da != db:
		return da > db
	if int(a.record.get("pf", 0)) != int(b.record.get("pf", 0)):
		return int(a.record.get("pf", 0)) > int(b.record.get("pf", 0))
	return a.id < b.id

## +1 if a beat b more often this season, -1 if less, 0 if even / not played.
static func head_to_head(lg: League, a: String, b: String) -> int:
	var score := 0
	for wk in lg.schedule:
		for g in wk:
			if not g["played"]:
				continue
			if (g["home"] == a and g["away"] == b) or (g["home"] == b and g["away"] == a):
				var a_pts: int = int(g["hs"]) if g["home"] == a else int(g["as"])
				var b_pts: int = int(g["as"]) if g["home"] == a else int(g["hs"])
				score += signi(a_pts - b_pts)
	return signi(score)

static func standings(lg: League) -> Array:
	return sort_teams(lg, lg.teams.values())

static func conference_standings(lg: League, conf: int) -> Array:
	return sort_teams(lg, lg.teams.values().filter(func(t): return t.conf == conf))

static func division_standings(lg: League, conf: int, div: int) -> Array:
	return sort_teams(lg, lg.teams.values().filter(func(t): return t.conf == conf and t.div == div))

# ================================================================= results

## Records a final score for both teams. Returns false if already recorded
## (prevents duplicate advancement).
static func apply_result(lg: League, g: Dictionary, hs: int, as_: int, ot: bool) -> bool:
	if g.get("played", false):
		return false
	g["played"] = true
	g["hs"] = hs
	g["as"] = as_
	g["ot"] = ot
	if g.get("playoff", false):
		return true
	var h: Team = lg.teams[g["home"]]
	var a: Team = lg.teams[g["away"]]
	var same_div := h.conf == a.conf and h.div == a.div
	var same_conf := h.conf == a.conf
	for pair in [[h, hs, as_], [a, as_, hs]]:
		var t: Team = pair[0]
		var pf: int = pair[1]
		var pa: int = pair[2]
		var r := t.record
		r["pf"] = int(r.get("pf", 0)) + pf
		r["pa"] = int(r.get("pa", 0)) + pa
		var key := "w" if pf > pa else ("l" if pf < pa else "t")
		r[key] = int(r.get(key, 0)) + 1
		if same_div:
			r["d" + key] = int(r.get("d" + key, 0)) + 1
		if same_conf:
			r["c" + key] = int(r.get("c" + key, 0)) + 1
		var st := int(r.get("streak", 0))
		if key == "w":
			r["streak"] = st + 1 if st > 0 else 1
		elif key == "l":
			r["streak"] = st - 1 if st < 0 else -1
		else:
			r["streak"] = 0
	return true

## Merges a box score into player season/career stats.
static func apply_player_stats(lg: League, stats: StatsRecorder, g: Dictionary) -> void:
	for pid in stats.lines:
		var p: Player = lg.players.get(pid)
		if p == null:
			continue
		for key in stats.lines[pid]:
			p.add_stat(key, float(stats.lines[pid][key]))
		p.add_stat("gp", 1.0)
	for side_tid in [g["home"], g["away"]]:
		var t: Team = lg.teams[side_tid]
		for pos in Team.STARTERS:
			for p in lg.starters(t, pos, Team.STARTERS[pos]):
				p.games_started += 1
				if not stats.lines.has(p.id):
					p.add_stat("gp", 1.0)

## Full post-game processing for a finished GameState.
static func finalize_game(lg: League, g: Dictionary, state: GameState, stats: StatsRecorder) -> bool:
	if not apply_result(lg, g, state.score[0], state.score[1], state.quarter > 4):
		return false
	apply_player_stats(lg, stats, g)
	var pog := stats.top_impact(-1)
	g["pog"] = pog
	g["box"] = {"home": _team_line(state, 0), "away": _team_line(state, 1)}
	for tid in [g["home"], g["away"]]:
		Progression.post_game(lg, lg.teams[tid], tid == (g["home"] if state.winner == 0 else (g["away"] if state.winner == 1 else "")))
	Finance.game_revenue(lg, g)
	if g.get("playoff", false):
		g["winner"] = g["home"] if state.score[0] > state.score[1] else g["away"]
		if g.get("final", false):
			var champ_side := 0 if g["winner"] == g["home"] else 1
			var mvp := stats.top_impact(champ_side)
			g["mvp"] = mvp
	return true

static func _team_line(state: GameState, side: int) -> Dictionary:
	var ts: Dictionary = state.team_stats[side]
	return {"yds": int(ts["total_yards"]), "pass": int(ts["pass_yards"]), "rush": int(ts["rush_yards"]), "to": int(ts["turnovers"]), "fd": int(ts["first_downs"])}

## Simulates a CPU game with full-length quarters.
static func sim_game(lg: League, g: Dictionary) -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(g["id"]) + str(lg.seed))
	var rules := RulesEngine.new(900.0, 1.0, bool(g.get("playoff", false)), rng)
	var stats := StatsRecorder.new()
	var sim := DriveSimulator.new(rules, lg, lg.teams[g["home"]], lg.teams[g["away"]], rng, stats)
	var st := sim.simulate_game()
	finalize_game(lg, g, st, stats)
	return st

## Simulates the user's own game (when they choose not to play it live).
static func sim_user_game(lg: League, g: Dictionary) -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(g["id"]) + "u" + str(lg.seed))
	var rules := RulesEngine.new(900.0, 1.0, bool(g.get("playoff", false)), rng)
	var stats := StatsRecorder.new()
	var sim := DriveSimulator.new(rules, lg, lg.teams[g["home"]], lg.teams[g["away"]], rng, stats)
	var user_side := 0 if g["home"] == lg.user_team_id else 1
	var diffs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/difficulty.json"))
	var lvl: Dictionary = diffs["levels"][clampi(int(lg.settings.get("difficulty", 1)), 0, 3)]
	sim.apply_difficulty(user_side, float(lvl["sim_bonus"]), 1.0)
	var st := sim.simulate_game()
	finalize_game(lg, g, st, stats)
	return st

# ================================================================= advancement

## True once every game of the current week (or playoff round) is final.
static func week_complete(lg: League) -> bool:
	if lg.phase == League.Phase.REGULAR:
		for g in week_games(lg, lg.week):
			if not g["played"]:
				return false
		return true
	if lg.phase == League.Phase.PLAYOFFS:
		for g in current_playoff_games(lg):
			if not g["played"]:
				return false
		return true
	return true

## Simulates every remaining CPU game this week, then advances. The user's
## game must already be played (live or simulated). Returns a report.
static func advance(lg: League) -> Dictionary:
	var report := {"results": [], "events": []}
	if not user_game(lg).is_empty():
		report["blocked"] = "Play or simulate your game first."
		return report
	if lg.phase == League.Phase.REGULAR:
		for g in week_games(lg, lg.week):
			if not g["played"]:
				sim_game(lg, g)
			report["results"].append(g)
		Progression.weekly(lg)
		FranchiseOps.weekly(lg, report)
		lg.week += 1
		if lg.week >= season_weeks(lg):
			start_playoffs(lg)
			report["events"].append("playoffs")
	elif lg.phase == League.Phase.PLAYOFFS:
		for g in current_playoff_games(lg):
			if not g["played"]:
				sim_game(lg, g)
			report["results"].append(g)
		Progression.weekly(lg)
		advance_playoffs(lg, report)
	return report

# ================================================================= playoffs

## Seeds: two division winners (by record), then the two best remaining teams.
static func playoff_seeds(lg: League, conf: int) -> Array:
	var winners: Array = []
	for d in 2:
		var ds := division_standings(lg, conf, d)
		if not ds.is_empty():
			winners.append(ds[0])
	winners = sort_teams(lg, winners)
	var rest := conference_standings(lg, conf).filter(func(t): return not winners.has(t))
	var seeds: Array = winners + rest.slice(0, 2)
	return seeds.map(func(t): return t.id)

static func start_playoffs(lg: League) -> void:
	lg.phase = League.Phase.PLAYOFFS
	var seeds := {}
	var games: Array = []
	for conf in 2:
		var s := playoff_seeds(lg, conf)
		seeds[str(conf)] = s
		games.append(_playoff_game(lg, 0, conf, s[0], s[3]))
		games.append(_playoff_game(lg, 0, conf, s[1], s[2]))
	lg.playoffs = {"round": 0, "seeds": seeds, "games": games, "champion": "", "runner_up": ""}
	for c in seeds:
		for tid in seeds[c]:
			lg.teams[tid].record["playoff"] = true
	lg.add_news("The playoff field is set!", "playoffs")

static func _playoff_game(lg: League, rnd: int, conf: int, home: String, away: String, final: bool = false) -> Dictionary:
	return {"id": "%d-P%d-%d-%s" % [lg.year, rnd, conf, home], "round": rnd, "conf": conf, "home": home, "away": away,
		"played": false, "hs": 0, "as": 0, "ot": false, "playoff": true, "final": final, "week": 100 + rnd}

static func current_playoff_games(lg: League) -> Array:
	var r := int(lg.playoffs.get("round", 0))
	return lg.playoffs.get("games", []).filter(func(g): return int(g["round"]) == r)

static func round_name(lg: League, r: int) -> String:
	if r >= 2:
		return lg.championship_name
	return PLAYOFF_ROUNDS[r]

static func _seed_of(lg: League, tid: String) -> int:
	for c in lg.playoffs.get("seeds", {}):
		var arr: Array = lg.playoffs["seeds"][c]
		if arr.has(tid):
			return arr.find(tid)
	return 99

static func advance_playoffs(lg: League, report: Dictionary) -> void:
	if not week_complete(lg):
		return
	var r := int(lg.playoffs["round"])
	var winners: Array = current_playoff_games(lg).map(func(g): return g.get("winner", ""))
	if r == 0:
		for conf in 2:
			var ws: Array = current_playoff_games(lg).filter(func(g): return g["conf"] == conf).map(func(g): return g["winner"])
			ws.sort_custom(func(a, b): return _seed_of(lg, a) < _seed_of(lg, b))
			lg.playoffs["games"].append(_playoff_game(lg, 1, conf, ws[0], ws[1]))
		lg.playoffs["round"] = 1
	elif r == 1:
		var champs: Array = winners.duplicate()
		champs.sort_custom(func(a, b): return _ahead(lg, lg.teams[a], lg.teams[b]))
		lg.playoffs["games"].append(_playoff_game(lg, 2, -1, champs[0], champs[1], true))
		lg.playoffs["round"] = 2
	else:
		var final_g: Dictionary = current_playoff_games(lg)[0]
		lg.playoffs["champion"] = final_g["winner"]
		lg.playoffs["runner_up"] = final_g["away"] if final_g["winner"] == final_g["home"] else final_g["home"]
		lg.playoffs["final_mvp"] = final_g.get("mvp", "")
		report["events"].append("champion")
		end_season(lg)

static func team_playoff_result(lg: League, tid: String) -> String:
	if lg.playoffs.is_empty():
		return ""
	if lg.playoffs.get("champion", "") == tid:
		return "Champion"
	if lg.playoffs.get("runner_up", "") == tid:
		return "Runner-up"
	var best := -1
	for g in lg.playoffs.get("games", []):
		if g["home"] == tid or g["away"] == tid:
			best = maxi(best, int(g["round"]))
	if best < 0:
		return ""
	return "Lost " + round_name(lg, best)

# ================================================================= season end

static func end_season(lg: League) -> void:
	Awards.season_awards(lg)
	Awards.update_records(lg)
	Awards.archive_season(lg)
	lg.phase = League.Phase.OFFSEASON
	lg.offseason_stage = "review"
	Finance.season_payout(lg)
	var champ: Team = lg.teams.get(lg.playoffs.get("champion", ""))
	if champ != null:
		lg.add_news("%s win the %d %s!" % [champ.full_name(), lg.year, lg.championship_name], "champion")

## Starts the next season after the offseason completes.
static func start_new_season(lg: League) -> void:
	lg.year += 1
	lg.week = 0
	lg.phase = League.Phase.REGULAR
	lg.offseason_stage = "review"
	lg.playoffs = {}
	for t in lg.teams.values():
		t.reset_record()
		if t.is_user:
			lg.sanitize_depth(t)
		else:
			lg.auto_depth(t)
	for p in lg.players.values():
		p.season_stats = {}
		p.games_started = 0
		p.fatigue = 0.0
		p.xp = 0.0
	_prune_free_agents(lg)
	generate_schedule(lg)
	lg.add_news("The %d season kicks off!" % lg.year, "season")

## Keeps the free-agent pool to a sensible size; unsigned fringe players
## leave the league (and the save file).
static func _prune_free_agents(lg: League, keep: int = 90) -> void:
	var fas: Array = lg.free_agents.filter(func(pid): return lg.players.has(pid))
	fas.sort_custom(func(a, b): return lg.players[a].overall() > lg.players[b].overall())
	for pid in fas.slice(keep):
		Awards.retire_player(lg, pid)
	lg.free_agents = lg.free_agents.filter(func(pid): return lg.players.has(pid) and not lg.players[pid].retired)
