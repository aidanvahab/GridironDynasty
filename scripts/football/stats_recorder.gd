class_name StatsRecorder
extends RefCounted
## Per-game box score keyed by player id. Shared by live play and simulation.

var lines: Dictionary = {} ## pid -> {stat: value}
var team_of: Dictionary = {} ## pid -> side

func add(pid: String, key: String, amount: float = 1.0, side: int = -1) -> void:
	if pid == "":
		return
	if not lines.has(pid):
		lines[pid] = {}
	lines[pid][key] = lines[pid].get(key, 0.0) + amount
	if side >= 0:
		team_of[pid] = side

func get_stat(pid: String, key: String) -> float:
	return float(lines.get(pid, {}).get(key, 0.0))

## Returns [pid, value] of the top player on `side` for `key`.
func leader(side: int, key: String) -> Array:
	var best := ""
	var best_v := -INF
	for pid in lines:
		if team_of.get(pid, -1) != side:
			continue
		var v := float(lines[pid].get(key, 0.0))
		if v > best_v:
			best_v = v
			best = pid
	return [best, best_v]

## Game score used for player-of-the-game and championship MVP.
func impact(pid: String) -> float:
	var l: Dictionary = lines.get(pid, {})
	return l.get("pass_yds", 0.0) * 0.04 + l.get("pass_td", 0.0) * 4.0 - l.get("int_thrown", 0.0) * 3.0 \
		+ l.get("rush_yds", 0.0) * 0.1 + l.get("rush_td", 0.0) * 6.0 + l.get("rec_yds", 0.0) * 0.1 \
		+ l.get("rec_td", 0.0) * 6.0 + l.get("tackles", 0.0) * 0.8 + l.get("sacks", 0.0) * 4.0 \
		+ l.get("def_int", 0.0) * 5.0 + l.get("fg_made", 0.0) * 2.0 + l.get("ff", 0.0) * 3.0

func top_impact(side: int) -> String:
	var best := ""
	var best_v := -INF
	for pid in lines:
		if side >= 0 and team_of.get(pid, -1) != side:
			continue
		var v := impact(pid)
		if v > best_v:
			best_v = v
			best = pid
	return best
