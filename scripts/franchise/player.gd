class_name Player
extends RefCounted
## A fictional player. All attributes are 1..99 and feed directly into live
## gameplay (movement, throwing, catching, blocking, tackling, kicking) and the
## statistical simulation.

const POSITIONS := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]
const OFFENSE := ["QB", "RB", "WR", "TE", "OL"]
const DEFENSE := ["DL", "LB", "CB", "S"]

const ATTRS := [
	"speed", "accel", "agility", "strength", "awareness", "stamina",
	"throw_power", "throw_acc", "decision",
	"carrying", "balance", "catching", "route",
	"blocking", "tackling", "coverage", "pass_rush",
	"kick_power", "kick_acc",
]

const ATTR_LABELS := {
	"speed": "Speed", "accel": "Acceleration", "agility": "Agility", "strength": "Strength",
	"awareness": "Awareness", "stamina": "Stamina", "throw_power": "Arm Strength",
	"throw_acc": "Accuracy", "decision": "Decision Making", "carrying": "Ball Security",
	"balance": "Contact Balance", "catching": "Catching", "route": "Route Running",
	"blocking": "Blocking", "tackling": "Tackling", "coverage": "Coverage",
	"pass_rush": "Pass Rush", "kick_power": "Kick Power", "kick_acc": "Kick Accuracy",
}

## Overall-rating weights. Each position values different attributes so a fast
## receiver is not automatically a good blocker, etc.
const WEIGHTS := {
	"QB": {"throw_acc": 0.30, "throw_power": 0.20, "decision": 0.25, "awareness": 0.10, "speed": 0.08, "agility": 0.07},
	"RB": {"speed": 0.20, "accel": 0.15, "agility": 0.15, "carrying": 0.15, "balance": 0.15, "catching": 0.08, "strength": 0.07, "awareness": 0.05},
	"WR": {"speed": 0.25, "route": 0.25, "catching": 0.25, "agility": 0.10, "accel": 0.10, "awareness": 0.05},
	"TE": {"catching": 0.20, "route": 0.15, "blocking": 0.25, "strength": 0.15, "speed": 0.15, "awareness": 0.10},
	"OL": {"blocking": 0.45, "strength": 0.35, "awareness": 0.20},
	"DL": {"pass_rush": 0.35, "strength": 0.30, "tackling": 0.20, "accel": 0.15},
	"LB": {"tackling": 0.30, "awareness": 0.20, "coverage": 0.15, "speed": 0.15, "pass_rush": 0.10, "strength": 0.10},
	"CB": {"coverage": 0.35, "speed": 0.30, "agility": 0.10, "catching": 0.10, "awareness": 0.10, "tackling": 0.05},
	"S": {"coverage": 0.30, "speed": 0.20, "tackling": 0.20, "awareness": 0.20, "catching": 0.10},
	"K": {"kick_power": 0.5, "kick_acc": 0.5},
}

const PERSONALITIES := ["Leader", "Competitor", "Team Player", "Mercenary", "Showboat", "Quiet Pro"]

var id: String = ""
var first_name: String = ""
var last_name: String = ""
var pos: String = "WR"
var age: int = 22
var number: int = 0
var attrs: Dictionary = {}
var potential: int = 70 ## true ceiling for overall
var salary: float = 1.0 ## $M per season
var years: int = 1 ## contract seasons remaining including the current one
var morale: float = 70.0
var fatigue: float = 0.0
var injury_weeks: int = 0
var skin: int = 0
var build: float = 1.0 ## body proportion scale used by the avatar
var personality: String = "Team Player"
var experience: int = 0
var team_id: String = "" ## "" = free agent / prospect
var draft_info: Dictionary = {} ## {year, round, pick, team}
var season_stats: Dictionary = {}
var career_stats: Dictionary = {}
var history: Array = [] ## [{year, team, ovr, age, stats}]
var awards: Array = [] ## [{year, award}]
var retired: bool = false
var xp: float = 0.0 ## accumulated development points this season
var games_started: int = 0 ## this season
var scout_error: int = 0 ## prospect scouting noise (hidden)

func full_name() -> String:
	return "%s %s" % [first_name, last_name]

