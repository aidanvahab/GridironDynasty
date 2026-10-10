class_name Trades
extends RefCounted
## Trade valuation and execution. Value accounts for quality, age/potential,
## contract surplus and the receiving team's positional need and strategy.

## Value of player p to team t.
static func value(lg: League, p: Player, t: Team) -> float:
	var ovr := float(p.overall())
	var v := pow(maxf(ovr - 40.0, 1.0), 1.7)
	# Youth with upside is worth more; age erodes value quickly after 30.
	if p.age <= 25:
		v += float(maxi(0, p.potential - p.overall())) * 6.0
	if p.age >= 30:
		v *= maxf(0.35, 1.0 - (p.age - 29) * 0.12)
	# Contract surplus: cheap production is valuable.
	var surplus := (p.market_value() - p.salary) * float(maxi(p.years, 1))
	v += surplus * 6.0
	if p.pos == "QB":
		v *= 1.35
	elif p.pos == "K":
		v *= 0.4
	# Positional need of the receiving team.
	var have: Array = lg.players_at(t, p.pos)
	var better := have.filter(func(x): return x.id != p.id and x.overall() >= p.overall()).size()
	var starters: int = Team.STARTERS.get(p.pos, 1)
	if better < starters:
		v *= 1.2
	elif better >= starters + 2:
		v *= 0.75
	# Rebuilding teams prefer youth; contenders prefer current quality.
	if t.win_pct() < 0.4 and p.age >= 29:
		v *= 0.8
	return maxf(v, 1.0)

static func trade_window_open(lg: League) -> bool:
	if lg.phase == League.Phase.REGULAR:
		return lg.week < int(ceil(Season.season_weeks(lg) * 0.67))
	if lg.phase == League.Phase.OFFSEASON:
		return lg.offseason_stage in ["resign", "free_agency", "camp"]
	return false

## Validates that rosters and cap stay legal after the swap.
static func validate(lg: League, a: Team, b: Team, a_gives: Array, b_gives: Array) -> String:
	if a_gives.is_empty() and b_gives.is_empty():
		return "Add players to the trade."
	if a_gives.is_empty() or b_gives.is_empty():
		return "Both teams must send at least one player."
	for pid in a_gives:
		if not lg.players.has(pid) or lg.players[pid].team_id != a.id:
			return "Invalid player in trade."
	for pid in b_gives:
		if not lg.players.has(pid) or lg.players[pid].team_id != b.id:
			return "Invalid player in trade."
	for side in [[a, a_gives, b_gives], [b, b_gives, a_gives]]:
		var t: Team = side[0]
		var out_ids: Array = side[1]
		var in_ids: Array = side[2]
		var size := t.roster.size() - out_ids.size() + in_ids.size()
		if size > Team.ROSTER_MAX:
			return "%s would exceed the roster limit." % t.abbr
		if size < Team.ROSTER_MIN:
			return "%s would fall below the roster minimum." % t.abbr
		for pos in Team.MIN_AT:
			var cnt := lg.position_count(t, pos)
			for pid in out_ids:
				if lg.players[pid].pos == pos:
					cnt -= 1
			for pid in in_ids:
				if lg.players[pid].pos == pos:
					cnt += 1
			if cnt < int(Team.MIN_AT[pos]):
				return "%s would have too few %s." % [t.abbr, pos]
		if Contracts.cap_on(lg):
			var pay := lg.payroll(t)
			for pid in out_ids:
				pay -= lg.players[pid].salary
			for pid in in_ids:
				pay += lg.players[pid].salary
			if pay > League.SALARY_CAP + 0.001:
				return "%s would be over the salary cap." % t.abbr
	return ""

## CPU decision on a proposal from team a (user) to CPU team b.
static func evaluate(lg: League, a: Team, b: Team, a_gives: Array, b_gives: Array) -> Dictionary:
	var err := validate(lg, a, b, a_gives, b_gives)
	if err != "":
		return {"accepted": false, "reason": err, "in": 0.0, "out": 0.0}
	var v_in := 0.0
	for pid in a_gives:
		v_in += value(lg, lg.players[pid], b)
	var v_out := 0.0
	for pid in b_gives:
		v_out += value(lg, lg.players[pid], b)
	# Consolidation premium: stars cost more than a pile of depth.
	var best_out := 0.0
	for pid in b_gives:
		best_out = maxf(best_out, value(lg, lg.players[pid], b))
	var best_in := 0.0
	for pid in a_gives:
		best_in = maxf(best_in, value(lg, lg.players[pid], b))
	if best_out > best_in * 1.4:
		v_in *= 0.85
	var diff_mult := 1.0 + float(lg.settings.get("difficulty", 1)) * 0.04
	var accepted := v_in >= v_out * diff_mult
	var reason := "Deal!" if accepted else ("Not enough value coming back." if v_in < v_out * 0.8 else "Close — sweeten the deal a little.")
	return {"accepted": accepted, "reason": reason, "in": v_in, "out": v_out}

static func execute(lg: League, a: Team, b: Team, a_gives: Array, b_gives: Array) -> String:
	var err := validate(lg, a, b, a_gives, b_gives)
	if err != "":
		return err
	for pid in a_gives:
		a.roster.erase(pid)
		b.roster.append(pid)
		lg.players[pid].team_id = b.id
		lg.players[pid].morale = maxf(5.0, lg.players[pid].morale - 4.0)
	for pid in b_gives:
		b.roster.erase(pid)
		a.roster.append(pid)
		lg.players[pid].team_id = a.id
	for t in [a, b]:
		for pid in t.roster:
			Contracts._assign_number(lg, t, lg.players[pid])
		if t.is_user:
			lg.sanitize_depth(t)
		else:
			lg.auto_depth(t)
	var names_a := ", ".join(a_gives.map(func(pid): return lg.players[pid].full_name()))
	var names_b := ", ".join(b_gives.map(func(pid): return lg.players[pid].full_name()))
	Contracts.log_tx(lg, "TRADE: %s send %s to %s for %s" % [a.abbr, names_a, b.abbr, names_b])
	lg.add_news("Trade: %s acquire %s from %s." % [a.abbr, names_b, b.abbr], "trade")
	return ""

## Occasionally a CPU team proposes a deal for one of the user's players.
static func generate_offer(lg: League) -> Dictionary:
	var ut := lg.user_team()
	var cands := lg.roster_players(ut).filter(func(p): return p.overall() >= 68 and lg.position_count(ut, p.pos) > int(Team.MIN_AT[p.pos]))
	if cands.is_empty():
		return {}
	var target: Player = cands[lg.rng.randi_range(0, cands.size() - 1)]
	var others: Array = lg.teams.values().filter(func(t): return not t.is_user)
	var cpu: Team = others[lg.rng.randi_range(0, others.size() - 1)]
	var want := value(lg, target, cpu)
	var pool := lg.roster_players(cpu).filter(func(p): return lg.position_count(cpu, p.pos) > int(Team.MIN_AT[p.pos]))
	pool.sort_custom(func(x, y): return absf(value(lg, x, ut) - want) < absf(value(lg, y, ut) - want))
	if pool.is_empty():
		return {}
	var give: Array = [pool[0].id]
	if value(lg, pool[0], ut) < want * 0.8 and pool.size() > 1:
		give.append(pool[1].id)
	if validate(lg, ut, cpu, [target.id], give) != "":
		return {}
	return {"team": cpu.id, "want": [target.id], "give": give, "week": lg.week, "year": lg.year}
