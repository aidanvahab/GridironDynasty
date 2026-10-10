class_name Lineup
extends RefCounted
## Builds pooled FieldAgents for a team from its depth chart, dressed in home
## or away uniforms.

const OFF_SLOTS := {"QB": ["QB", 0], "B": ["RB", 0], "X": ["WR", 0], "Z": ["WR", 1], "S": ["WR", 2], "Y": ["TE", 0], "LT": ["OL", 0], "LG": ["OL", 1], "C": ["OL", 2], "RG": ["OL", 3], "RT": ["OL", 4]}
const DEF_SLOTS := {"DL1": ["DL", 0], "DL2": ["DL", 1], "DL3": ["DL", 2], "DL4": ["DL", 3], "LB1": ["LB", 0], "LB2": ["LB", 1], "LB3": ["LB", 2], "CB1": ["CB", 0], "CB2": ["CB", 1], "CB3": ["CB", 2], "S1": ["S", 0], "S2": ["S", 1]}

static func uniform(t: Team, home: bool) -> Dictionary:
	var cream := Color("#F5F0E5")
	if home:
		var pants := t.secondary if t.secondary.get_luminance() > 0.55 else cream
		return {"jersey": t.primary, "pants": pants, "helmet": t.primary, "trim": t.secondary if t.secondary.get_luminance() > 0.35 else t.accent, "mask": Color("#C8CED6")}
	return {"jersey": cream, "pants": t.primary, "helmet": t.primary, "trim": t.primary, "mask": Color("#3A3F47")}

static func _make(parent: Node, league: League, t: Team, slots: Dictionary, unit: FieldAgent.Unit, uni: Dictionary, font: Font) -> Dictionary:
	var out := {}
	var used := {}
	for slot in slots:
		var pos: String = slots[slot][0]
		var idx: int = slots[slot][1]
		var group := league.starters(t, pos, idx + 1)
		var p: Player = null
		if group.size() > idx:
			p = group[idx]
		# Avoid placing one player in two slots.
		if p == null or used.has(p.id):
			for cand in league.roster_players(t):
				if not used.has(cand.id) and cand.pos == pos:
					p = cand
					break
		if p == null or used.has(p.id):
			for cand in league.roster_players(t):
				if not used.has(cand.id):
					p = cand
					break
		used[p.id] = true
		var a := FieldAgent.new()
		a.name = "%s_%s" % ["O" if unit == FieldAgent.Unit.OFFENSE else "D", slot]
		parent.add_child(a)
		a.setup(p, unit, slot, pos, uni["jersey"], uni["pants"], uni["helmet"], uni["trim"], uni["mask"], font)
		out[slot] = a
	return out

static func build_offense(parent: Node, league: League, t: Team, home: bool, font: Font) -> Dictionary:
	return _make(parent, league, t, OFF_SLOTS, FieldAgent.Unit.OFFENSE, uniform(t, home), font)

static func build_defense(parent: Node, league: League, t: Team, home: bool, font: Font) -> Dictionary:
	return _make(parent, league, t, DEF_SLOTS, FieldAgent.Unit.DEFENSE, uniform(t, home), font)
