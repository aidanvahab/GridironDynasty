class_name PlayerGenerator
extends RefCounted
## Procedural creation of fictional players with position archetypes, so
## players have distinct strengths and weaknesses.

const TEMPLATES := {
	"QB": {"speed": 58, "accel": 62, "agility": 60, "strength": 55, "awareness": 68, "stamina": 75, "throw_power": 72, "throw_acc": 70, "decision": 68, "carrying": 58, "balance": 50, "catching": 40, "route": 30, "blocking": 25, "tackling": 25, "coverage": 25, "pass_rush": 20, "kick_power": 30, "kick_acc": 30},
	"RB": {"speed": 80, "accel": 80, "agility": 76, "strength": 64, "awareness": 62, "stamina": 78, "throw_power": 35, "throw_acc": 30, "decision": 40, "carrying": 72, "balance": 72, "catching": 60, "route": 50, "blocking": 45, "tackling": 30, "coverage": 25, "pass_rush": 20, "kick_power": 25, "kick_acc": 25},
	"WR": {"speed": 84, "accel": 80, "agility": 78, "strength": 50, "awareness": 64, "stamina": 76, "throw_power": 35, "throw_acc": 30, "decision": 40, "carrying": 62, "balance": 55, "catching": 74, "route": 72, "blocking": 35, "tackling": 25, "coverage": 30, "pass_rush": 20, "kick_power": 25, "kick_acc": 25},
	"TE": {"speed": 70, "accel": 68, "agility": 62, "strength": 72, "awareness": 64, "stamina": 76, "throw_power": 30, "throw_acc": 25, "decision": 40, "carrying": 62, "balance": 66, "catching": 68, "route": 62, "blocking": 66, "tackling": 30, "coverage": 25, "pass_rush": 25, "kick_power": 25, "kick_acc": 25},
	"OL": {"speed": 48, "accel": 55, "agility": 48, "strength": 78, "awareness": 66, "stamina": 74, "throw_power": 25, "throw_acc": 20, "decision": 35, "carrying": 30, "balance": 60, "catching": 25, "route": 20, "blocking": 74, "tackling": 30, "coverage": 20, "pass_rush": 30, "kick_power": 20, "kick_acc": 20},
	"DL": {"speed": 62, "accel": 70, "agility": 58, "strength": 78, "awareness": 62, "stamina": 72, "throw_power": 25, "throw_acc": 20, "decision": 35, "carrying": 30, "balance": 60, "catching": 30, "route": 20, "blocking": 40, "tackling": 70, "coverage": 30, "pass_rush": 72, "kick_power": 20, "kick_acc": 20},
	"LB": {"speed": 72, "accel": 72, "agility": 66, "strength": 70, "awareness": 68, "stamina": 76, "throw_power": 25, "throw_acc": 20, "decision": 40, "carrying": 35, "balance": 60, "catching": 50, "route": 25, "blocking": 35, "tackling": 74, "coverage": 62, "pass_rush": 60, "kick_power": 20, "kick_acc": 20},
	"CB": {"speed": 84, "accel": 82, "agility": 80, "strength": 50, "awareness": 66, "stamina": 78, "throw_power": 25, "throw_acc": 20, "decision": 40, "carrying": 45, "balance": 50, "catching": 60, "route": 40, "blocking": 25, "tackling": 58, "coverage": 74, "pass_rush": 30, "kick_power": 20, "kick_acc": 20},
	"S": {"speed": 78, "accel": 76, "agility": 72, "strength": 60, "awareness": 70, "stamina": 78, "throw_power": 25, "throw_acc": 20, "decision": 40, "carrying": 45, "balance": 55, "catching": 58, "route": 35, "blocking": 30, "tackling": 70, "coverage": 70, "pass_rush": 40, "kick_power": 20, "kick_acc": 20},
	"K": {"speed": 50, "accel": 50, "agility": 50, "strength": 45, "awareness": 55, "stamina": 70, "throw_power": 30, "throw_acc": 30, "decision": 40, "carrying": 30, "balance": 40, "catching": 35, "route": 20, "blocking": 20, "tackling": 30, "coverage": 20, "pass_rush": 20, "kick_power": 74, "kick_acc": 72},
}

