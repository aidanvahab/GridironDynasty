class_name PlayResult
extends RefCounted
## Outcome of one scrimmage down, expressed relative to the line of scrimmage
## in the offense frame. Produced by live gameplay *and* the drive simulator,
## consumed by RulesEngine.apply_scrimmage(). The rules engine — never the
## producer — decides first downs, scores, safeties and possession.

enum Kind { RUN, PASS_COMPLETE, PASS_INCOMPLETE, SACK, INTERCEPTION, FUMBLE_LOST, KNEEL, SPIKE }

var kind: Kind = Kind.RUN
## Yards from the line of scrimmage to where the ball became dead (runs,
## completions, sacks) or where the defense gained possession (turnovers).
var gain: float = 0.0
var out_of_bounds: bool = false
## Yards the defense returned a turnover, measured toward the offense's goal.
var return_yards: float = 0.0
## Seconds of live action.
var elapsed: float = 5.0
var description: String = ""
## Optional per-player attribution used by the stats recorder:
## passer, receiver, rusher, tackler, interceptor, sacker, fumbler, recoverer (player ids)
var credit: Dictionary = {}
## Air yards for completions (for display only).
var air_yards: float = 0.0

static func make(k: Kind, g: float, t: float = 5.0, oob: bool = false) -> PlayResult:
	var r := PlayResult.new()
	r.kind = k
	r.gain = g
	r.elapsed = t
	r.out_of_bounds = oob
	return r

func is_pass() -> bool:
	return kind == Kind.PASS_COMPLETE or kind == Kind.PASS_INCOMPLETE or kind == Kind.INTERCEPTION or kind == Kind.SACK

func is_turnover() -> bool:
	return kind == Kind.INTERCEPTION or kind == Kind.FUMBLE_LOST

func kind_name() -> String:
	return Kind.keys()[kind]
