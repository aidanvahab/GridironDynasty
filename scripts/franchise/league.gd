class_name League
extends RefCounted
## Root of all persistent career data. Serialized by SaveManager.

const SCHEMA_VERSION := 1
const START_YEAR := 2027
const SALARY_CAP := 170.0 ## $M
const ROSTER_TEMPLATE := {"QB": 3, "RB": 3, "WR": 5, "TE": 2, "OL": 7, "DL": 6, "LB": 4, "CB": 4, "S": 3, "K": 1}
const STAFF_ROLES := ["oc", "dc", "dev", "scout", "med"]
const STAFF_TITLES := {"oc": "Offensive Coordinator", "dc": "Defensive Coordinator", "dev": "Player Development", "scout": "Head Scout", "med": "Head of Medical"}

enum Phase { REGULAR, PLAYOFFS, OFFSEASON }
## Offseason stages, in order.
const OFFSEASON_STAGES := ["review", "resign", "draft", "free_agency", "camp"]

var year: int = START_YEAR
var week: int = 0
var phase: Phase = Phase.REGULAR
var offseason_stage: String = "review"
var teams: Dictionary = {} ## id -> Team
var team_order: Array = []
var players: Dictionary = {} ## id -> Player
var free_agents: Array = []
var prospects: Array = []
var schedule: Array = [] ## weeks -> Array of game dicts
var playoffs: Dictionary = {}
var history: Dictionary = {}
var settings: Dictionary = {}
var user_team_id: String = ""
var coach_name: String = "Coach"
var next_id: int = 1
var seed: int = 0
var news: Array = []
var pending_event: Dictionary = {}
var trade_offers: Array = []
var draft_state: Dictionary = {}
var meta: Dictionary = {}
var rng := RandomNumberGenerator.new()
var championship_name: String = "Crown Bowl"
var league_name: String = "United Gridiron League"
var conferences: Array = ["Atlantic", "Frontier"]
var divisions: Array = [["Coast", "Harbor"], ["Summit", "Plains"]]

# ------------------------------------------------------------- creation

static func default_settings() -> Dictionary:
	return {
		"difficulty": 1, ## 0 rookie, 1 pro, 2 all-pro, 3 legend
		"game_length": 1, ## index into Settings.GAME_LENGTHS
		"assist": 1, ## 0 none, 1 standard, 2 full
		"season_games": 14,
		"injuries": true,
		"salary_cap": true,
		"fatigue": true,
		"autosave": true,
	}

