class_name Draft
extends RefCounted
## Rookie draft: class generation, order, scouting uncertainty, AI picks and
## rookie contracts. Draft order: non-playoff teams worst-to-best, then
## playoff teams by round of elimination, champion last.

const ROUNDS := 5
const CLASS_SIZE := 110
const POS_MIX := {"QB": 7, "RB": 9, "WR": 15, "TE": 7, "OL": 17, "DL": 15, "LB": 12, "CB": 13, "S": 10, "K": 5}

static func generate_class(lg: League) -> void:
	lg.prospects.clear()
	var slots: Array = []
	for pos in POS_MIX:
		for i in POS_MIX[pos]:
			slots.append(pos)
	Season._shuffle(lg.rng, slots)
	for i in slots.size():
		var quality := clampf(1.0 - float(i) / float(slots.size()) + lg.rng.randfn(0.0, 0.15), 0.0, 1.0)
		var p := PlayerGenerator.create_prospect(lg.rng, lg.new_id(), slots[i], quality)
		lg.players[p.id] = p
		lg.prospects.append(p.id)

static func order(lg: League) -> Array:
	var teams: Array = lg.teams.values()
	var non_playoff := teams.filter(func(t): return not t.record.get("playoff", false))
	non_playoff = Season.sort_teams(lg, non_playoff)
	non_playoff.reverse()
	var playoff := teams.filter(func(t): return t.record.get("playoff", false))
	playoff.sort_custom(func(a: Team, b: Team) -> bool:
		var ra := _elim_round(lg, a.id)
		var rb := _elim_round(lg, b.id)
		if ra != rb:
			return ra < rb
		return Season._ahead(lg, b, a))
	return (non_playoff + playoff).map(func(t): return t.id)

static func _elim_round(lg: League, tid: String) -> int:
	if lg.playoffs.get("champion", "") == tid:
		return 9
	var best := -1
	for g in lg.playoffs.get("games", []):
		if g["home"] == tid or g["away"] == tid:
			best = maxi(best, int(g["round"]))
	return best

static func start(lg: League) -> void:
	if lg.prospects.is_empty():
		generate_class(lg)
	var pts := {}
	for t in lg.teams.values():
		pts[t.id] = 8 + int(t.facilities.get("scouting", 1)) * 4 + int(round(lg.staff_rating(t, "scout")))
	lg.draft_state = {"round": 0, "pick": 0, "order": order(lg), "picks": [], "points": pts, "scouted": {}, "done": false}

static func on_clock(lg: League) -> String:
	var ds := lg.draft_state
	if ds.is_empty() or ds.get("done", false):
		return ""
	var ord: Array = ds["order"]
	return ord[int(ds["pick"]) % ord.size()]

static func overall_pick(lg: League) -> int:
	return int(lg.draft_state.get("round", 0)) * lg.draft_state.get("order", []).size() + int(lg.draft_state.get("pick", 0)) + 1

## Scouting report as the user's front office sees it.
static func report(lg: League, p: Player, t: Team) -> Dictionary:
	var fac := float(t.facilities.get("scouting", 1))
	var coach := lg.staff_rating(t, "scout")
	var err := float(p.scout_error) * clampf(1.25 - (fac - 1.0) * 0.15 - (coach - 1.0) * 0.1, 0.25, 1.3)
	var spread := int(round(clampf(7.0 - fac - coach * 0.6, 2.0, 7.0)))
	if lg.draft_state.get("scouted", {}).get(p.id, false):
		err *= 0.25
		spread = 1
	var est := int(round(p.overall() + err))
	var pot_est := p.potential + int(round(err * 0.8))
	var grade := "D"
	if pot_est >= 82:
		grade = "A"
	elif pot_est >= 74:
		grade = "B"
	elif pot_est >= 66:
		grade = "C"
	return {"low": clampi(est - spread, 30, 99), "high": clampi(est + spread, 30, 99), "est": est, "grade": grade, "pot_est": pot_est}

static func scout(lg: League, t: Team, p: Player) -> String:
	var pts: Dictionary = lg.draft_state.get("points", {})
	if int(pts.get(t.id, 0)) <= 0:
		return "No scouting points left this draft."
	var sc: Dictionary = lg.draft_state.get("scouted", {})
	if sc.get(p.id, false):
		return "Already scouted."
	pts[t.id] = int(pts[t.id]) - 1
	sc[p.id] = true
	lg.draft_state["scouted"] = sc
	return ""

static func rookie_salary(overall_pick: int) -> float:
	return snappedf(maxf(0.75, 4.2 - float(overall_pick - 1) * 0.06), 0.05)

static func make_pick(lg: League, tid: String, pid: String) -> String:
	if on_clock(lg) != tid:
		return "It's not your pick."
	if not lg.prospects.has(pid):
		return "That player is no longer available."
	var t: Team = lg.teams[tid]
	var p: Player = lg.players[pid]
	var opick := overall_pick(lg)
	lg.prospects.erase(pid)
	p.draft_info = {"year": lg.year, "round": int(lg.draft_state["round"]) + 1, "pick": opick, "team": tid}
	Contracts.sign_player(lg, t, p, rookie_salary(opick), 4 if opick <= 16 else 3, true)
	lg.draft_state["picks"].append({"pick": opick, "round": int(lg.draft_state["round"]) + 1, "team": tid, "player": pid, "name": p.full_name(), "pos": p.pos, "ovr": p.overall(), "pot": p.potential})
	if t.is_user:
		lg.add_news("You drafted %s (%s) with pick #%d." % [p.full_name(), p.pos, opick], "draft")
	_advance(lg)
	return ""

static func _advance(lg: League) -> void:
	var ds := lg.draft_state
	ds["pick"] = int(ds["pick"]) + 1
	if int(ds["pick"]) >= ds["order"].size():
		ds["pick"] = 0
		ds["round"] = int(ds["round"]) + 1
	if int(ds["round"]) >= ROUNDS or lg.prospects.is_empty():
		finish(lg)

static func ai_choice(lg: League, tid: String) -> String:
	var t: Team = lg.teams[tid]
	var best := ""
	var bv := -INF
	for pid in lg.prospects:
		var p: Player = lg.players[pid]
		var seen := float(p.overall() + p.scout_error) * 0.55 + float(p.potential + p.scout_error) * 0.45
		var have := lg.position_count(t, p.pos)
		var need := float(Team.MIN_AT.get(p.pos, 1) + 1 - have) * 3.0
		if p.pos == "K" and have >= 1:
			need -= 8.0
		var v := seen + need + lg.rng.randf_range(-2.0, 2.0)
		if v > bv:
			bv = v
			best = pid
	return best

## Runs CPU picks until the user is on the clock or the draft ends.
static func sim_to_user(lg: League) -> void:
	var guard := 0
	while not lg.draft_state.get("done", true) and guard < 200:
		guard += 1
		var tid := on_clock(lg)
		if lg.teams[tid].is_user:
			return
		make_pick(lg, tid, ai_choice(lg, tid))

static func auto_pick_user(lg: League) -> void:
	var tid := on_clock(lg)
	if tid == lg.user_team_id:
		make_pick(lg, tid, ai_choice(lg, tid))

static func finish(lg: League) -> void:
	var ds := lg.draft_state
	if ds.get("done", false):
		return
	ds["done"] = true
	lg.history["drafts"].append({"year": lg.year, "picks": ds.get("picks", []).duplicate(true)})
	# Undrafted rookies become free agents.
	for pid in lg.prospects:
		var p: Player = lg.players[pid]
		p.team_id = ""
		if not lg.free_agents.has(pid):
			lg.free_agents.append(pid)
	lg.prospects.clear()
