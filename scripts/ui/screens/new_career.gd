class_name NewCareerScreen
extends Control
## Five-step career setup with a one-click recommended configuration.

const STEPS := ["Coach", "Franchise", "Identity", "Difficulty", "League Rules", "Confirm"]

var step: int = 0
var cfg: Dictionary = {}
var _catalog: Dictionary
var _body: VBoxContainer
var _steps_row: HBoxContainer
var _preview_logo: TeamLogo
var _preview_name: Label
var _nav_next: Button
var _nav_back: Button
var _focus: Control

func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catalog = League.load_catalog()
	cfg = {
		"coach": "Alex Rivers", "slot": _free_slot(), "team_id": "IWF", "custom": false,
		"city": "", "name": "", "abbr": "", "logo": {"shape": "shield", "emblem": "hammer"},
		"primary": "#3A3F47", "secondary": "#F28C38", "accent": "#F5F0E5",
		"difficulty": int(Settings.get_value("difficulty")), "game_length": int(Settings.get_value("game_length")),
		"assist": int(Settings.get_value("assist")), "season_games": 14, "injuries": true, "salary_cap": true, "fatigue": true,
	}
	_apply_team_defaults("IWF")
	var bg := ColorRect.new()
	bg.color = Palette.NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pattern := _Stripes.new()
	pattern.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pattern)
	var root := UI.vbox(18)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 120
	root.offset_right = -120
	root.offset_top = 70
	root.offset_bottom = -60
	add_child(root)
	var head := UI.hbox(20)
	head.add_child(UI.heading("New Career", 64, Palette.CREAM))
	head.add_child(UI.expand(UI.spacer()))
	var rec := UI.button("USE RECOMMENDED SETUP", _recommended, "ghost", 340)
	rec.tooltip_text = "Pro difficulty, standard game length, standard passing assist, 14-game season. Takes you straight to the summary."
	head.add_child(rec)
	root.add_child(head)
	_steps_row = UI.hbox(10)
	root.add_child(_steps_row)
	var main := UI.hbox(30)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	var card := UI.panel(Palette.PANEL, 18, Color(1, 1, 1, 0.06), 30)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(card)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(sc)
	_body = UI.vbox(16)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	var side := UI.panel(Palette.DEEP_BLUE, 18, Color(1, 1, 1, 0.06), 26)
	side.custom_minimum_size = Vector2(440, 0)
	main.add_child(side)
	var sv := UI.vbox(14)
	side.add_child(sv)
	sv.add_child(UI.label("YOUR FRANCHISE", 20, Palette.CREAM_DIM, "heading"))
	_preview_logo = TeamLogo.new()
	_preview_logo.custom_minimum_size = Vector2(260, 260)
	sv.add_child(_preview_logo)
	_preview_name = UI.label("", 34, Palette.CREAM, "heading")
	_preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_name.custom_minimum_size = Vector2(380, 0)
	sv.add_child(_preview_name)
	var nav := UI.hbox(12)
	_nav_back = UI.button("BACK", _back, "ghost", 180)
	_nav_next = UI.button("NEXT", _next, "primary", 220)
	nav.add_child(_nav_back)
	nav.add_child(UI.expand(UI.spacer()))
	nav.add_child(_nav_next)
	root.add_child(nav)
	_render()

func _free_slot() -> int:
	for i in SaveManager.SLOTS:
		if not SaveManager.has_save(i):
			return i
	return 0

func _apply_team_defaults(tid: String) -> void:
	for td in _catalog["teams"]:
		if td["id"] == tid:
			cfg["team_id"] = tid
			if not cfg["custom"]:
				cfg["city"] = td["city"]
				cfg["name"] = td["name"]
				cfg["abbr"] = td["abbr"]
			cfg["logo"] = td["logo"].duplicate()
			cfg["primary"] = td["primary"]
			cfg["secondary"] = td["secondary"]
			cfg["accent"] = td["accent"]
			cfg["stadium"] = td["stadium"]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()

func _render() -> void:
	for c in _steps_row.get_children():
		c.queue_free()
	for i in STEPS.size():
		var on := i == step
		var done := i < step
		var p := UI.panel(Palette.ORANGE if on else (Palette.TEAL.darkened(0.3) if done else Palette.PANEL_LIGHT), 8, Color(0, 0, 0, 0), 10)
		p.add_child(UI.label("%d  %s" % [i + 1, STEPS[i].to_upper()], 18, Palette.NAVY if on else Palette.CREAM, "heading"))
		_steps_row.add_child(p)
	for c in _body.get_children():
		c.queue_free()
	_focus = null
	match step:
		0: _step_coach()
		1: _step_franchise()
		2: _step_identity()
		3: _step_difficulty()
		4: _step_rules()
		5: _step_confirm()
	_nav_back.text = "MAIN MENU" if step == 0 else "BACK"
	_nav_next.text = "START CAREER" if step == STEPS.size() - 1 else "NEXT"
	_update_preview()
	if _focus != null:
		_focus.call_deferred("grab_focus")
	else:
		_nav_next.call_deferred("grab_focus")

