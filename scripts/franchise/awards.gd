class_name Awards
extends RefCounted
## Season awards, league records and franchise history.

const RECORD_STATS := {
	"pass_yds": "Passing Yards", "pass_td": "Passing TDs", "rush_yds": "Rushing Yards",
	"rush_td": "Rushing TDs", "rec_yds": "Receiving Yards", "rec_td": "Receiving TDs",
	"sacks": "Sacks", "def_int": "Interceptions", "tackles": "Tackles", "fg_made": "Field Goals",
}

static func impact(p: Player) -> float:
	var s := p.season_stats
	var v := float(s.get("pass_yds", 0)) * 0.04 + float(s.get("pass_td", 0)) * 4.0 - float(s.get("int_thrown", 0)) * 2.5
	v += float(s.get("rush_yds", 0)) * 0.1 + float(s.get("rush_td", 0)) * 6.0
	v += float(s.get("rec_yds", 0)) * 0.1 + float(s.get("rec_td", 0)) * 6.0
	return v

static func def_impact(p: Player) -> float:
	var s := p.season_stats
	return float(s.get("tackles", 0)) * 1.0 + float(s.get("sacks", 0)) * 5.0 + float(s.get("def_int", 0)) * 6.0 + float(s.get("ff", 0)) * 4.0

static func _best(lg: League, score: Callable, filter: Callable = func(_p): return true) -> Player:
	var best: Player = null
	var bv := -INF
	for p in lg.players.values():
		if p.retired or p.team_id == "" or not filter.call(p):
			continue
		var v: float = score.call(p)
		if v > bv:
			bv = v
			best = p
	return best

static func season_awards(lg: League) -> void:
	var list: Array = []
	var win_bonus := func(p: Player) -> float:
		var t: Team = lg.teams.get(p.team_id)
		return t.win_pct() * 40.0 if t != null else 0.0
	var mvp := _best(lg, func(p): return impact(p) + win_bonus.call(p))
	var dpoy := _best(lg, func(p): return def_impact(p), func(p): return p.pos in Player.DEFENSE)
	var roty := _best(lg, func(p): return impact(p) + def_impact(p), func(p): return p.experience == 0)
	var passing := _best(lg, func(p): return p.stat("pass_yds"))
	var rushing := _best(lg, func(p): return p.stat("rush_yds"))
	var receiving := _best(lg, func(p): return p.stat("rec_yds"))
	for pair in [["MVP", mvp], ["Defensive Player of the Year", dpoy], ["Rookie of the Year", roty], ["Passing Leader", passing], ["Rushing Leader", rushing], ["Receiving Leader", receiving]]:
		var p: Player = pair[1]
		if p == null:
			continue
		p.awards.append({"year": lg.year, "award": pair[0]})
		list.append({"award": pair[0], "player": p.id, "name": p.full_name(), "team": p.team_id, "pos": p.pos})
	var final_mvp: String = lg.playoffs.get("final_mvp", "")
	if final_mvp != "" and lg.players.has(final_mvp):
		var fp: Player = lg.players[final_mvp]
		fp.awards.append({"year": lg.year, "award": lg.championship_name + " MVP"})
		list.append({"award": lg.championship_name + " MVP", "player": fp.id, "name": fp.full_name(), "team": fp.team_id, "pos": fp.pos})
	lg.history["awards"].append({"year": lg.year, "list": list})
	for a in list:
		if lg.teams.has(a["team"]) and lg.teams[a["team"]].is_user:
			lg.add_news("%s wins %s!" % [a["name"], a["award"]], "award")

