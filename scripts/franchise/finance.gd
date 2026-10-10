class_name Finance
extends RefCounted
## Franchise operating budget (separate from the player salary cap): gate
## revenue, staff payroll, facility upgrades and season payouts.

const FACILITY_COST := [0.0, 0.0, 7.0, 12.0, 18.0, 26.0] ## cost to reach level N
const FACILITY_INFO := {
	"training": {"name": "Training Complex", "effect": "+8% player development per level"},
	"medical": {"name": "Medical Center", "effect": "-10% injury rate and faster recovery per level"},
	"stadium": {"name": "Stadium Upgrades", "effect": "+15% game revenue and +0.4 home-field per level"},
	"scouting": {"name": "Scouting Department", "effect": "+4 scouting points and sharper draft reports per level"},
}

static func game_revenue(lg: League, g: Dictionary) -> void:
	var h: Team = lg.teams[g["home"]]
	var mult := 1.0 + (float(h.facilities.get("stadium", 1)) - 1.0) * 0.15
	var rev := (2.2 + h.fans * 0.035) * mult
	if g.get("playoff", false):
		rev *= 1.6
	h.funds += rev
	g["revenue"] = rev

static func weekly_expenses(lg: League, t: Team) -> float:
	var total := 0.0
	for role in t.staff:
		total += float(t.staff[role].get("salary", 1.0))
	return total / maxf(1.0, float(Season.season_weeks(lg)))

static func season_payout(lg: League) -> void:
	for t in lg.teams.values():
		var bonus := 4.0 + float(t.record.get("w", 0)) * 0.6
		if lg.playoffs.get("champion", "") == t.id:
			bonus += 10.0
		elif t.record.get("playoff", false):
			bonus += 4.0
		t.funds += bonus
		if t.is_user:
			lg.add_news("League revenue share: %s added to the budget." % UI.money(bonus), "finance")

static func upgrade_cost(t: Team, key: String) -> float:
	var lvl := int(t.facilities.get(key, 1))
	if lvl >= 5:
		return -1.0
	return FACILITY_COST[lvl + 1]

static func upgrade(lg: League, t: Team, key: String) -> String:
	var cost := upgrade_cost(t, key)
	if cost < 0.0:
		return "Already at maximum level."
	if t.funds < cost:
		return "Not enough funds (%s needed)." % UI.money(cost)
	t.funds -= cost
	t.facilities[key] = int(t.facilities[key]) + 1
	lg.add_news("%s upgraded to level %d." % [FACILITY_INFO[key]["name"], t.facilities[key]], "finance")
	return ""
