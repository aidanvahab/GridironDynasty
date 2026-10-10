class_name FranchiseOps
extends RefCounted
## Weekly franchise upkeep, coaching staff, morale decision events, and the
## offseason stage machine.

const ROLE_EFFECTS := {
	"oc": "Improves offensive execution: receiver separation in live play and simulated offense (+1.2 rating per star).",
	"dc": "Improves defensive play in simulated opponent drives (+1.2 rating per star).",
	"dev": "Speeds up player development (+10% per star above 2.5).",
	"scout": "Narrows draft scouting error and adds scouting points.",
	"med": "Faster fatigue recovery and fewer injuries.",
}

# ================================================================= weekly

static func weekly(lg: League, report: Dictionary) -> void:
	for t in lg.teams.values():
		t.funds -= Finance.weekly_expenses(lg, t)
		if not t.is_user:
			Contracts.ensure_legal(lg, t)
	var ut := lg.user_team()
	# Short-handed? Warn the user (they decide who to sign).
	for pos in Team.STARTERS:
		var healthy := lg.depth_players(ut, pos).filter(func(p): return p.is_available()).size()
		if healthy < int(Team.STARTERS[pos]):
			lg.add_news("Depth alert: only %d healthy %s. Check free agency." % [healthy, pos], "alert")
	# Occasional CPU trade offer.
	if Trades.trade_window_open(lg) and lg.rng.randf() < 0.18 and lg.trade_offers.size() < 2:
		var offer := Trades.generate_offer(lg)
		if not offer.is_empty():
			lg.trade_offers.append(offer)
			report["events"].append("trade_offer")
			lg.add_news("%s have made a trade offer." % lg.teams[offer["team"]].full_name(), "trade")
	# Morale decision events every few weeks.
	if lg.pending_event.is_empty() and lg.week >= 1 and lg.rng.randf() < 0.3:
		var ev := generate_event(lg)
		if not ev.is_empty():
			lg.pending_event = ev
			report["events"].append("decision")

# ================================================================= staff

static func staff_candidates(lg: League, role: String) -> Array:
	var pool: Dictionary = lg.meta.get("staff_pool", {})
	var key := "%s_%d" % [role, lg.year]
	if not pool.has(key):
		var arr: Array = []
		for i in 3:
			var r := snappedf(clampf(lg.rng.randfn(2.8, 1.0), 1.0, 5.0), 0.5)
			arr.append(lg.make_staff(role, r))
		pool[key] = arr
		lg.meta["staff_pool"] = pool
	return pool[key]

static func hire_fee(c: Dictionary) -> float:
	return snappedf(float(c["salary"]) * 1.5, 0.05)

static func hire(lg: League, t: Team, role: String, idx: int) -> String:
	var cands := staff_candidates(lg, role)
	if idx < 0 or idx >= cands.size():
		return "Candidate unavailable."
	var c: Dictionary = cands[idx]
	var fee := hire_fee(c)
	if t.funds < fee:
		return "Not enough funds (%s signing fee)." % Fmt.money(fee)
	t.funds -= fee
	var old: Dictionary = t.staff.get(role, {})
	t.staff[role] = c.duplicate()
	cands.remove_at(idx)
	if not old.is_empty():
		cands.append(old)
	# Coaching changes ripple through the locker room.
	var delta := (float(c["rating"]) - float(old.get("rating", 2.0))) * 1.5
	for pid in t.roster:
		lg.players[pid].morale = clampf(lg.players[pid].morale + delta - 1.0, 5.0, 100.0)
	lg.add_news("Hired %s as %s." % [c["name"], League.STAFF_TITLES[role]], "staff")
	return ""

# ================================================================= events