static func update_records(lg: League) -> void:
	var rec: Dictionary = lg.history["records"]
	if not rec.has("season"):
		rec["season"] = {}
	if not rec.has("career"):
		rec["career"] = {}
	if not rec.has("team"):
		rec["team"] = {}
	for key in RECORD_STATS:
		for p in lg.players.values():
			var v: float = p.stat(key)
			var cur: Dictionary = rec["season"].get(key, {"value": 0.0})
			if v > float(cur["value"]) and v > 0.0:
				var broke := float(cur["value"]) > 0.0
				rec["season"][key] = {"value": v, "player": p.id, "name": p.full_name(), "team": p.team_id, "year": lg.year}
				if broke and lg.teams.has(p.team_id) and lg.teams[p.team_id].is_user:
					lg.add_news("RECORD! %s set a new single-season %s mark (%d)." % [p.full_name(), RECORD_STATS[key], int(v)], "record")
			var cv: float = float(p.career_stats.get(key, 0.0))
			var ccur: Dictionary = rec["career"].get(key, {"value": 0.0})
			if cv > float(ccur["value"]) and cv > 0.0:
				rec["career"][key] = {"value": cv, "player": p.id, "name": p.full_name(), "team": p.team_id, "year": lg.year}
	for t in lg.teams.values():
		var w := int(t.record.get("w", 0))
		var best: Dictionary = rec["team"].get("wins", {"value": 0})
		if w > int(best["value"]):
			rec["team"]["wins"] = {"value": w, "team": t.id, "name": t.full_name(), "year": lg.year}
		var pf := int(t.record.get("pf", 0))
		var bpf: Dictionary = rec["team"].get("points", {"value": 0})
		if pf > int(bpf["value"]):
			rec["team"]["points"] = {"value": pf, "team": t.id, "name": t.full_name(), "year": lg.year}

static func archive_season(lg: League) -> void:
	var champ: String = lg.playoffs.get("champion", "")
	if champ != "":
		lg.history["champions"].append({"year": lg.year, "team": champ, "name": lg.teams[champ].full_name(), "runner_up": lg.playoffs.get("runner_up", ""), "mvp": lg.playoffs.get("final_mvp", "")})
	for t in lg.teams.values():
		var res := Season.team_playoff_result(lg, t.id)
		t.history.append({"year": lg.year, "w": int(t.record.get("w", 0)), "l": int(t.record.get("l", 0)), "t": int(t.record.get("t", 0)), "pf": int(t.record.get("pf", 0)), "pa": int(t.record.get("pa", 0)), "result": res})
		if res == "Champion":
			t.prestige = minf(100.0, t.prestige + 12.0)
			t.fans = minf(100.0, t.fans + 10.0)
		elif res != "":
			t.prestige = minf(100.0, t.prestige + 4.0)
			t.fans = minf(100.0, t.fans + 4.0)
		else:
			t.prestige = clampf(t.prestige + (t.win_pct() - 0.5) * 8.0, 10.0, 100.0)
			t.fans = clampf(t.fans + (t.win_pct() - 0.5) * 8.0, 10.0, 100.0)
	var ut := lg.user_team()
	var snapshot: Array = []
	var top := lg.roster_players(ut)
	top.sort_custom(func(a: Player, b: Player): return a.overall() > b.overall())
	for p in top.slice(0, 8):
		snapshot.append({"id": p.id, "name": p.full_name(), "pos": p.pos, "ovr": p.overall(), "age": p.age})
	lg.history["user_seasons"].append({
		"year": lg.year, "record": ut.record_string(), "w": int(ut.record.get("w", 0)), "l": int(ut.record.get("l", 0)),
		"pf": int(ut.record.get("pf", 0)), "pa": int(ut.record.get("pa", 0)),
		"result": Season.team_playoff_result(lg, ut.id), "roster": snapshot, "ovr": lg.team_overall(ut),
	})

## Marks a player retired; notable careers enter the Hall of Legends.
static func retire_player(lg: League, pid: String) -> void:
	var p: Player = lg.players.get(pid)
	if p == null:
		return
	var t: Team = lg.teams.get(p.team_id)
	if t != null:
		t.roster.erase(pid)
		lg.sanitize_depth(t)
	lg.free_agents.erase(pid)
	p.retired = true
	var cs := p.career_stats
	var score := float(cs.get("pass_yds", 0)) * 0.002 + float(cs.get("rush_yds", 0)) * 0.006 + float(cs.get("rec_yds", 0)) * 0.006 \
		+ float(cs.get("sacks", 0)) * 0.6 + float(cs.get("def_int", 0)) * 0.8 + p.awards.size() * 6.0
	var was_user := t != null and t.is_user
	if score >= 40.0 or (was_user and score >= 15.0):
		lg.history["hall"].append({"id": p.id, "name": p.full_name(), "pos": p.pos, "year": lg.year, "team": p.team_id, "score": score, "awards": p.awards.size(), "career": cs.duplicate()})
		if was_user:
			lg.add_news("%s retires — a franchise legend." % p.full_name(), "retire")
	elif was_user:
		lg.add_news("%s has retired." % p.full_name(), "retire")
	p.team_id = ""
	# Retired players without a legacy are dropped to keep saves compact.
	if score < 15.0:
		lg.players.erase(pid)
