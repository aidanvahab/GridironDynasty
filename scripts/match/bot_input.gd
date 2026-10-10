class_name BotInput
extends PlayInput
## Scripted controller used by automated gameplay tests and the attract-mode
## demo. A plan is a Dictionary:
##   {"snap_at": 0.3, "throw_to": 0..4, "throw_at": sec, "power": 0..1,
##    "run": true, "run_dir": Vector2, "juke_at": sec, "dive_at": sec,
##    "throw_away_at": sec, "auto": true}
## With "auto", the bot picks the most open receiver itself.

var plan: Dictionary = {}
var _t := 0.0
var _snapped := false
var _charging := false
var _charge_start := -1.0
var _thrown := false

func _init(p_plan: Dictionary = {}) -> void:
	plan = p_plan

func poll(play: Node, dt: float) -> void:
	clear()
	_t += dt
	var stage: int = play.get("stage")
	if stage == LivePlay.Stage.PRESNAP:
		if _t >= float(plan.get("snap_at", 0.3)) and not _snapped:
			snap = true
			_snapped = true
		return
	if stage != LivePlay.Stage.LIVE:
		return
	var pt: float = play.get("t")
	var lp: LivePlay = play
	var carrier := lp.ball.carrier as FieldAgent
	var i_am_qb := carrier != null and carrier == lp.qb and not lp.thrown
	if plan.has("throw_away_at") and i_am_qb and pt >= float(plan["throw_away_at"]):
		throw_away = true
		return
	if i_am_qb and plan.has("throw_at") and not _thrown:
		var tt: float = plan["throw_at"]
		var idx: int = plan.get("throw_to", 0)
		if plan.get("auto", false):
			idx = lp.most_open_receiver()
		var power: float = plan.get("power", 0.6)
		var hold := power * LivePlay.CHARGE_TIME
		if pt >= tt - hold and _charge_start < 0.0:
			target = idx
			_charge_start = pt
		if _charge_start >= 0.0:
			if pt - _charge_start < hold:
				charging = true
			else:
				release = true
				_thrown = true
		return
	if carrier != null and carrier == lp.user:
		var d: Vector2 = plan.get("run_dir", Vector2(0, 1))
		if plan.has("weave"):
			d = (d + Vector2(sin(pt * 2.0) * float(plan["weave"]), 0)).normalized()
		move = d
		any_move = plan.get("run", false) or lp.thrown or carrier != lp.qb
		sprint = plan.get("sprint", true)
		if plan.has("juke_at") and absf(pt - float(plan["juke_at"])) < dt * 0.5 + 0.0001:
			juke = true
		if plan.has("dive_at") and pt >= float(plan["dive_at"]) and pt - dt < float(plan["dive_at"]):
			dive = true
		if not any_move:
			move = Vector2.ZERO
