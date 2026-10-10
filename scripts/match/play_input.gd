class_name PlayInput
extends RefCounted
## Per-frame control intents for the user-controlled player. HumanInput reads
## devices; BotInput (tests/autoplay) produces the same intents from a script.

var move := Vector2.ZERO ## x = offense right, y = upfield; length 0..1
var sprint := false
var snap := false ## just pressed
var juke := false ## just pressed
var dive := false ## just pressed
var target := -1 ## receiver index 0..4 just selected
var charging := false ## throw button held
var release := false ## throw button released this frame
var cancel := false
var throw_away := false
var has_aim := false
var aim_world := Vector3.ZERO
var aim_nudge := Vector2.ZERO ## gamepad right stick fine aim
var quick_throw := -1 ## full-assist one-button throw to receiver index
var any_move := false

func clear() -> void:
	move = Vector2.ZERO
	sprint = false
	snap = false
	juke = false
	dive = false
	target = -1
	charging = false
	release = false
	cancel = false
	throw_away = false
	has_aim = false
	aim_nudge = Vector2.ZERO
	quick_throw = -1
	any_move = false

## Override: fill intents for this frame. `play` is the LivePlay.
func poll(_play: Node, _dt: float) -> void:
	clear()