const ARCHETYPES := {
	"QB": [
		{"name": "Gunslinger", "mods": {"throw_power": 10, "throw_acc": -5, "decision": -4}},
		{"name": "Field General", "mods": {"decision": 9, "throw_acc": 6, "throw_power": -6, "speed": -6}},
		{"name": "Scrambler", "mods": {"speed": 16, "agility": 14, "accel": 12, "throw_acc": -6, "decision": -3}},
	],
	"RB": [
		{"name": "Speed Back", "mods": {"speed": 7, "accel": 6, "strength": -8, "balance": -6}},
		{"name": "Power Back", "mods": {"strength": 12, "balance": 10, "speed": -5, "agility": -6}},
		{"name": "Receiving Back", "mods": {"catching": 14, "route": 14, "strength": -6}},
	],
	"WR": [
		{"name": "Deep Threat", "mods": {"speed": 8, "accel": 4, "route": -6, "catching": -4}},
		{"name": "Possession", "mods": {"catching": 9, "route": 8, "speed": -7, "strength": 8}},
		{"name": "Slot", "mods": {"agility": 9, "route": 6, "accel": 6, "strength": -8}},
	],
	"TE": [
		{"name": "Blocking TE", "mods": {"blocking": 12, "strength": 8, "catching": -8, "route": -8}},
		{"name": "Receiving TE", "mods": {"catching": 9, "route": 9, "speed": 5, "blocking": -12}},
	],
	"OL": [
		{"name": "Mauler", "mods": {"strength": 9, "awareness": -5}},
		{"name": "Technician", "mods": {"blocking": 5, "awareness": 8, "strength": -6}},
	],
	"DL": [
		{"name": "Speed Rusher", "mods": {"accel": 10, "speed": 8, "pass_rush": 6, "strength": -10}},
		{"name": "Run Stuffer", "mods": {"strength": 10, "tackling": 6, "pass_rush": -8, "speed": -6}},
	],
	"LB": [
		{"name": "Coverage LB", "mods": {"coverage": 12, "speed": 6, "strength": -8, "pass_rush": -8}},
		{"name": "Thumper", "mods": {"tackling": 8, "strength": 8, "coverage": -10}},
		{"name": "Edge Blitzer", "mods": {"pass_rush": 14, "accel": 6, "coverage": -10}},
	],
	"CB": [
		{"name": "Ballhawk", "mods": {"catching": 12, "awareness": 6, "speed": -4}},
		{"name": "Shutdown", "mods": {"coverage": 6, "agility": 5, "catching": -6}},
		{"name": "Speedster", "mods": {"speed": 8, "accel": 6, "coverage": -6}},
	],
	"S": [
		{"name": "Free Safety", "mods": {"coverage": 8, "speed": 5, "tackling": -8}},
		{"name": "Strong Safety", "mods": {"tackling": 9, "strength": 8, "coverage": -8}},
	],
	"K": [
		{"name": "Big Leg", "mods": {"kick_power": 10, "kick_acc": -6}},
		{"name": "Precision", "mods": {"kick_acc": 9, "kick_power": -6}},
	],
}

const NUMBER_RANGES := {
	"QB": [[1, 19]], "RB": [[20, 49]], "WR": [[10, 19], [80, 89]], "TE": [[80, 89], [40, 49]],
	"OL": [[50, 79]], "DL": [[90, 99], [50, 79]], "LB": [[40, 59]], "CB": [[20, 39]],
	"S": [[20, 49]], "K": [[1, 19]],
}

const BUILD := {"QB": 1.0, "RB": 1.0, "WR": 0.93, "TE": 1.1, "OL": 1.26, "DL": 1.2, "LB": 1.08, "CB": 0.93, "S": 0.98, "K": 0.92}

static var _names: Dictionary = {}

