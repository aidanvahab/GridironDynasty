class_name Team
extends RefCounted
## A franchise: identity, roster, depth chart, staff, facilities and record.

## Starters required by the base formations.
const STARTERS := {"QB": 1, "RB": 1, "WR": 3, "TE": 1, "OL": 5, "DL": 4, "LB": 3, "CB": 3, "S": 2, "K": 1}
## Minimum players at each position for a legal roster.
const MIN_AT := {"QB": 2, "RB": 2, "WR": 4, "TE": 2, "OL": 6, "DL": 5, "LB": 4, "CB": 4, "S": 3, "K": 1}
const ROSTER_MAX := 40
const ROSTER_MIN := 33

var id: String = ""
var city: String = ""
var name: String = ""
var abbr: String = ""
var primary: Color = Color.WHITE
var secondary: Color = Color.BLACK
var accent: Color = Color.GRAY
var logo: Dictionary = {"shape": "circle", "emblem": "star"}
var stadium: String = "classic"
var conf: int = 0
var div: int = 0
var offense_style: String = "balanced" ## pass / run / balanced
var defense_style: String = "balanced" ## aggressive / conservative / balanced
var roster: Array = [] ## player ids
var depth: Dictionary = {} ## pos -> Array of player ids in order
var prestige: float = 50.0
var fans: float = 50.0
var funds: float = 20.0 ## $M operating budget for staff and facilities
var staff: Dictionary = {} ## role -> {name, rating, salary, years}
var facilities: Dictionary = {"training": 1, "medical": 1, "stadium": 1, "scouting": 1}
var record: Dictionary = {}
var history: Array = [] ## [{year, w, l, t, pf, pa, result}]
var is_user: bool = false
var chemistry: float = 60.0

func full_name() -> String:
	return "%s %s" % [city, name]

func reset_record() -> void:
	record = {"w": 0, "l": 0, "t": 0, "pf": 0, "pa": 0, "dw": 0, "dl": 0, "dt": 0, "cw": 0, "cl": 0, "ct": 0, "streak": 0}

func win_pct() -> float:
	var g := float(record.get("w", 0) + record.get("l", 0) + record.get("t", 0))
	if g <= 0.0:
		return 0.0
	return (float(record.get("w", 0)) + 0.5 * float(record.get("t", 0))) / g

func record_string() -> String:
	var t := int(record.get("t", 0))
	if t > 0:
		return "%d-%d-%d" % [record.get("w", 0), record.get("l", 0), t]
	return "%d-%d" % [record.get("w", 0), record.get("l", 0)]

func to_dict() -> Dictionary:
	return {
		"id": id, "city": city, "name": name, "abbr": abbr,
		"primary": primary.to_html(false), "secondary": secondary.to_html(false), "accent": accent.to_html(false),
		"logo": logo.duplicate(), "stadium": stadium, "conf": conf, "div": div,
		"offense": offense_style, "defense": defense_style, "roster": roster.duplicate(),
		"depth": depth.duplicate(true), "prestige": prestige, "fans": fans, "funds": funds,
		"staff": staff.duplicate(true), "facilities": facilities.duplicate(),
		"record": record.duplicate(), "history": history.duplicate(true), "is_user": is_user,
		"chemistry": chemistry,
	}

static func from_dict(d: Dictionary) -> Team:
	var t := Team.new()
	t.id = str(d.get("id", ""))
	t.city = str(d.get("city", ""))
	t.name = str(d.get("name", ""))
	t.abbr = str(d.get("abbr", t.id))
	t.primary = Color(str(d.get("primary", "ffffff")))
	t.secondary = Color(str(d.get("secondary", "000000")))
	t.accent = Color(str(d.get("accent", "808080")))
	t.logo = d.get("logo", {"shape": "circle", "emblem": "star"})
	t.stadium = str(d.get("stadium", "classic"))
	t.conf = int(d.get("conf", 0))
	t.div = int(d.get("div", 0))
	t.offense_style = str(d.get("offense", "balanced"))
	t.defense_style = str(d.get("defense", "balanced"))
	t.roster = d.get("roster", [])
	t.depth = d.get("depth", {})
	t.prestige = float(d.get("prestige", 50.0))
	t.fans = float(d.get("fans", 50.0))
	t.funds = float(d.get("funds", 20.0))
	t.staff = d.get("staff", {})
	var fac: Dictionary = d.get("facilities", {})
	for k in t.facilities:
		t.facilities[k] = clampi(int(fac.get(k, 1)), 1, 5)
	t.record = d.get("record", {})
	if t.record.is_empty():
		t.reset_record()
	t.history = d.get("history", [])
	t.is_user = bool(d.get("is_user", false))
	t.chemistry = float(d.get("chemistry", 60.0))
	return t
