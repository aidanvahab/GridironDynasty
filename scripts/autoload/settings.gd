extends Node
## Persistent user settings (user://settings.cfg), input map and display/audio
## application. Every setting here is applied immediately and saved.

signal changed(key: String)

const PATH := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var values: Dictionary = {
	"master_volume": 0.85,
	"music_volume": 0.6,
	"sfx_volume": 0.85,
	"crowd_volume": 0.75,
	"window_mode": 0, ## 0 windowed, 1 fullscreen, 2 borderless fullscreen
	"resolution": 1, ## index into RESOLUTIONS (windowed)
	"vsync": true,
	"quality": 2, ## 0 low, 1 medium, 2 high
	"camera_sensitivity": 1.0,
	"mouse_sensitivity": 1.0,
	"camera_assist": true,
	"camera_shake": true,
	"ui_scale": 1.0,
	"difficulty": 1,
	"assist": 1,
	"game_length": 1,
	"show_routes": true,
	"tutorial_enabled": true,
	"tutorials_seen": {},
	"debug_overlay": false,
}

var last_input_was_mouse := true
var last_input_was_gamepad := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_setup_input_map()
	load_settings()
	apply_all()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		last_input_was_mouse = true
		last_input_was_gamepad = false
	elif event is InputEventKey:
		last_input_was_mouse = event is InputEventKey and last_input_was_mouse
		last_input_was_gamepad = false
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		last_input_was_gamepad = true
		last_input_was_mouse = false

func get_value(key: String) -> Variant:
	return values.get(key)

func set_value(key: String, v: Variant) -> void:
	values[key] = v
	apply(key)
	save_settings()
	changed.emit(key)

func load_settings() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(PATH)
	if err != OK:
		return
	for k in values.keys():
		if cf.has_section_key("settings", k):
			var v: Variant = cf.get_value("settings", k)
			if typeof(v) == typeof(values[k]) or (typeof(values[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				values[k] = v

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	var err := cf.save(PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))

func apply_all() -> void:
	for k in values:
		apply(k)

func apply(key: String) -> void:
	match key:
		"master_volume":
			_set_bus("Master", values[key])
		"music_volume":
			_set_bus("Music", values[key])
		"sfx_volume":
			_set_bus("SFX", values[key])
		"crowd_volume":
			_set_bus("Crowd", values[key])
		"window_mode", "resolution":
			_apply_window()
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
		"ui_scale":
			if get_tree() != null and get_tree().root != null:
				get_tree().root.content_scale_factor = clampf(float(values["ui_scale"]), 0.75, 1.5)

func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match int(values["window_mode"]):
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res: Vector2i = RESOLUTIONS[clampi(int(values["resolution"]), 0, RESOLUTIONS.size() - 1)]
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			res = Vector2i(mini(res.x, screen.size.x), mini(res.y, screen.size.y))
			DisplayServer.window_set_size(res)
			DisplayServer.window_set_position(screen.position + (screen.size - res) / 2)

func _setup_audio_buses() -> void:
	for bus in ["Music", "SFX", "Crowd"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")

func _set_bus(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var v := clampf(float(linear), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))

# ---------------------------------------------------------------- input

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mouse(btn: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	return e

func _pad(btn: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	return e

func _axis(axis: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e

func _action(name: String, events: Array, deadzone: float = 0.3) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, deadzone)
	for e in events:
		InputMap.action_add_event(name, e)

## The binding table is also shown to the player in Settings > Controls.
const BINDINGS := [
	["Move", "W A S D / Arrows", "Left Stick"],
	["Sprint", "Shift", "RT / R2"],
	["Snap ball", "Space", "A / Cross"],
	["Select receiver", "1 - 5", "A B X Y RB (hold to charge)"],
	["Charge & throw", "Hold / release Left Mouse", "Hold / release receiver button"],
	["Fine aim", "Mouse", "Right Stick"],
	["Cancel target", "Q", "LB / L1"],
	["Throw ball away", "E", "Back / Select + LB"],
	["Juke (ball carrier)", "Space", "A / Cross"],
	["Dive (ball carrier)", "C", "B / Circle"],
	["Flip play (pre-snap)", "F", "Y / Triangle"],
	["Audible (pre-snap)", "R", "X / Square"],
	["Timeout (pre-snap)", "T", "D-Pad Down"],
	["Show routes (pre-snap)", "Tab", "D-Pad Up"],
	["Replay last play", "V", "D-Pad Left"],
	["Pause", "Esc", "Start"],
]

func _setup_input_map() -> void:
	_action("move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)], 0.2)
	_action("move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)], 0.2)
	_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)], 0.2)
	_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)], 0.2)
	_action("aim_forward", [_axis(JOY_AXIS_RIGHT_Y, -1.0)], 0.25)
	_action("aim_back", [_axis(JOY_AXIS_RIGHT_Y, 1.0)], 0.25)
	_action("aim_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)], 0.25)
	_action("aim_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)], 0.25)
	_action("sprint", [_key(KEY_SHIFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("snap", [_key(KEY_SPACE), _pad(JOY_BUTTON_A)])
	_action("juke", [_key(KEY_SPACE), _pad(JOY_BUTTON_A)])
	_action("dive", [_key(KEY_C), _pad(JOY_BUTTON_B)])
	_action("throw", [_mouse(MOUSE_BUTTON_LEFT)])
	for i in 5:
		_action("target_%d" % (i + 1), [_key([KEY_1, KEY_2, KEY_3, KEY_4, KEY_5][i])])
	_action("pad_target_1", [_pad(JOY_BUTTON_A)])
	_action("pad_target_2", [_pad(JOY_BUTTON_B)])
	_action("pad_target_3", [_pad(JOY_BUTTON_X)])
	_action("pad_target_4", [_pad(JOY_BUTTON_Y)])
	_action("pad_target_5", [_pad(JOY_BUTTON_RIGHT_SHOULDER)])
	_action("cancel_target", [_key(KEY_Q), _pad(JOY_BUTTON_LEFT_SHOULDER)])
	_action("throw_away", [_key(KEY_E), _pad(JOY_BUTTON_BACK)])
	_action("flip_play", [_key(KEY_F), _pad(JOY_BUTTON_Y)])
	_action("audible", [_key(KEY_R), _pad(JOY_BUTTON_X)])
	_action("timeout", [_key(KEY_T), _pad(JOY_BUTTON_DPAD_DOWN)])
	_action("toggle_routes", [_key(KEY_TAB), _pad(JOY_BUTTON_DPAD_UP)])
	_action("replay", [_key(KEY_V), _pad(JOY_BUTTON_DPAD_LEFT)])
	_action("pause", [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)])
	_action("debug_toggle", [_key(KEY_F3)])
	_action("kick_power", [_key(KEY_SPACE), _mouse(MOUSE_BUTTON_LEFT), _pad(JOY_BUTTON_A)])
	_action("kick_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)], 0.2)
	_action("kick_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)], 0.2)
	# Menu navigation additions (ui_accept etc. exist by default).
	InputMap.action_add_event("ui_cancel", _pad(JOY_BUTTON_B))
