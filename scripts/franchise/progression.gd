class_name Progression
extends RefCounted
## Player development: weekly training, post-game fatigue/injuries/morale,
## offseason growth and aging, and retirement.

## Development multiplier from coaching and facilities.
static func dev_multiplier(lg: League, t: Team) -> float:
	var coach := (lg.staff_rating(t, "dev") - 2.5) * 0.1 ## -0.15 .. +0.25
	var fac := (float(t.facilities.get("training", 1)) - 1.0) * 0.08
	return clampf(1.0 + coach + fac, 0.6, 1.6)

static func age_factor(age: int) -> float:
	if age <= 23:
		return 1.0
	if age <= 26:
		return 0.7
	if age <= 29:
		return 0.3
	return 0.0

## Raises (or lowers) a player's overall by roughly `delta` by adjusting the
## attributes that matter for his position, keeping his profile intact.
static func shift_overall(p: Player, delta: int, rng: RandomNumberGenerator) -> void:
	if delta == 0:
		return
	var w: Dictionary = Player.WEIGHTS[p.pos]
	var keys: Array = w.keys()
	var target := p.overall() + delta
	var guard := 0
	while p.overall() != target and guard < 60:
		guard += 1
		var k: String = keys[rng.randi_range(0, keys.size() - 1)]
		p.attrs[k] = clampi(int(p.attrs[k]) + signi(delta), 15, 99)
		if (delta > 0 and p.overall() >= 99) or (delta < 0 and p.overall() <= 25):
			break
	# Physical decline with age also touches speed/acceleration.
	if delta < 0 and p.age >= 30:
		for k in ["speed", "accel"]:
			p.attrs[k] = clampi(int(p.attrs[k]) - rng.randi_range(0, 2), 15, 99)

static func weekly(lg: League) -> void:
	var rng := lg.rng
	for t in lg.teams.values():
		var dm := dev_multiplier(lg, t)
		var med := float(t.facilities.get("medical", 1))
		var recover := 18.0 + med * 3.0 + (lg.staff_rating(t, "med") - 2.5) * 3.0
		for pid in t.roster:
			var p: Player = lg.players[pid]
			p.fatigue = maxf(0.0, p.fatigue - recover)
			if p.injury_weeks > 0:
				p.injury_weeks -= 1
				if p.injury_weeks == 0 and t.is_user:
					lg.add_news("%s has returned from injury." % p.full_name(), "injury")
			# Training: young players with headroom improve during the season.
			var gap := float(p.potential - p.overall())
			if gap > 0.0:
				var chance := clampf(gap * 0.012 * dm * age_factor(p.age) + (0.03 if p.games_started > 0 else 0.0), 0.0, 0.35)
				if rng.randf() < chance:
					shift_overall(p, 1, rng)
					p.xp += 1.0
		if not t.is_user:
			lg.auto_depth(t)
		else:
			lg.sanitize_depth(t)

## Fatigue, injuries and morale after a game.
static func post_game(lg: League, t: Team, won: bool) -> void:
	var rng := lg.rng
	var med := float(t.facilities.get("medical", 1))
	var inj_mult := (1.0 - (med - 1.0) * 0.1) * (1.0 - (lg.staff_rating(t, "med") - 2.5) * 0.06)
	var injuries_on := bool(lg.settings.get("injuries", true))
	var starters := {}
	for pos in Team.STARTERS:
		for p in lg.starters(t, pos, Team.STARTERS[pos]):
			starters[p.id] = true
	for pid in t.roster:
		var p: Player = lg.players[pid]
		if starters.has(pid):
			if bool(lg.settings.get("fatigue", true)):
				p.fatigue = minf(60.0, p.fatigue + 22.0 - p.a("stamina") * 0.08)
			if injuries_on and rng.randf() < 0.011 * inj_mult:
				var weeks := rng.randi_range(1, 6)
				if med >= 3.0:
					weeks = maxi(1, weeks - 1)
				if med >= 5.0:
					weeks = maxi(1, weeks - 1)
				p.injury_weeks = weeks
				lg.add_news("%s (%s, %s) injured — out %d week%s." % [p.full_name(), p.pos, t.abbr, weeks, "s" if weeks > 1 else ""], "injury")
			p.morale = clampf(p.morale + (2.5 if won else -1.5), 5.0, 100.0)
		else:
			# Talented backups grow restless without snaps.
			var penalty := 0.6 if p.overall() >= 72 else 0.0
			p.morale = clampf(p.morale + (1.0 if won else -0.5) - penalty, 5.0, 100.0)
	_update_chemistry(lg, t)

