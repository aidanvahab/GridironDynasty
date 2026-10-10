class_name Contracts
extends RefCounted
## Salary cap, signings, releases, negotiations, expirations and CPU roster
## management. Every transaction validates roster and cap rules so the league
## can never reach an illegal state (duplicate ownership, negative rosters).

const PERSONALITY_MULT := {"Mercenary": 1.15, "Showboat": 1.08, "Competitor": 1.0, "Leader": 0.97, "Quiet Pro": 0.96, "Team Player": 0.92}
const MAX_ATTEMPTS := 3

static func cap_on(lg: League) -> bool:
	return bool(lg.settings.get("salary_cap", true))

static func can_add(lg: League, t: Team, p: Player, salary: float) -> String:
	if p.retired:
		return "%s has retired." % p.full_name()
	if p.team_id == t.id:
		return "%s is already on your roster." % p.full_name()
	if t.roster.size() >= Team.ROSTER_MAX:
		return "Roster is full (%d players). Release someone first." % Team.ROSTER_MAX
	if cap_on(lg) and lg.payroll(t) + salary > League.SALARY_CAP + 0.001:
		return "Not enough cap space (%s available)." % UI.money(lg.cap_space(t))
	return ""

static func can_remove(lg: League, t: Team, p: Player) -> String:
	if p.team_id != t.id:
		return "%s is not on this roster." % p.full_name()
	if lg.position_count(t, p.pos) <= int(Team.MIN_AT.get(p.pos, 1)):
		return "You need at least %d %s on the roster." % [Team.MIN_AT[p.pos], p.pos]
	if t.roster.size() <= Team.ROSTER_MIN:
		return "Roster cannot drop below %d players." % Team.ROSTER_MIN
	return ""

static func _assign_number(lg: League, t: Team, p: Player) -> void:
	var taken: Array = []
	for pid in t.roster:
		if pid != p.id:
			taken.append(lg.players[pid].number)
	if taken.has(p.number) or p.number <= 0:
		p.number = PlayerGenerator.pick_number(lg.rng, p.pos, taken)

static func sign_player(lg: League, t: Team, p: Player, salary: float, years: int, force: bool = false) -> String:
	var err := can_add(lg, t, p, salary)
	if err != "" and not force:
		return err
	if p.team_id != "" and lg.teams.has(p.team_id):
		var old: Team = lg.teams[p.team_id]
		old.roster.erase(p.id)
		lg.sanitize_depth(old)
	lg.free_agents.erase(p.id)
	lg.prospects.erase(p.id)
	p.salary = snappedf(maxf(0.6, salary), 0.05)
	p.years = clampi(years, 1, 5)
	p.team_id = t.id
	t.roster.append(p.id)
	_assign_number(lg, t, p)
	if t.is_user:
		lg.sanitize_depth(t)
	else:
		lg.auto_depth(t)
	log_tx(lg, "%s signed %s (%s) — %s × %d yr" % [t.abbr, p.full_name(), p.pos, UI.money(p.salary), p.years])
	return ""

static func release(lg: League, t: Team, p: Player, force: bool = false) -> String:
	var err := can_remove(lg, t, p)
	if err != "" and not force:
		return err
	t.roster.erase(p.id)
	p.team_id = ""
	p.years = 0
	if not lg.free_agents.has(p.id):
		lg.free_agents.append(p.id)
	if t.is_user:
		lg.sanitize_depth(t)
		# Cutting a respected veteran shakes the locker room a little.
		if p.overall() >= 70:
			for pid in t.roster:
				lg.players[pid].morale = maxf(5.0, lg.players[pid].morale - 1.5)
	else:
		lg.auto_depth(t)
	log_tx(lg, "%s released %s (%s)" % [t.abbr, p.full_name(), p.pos])
	return ""

static func log_tx(lg: League, text: String) -> void:
	var tx: Array = lg.history.get("transactions", [])
	tx.push_front({"year": lg.year, "week": lg.week, "text": text})
	if tx.size() > 200:
		tx.resize(200)
	lg.history["transactions"] = tx

