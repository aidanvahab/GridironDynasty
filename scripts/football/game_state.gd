class_name GameState
extends RefCounted
## Complete, serializable state of one football game. Mutated only by RulesEngine.

enum Phase { PREGAME, KICKOFF, SCRIMMAGE, TRY, GAME_OVER }

const HOME := 0
const AWAY := 1

var phase: Phase = Phase.PREGAME
var quarter: int = 1 ## 1-4 regulation, 5+ overtime periods
var clock: float = 900.0 ## seconds remaining in the current period
var score: Array[int] = [0, 0]
var timeouts: Array[int] = [3, 3]
var possession: int = HOME
var ball_on: float = 25.0 ## offense frame, yards from the offense's own goal line
var down: int = 1
var first_down_line: float = 35.0 ## offense frame
var clock_running: bool = false
var home_dir: int = 1 ## world direction the home team drives this quarter
var kicking_side: int = HOME ## who kicks off when phase == KICKOFF
var free_kick: bool = false ## kickoff after a safety
var opening_receiver: int = HOME
var two_minute_warning_given: bool = false
var try_side: int = HOME ## side attempting the try during Phase.TRY

# Overtime bookkeeping
var ot_receiver: int = -1
var ot_poss_index: int = 0

# Running totals
var team_stats: Array[Dictionary] = [{}, {}]
var scoring_log: Array[Dictionary] = []
var play_log: Array[Dictionary] = []
var drive_count: Array[int] = [0, 0]
var last_score: Dictionary = {}
var winner: int = -1 ## -1 undecided, 2 = tie

func _init() -> void:
	for i in 2:
		team_stats[i] = new_team_stats()

static func new_team_stats() -> Dictionary:
	return {
		"first_downs": 0, "plays": 0, "total_yards": 0.0, "pass_yards": 0.0,
		"rush_yards": 0.0, "turnovers": 0, "third_att": 0, "third_conv": 0,
		"fourth_att": 0, "fourth_conv": 0, "top": 0.0, "sacks_allowed": 0,
		"punts": 0, "fg_att": 0, "fg_made": 0, "td": 0,
	}

static func other(side: int) -> int:
	return 1 - side

func defense() -> int:
	return 1 - possession

func yards_to_go() -> float:
	return maxf(first_down_line - ball_on, 0.0)

func is_goal_to_go() -> bool:
	return first_down_line >= 100.0

func offense_dir() -> int:
	return home_dir if possession == HOME else -home_dir

func dir_for(side: int) -> int:
	return home_dir if side == HOME else -home_dir

func is_overtime() -> bool:
	return quarter >= 5

func is_over() -> bool:
	return phase == Phase.GAME_OVER

func to_dict() -> Dictionary:
	return {
		"phase": phase, "quarter": quarter, "clock": clock, "score": score.duplicate(),
		"timeouts": timeouts.duplicate(), "possession": possession, "ball_on": ball_on,
		"down": down, "first_down_line": first_down_line, "clock_running": clock_running,
		"home_dir": home_dir, "kicking_side": kicking_side, "free_kick": free_kick,
		"opening_receiver": opening_receiver, "two_minute_warning_given": two_minute_warning_given,
		"try_side": try_side, "ot_receiver": ot_receiver, "ot_poss_index": ot_poss_index,
		"team_stats": team_stats.duplicate(true), "scoring_log": scoring_log.duplicate(true),
		"drive_count": drive_count.duplicate(), "winner": winner,
	}