static func generate_event(lg: League) -> Dictionary:
	var ut := lg.user_team()
	var roster := lg.roster_players(ut)
	var kinds: Array = ["media", "training", "community"]
	var star: Player = null
	for p in roster:
		if p.overall() >= 76 and p.salary < p.market_value() * 0.7 and p.years <= 2:
			star = p
	if star != null:
		kinds.append("contract")
	var benched: Player = null
	for p in roster:
		var group := lg.depth_players(ut, p.pos)
		var idx := group.find(p)
		if idx >= int(Team.STARTERS.get(p.pos, 1)) and p.overall() >= 70 and p.morale < 60.0:
			benched = p
	if benched != null:
		kinds.append("playing_time")
	var vet: Player = null
	for p in roster:
		if p.age >= 30 and p.personality == "Leader":
			vet = p
	if vet != null:
		kinds.append("mentor")
	var kind: String = kinds[lg.rng.randi_range(0, kinds.size() - 1)]
	match kind:
		"contract":
			var ask := Contracts.asking(lg, ut, star)
			return {"kind": kind, "player": star.id, "title": "%s Wants a New Deal" % star.full_name(),
				"text": "%s (%s, %d OVR) feels underpaid at %s and wants an extension." % [star.full_name(), star.pos, star.overall(), Fmt.money(star.salary)],
				"options": [
					{"label": "Extend at %s × %d yrs" % [Fmt.money(ask["salary"]), ask["years"]], "effect": "Morale +15, salary rises to his ask"},
					{"label": "Promise to revisit", "effect": "Morale -5"},
					{"label": "Refuse", "effect": "Morale -15, team chemistry -3"}]}
		"playing_time":
			return {"kind": kind, "player": benched.id, "title": "%s Wants More Snaps" % benched.full_name(),
				"text": "%s (%s, %d OVR) is frustrated sitting behind the starter." % [benched.full_name(), benched.pos, benched.overall()],
				"options": [
					{"label": "Promote him to starter", "effect": "He moves to the top of the depth chart, morale +12"},
					{"label": "Explain his role", "effect": "Morale -8"},
					{"label": "Put him on the trade block", "effect": "Morale -4, CPU teams may call"}]}
		"mentor":
			return {"kind": kind, "player": vet.id, "title": "Veteran Leadership",
				"text": "%s offers to mentor the young players after practice." % vet.full_name(),
				"options": [
					{"label": "Make it official", "effect": "Players 24 and under gain +1 development step; veteran morale +5; funds -$0.5M"},
					{"label": "Keep focus on game prep", "effect": "No effect"}]}
		"media":
			return {"kind": kind, "player": "", "title": "Media Day",
				"text": "Reporters ask about this week's matchup. How do you set the tone?",
				"options": [
					{"label": "Talk up the team", "effect": "Fans +3, morale +4 now; morale -6 if you lose this week"},
					{"label": "Stay humble", "effect": "Team chemistry +2"}]}
		"training":
			return {"kind": kind, "player": "", "title": "Training Intensity",
				"text": "The strength staff asks how hard to push practice this week.",
				"options": [
					{"label": "Push hard", "effect": "Young players gain development, all players +12 fatigue"},
					{"label": "Recovery week", "effect": "All fatigue cleared, morale +3"}]}
		_:
			return {"kind": "community", "player": "", "title": "Community Event",
				"text": "The city asks the franchise to host a youth football clinic.",
				"options": [
					{"label": "Host it ($1.0M)", "effect": "Fans +5, prestige +1, funds -$1.0M"},
					{"label": "Decline", "effect": "Fans -1"}]}

static func resolve_event(lg: League, choice: int) -> String:
	var ev := lg.pending_event
	if ev.is_empty():
		return ""
	var ut := lg.user_team()
	var p: Player = lg.players.get(ev.get("player", ""))
	var msg := ""
	match ev["kind"]:
		"contract":
			if choice == 0:
				var ask := Contracts.asking(lg, ut, p)
				if Contracts.cap_on(lg) and lg.payroll(ut) - p.salary + float(ask["salary"]) > League.SALARY_CAP:
					p.morale = maxf(5.0, p.morale - 5.0)
					msg = "Not enough cap space to extend him — he is disappointed (morale -5)."
				else:
					p.salary = ask["salary"]
					p.years = ask["years"]
					p.morale = minf(100.0, p.morale + 15.0)
					msg = "%s signs his extension." % p.full_name()
			elif choice == 1:
				p.morale = maxf(5.0, p.morale - 5.0)
				msg = "%s accepts, for now." % p.first_name
			else:
				p.morale = maxf(5.0, p.morale - 15.0)
				ut.chemistry = maxf(20.0, ut.chemistry - 3.0)
				msg = "%s is unhappy with the decision." % p.full_name()
		"playing_time":
			if choice == 0:
				var depth: Array = ut.depth.get(p.pos, [])
				depth.erase(p.id)
				depth.push_front(p.id)
				ut.depth[p.pos] = depth
				p.morale = minf(100.0, p.morale + 12.0)
				msg = "%s is now your starting %s." % [p.full_name(), p.pos]
			elif choice == 1:
				p.morale = maxf(5.0, p.morale - 8.0)
				msg = "%s grudgingly accepts his role." % p.first_name
			else:
				p.morale = maxf(5.0, p.morale - 4.0)
				var block: Array = lg.meta.get("trade_block", [])
				if not block.has(p.id):
					block.append(p.id)
				lg.meta["trade_block"] = block
				msg = "%s has been placed on the trade block." % p.full_name()
		"mentor":
			if choice == 0:
				ut.funds -= 0.5
				p.morale = minf(100.0, p.morale + 5.0)
				for q in lg.roster_players(ut):
					if q.age <= 24 and q.overall() < q.potential:
						Progression.shift_overall(q, 1, lg.rng)
				msg = "The young core soaks up %s's wisdom." % p.last_name
			else:
				msg = "Focus stays on game prep."
		"media":
			if choice == 0:
				ut.fans = minf(100.0, ut.fans + 3.0)
				for q in lg.roster_players(ut):
					q.morale = minf(100.0, q.morale + 4.0)
				lg.meta["hype_week"] = lg.week
				msg = "The fans love the confidence. Now back it up."
			else:
				ut.chemistry = minf(100.0, ut.chemistry + 2.0)
				msg = "The locker room appreciates the steady approach."
		"training":
			if choice == 0:
				for q in lg.roster_players(ut):
					q.fatigue = minf(60.0, q.fatigue + 12.0)
					if q.age <= 25 and q.overall() < q.potential and lg.rng.randf() < 0.5:
						Progression.shift_overall(q, 1, lg.rng)
				msg = "A grueling week of practice. The young guys got better."
			else:
				for q in lg.roster_players(ut):
					q.fatigue = 0.0
					q.morale = minf(100.0, q.morale + 3.0)
				msg = "Fresh legs for Sunday."
		"community":
			if choice == 0:
				ut.funds -= 1.0
				ut.fans = minf(100.0, ut.fans + 5.0)
				ut.prestige = minf(100.0, ut.prestige + 1.0)
				msg = "The clinic was a hit with local families."
			else:
				ut.fans = maxf(0.0, ut.fans - 1.0)
				msg = "The franchise passes on the event."
	lg.pending_event = {}
	lg.add_news(msg, "event")
	return msg