## Contract demand for player `p` from team `t`: {salary, years}.
static func asking(lg: League, t: Team, p: Player) -> Dictionary:
	var base := p.market_value() * float(PERSONALITY_MULT.get(p.personality, 1.0))
	if p.morale < 45.0 and p.team_id == t.id:
		base *= 1.1 ## unhappy players want more to stay
	base *= 1.0 - (t.prestige - 50.0) * 0.002
	var years := 3
	if p.age <= 25:
		years = 4
	elif p.age >= 31:
		years = 1 if p.age >= 33 else 2
	return {"salary": snappedf(maxf(0.75, base), 0.05), "years": years}

## Player response to an offer: {accepted, message, ask}.
static func negotiate(lg: League, t: Team, p: Player, salary: float, years: int) -> Dictionary:
	var ask := asking(lg, t, p)
	var attempts: Dictionary = lg.meta.get("neg_attempts", {})
	var used := int(attempts.get(p.id, 0))
	if used >= MAX_ATTEMPTS:
		return {"accepted": false, "message": "%s has ended talks with you this period." % p.full_name(), "ask": ask, "closed": true}
	var ratio := salary / maxf(0.01, float(ask["salary"]))
	var leeway := 0.04 + t.prestige * 0.0008 + (p.morale - 50.0) * 0.001
	var year_fit := 1.0 - absf(years - int(ask["years"])) * 0.03
	if ratio * year_fit >= 1.0 - leeway:
		var err := ""
		if p.team_id != t.id:
			err = sign_player(lg, t, p, salary, years)
		else:
			# Extension / re-signing: check the raise fits under the cap.
			if cap_on(lg) and lg.payroll(t) - p.salary + salary > League.SALARY_CAP + 0.001:
				err = "Not enough cap space for this contract."
			else:
				p.salary = snappedf(salary, 0.05)
				p.years = clampi(years, 1, 5)
				p.morale = minf(100.0, p.morale + 6.0)
				log_tx(lg, "%s re-signed %s — %s × %d yr" % [t.abbr, p.full_name(), UI.money(p.salary), p.years])
		if err != "":
			return {"accepted": false, "message": err, "ask": ask}
		attempts.erase(p.id)
		lg.meta["neg_attempts"] = attempts
		return {"accepted": true, "message": "%s accepts: %s per year for %d year%s." % [p.full_name(), UI.money(salary), years, "s" if years > 1 else ""], "ask": ask}
	used += 2 if ratio < 0.8 else 1
	attempts[p.id] = used
	lg.meta["neg_attempts"] = attempts
	var msg := "%s wants about %s per year for %d years." % [p.full_name(), UI.money(ask["salary"]), ask["years"]]
	if ratio < 0.8:
		msg = "%s is insulted by the offer. " % p.first_name + msg
	return {"accepted": false, "message": msg, "ask": ask, "closed": used >= MAX_ATTEMPTS}

## Decrements contracts at season end. Returns players whose deals expired,
## grouped by team id. Expired players stay rostered until the re-sign stage
## finishes.
static func tick_contracts(lg: League) -> Dictionary:
	var out := {}
	for t in lg.teams.values():
		var exp: Array = []
		for pid in t.roster:
			var p: Player = lg.players[pid]
			p.years -= 1
			if p.years <= 0:
				p.years = 0
				exp.append(pid)
		out[t.id] = exp
	lg.meta["expiring"] = out
	lg.meta["neg_attempts"] = {}
	return out

static func expiring_for(lg: League, t: Team) -> Array:
	var all: Dictionary = lg.meta.get("expiring", {})
	var ids: Array = all.get(t.id, [])
	return ids.filter(func(pid): return lg.players.has(pid) and lg.players[pid].team_id == t.id and lg.players[pid].years == 0)

## CPU teams re-sign valuable players and let the rest walk.
static func ai_resign(lg: League) -> void:
	for t in lg.teams.values():
		if t.is_user:
			continue
		var exp := expiring_for(lg, t)
		exp.sort_custom(func(a, b): return lg.players[a].overall() > lg.players[b].overall())
		for pid in exp:
			var p: Player = lg.players[pid]
			var ask := asking(lg, t, p)
			var keep := p.overall() >= 66 and p.age <= 31 and lg.rng.randf() < 0.75
			var room := lg.payroll(t) - p.salary + float(ask["salary"]) <= League.SALARY_CAP * 0.97
			if keep and room:
				p.salary = ask["salary"]
				p.years = ask["years"]
			else:
				t.roster.erase(pid)
				p.team_id = ""
				lg.free_agents.append(pid)
		lg.auto_depth(t)