func short_name() -> String:
	return "%s. %s" % [first_name.substr(0, 1), last_name]

func a(attr: String) -> float:
	return float(attrs.get(attr, 50))

func overall() -> int:
	return overall_at(pos)

func overall_at(position: String) -> int:
	var w: Dictionary = WEIGHTS[position]
	var total := 0.0
	for k in w:
		total += a(k) * float(w[k])
	return clampi(int(round(total)), 1, 99)

## Rating with morale and fatigue applied (used by games).
func effective(attr: String) -> float:
	var m := (morale - 60.0) * 0.06 ## -3.6 .. +2.4
	var f := -fatigue * 0.08
	return clampf(a(attr) + m + f, 1.0, 99.0)

## Movement speed in yards/second for live gameplay.
func top_speed() -> float:
	return 5.8 + effective("speed") * 0.042 ## 40 -> 7.5, 99 -> 9.96

func is_available() -> bool:
	return injury_weeks <= 0 and not retired

func market_value() -> float:
	## Expected salary ($M) for a fair contract given quality and age.
	var ovr := float(overall())
	var base := pow(maxf(ovr - 45.0, 1.0) / 50.0, 2.6) * 22.0 + 0.75
	if pos == "QB":
		base *= 1.7
	elif pos == "K":
		base *= 0.35
	elif pos == "OL" or pos == "S":
		base *= 0.85
	if age >= 31:
		base *= maxf(0.5, 1.0 - (age - 30) * 0.08)
	return snappedf(clampf(base, 0.75, 45.0), 0.05)

func add_stat(key: String, amount: float) -> void:
	season_stats[key] = season_stats.get(key, 0.0) + amount
	career_stats[key] = career_stats.get(key, 0.0) + amount

func stat(key: String) -> float:
	return float(season_stats.get(key, 0.0))

func to_dict() -> Dictionary:
	return {
		"id": id, "first": first_name, "last": last_name, "pos": pos, "age": age,
		"number": number, "attrs": attrs.duplicate(), "potential": potential,
		"salary": salary, "years": years, "morale": morale, "fatigue": fatigue,
		"injury": injury_weeks, "skin": skin, "build": build, "personality": personality,
		"exp": experience, "team": team_id, "draft": draft_info.duplicate(),
		"ss": season_stats.duplicate(), "cs": career_stats.duplicate(),
		"history": history.duplicate(true), "awards": awards.duplicate(true),
		"retired": retired, "xp": xp, "gs": games_started, "se": scout_error,
	}

static func from_dict(d: Dictionary) -> Player:
	var p := Player.new()
	p.id = str(d.get("id", ""))
	p.first_name = str(d.get("first", "John"))
	p.last_name = str(d.get("last", "Doe"))
	p.pos = str(d.get("pos", "WR"))
	if not WEIGHTS.has(p.pos):
		p.pos = "WR"
	p.age = int(d.get("age", 22))
	p.number = int(d.get("number", 0))
	var at: Dictionary = d.get("attrs", {})
	for k in ATTRS:
		p.attrs[k] = clampi(int(at.get(k, 50)), 1, 99)
	p.potential = int(d.get("potential", 70))
	p.salary = float(d.get("salary", 1.0))
	p.years = int(d.get("years", 1))
	p.morale = float(d.get("morale", 70.0))
	p.fatigue = float(d.get("fatigue", 0.0))
	p.injury_weeks = int(d.get("injury", 0))
	p.skin = int(d.get("skin", 0))
	p.build = float(d.get("build", 1.0))
	p.personality = str(d.get("personality", "Team Player"))
	p.experience = int(d.get("exp", 0))
	p.team_id = str(d.get("team", ""))
	p.draft_info = d.get("draft", {})
	p.season_stats = d.get("ss", {})
	p.career_stats = d.get("cs", {})
	p.history = d.get("history", [])
	p.awards = d.get("awards", [])
	p.retired = bool(d.get("retired", false))
	p.xp = float(d.get("xp", 0.0))
	p.games_started = int(d.get("gs", 0))
	p.scout_error = int(d.get("se", 0))
	return p