static func load_catalog() -> Dictionary:
	var f := FileAccess.open("res://data/teams.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

## config: {coach, team_id (catalog team replaced by the user), city, name, abbr,
##          primary, secondary, accent, logo, settings}
static func create_new(config: Dictionary, p_seed: int) -> League:
	var lg := League.new()
	lg.seed = p_seed
	lg.rng.seed = p_seed
	lg.coach_name = str(config.get("coach", "Coach"))
	lg.settings = default_settings()
	lg.settings.merge(config.get("settings", {}), true)
	var cat := load_catalog()
	lg.league_name = cat["league_name"]
	lg.championship_name = cat["championship"]
	lg.conferences = cat["conferences"]
	lg.divisions = cat["divisions"]
	var user_id: String = str(config.get("team_id", cat["teams"][0]["id"]))
	for td in cat["teams"]:
		var t := Team.from_dict({
			"id": td["id"], "city": td["city"], "name": td["name"], "abbr": td["abbr"],
			"primary": td["primary"], "secondary": td["secondary"], "accent": td["accent"],
			"logo": td["logo"], "stadium": td["stadium"], "conf": td["conf"], "div": td["div"],
			"offense": td["offense"], "defense": td["defense"],
		})
		if t.id == user_id:
			t.is_user = true
			for key in ["city", "name", "abbr"]:
				if config.has(key) and str(config[key]) != "":
					t.set(key, str(config[key]))
			if config.has("primary"):
				t.primary = Color(str(config["primary"]))
			if config.has("secondary"):
				t.secondary = Color(str(config["secondary"]))
			if config.has("accent"):
				t.accent = Color(str(config["accent"]))
			if config.has("logo"):
				t.logo = config["logo"]
			if config.has("stadium"):
				t.stadium = str(config["stadium"])
		lg.teams[t.id] = t
		lg.team_order.append(t.id)
	lg.user_team_id = user_id
	lg._populate_rosters()
	for t in lg.teams.values():
		lg.auto_depth(t)
		lg._init_staff(t)
		t.reset_record()
	lg.history = {"champions": [], "awards": [], "drafts": [], "records": {}, "user_seasons": [], "hall": [], "transactions": []}
	Season.generate_schedule(lg)
	return lg

func _team_quality() -> Dictionary:
	## Spread of team strength; the user's club starts as an overlooked franchise.
	var q := {}
	var ids := team_order.duplicate()
	var tiers := [77, 76, 75, 74, 73, 72, 72, 71, 70, 70, 69, 68, 68, 67, 66, 65]
	var shuffled := tiers.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var k := 0
	for id in ids:
		q[id] = shuffled[k % shuffled.size()]
		k += 1
	q[user_team_id] = 66
	return q

func _populate_rosters() -> void:
	var quality := _team_quality()
	for tid in team_order:
		var t: Team = teams[tid]
		var tq: int = quality[tid]
		var numbers: Array = []
		for pos in ROSTER_TEMPLATE:
			var count: int = ROSTER_TEMPLATE[pos]
			if t.is_user and pos == "QB":
				count -= 1 ## room for the young prospect added below
			var starters: int = Team.STARTERS.get(pos, 1)
			for i in count:
				var is_starter := i < starters
				var target := tq + int(round(rng.randfn(0.0, 4.5))) if is_starter else tq - 9 + int(round(rng.randfn(0.0, 4.0)))
				var age := rng.randi_range(24, 32) if is_starter else rng.randi_range(21, 29)
				var p := PlayerGenerator.create(rng, new_id(), pos, clampi(target, 45, 90), age)
				p.number = PlayerGenerator.pick_number(rng, pos, numbers)
				numbers.append(p.number)
				add_player(p, tid)
		_normalize_payroll(t)
	# The overlooked franchise gets one reason for hope: a raw young quarterback.
	var ut: Team = teams[user_team_id]
	var qb := PlayerGenerator.create(rng, new_id(), "QB", 64, 22)
	qb.potential = 90
	qb.salary = 1.2
	qb.years = 3
	var nums: Array = []
	for pid in ut.roster:
		nums.append(players[pid].number)
	qb.number = PlayerGenerator.pick_number(rng, "QB", nums)
	add_player(qb, user_team_id)
	# Free-agent pool.
	for pos in ROSTER_TEMPLATE:
		for i in (3 if pos != "K" else 2):
			var p := PlayerGenerator.create(rng, new_id(), pos, rng.randi_range(52, 66), rng.randi_range(23, 33))
			p.years = 0
			players[p.id] = p
			free_agents.append(p.id)

func _normalize_payroll(t: Team) -> void:
	var total := payroll(t)
	var target := SALARY_CAP * rng.randf_range(0.82, 0.93)
	if total > 0.0:
		var f := target / total
		for pid in t.roster:
			var p: Player = players[pid]
			p.salary = snappedf(maxf(0.6, p.salary * f), 0.05)

func _init_staff(t: Team) -> void:
	for role in STAFF_ROLES:
		var r := clampf(rng.randfn(2.4, 0.8), 1.0, 4.5)
		if t.is_user:
			r = 2.0
		t.staff[role] = make_staff(role, snappedf(r, 0.5))
	t.funds = 25.0 if t.is_user else 30.0
	t.fans = 40.0 if t.is_user else rng.randf_range(45.0, 75.0)
	t.prestige = 35.0 if t.is_user else rng.randf_range(40.0, 75.0)
	if not t.is_user:
		for k in t.facilities:
			t.facilities[k] = rng.randi_range(1, 3)

func make_staff(role: String, rating: float) -> Dictionary:
	var n := PlayerGenerator.names()
	var nm: String = "%s %s" % [n["first"][rng.randi_range(0, n["first"].size() - 1)], n["last"][rng.randi_range(0, n["last"].size() - 1)]]
	return {"role": role, "name": nm, "rating": rating, "salary": snappedf(0.5 + pow(rating, 1.7) * 0.45, 0.05), "years": rng.randi_range(1, 3)}

# ------------------------------------------------------------- ids / lookup

func new_id() -> String:
	var s := "p%d" % next_id
	next_id += 1
	return s

func add_player(p: Player, tid: String) -> void:
	players[p.id] = p
	p.team_id = tid
	if tid != "":
		var t: Team = teams[tid]
		if not t.roster.has(p.id):
			t.roster.append(p.id)

func user_team() -> Team:
	return teams[user_team_id]

func team(id: String) -> Team:
	return teams.get(id)

func player(id: String) -> Player:
	return players.get(id)

func roster_players(t: Team) -> Array:
	var out: Array = []
	for pid in t.roster:
		if players.has(pid):
			out.append(players[pid])
	return out

func players_at(t: Team, pos: String) -> Array:
	var out: Array = []
	for pid in t.roster:
		var p: Player = players.get(pid)
		if p != null and p.pos == pos:
			out.append(p)
	return out

func payroll(t: Team) -> float:
	var total := 0.0
	for pid in t.roster:
		var p: Player = players.get(pid)
		if p != null:
			total += p.salary
	return total

func cap_space(t: Team) -> float:
	return SALARY_CAP - payroll(t)

func position_count(t: Team, pos: String) -> int:
	return players_at(t, pos).size()

# ------------------------------------------------------------- depth chart

## Orders each position group by overall; injured players move to the end.
func auto_depth(t: Team) -> void:
	for pos in Player.POSITIONS:
		var group := players_at(t, pos)
		group.sort_custom(func(x: Player, y: Player) -> bool:
			if x.is_available() != y.is_available():
				return x.is_available()
			return x.overall() > y.overall())
		var ids: Array = []
		for p in group:
			ids.append(p.id)
		t.depth[pos] = ids

## Keeps manual ordering but removes departed players and appends new ones.
func sanitize_depth(t: Team) -> void:
	for pos in Player.POSITIONS:
		var current: Array = t.depth.get(pos, [])
		var valid: Array = []
		for pid in current:
			var p: Player = players.get(pid)
			if p != null and p.team_id == t.id and p.pos == pos and not valid.has(pid):
				valid.append(pid)
		for p in players_at(t, pos):
			if not valid.has(p.id):
				valid.append(p.id)
		t.depth[pos] = valid

## Healthy players at a position in depth order.
func depth_players(t: Team, pos: String) -> Array:
	var out: Array = []
	for pid in t.depth.get(pos, []):
		var p: Player = players.get(pid)
		if p != null and p.is_available() and p.team_id == t.id:
			out.append(p)
	# Fall back to injured players only if nobody healthy remains.
	if out.is_empty():
		for pid in t.depth.get(pos, []):
			var p: Player = players.get(pid)
			if p != null:
				out.append(p)
	return out

## Starter lookup with cross-position fallback so a lineup is always complete.
func starters(t: Team, pos: String, count: int) -> Array:
	var out := depth_players(t, pos).slice(0, count)
	if out.size() < count:
		var fallback := {"QB": "RB", "RB": "WR", "WR": "TE", "TE": "WR", "OL": "DL", "DL": "OL", "LB": "S", "CB": "S", "S": "CB", "K": "QB"}
		for p in depth_players(t, fallback[pos]):
			if out.size() >= count:
				break
			if not out.has(p):
				out.append(p)
	return out

# ------------------------------------------------------------- strength

func staff_rating(t: Team, role: String) -> float:
	return float(t.staff.get(role, {}).get("rating", 1.0))

## Aggregate ratings used by the drive simulator. Includes coaching effects.
func team_ratings(t: Team) -> Dictionary:
	var qb: Player = starters(t, "QB", 1)[0]
	var rb: Array = starters(t, "RB", 1)
	var wr: Array = starters(t, "WR", 3)
	var te: Array = starters(t, "TE", 1)
	var ol: Array = starters(t, "OL", 5)
	var dl: Array = starters(t, "DL", 4)
	var lb: Array = starters(t, "LB", 3)
	var cb: Array = starters(t, "CB", 3)
	var sf: Array = starters(t, "S", 2)
	var k: Array = starters(t, "K", 1)
	var oc := (staff_rating(t, "oc") - 2.5) * 1.2
	var dc := (staff_rating(t, "dc") - 2.5) * 1.2
	var qbv := (qb.effective("throw_acc") * 0.4 + qb.effective("decision") * 0.35 + qb.effective("throw_power") * 0.25)
	var recv := _avg(wr, func(p): return p.effective("route") * 0.4 + p.effective("catching") * 0.35 + p.effective("speed") * 0.25) * 0.8 + _avg(te, func(p): return p.effective("catching") * 0.6 + p.effective("route") * 0.4) * 0.2
	var olv := _avg(ol, func(p): return p.effective("blocking") * 0.6 + p.effective("strength") * 0.4)
	var rbv := _avg(rb, func(p): return float(p.overall()))
	var pr := _avg(dl, func(p): return p.effective("pass_rush") * 0.7 + p.effective("accel") * 0.3) * 0.75 + _avg(lb, func(p): return p.effective("pass_rush")) * 0.25
	var cov := _avg(cb, func(p): return p.effective("coverage") * 0.65 + p.effective("speed") * 0.35) * 0.6 + _avg(sf, func(p): return p.effective("coverage")) * 0.25 + _avg(lb, func(p): return p.effective("coverage")) * 0.15
	var rund := _avg(dl, func(p): return p.effective("strength") * 0.5 + p.effective("tackling") * 0.5) * 0.45 + _avg(lb, func(p): return p.effective("tackling")) * 0.4 + _avg(sf, func(p): return p.effective("tackling")) * 0.15
	var chem := (t.chemistry - 60.0) * 0.05
	return {
		"qb": qbv + oc + chem, "recv": recv + oc + chem, "ol": olv + chem, "rb": rbv + oc + chem,
		"pass_rush": pr + dc + chem, "coverage": cov + dc + chem, "run_def": rund + dc + chem,
		"k_power": k[0].effective("kick_power") if k.size() > 0 else 50.0,
		"k_acc": k[0].effective("kick_acc") if k.size() > 0 else 50.0,
		"qb_mobility": qb.effective("speed"),
		"offense": (qbv * 0.4 + recv * 0.25 + olv * 0.2 + rbv * 0.15) + oc + chem,
		"defense": (pr * 0.35 + cov * 0.4 + rund * 0.25) + dc + chem,
	}

static func _avg(arr: Array, f: Callable) -> float:
	if arr.is_empty():
		return 50.0
	var s := 0.0
	for p in arr:
		s += float(f.call(p))
	return s / float(arr.size())

var _baseline: Dictionary = {}
var _baseline_key: String = ""

## League-average team ratings; the simulator measures teams relative to these
## so the model stays calibrated as the league's talent level drifts.
func rating_baseline() -> Dictionary:
	var key := "%d-%d-%d" % [year, week, int(phase)]
	if key == _baseline_key and not _baseline.is_empty():
		return _baseline
	var sums := {}
	for t in teams.values():
		var r := team_ratings(t)
		for k in r:
			sums[k] = sums.get(k, 0.0) + float(r[k])
	for k in sums:
		sums[k] = sums[k] / float(teams.size())
	_baseline = sums
	_baseline_key = key
	return _baseline

func team_overall(t: Team) -> int:
	var r := team_ratings(t)
	return int(round((r["offense"] + r["defense"]) * 0.5))

func add_news(text: String, kind: String = "info") -> void:
	news.push_front({"year": year, "week": week, "text": text, "kind": kind})
	if news.size() > 60:
		news.resize(60)

# ------------------------------------------------------------- serialization

func to_dict() -> Dictionary:
	var tdict := {}
	for id in teams:
		tdict[id] = teams[id].to_dict()
	var pdict := {}
	for id in players:
		pdict[id] = players[id].to_dict()
	return {
		"year": year, "week": week, "phase": int(phase), "offseason_stage": offseason_stage,
		"teams": tdict, "team_order": team_order.duplicate(), "players": pdict,
		"free_agents": free_agents.duplicate(), "prospects": prospects.duplicate(),
		"schedule": schedule.duplicate(true), "playoffs": playoffs.duplicate(true),
		"history": history.duplicate(true), "settings": settings.duplicate(true),
		"user_team_id": user_team_id, "coach_name": coach_name, "next_id": next_id,
		"seed": seed, "rng_state": rng.state, "news": news.duplicate(true),
		"pending_event": pending_event.duplicate(true), "trade_offers": trade_offers.duplicate(true),
		"draft_state": draft_state.duplicate(true), "meta": meta.duplicate(true),
		"championship_name": championship_name, "league_name": league_name,
		"conferences": conferences.duplicate(), "divisions": divisions.duplicate(true),
	}

## Builds a League from saved data. Returns null if essential data is missing.
## Repairs inconsistent references (dangling ids, duplicated ownership).
static func from_dict(d: Dictionary) -> League:
	for key in ["teams", "players", "user_team_id", "year", "schedule"]:
		if not d.has(key):
			push_warning("Save is missing '%s'" % key)
			return null
	var lg := League.new()
	lg.year = int(d.get("year", START_YEAR))
	lg.week = int(d.get("week", 0))
	lg.phase = clampi(int(d.get("phase", 0)), 0, 2) as Phase
	lg.offseason_stage = str(d.get("offseason_stage", "review"))
	for id in d["players"]:
		var p := Player.from_dict(d["players"][id])
		if p.id != "":
			lg.players[p.id] = p
	for id in d["teams"]:
		var t := Team.from_dict(d["teams"][id])
		lg.teams[t.id] = t
	lg.team_order = d.get("team_order", lg.teams.keys())
	lg.free_agents = d.get("free_agents", [])
	lg.prospects = d.get("prospects", [])
	lg.schedule = d.get("schedule", [])
	lg.playoffs = d.get("playoffs", {})
	lg.history = d.get("history", {})
	for k in ["champions", "awards", "drafts", "user_seasons", "hall", "transactions"]:
		if not lg.history.has(k):
			lg.history[k] = []
	if not lg.history.has("records"):
		lg.history["records"] = {}
	lg.settings = default_settings()
	lg.settings.merge(d.get("settings", {}), true)
	lg.user_team_id = str(d["user_team_id"])
	lg.coach_name = str(d.get("coach_name", "Coach"))
	lg.next_id = int(d.get("next_id", 1))
	lg.seed = int(d.get("seed", 0))
	lg.rng.seed = lg.seed
	if d.has("rng_state"):
		lg.rng.state = int(d["rng_state"])
	lg.news = d.get("news", [])
	lg.pending_event = d.get("pending_event", {})
	lg.trade_offers = d.get("trade_offers", [])
	lg.draft_state = d.get("draft_state", {})
	lg.meta = d.get("meta", {})
	lg.championship_name = str(d.get("championship_name", "Crown Bowl"))
	lg.league_name = str(d.get("league_name", "United Gridiron League"))
	lg.conferences = d.get("conferences", ["Atlantic", "Frontier"])
	lg.divisions = d.get("divisions", [["Coast", "Harbor"], ["Summit", "Plains"]])
	if not lg.teams.has(lg.user_team_id):
		push_warning("Save references an unknown user team")
		return null
	lg.repair()
	return lg

## Enforces ownership invariants: every rostered player exists, belongs to
## exactly one team, and the free-agent/prospect lists contain no owned players.
func repair() -> int:
	var fixes := 0
	var owner := {}
	for tid in team_order:
		var t: Team = teams.get(tid)
		if t == null:
			continue
		var clean: Array = []
		for pid in t.roster:
			var p: Player = players.get(pid)
			if p == null or owner.has(pid) or p.retired:
				fixes += 1
				continue
			owner[pid] = tid
			if p.team_id != tid:
				p.team_id = tid
				fixes += 1
			clean.append(pid)
		t.roster = clean
		sanitize_depth(t)
	var fa: Array = []
	for pid in free_agents:
		var p: Player = players.get(pid)
		if p == null or owner.has(pid) or fa.has(pid) or p.retired:
			fixes += 1
			continue
		p.team_id = ""
		fa.append(pid)
	free_agents = fa
	var pr: Array = []
	for pid in prospects:
		if players.has(pid) and not owner.has(pid) and not pr.has(pid):
			pr.append(pid)
		else:
			fixes += 1
	prospects = pr
	# Players claimed by nobody become free agents.
	for pid in players:
		var p: Player = players[pid]
		if not p.retired and not owner.has(pid) and not free_agents.has(pid) and not prospects.has(pid):
			p.team_id = ""
			free_agents.append(pid)
			fixes += 1
	return fixes