## Expired user players who were not re-signed become free agents.
static func release_unsigned(lg: League, t: Team) -> Array:
	var gone: Array = []
	for pid in expiring_for(lg, t):
		var p: Player = lg.players[pid]
		t.roster.erase(pid)
		p.team_id = ""
		if not lg.free_agents.has(pid):
			lg.free_agents.append(pid)
		gone.append(pid)
	lg.sanitize_depth(t)
	return gone

## CPU free agency: fill positional minimums, then add depth with value.
static func ai_free_agency(lg: League, rounds: int = 3) -> void:
	var order: Array = lg.team_order.duplicate()
	for r in rounds:
		Season._shuffle(lg.rng, order)
		for tid in order:
			var t: Team = lg.teams[tid]
			if t.is_user:
				continue
			var need := _most_needed(lg, t)
			if need == "" and t.roster.size() >= 38:
				continue
			var best: Player = null
			var best_v := -INF
			for pid in lg.free_agents:
				var p: Player = lg.players[pid]
				if need != "" and p.pos != need:
					continue
				var ask: float = asking(lg, t, p)["salary"]
				if cap_on(lg) and lg.payroll(t) + ask > League.SALARY_CAP:
					continue
				var v := float(p.overall()) - ask * 0.6 - maxf(0.0, p.age - 30) * 1.5
				if v > best_v:
					best_v = v
					best = p
			if best != null and t.roster.size() < Team.ROSTER_MAX:
				var a := asking(lg, t, best)
				sign_player(lg, t, best, a["salary"], a["years"], true)

static func _most_needed(lg: League, t: Team) -> String:
	var worst := ""
	var worst_gap := 0
	for pos in Team.MIN_AT:
		var gap := int(Team.MIN_AT[pos]) + (1 if pos in ["WR", "OL", "DL", "CB"] else 0) - lg.position_count(t, pos)
		if gap > worst_gap:
			worst_gap = gap
			worst = pos
	return worst

## Guarantees a legal roster for a CPU team: positional minimums met, no more
## than the maximum, payroll under the cap. Generates replacement-level
## players if the free-agent pool runs dry.
static func ensure_legal(lg: League, t: Team) -> void:
	for pos in Team.MIN_AT:
		var guard := 0
		while lg.position_count(t, pos) < int(Team.MIN_AT[pos]) and guard < 6:
			guard += 1
			var cand: Player = null
			for pid in lg.free_agents:
				var p: Player = lg.players[pid]
				if p.pos == pos and (cand == null or p.overall() > cand.overall()):
					cand = p
			if cand == null:
				cand = PlayerGenerator.create(lg.rng, lg.new_id(), pos, lg.rng.randi_range(50, 58), lg.rng.randi_range(22, 27))
				lg.players[cand.id] = cand
				lg.free_agents.append(cand.id)
			sign_player(lg, t, cand, 0.75, 1, true)
	while t.roster.size() < Team.ROSTER_MIN:
		var pos: String = ["WR", "OL", "DL", "LB", "CB", "S", "RB", "TE"][lg.rng.randi_range(0, 7)]
		var p2 := PlayerGenerator.create(lg.rng, lg.new_id(), pos, lg.rng.randi_range(50, 58), lg.rng.randi_range(22, 27))
		lg.players[p2.id] = p2
		sign_player(lg, t, p2, 0.75, 1, true)
	if not t.is_user:
		var guard2 := 0
		while (t.roster.size() > Team.ROSTER_MAX or (cap_on(lg) and lg.payroll(t) > League.SALARY_CAP)) and guard2 < 30:
			guard2 += 1
			var cut := _worst_value(lg, t)
			if cut == null:
				break
			release(lg, t, cut, true)
		lg.auto_depth(t)

static func _worst_value(lg: League, t: Team) -> Player:
	var worst: Player = null
	var wv := INF
	for pid in t.roster:
		var p: Player = lg.players[pid]
		if lg.position_count(t, p.pos) <= int(Team.MIN_AT.get(p.pos, 1)):
			continue
		var v := float(p.overall()) - p.salary * 0.8
		if v < wv:
			wv = v
			worst = p
	return worst