static func _update_chemistry(lg: League, t: Team) -> void:
	var total := 0.0
	var leaders := 0
	for pid in t.roster:
		var p: Player = lg.players[pid]
		total += p.morale
		if p.personality == "Leader" and p.overall() >= 70:
			leaders += 1
	var avg := total / maxf(1.0, float(t.roster.size()))
	t.chemistry = clampf(avg + minf(leaders, 4) * 2.0 - 5.0, 20.0, 100.0)

## Offseason development: growth for the young, decline for veterans.
## Returns a list of notable changes for the user's team.
static func offseason(lg: League) -> Array:
	var rng := lg.rng
	var notes: Array = []
	for p in lg.players.values():
		if p.retired:
			continue
		var t: Team = lg.teams.get(p.team_id)
		var dm := dev_multiplier(lg, t) if t != null else 1.0
		var before: int = p.overall()
		var delta := 0.0
		var gap := float(p.potential - before)
		if p.age <= 23:
			delta = gap * 0.32 * dm + rng.randfn(0.5, 1.6)
		elif p.age <= 26:
			delta = gap * 0.24 * dm + rng.randfn(0.2, 1.4)
		elif p.age <= 29:
			delta = gap * 0.12 * dm + rng.randfn(0.0, 1.2)
		elif p.age <= 31:
			delta = rng.randfn(-1.5, 1.4)
		elif p.age <= 33:
			delta = rng.randfn(-3.0, 1.6)
		else:
			delta = rng.randfn(-5.0, 2.0)
		if p.games_started >= 6 and p.age <= 27:
			delta += 1.0 ## experience from real snaps
		var d := int(round(delta))
		if before + d > p.potential and d > 0:
			d = maxi(0, p.potential - before)
		shift_overall(p, d, rng)
		p.age += 1
		p.experience += 1
		p.history.append({"year": lg.year, "team": p.team_id, "ovr": before, "age": p.age - 1, "stats": p.season_stats.duplicate()})
		if p.history.size() > 20:
			p.history.pop_front()
		if t != null and t.is_user and absi(p.overall() - before) >= 3:
			notes.append({"player": p.id, "from": before, "to": p.overall()})
		# Potential settles as careers mature.
		if p.age >= 28:
			p.potential = maxi(p.overall(), p.potential - rng.randi_range(0, 2))
		p.injury_weeks = 0
		p.morale = lerpf(p.morale, 70.0, 0.4)
	return notes

## Retires aging or fading players. Returns retired player ids.
static func retirements(lg: League) -> Array:
	var out: Array = []
	for p in lg.players.values():
		if p.retired:
			continue
		var chance := 0.0
		if p.age >= 37:
			chance = 0.85
		elif p.age >= 34:
			chance = 0.35 + (p.age - 34) * 0.15
		elif p.age >= 31:
			chance = 0.08 if p.overall() < 62 else 0.02
		if p.team_id == "" and p.age >= 29 and p.overall() < 58:
			chance = maxf(chance, 0.5)
		if p.pos == "K":
			chance *= 0.5
		if lg.rng.randf() < chance:
			out.append(p.id)
	for pid in out:
		Awards.retire_player(lg, pid)
	return out
