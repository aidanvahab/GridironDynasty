class_name SettingsPanel
extends Control
## Full settings screen (audio, display, gameplay, camera, accessibility,
## controls reference). Used from the main menu, hub and pause menu.

signal closed

var _tabs: Dictionary = {}
var _content: VBoxContainer
var _tab_bar: HBoxContainer
var _first_focus: Control

func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UI.panel(Palette.NAVY, 20, Palette.PANEL_LIGHT, 30)
	p.custom_minimum_size = Vector2(1180, 780)
	center.add_child(p)
	var v := UI.vbox(16)
	p.add_child(v)
	var head := UI.hbox(20)
	head.add_child(UI.heading("Settings", 56, Palette.CREAM))
	head.add_child(UI.expand(UI.spacer()))
	var close := UI.button("DONE", _close, "primary", 160)
	head.add_child(close)
	v.add_child(head)
	_tab_bar = UI.hbox(8)
	v.add_child(_tab_bar)
	for t in ["Audio", "Display", "Gameplay", "Camera", "Controls"]:
		var b := UI.button(t, func(): _show(t), "ghost", 150)
		b.set_meta("tab", t)
		_tab_bar.add_child(b)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_content = UI.vbox(14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_content)
	_show("Audio")
	UI.pop_in(p)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	Audio.ui("back")
	closed.emit()
	queue_free()

func _show(tab: String) -> void:
	for b in _tab_bar.get_children():
		var on: bool = b.get_meta("tab") == tab
		b.add_theme_stylebox_override("normal", UI.box(Palette.ORANGE if on else Color(0, 0, 0, 0), 8, Color(1, 1, 1, 0.12), 1, 14))
		b.add_theme_color_override("font_color", Palette.NAVY if on else Palette.CREAM)
	for c in _content.get_children():
		c.queue_free()
	_first_focus = null
	match tab:
		"Audio":
			_slider("Master Volume", "master_volume")
			_slider("Music Volume", "music_volume")
			_slider("Effects Volume", "sfx_volume")
			_slider("Crowd Volume", "crowd_volume")
		"Display":
			_options("Window Mode", "window_mode", ["Windowed", "Fullscreen", "Borderless Fullscreen"])
			_options("Window Size", "resolution", Settings.RESOLUTIONS.map(func(r): return "%d × %d" % [r.x, r.y]))
			_toggle("VSync", "vsync")
			_options("Graphics Quality", "quality", ["Low", "Medium", "High"], "Low reduces crowd density, shadows and post-processing. Takes effect next match.")
			_slider("UI Scale", "ui_scale", 0.75, 1.5, 0.05)
		"Gameplay":
			var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/difficulty.json"))["levels"]
			_options("Difficulty", "difficulty", levels.map(func(l): return l["name"]), "Applies to every game, including your career. Changes defensive reaction speed, coverage, tackling and simulation balance.")
			_options("Passing Assistance", "assist", ["Off", "Standard", "Full"], "Standard shows where the pass will land. Full throws with automatic lead and power.")
			_options("Game Length", "game_length", ["Quick (4 min)", "Standard (6 min)", "Extended (10 min)", "Full (15 min)"])
			_toggle("Show route overlay before the snap", "show_routes")
			_toggle("Coaching tips", "tutorial_enabled")
			var rb := UI.button("REPLAY TUTORIAL TIPS", func():
				Settings.set_value("tutorials_seen", {})
				Settings.set_value("tutorial_enabled", true)
				Audio.ui("confirm"), "secondary", 320)
			rb.tooltip_text = "Shows every coaching tip again, including the first-career walkthrough."
			_content.add_child(rb)
		"Camera":
			_slider("Camera Follow Speed", "camera_sensitivity", 0.4, 2.0, 0.05)
			_slider("Mouse Aim Sensitivity", "mouse_sensitivity", 0.4, 2.0, 0.05)
			_toggle("Camera assist (lead the ball carrier)", "camera_assist")
			_toggle("Camera shake on big hits", "camera_shake")
		"Controls":
			var g := GridContainer.new()
			g.columns = 3
			g.add_theme_constant_override("h_separation", 40)
			g.add_theme_constant_override("v_separation", 6)
			for h in ["ACTION", "KEYBOARD & MOUSE", "CONTROLLER"]:
				g.add_child(UI.label(h, 18, Palette.GOLD, "heading"))
			for b in Settings.BINDINGS:
				g.add_child(UI.label(b[0], 20, Palette.CREAM, "body_bold"))
				g.add_child(UI.label(b[1], 20, Palette.CREAM_DIM))
				g.add_child(UI.label(b[2], 20, Palette.CREAM_DIM))
			_content.add_child(g)
			var pads := Input.get_connected_joypads()
			var txt := "Controller detected: %s" % Input.get_joy_name(pads[0]) if pads.size() > 0 else "No controller detected. Connect one at any time; menus support D-pad / stick navigation."
			_content.add_child(UI.label(txt, 18, Palette.TEAL, "body_bold"))
	if _first_focus != null:
		_first_focus.call_deferred("grab_focus")

func _row(title: String, tip: String = "") -> HBoxContainer:
	var h := UI.hbox(20)
	var l := UI.label(title, 24, Palette.CREAM, "sub")
	l.custom_minimum_size = Vector2(420, 0)
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(l)
	_content.add_child(h)
	return h

func _slider(title: String, key: String, lo: float = 0.0, hi: float = 1.0, step: float = 0.05) -> void:
	var h := _row(title)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(480, 32)
	s.focus_mode = Control.FOCUS_ALL
	var val := UI.label("", 22, Palette.GOLD, "heading")
	var fmt := func(v: float) -> String:
		return "%d%%" % int(round(v * 100.0)) if hi <= 1.0 else "%.2fx" % v
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(v):
		Settings.set_value(key, v)
		val.text = fmt.call(v))
	h.add_child(s)
	h.add_child(val)
	if _first_focus == null:
		_first_focus = s

func _toggle(title: String, key: String) -> void:
	var h := _row(title)
	var c := CheckBox.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.text = "On" if c.button_pressed else "Off"
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(on):
		Settings.set_value(key, on)
		c.text = "On" if on else "Off"
		Audio.ui("click"))
	h.add_child(c)
	if _first_focus == null:
		_first_focus = c

func _options(title: String, key: String, opts: Array, tip: String = "") -> void:
	var h := _row(title, tip)
	var ob := OptionButton.new()
	for o in opts:
		ob.add_item(str(o))
	ob.selected = clampi(int(Settings.get_value(key)), 0, opts.size() - 1)
	ob.custom_minimum_size = Vector2(400, 48)
	ob.focus_mode = Control.FOCUS_ALL
	ob.add_theme_font_override("font", UI.font("sub"))
	ob.add_theme_font_size_override("font_size", 22)
	ob.item_selected.connect(func(i):
		Settings.set_value(key, i)
		Audio.ui("click"))
	h.add_child(ob)
	if _first_focus == null:
		_first_focus = ob