func _update_preview() -> void:
	_preview_logo.configure(cfg["logo"], Color(cfg["primary"]), Color(cfg["secondary"]), Color(cfg["accent"]), str(cfg["name"]).substr(0, 1))
	_preview_name.text = ("%s %s" % [cfg["city"], cfg["name"]]).to_upper() + "\n" + str(cfg["abbr"])

func _title(t: String, sub: String = "") -> void:
	_body.add_child(UI.heading(t, 40, Palette.GOLD))
	if sub != "":
		var l := UI.label(sub, 20, Palette.CREAM_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(900, 0)
		_body.add_child(l)

func _step_coach() -> void:
	_title("Who's the new head coach?", "Your name will appear on the franchise history and records.")
	var le := LineEdit.new()
	le.text = cfg["coach"]
	le.max_length = 24
	le.custom_minimum_size = Vector2(520, 58)
	le.text_changed.connect(func(t): cfg["coach"] = t.strip_edges())
	_body.add_child(le)
	_focus = le
	_body.add_child(UI.spacer(0, 10))
	_body.add_child(UI.label("SAVE SLOT", 20, Palette.CREAM_DIM, "heading"))
	var row := UI.hbox(10)
	for i in SaveManager.SLOTS:
		var info := SaveManager.slot_info(i)
		var txt := "Slot %d — %s" % [i + 1, "Empty" if info.is_empty() else str(info.get("team", "In use"))]
		var b := UI.button(txt, func():
			cfg["slot"] = i
			_render(), "primary" if cfg["slot"] == i else "secondary", 280)
		if not info.is_empty():
			b.tooltip_text = "Starting here will overwrite this career when you confirm."
		row.add_child(b)
	_body.add_child(row)
	if SaveManager.has_save(int(cfg["slot"])):
		_body.add_child(UI.label("Warning: slot %d already holds a career. It will be replaced." % (int(cfg["slot"]) + 1), 19, Palette.RED, "body_bold"))

func _step_franchise() -> void:
	_title("Choose your franchise", "Every club in the %s is fictional. The team you pick becomes an overlooked franchise with a thin roster — and one raw quarterback prospect." % _catalog["league_name"])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for td in _catalog["teams"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 120)
		b.focus_mode = Control.FOCUS_ALL
		var sel: bool = cfg["team_id"] == td["id"]
		b.add_theme_stylebox_override("normal", UI.box(Color(td["primary"]).darkened(0.45) if sel else Palette.PANEL_LIGHT, 10, Palette.ORANGE if sel else Color(1, 1, 1, 0.06), 3 if sel else 1, 10))
		b.add_theme_stylebox_override("hover", UI.box(Color(td["primary"]).darkened(0.35), 10, Palette.ORANGE, 2, 10))
		b.add_theme_stylebox_override("focus", UI.box(Color(0, 0, 0, 0), 10, Palette.GOLD, 3, 10))
		var h := UI.hbox(10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.position = Vector2(10, 14)
		var logo := TeamLogo.new()
		logo.configure(td["logo"], Color(td["primary"]), Color(td["secondary"]), Color(td["accent"]), str(td["name"]).substr(0, 1))
		logo.custom_minimum_size = Vector2(80, 80)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(logo)
		var v := UI.vbox(0)
		v.add_child(UI.label(str(td["city"]).to_upper(), 16, Palette.CREAM_DIM, "heading"))
		v.add_child(UI.label(str(td["name"]).to_upper(), 26, Palette.CREAM, "heading"))
		v.add_child(UI.label("%s · %s" % [str(td["stadium"]).capitalize(), _catalog["conferences"][int(td["conf"])]], 14, Palette.MUTED, "semi"))
		for c in v.get_children():
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		b.add_child(h)
		b.pressed.connect(func():
			cfg["custom"] = false
			_apply_team_defaults(td["id"])
			Audio.ui("click")
			_render())
		grid.add_child(b)
		if sel:
			_focus = b
	_body.add_child(grid)

func _step_identity() -> void:
	_title("Make it yours", "Keep the club's identity or rebrand it with an original city, name, logo and colors.")
	var custom := CheckBox.new()
	custom.text = "Rebrand the franchise"
	custom.button_pressed = cfg["custom"]
	custom.toggled.connect(func(on):
		cfg["custom"] = on
		if on:
			cfg["city"] = _catalog["custom_cities"][0]
			cfg["name"] = _catalog["custom_names"][0]
			cfg["abbr"] = _abbr_for(cfg["city"])
		else:
			_apply_team_defaults(cfg["team_id"])
		_render())
	_body.add_child(custom)
	_focus = custom
	if cfg["custom"]:
		_body.add_child(_picker("Home City", _catalog["custom_cities"], cfg["city"], func(v):
			cfg["city"] = v
			cfg["abbr"] = _abbr_for(v)
			_update_preview()))
		_body.add_child(_picker("Team Name", _catalog["custom_names"], cfg["name"], func(v):
			cfg["name"] = v
			_update_preview()))
	_body.add_child(_picker("Logo Shape", _catalog["logo_shapes"], cfg["logo"]["shape"], func(v):
		cfg["logo"]["shape"] = v
		_update_preview()))
	_body.add_child(_picker("Emblem", _catalog["logo_emblems"], cfg["logo"]["emblem"], func(v):
		cfg["logo"]["emblem"] = v
		_update_preview()))
	_body.add_child(UI.label("TEAM COLORS", 20, Palette.CREAM_DIM, "heading"))
	var row := UI.hbox(10)
	for preset in _catalog["color_presets"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 56)
		b.focus_mode = Control.FOCUS_ALL
		var st := UI.box(Color(preset[0]), 8, Color(preset[1]), 4, 4)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", UI.box(Color(preset[0]).lightened(0.1), 8, Palette.GOLD, 4, 4))
		b.add_theme_stylebox_override("focus", UI.box(Color(0, 0, 0, 0), 8, Palette.GOLD, 3, 4))
		b.pressed.connect(func():
			cfg["primary"] = preset[0]
			cfg["secondary"] = preset[1]
			cfg["accent"] = preset[2]
			Audio.ui("click")
			_update_preview())
		row.add_child(b)
	var keep := UI.button("Original", func():
		var keep_custom: bool = cfg["custom"]
		var c: String = cfg["city"]
		var n: String = cfg["name"]
		var a: String = cfg["abbr"]
		var lg: Dictionary = cfg["logo"].duplicate()
		_apply_team_defaults(cfg["team_id"])
		cfg["logo"] = lg
		if keep_custom:
			cfg["city"] = c
			cfg["name"] = n
			cfg["abbr"] = a
		_update_preview(), "ghost", 140)
	row.add_child(keep)
	_body.add_child(row)

func _abbr_for(city: String) -> String:
	var parts := city.split(" ")
	if parts.size() >= 2:
		return (parts[0].substr(0, 2) + parts[1].substr(0, 1)).to_upper()
	return city.substr(0, 3).to_upper()

func _picker(title: String, options: Array, current: String, cb: Callable) -> Control:
	var h := UI.hbox(14)
	var l := UI.label(title, 22, Palette.CREAM, "sub")
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	var ob := OptionButton.new()
	for o in options:
		ob.add_item(str(o).capitalize() if title in ["Logo Shape", "Emblem"] else str(o))
	ob.selected = maxi(0, options.find(current))
	ob.custom_minimum_size = Vector2(360, 50)
	ob.add_theme_font_override("font", UI.font("sub"))
	ob.add_theme_font_size_override("font_size", 22)
	ob.item_selected.connect(func(i): cb.call(options[i]))
	h.add_child(ob)
	return h

func _choice_row(title: String, opts: Array, key: String, descs: Array = []) -> void:
	_body.add_child(UI.label(title.to_upper(), 20, Palette.CREAM_DIM, "heading"))
	var row := UI.hbox(10)
	for i in opts.size():
		var b := UI.button(str(opts[i]), func():
			cfg[key] = i
			Audio.ui("click")
			_render(), "primary" if int(cfg[key]) == i else "secondary", 210)
		if descs.size() > i:
			b.tooltip_text = str(descs[i])
		row.add_child(b)
		if int(cfg[key]) == i and _focus == null:
			_focus = b
	_body.add_child(row)
	if descs.size() > int(cfg[key]):
		_body.add_child(UI.label(str(descs[int(cfg[key])]), 18, Palette.TEAL, "body_bold"))

func _step_difficulty() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/difficulty.json"))
	_title("How do you want to play?", "You can change these later in Settings.")
	_choice_row("Difficulty", d["levels"].map(func(l): return l["name"]), "difficulty", d["levels"].map(func(l): return l["desc"]))
	_choice_row("Game Length", d["game_lengths"].map(func(l): return l["name"]), "game_length", d["game_lengths"].map(func(l): return l["desc"]))
	_choice_row("Passing Assistance", d["assist"].map(func(l): return l["name"]), "assist", d["assist"].map(func(l): return l["desc"]))

func _step_rules() -> void:
	_title("League rules", "Optional simulation settings for your league.")
	_body.add_child(UI.label("SEASON LENGTH", 20, Palette.CREAM_DIM, "heading"))
	var row := UI.hbox(10)
	for n in [10, 14, 15]:
		var b := UI.button("%d games" % n, func():
			cfg["season_games"] = n
			_render(), "primary" if int(cfg["season_games"]) == n else "secondary", 200)
		row.add_child(b)
		if int(cfg["season_games"]) == n:
			_focus = b
	_body.add_child(row)
	for opt in [["injuries", "Injuries", "Players can miss games after injuries. Medical upgrades shorten them."], ["salary_cap", "Salary cap ($%dM)" % int(League.SALARY_CAP), "Enforce the salary cap on signings and trades."], ["fatigue", "Fatigue", "Starters tire across games and recover during the week."]]:
		var c := CheckBox.new()
		c.text = opt[1]
		c.tooltip_text = opt[2]
		c.button_pressed = cfg[opt[0]]
		c.toggled.connect(func(on): cfg[opt[0]] = on)
		_body.add_child(c)
	_body.add_child(UI.label("Playoffs: 8 teams (two division winners + two wild cards per conference). Ties possible in the regular season after one overtime period.", 18, Palette.CREAM_DIM))

func _step_confirm() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/difficulty.json"))
	_title("Ready to build a dynasty?")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 8)
	var rows := [
		["Coach", cfg["coach"]], ["Franchise", "%s %s (%s)" % [cfg["city"], cfg["name"], cfg["abbr"]]],
		["Difficulty", d["levels"][cfg["difficulty"]]["name"]], ["Game Length", d["game_lengths"][cfg["game_length"]]["name"]],
		["Passing Assist", d["assist"][cfg["assist"]]["name"]], ["Season", "%d games + playoffs" % cfg["season_games"]],
		["Injuries / Cap / Fatigue", "%s / %s / %s" % ["On" if cfg["injuries"] else "Off", "On" if cfg["salary_cap"] else "Off", "On" if cfg["fatigue"] else "Off"]],
		["Save Slot", "Slot %d%s" % [int(cfg["slot"]) + 1, " (overwrites existing)" if SaveManager.has_save(int(cfg["slot"])) else ""]],
	]
	for r in rows:
		g.add_child(UI.label(str(r[0]).to_upper(), 20, Palette.CREAM_DIM, "heading"))
		g.add_child(UI.label(str(r[1]), 24, Palette.CREAM, "sub"))
	_body.add_child(g)

func _recommended() -> void:
	cfg["difficulty"] = 1
	cfg["game_length"] = 1
	cfg["assist"] = 1
	cfg["season_games"] = 14
	cfg["injuries"] = true
	cfg["salary_cap"] = true
	cfg["fatigue"] = true
	if str(cfg["coach"]).strip_edges() == "":
		cfg["coach"] = "Alex Rivers"
	step = STEPS.size() - 1
	Audio.ui("confirm")
	_render()

func _back() -> void:
	if step == 0:
		App.go_main_menu()
		return
	step -= 1
	Audio.ui("back")
	_render()

func _next() -> void:
	if step == 0 and str(cfg["coach"]).strip_edges() == "":
		App.toast("Enter a coach name")
		Audio.ui("error")
		return
	if step < STEPS.size() - 1:
		step += 1
		Audio.ui("click")
		_render()
		return
	_start()

func _start() -> void:
	Audio.ui("confirm")
	Settings.set_value("difficulty", cfg["difficulty"])
	Settings.set_value("game_length", cfg["game_length"])
	Settings.set_value("assist", cfg["assist"])
	var config := {
		"coach": cfg["coach"], "team_id": cfg["team_id"], "city": cfg["city"], "name": cfg["name"], "abbr": cfg["abbr"],
		"primary": cfg["primary"], "secondary": cfg["secondary"], "accent": cfg["accent"], "logo": cfg["logo"],
		"settings": {"difficulty": cfg["difficulty"], "game_length": cfg["game_length"], "assist": cfg["assist"],
			"season_games": cfg["season_games"], "injuries": cfg["injuries"], "salary_cap": cfg["salary_cap"], "fatigue": cfg["fatigue"]},
	}
	SaveManager.delete_slot(int(cfg["slot"]))
	App.start_career(config, int(cfg["slot"]))


## Subtle diagonal field-stripe pattern used behind menu screens.
class _Stripes extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var step := 90.0
		var x := -h
		while x < w:
			draw_line(Vector2(x, h), Vector2(x + h, 0), Color(1, 1, 1, 0.025), 30.0)
			x += step
		draw_rect(Rect2(0, h - 8, w, 8), Palette.ORANGE)