static func names() -> Dictionary:
	if _names.is_empty():
		var f := FileAccess.open("res://data/names.json", FileAccess.READ)
		_names = JSON.parse_string(f.get_as_text())
	return _names

static func gauss(rng: RandomNumberGenerator, sd: float) -> float:
	return rng.randfn(0.0, sd)

## Creates a player at `pos` whose overall is close to `target_ovr`.
static func create(rng: RandomNumberGenerator, id: String, pos: String, target_ovr: int, age: int) -> Player:
	var p := Player.new()
	p.id = id
	var n := names()
	p.first_name = n["first"][rng.randi_range(0, n["first"].size() - 1)]
	p.last_name = n["last"][rng.randi_range(0, n["last"].size() - 1)]
	p.pos = pos
	p.age = age
	var tmpl: Dictionary = TEMPLATES[pos]
	var arch: Dictionary = ARCHETYPES[pos][rng.randi_range(0, ARCHETYPES[pos].size() - 1)]
	var mods: Dictionary = arch["mods"]
	for k in Player.ATTRS:
		var v := float(tmpl[k]) + float(mods.get(k, 0)) + gauss(rng, 5.0)
		p.attrs[k] = clampi(int(round(v)), 15, 99)
	_tune_to(p, target_ovr)
	p.personality = Player.PERSONALITIES[rng.randi_range(0, Player.PERSONALITIES.size() - 1)]
	p.skin = rng.randi_range(0, 5)
	p.build = BUILD[pos] * rng.randf_range(0.96, 1.05)
	var ovr := p.overall()
	var headroom := 0.0
	if age <= 23:
		headroom = absf(gauss(rng, 11.0)) + rng.randf_range(0.0, 6.0)
	elif age <= 26:
		headroom = absf(gauss(rng, 6.0))
	elif age <= 29:
		headroom = absf(gauss(rng, 2.5))
	p.potential = clampi(int(round(ovr + headroom)), ovr, 99)
	p.salary = snappedf(p.market_value() * rng.randf_range(0.85, 1.15), 0.05)
	p.years = rng.randi_range(1, 4)
	p.morale = rng.randf_range(60.0, 80.0)
	p.experience = maxi(0, age - 22)
	p.number = pick_number(rng, pos, [])
	return p

static func _tune_to(p: Player, target: int) -> void:
	var w: Dictionary = Player.WEIGHTS[p.pos]
	for _i in 6:
		var delta := target - p.overall()
		if delta == 0:
			break
		for k in w:
			p.attrs[k] = clampi(int(p.attrs[k]) + delta, 20, 99)

static func pick_number(rng: RandomNumberGenerator, pos: String, taken: Array) -> int:
	var ranges: Array = NUMBER_RANGES[pos]
	for _attempt in 40:
		var r: Array = ranges[rng.randi_range(0, ranges.size() - 1)]
		var num := rng.randi_range(r[0], r[1])
		if not taken.has(num):
			return num
	for num in range(1, 100):
		if not taken.has(num):
			return num
	return 0

## A draft prospect: young, raw, with a hidden scouting error that the scouting
## department reduces.
static func create_prospect(rng: RandomNumberGenerator, id: String, pos: String, quality: float) -> Player:
	var age := rng.randi_range(21, 23)
	var ovr := int(clampf(44.0 + quality * 24.0 + gauss(rng, 4.0), 40.0, 74.0))
	var p := create(rng, id, pos, ovr, age)
	var boom := rng.randf()
	var headroom := 4.0 + quality * 14.0 + gauss(rng, 7.0)
	if boom > 0.93:
		headroom += 12.0 ## late bloomer / hidden gem
	elif boom < 0.18:
		headroom *= 0.35 ## bust risk
	p.potential = clampi(int(round(ovr + maxf(headroom, 1.0))), ovr + 1, 99)
	p.salary = 0.0
	p.years = 0
	p.experience = 0
	p.scout_error = int(round(gauss(rng, 7.0)))
	return p