## Applies "hype" consequences once the user's game result is known.
static func after_user_game(lg: League, won: bool) -> void:
	if int(lg.meta.get("hype_week", -1)) == lg.week and not won:
		for q in lg.roster_players(lg.user_team()):
			q.morale = maxf(5.0, q.morale - 6.0)
		lg.add_news("After all that talk, the loss stings the locker room.", "event")
	lg.meta.erase("hype_week")

# ================================================================= offseason

## Advances the offseason stage machine. Returns a summary for the UI.
static func advance_offseason(lg: League) -> Dictionary:
	var out := {}
	match lg.offseason_stage:
		"review":
			# Season review -> contracts expire, re-sign period opens.
			out["retired"] = Progression.retirements(lg)
			Contracts.tick_contracts(lg)
			Contracts.ai_resign(lg)
			lg.offseason_stage = "resign"
		"resign":
			out["departed"] = Contracts.release_unsigned(lg, lg.user_team())
			Draft.start(lg)
			Draft.sim_to_user(lg)
			lg.offseason_stage = "draft"
		"draft":
			if not lg.draft_state.get("done", false):
				# Finish the draft automatically if the user moves on.
				var guard := 0
				while not lg.draft_state.get("done", false) and guard < 200:
					guard += 1
					var tid := Draft.on_clock(lg)
					Draft.make_pick(lg, tid, Draft.ai_choice(lg, tid))
			Contracts.ai_free_agency(lg, 4)
			lg.offseason_stage = "free_agency"
		"free_agency":
			Contracts.ai_free_agency(lg, 3)
			out["progress"] = Progression.offseason(lg)
			lg.offseason_stage = "camp"
		"camp":
			for t in lg.teams.values():
				if not t.is_user:
					Contracts.ensure_legal(lg, t)
			Season.start_new_season(lg)
			out["new_season"] = true
	return out

## Checks the user roster is legal before the season starts.
static func user_roster_issues(lg: League) -> Array:
	var t := lg.user_team()
	var issues: Array = []
	if t.roster.size() > Team.ROSTER_MAX:
		issues.append("Roster has %d players (max %d)." % [t.roster.size(), Team.ROSTER_MAX])
	if t.roster.size() < Team.ROSTER_MIN:
		issues.append("Roster has %d players (min %d)." % [t.roster.size(), Team.ROSTER_MIN])
	for pos in Team.MIN_AT:
		if lg.position_count(t, pos) < int(Team.MIN_AT[pos]):
			issues.append("Need at least %d %s." % [Team.MIN_AT[pos], pos])
	if Contracts.cap_on(lg) and lg.payroll(t) > League.SALARY_CAP:
		issues.append("Payroll %s exceeds the cap of %s." % [Fmt.money(lg.payroll(t)), Fmt.money(League.SALARY_CAP)])
	return issues
