class_name Playbook
extends RefCounted
## Loads data/playbook.json and resolves formations and routes into
## offense-frame coordinates (Vector2(downfield, lateral) relative to the ball).

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/playbook.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data

static func plays() -> Array:
	return data()["plays"]

static func play(id: String) -> Dictionary:
	for p in plays():
		if p["id"] == id:
			return p
	return {}

static func defense_calls() -> Array:
	return data()["defense"]["calls"]

static func defense_call(id: String) -> Dictionary:
	for c in defense_calls():
		if c["id"] == id:
			return c
	return defense_calls()[0]

static func front(id: String) -> Dictionary:
	return data()["defense"]["fronts"][id]

static func formation(id: String) -> Dictionary:
	return data()["formations"][id]

static func formation_name(id: String) -> String:
	return str(formation(id).get("name", id))

static func line_spots() -> Dictionary:
	return data()["line"]

static func route_def(name: String) -> Dictionary:
	return data()["route_library"].get(name, {"pts": [], "continue": false})

static func v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## Alignment for a slot ("QB", "X", "LT", ...). `flip` mirrors the play.
static func alignment(play_def: Dictionary, slot: String, flip: bool) -> Vector2:
	var p: Vector2
	if line_spots().has(slot):
		p = v2(line_spots()[slot])
	else:
		p = v2(formation(play_def["formation"])[slot])
	if flip:
		p.y = -p.y
	return p

## Resolves a receiver's route into offense-frame waypoints.
static func route_points(play_def: Dictionary, slot: String, flip: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rname: String = play_def.get("routes", {}).get(slot, "block")
	var rd := route_def(rname)
	var start := alignment(play_def, slot, flip)
	var side := signf(start.y)
	if absf(start.y) < 0.5:
		side = float(play_def.get("screen_side", 1)) * (-1.0 if flip else 1.0)
	elif rname == "screen":
		side = float(play_def.get("screen_side", 1)) * (-1.0 if flip else 1.0)
	for pt in rd["pts"]:
		var v := v2(pt)
		out.append(Vector2(start.x + v.x, start.y + v.y * side))
	return out

static func run_path(play_def: Dictionary, flip: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pt in play_def.get("run_path", []):
		var v := v2(pt)
		if flip:
			v.y = -v.y
		out.append(v)
	return out

static func is_run(play_def: Dictionary) -> bool:
	return play_def.get("category", "") in ["run", "qb_run"]

static func is_pass(play_def: Dictionary) -> bool:
	return play_def.get("category", "") in ["pass", "screen", "play_action"]

## Plays suggested for a situation (used for the "Suggested" tab and AI calls).
static func suggested(down: int, togo: float, ball_on: float, clock: float, quarter: int, score_diff: int) -> Array:
	var tags: Array = []
	if ball_on >= 88.0:
		tags.append_array(["goal_line", "redzone"])
	elif ball_on >= 78.0:
		tags.append("redzone")
	if togo <= 2.0:
		tags.append_array(["short_yardage", "run", "quick"])
	elif togo <= 6.0:
		tags.append_array(["short", "medium", "run", "quick"])
	elif togo <= 10.5:
		tags.append_array(["medium", "run", "pa", "short"])
		if down == 1:
			tags.append("deep")
	else:
		tags.append_array(["long", "deep", "medium", "blitz_beater"])
	var late := (quarter == 2 or quarter >= 4) and clock < 120.0
	if late and score_diff <= 0:
		tags.erase("run")
		tags.append("clock")
	var out: Array = []
	for p in plays():
		if p.get("special", "") != "":
			continue
		if ball_on < 78.0 and (p.get("tags", []).has("goal_line") and not p.get("tags", []).has("short_yardage")):
			continue
		if p.get("tags", []).has("desperation") and not (late and clock < 12.0):
			continue
		for t in p.get("tags", []):
			if tags.has(t):
				out.append(p["id"])
				break
	return out
