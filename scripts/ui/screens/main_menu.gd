class_name MainMenu
extends Node3D
## Animated main menu over a live 3D stadium.

var _ui: Control
var _menu: VBoxContainer
var _cam: BroadcastCamera
var _stadium: StadiumBuilder
var _rigs: Array[PlayerRig] = []
var _panel_host: Control
var _first: Button

func _ready() -> void:
	_build_world()
	_build_ui()
	Audio.music("music_menu")
	Audio.crowd_start(0.2)

func _build_world() -> void:
	var cat := League.load_catalog()
	var td: Dictionary = cat["teams"][randi() % cat["teams"].size()]
	var prim := Color(td["primary"])
	var sec := Color(td["secondary"])
	var quality := int(Settings.get_value("quality"))
	_stadium = StadiumBuilder.new()
	add_child(_stadium)
	_stadium.build(["classic", "modern", "historic"][randi() % 3], prim, sec, Color("#42B7AD"), "night", [0.3, 0.55, 0.85][quality], randi())
	_stadium.apply_quality(quality)
	_stadium.set_excitement(0.35)
	var field := FieldBuilder.new()
	add_child(field)
	field.build(prim, Color("#1A2C45"), td["name"], "Dynasty", UI.font("heading"))
	field.hide_down_markers()
	# A few players warming up at midfield.
	var font := UI.font("heading")
	for i in 7:
		var r := PlayerRig.new()
		add_child(r)
		var home := i % 2 == 0
		r.build(prim if home else Palette.CREAM, Palette.CREAM if home else prim, prim, sec, Color("#C8CED6"), [12, 88, 24, 55, 7, 31, 99][i], i % 6, 1.0 + (i % 3) * 0.1, font)
		r.position = Vector3(-8.0 + i * 2.6, 0, -3.0 + (i % 3) * 2.5)
		r.rotation.y = randf() * TAU
		r.set_pose([PlayerRig.Pose.IDLE, PlayerRig.Pose.STANCE2, PlayerRig.Pose.CELEBRATE, PlayerRig.Pose.STANCE3, PlayerRig.Pose.QB_SET, PlayerRig.Pose.IDLE, PlayerRig.Pose.RUN][i])
		r.pose_time = randf() * 2.0
		_rigs.append(r)
	_cam = BroadcastCamera.new()
	add_child(_cam)
	_cam.orbit_radius = 48.0
	_cam.orbit_height = 15.0
	_cam.orbit_angle = 0.6
	_cam.set_mode(BroadcastCamera.Mode.ORBIT, true)

func _process(delta: float) -> void:
	for r in _rigs:
		r.animate(delta)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UI.theme()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	# Left vignette for legibility.
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(Palette.NAVY, 0.94))
	g.set_color(1, Color(Palette.NAVY, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 1100
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(grad)
	var root := UI.vbox(10)
	root.position = Vector2(110, 110)
	_ui.add_child(root)
	# Logo lockup.
	var mark := UI.hbox(18)
	var ball := TeamLogo.new()
	ball.configure({"shape": "circle", "emblem": "star"}, Palette.ORANGE, Palette.CREAM, Palette.NAVY)
	ball.custom_minimum_size = Vector2(86, 86)
	mark.add_child(ball)
	var words := UI.vbox(-18)
	var l1 := UI.label("GRIDIRON", 104, Palette.CREAM, "display")
	l1.add_theme_constant_override("outline_size", 14)
	l1.add_theme_color_override("font_outline_color", Palette.NAVY)
	var l2 := UI.label("DYNASTY", 128, Palette.ORANGE, "display")
	l2.add_theme_constant_override("outline_size", 14)
	l2.add_theme_color_override("font_outline_color", Palette.NAVY)
	words.add_child(l1)
	words.add_child(l2)
	mark.add_child(words)
	root.add_child(mark)
	var stripe := UI.hbox(6)
	for c in [Palette.ORANGE, Palette.TEAL, Palette.GOLD]:
		var cr := ColorRect.new()
		cr.color = c
		cr.custom_minimum_size = Vector2(120, 6)
		stripe.add_child(cr)
	root.add_child(stripe)
	root.add_child(UI.label("Build a legend. One snap at a time.", 26, Palette.CREAM_DIM, "semi"))
	root.add_child(UI.spacer(0, 30))
	_menu = UI.vbox(12)
	root.add_child(_menu)
	_panel_host = Control.new()
	_panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_panel_host)
	var ver := UI.label("v%s  ·  Offline single-player" % ProjectSettings.get_setting("application/config/version", "1.0.0"), 16, Palette.MUTED)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	UI.place_at(ver, Vector2(110, -50))
	_ui.add_child(ver)
	_build_menu()
	UI.pop_in(root)

func _build_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()
	var latest := SaveManager.latest_slot()
	_first = null
	if latest >= 0:
		var info := SaveManager.slot_info(latest)
		var cont := UI.button("CONTINUE CAREER", func(): App.load_career(latest), "primary", 520)
		cont.custom_minimum_size = Vector2(520, 66)
		cont.add_theme_font_size_override("font_size", 30)
		_menu.add_child(cont)
		_menu.add_child(_save_card(info))
		_first = cont
	var nc := UI.button("NEW CAREER", _new_career, "primary" if latest < 0 else "secondary", 520)
	_menu.add_child(nc)
	if _first == null:
		_first = nc
	if SaveManager.any_save():
		_menu.add_child(UI.button("LOAD CAREER", _show_slots, "secondary", 520))
	_menu.add_child(UI.button("QUICK MATCH", _show_quick_match, "secondary", 520))
	_menu.add_child(UI.button("RECORDS", func(): App.go_records(), "secondary", 520))
	_menu.add_child(UI.button("SETTINGS", _show_settings, "secondary", 520))
	_menu.add_child(UI.button("QUIT", func(): App.quit_game(), "ghost", 520))
	_first.call_deferred("grab_focus")

func _save_card(info: Dictionary) -> Control:
	var p := UI.panel(Color(Palette.PANEL, 0.85), 10, Color(1, 1, 1, 0.06), 12)
	p.custom_minimum_size = Vector2(520, 0)
	var h := UI.hbox(14)
	var logo := TeamLogo.new()
	logo.configure(info.get("logo", {}), Color(str(info.get("primary", "F28C38"))), Color(str(info.get("secondary", "F5F0E5"))), Palette.NAVY)
	logo.custom_minimum_size = Vector2(56, 56)
	h.add_child(logo)
	var v := UI.vbox(0)
	v.add_child(UI.label(str(info.get("team", "")).to_upper(), 24, Palette.CREAM, "heading"))
	var phase_txt: String = ["Regular Season", "Playoffs", "Offseason"][clampi(int(info.get("phase", 0)), 0, 2)]
	var titles := int(info.get("titles", 0))
	v.add_child(UI.label("Coach %s  ·  %d %s  ·  %s%s" % [info.get("coach", ""), int(info.get("year", 0)), phase_txt, str(info.get("record", "0-0")), ("  ·  %d title%s" % [titles, "s" if titles != 1 else ""]) if titles > 0 else ""], 18, Palette.CREAM_DIM, "body_bold"))
	h.add_child(v)
	p.add_child(h)
	return p

func _clear_panel() -> void:
	for c in _panel_host.get_children():
		c.queue_free()

func _modal(width: int) -> VBoxContainer:
	_clear_panel()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_host.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_host.add_child(center)
	var p := UI.panel(Palette.NAVY, 20, Palette.PANEL_LIGHT, 28)
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	UI.pop_in(p)
	return v

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel_host.get_child_count() > 0:
		_clear_panel()
		_first.call_deferred("grab_focus")
		get_viewport().set_input_as_handled()

func _new_career() -> void:
	App.go_new_career()

func _show_settings() -> void:
	var sp := SettingsPanel.new()
	_ui.add_child(sp)
	sp.closed.connect(func(): _first.call_deferred("grab_focus"))

func _show_slots() -> void:
	var v := _modal(860)
	v.add_child(UI.heading("Load Career", 48))
	var focus: Button = null
	for i in SaveManager.SLOTS:
		var info := SaveManager.slot_info(i)
		var row := UI.hbox(12)
		if info.is_empty():
			row.add_child(UI.label("Slot %d — empty" % (i + 1), 22, Palette.MUTED, "sub"))
		else:
			var b := UI.button("SLOT %d" % (i + 1), func(): App.load_career(i), "primary", 140)
			row.add_child(b)
			if focus == null:
				focus = b
			row.add_child(_save_card(info))
			var del := UI.button("DELETE", func(): _confirm_delete(i), "danger", 120)
			del.tooltip_text = "Permanently delete this career."
			row.add_child(del)
		v.add_child(row)
	var back := UI.button("BACK", func():
		_clear_panel()
		_first.grab_focus(), "ghost", 200)
	v.add_child(back)
	(focus if focus != null else back).call_deferred("grab_focus")

func _confirm_delete(i: int) -> void:
	var v := _modal(640)
	v.add_child(UI.heading("Delete Career?", 44, Palette.RED))
	var info := SaveManager.slot_info(i)
	v.add_child(UI.label("%s (%s) in slot %d will be permanently deleted, including its backup. This cannot be undone." % [info.get("team", ""), info.get("coach", ""), i + 1], 21, Palette.CREAM).duplicate())
	var h := UI.hbox(12)
	var cancel := UI.button("CANCEL", _show_slots, "secondary", 200)
	h.add_child(cancel)
	h.add_child(UI.button("DELETE", func():
		SaveManager.delete_slot(i)
		Audio.ui("back")
		App.toast("Career deleted")
		_clear_panel()
		_build_menu(), "danger", 200))
	v.add_child(h)
	cancel.call_deferred("grab_focus")

func _show_quick_match() -> void:
	var v := _modal(1000)
	v.add_child(UI.heading("Quick Match", 48))
	v.add_child(UI.label("Pick any two franchises. You control the offense of your team.", 21, Palette.CREAM_DIM))
	var cat := League.load_catalog()
	var teams: Array = cat["teams"]
	var sel := {"you": 0, "opp": 1, "home": true, "tod": 1}
	var row := UI.hbox(30)
	var you_box := UI.vbox(8)
	var opp_box := UI.vbox(8)
	var you_label := UI.label("", 28, Palette.ORANGE, "heading")
	var opp_label := UI.label("", 28, Palette.TEAL, "heading")
	var you_logo := TeamLogo.new()
	you_logo.custom_minimum_size = Vector2(110, 110)
	var opp_logo := TeamLogo.new()
	opp_logo.custom_minimum_size = Vector2(110, 110)
	var refresh := func():
		var a: Dictionary = teams[sel["you"]]
		var b: Dictionary = teams[sel["opp"]]
		you_label.text = "%s %s" % [a["city"], a["name"]]
		opp_label.text = "%s %s" % [b["city"], b["name"]]
		you_logo.configure(a["logo"], Color(a["primary"]), Color(a["secondary"]), Color(a["accent"]), str(a["name"]).substr(0, 1))
		opp_logo.configure(b["logo"], Color(b["primary"]), Color(b["secondary"]), Color(b["accent"]), str(b["name"]).substr(0, 1))
	you_box.add_child(UI.label("YOUR TEAM", 18, Palette.CREAM_DIM, "heading"))
	you_box.add_child(you_logo)
	you_box.add_child(you_label)
	var yb := UI.hbox(8)
	yb.add_child(UI.button("◀", func():
		sel["you"] = (sel["you"] - 1 + teams.size()) % teams.size()
		if sel["you"] == sel["opp"]: sel["you"] = (sel["you"] - 1 + teams.size()) % teams.size()
		refresh.call(), "secondary", 70))
	yb.add_child(UI.button("▶", func():
		sel["you"] = (sel["you"] + 1) % teams.size()
		if sel["you"] == sel["opp"]: sel["you"] = (sel["you"] + 1) % teams.size()
		refresh.call(), "secondary", 70))
	you_box.add_child(yb)
	opp_box.add_child(UI.label("OPPONENT", 18, Palette.CREAM_DIM, "heading"))
	opp_box.add_child(opp_logo)
	opp_box.add_child(opp_label)
	var ob := UI.hbox(8)
	ob.add_child(UI.button("◀", func():
		sel["opp"] = (sel["opp"] - 1 + teams.size()) % teams.size()
		if sel["you"] == sel["opp"]: sel["opp"] = (sel["opp"] - 1 + teams.size()) % teams.size()
		refresh.call(), "secondary", 70))
	ob.add_child(UI.button("▶", func():
		sel["opp"] = (sel["opp"] + 1) % teams.size()
		if sel["you"] == sel["opp"]: sel["opp"] = (sel["opp"] + 1) % teams.size()
		refresh.call(), "secondary", 70))
	opp_box.add_child(ob)
	row.add_child(you_box)
	row.add_child(UI.label("VS", 54, Palette.GOLD, "display"))
	row.add_child(opp_box)
	v.add_child(row)
	var opts := UI.hbox(12)
	var venue := UI.button("Venue: Home", Callable(), "ghost", 220)
	venue.pressed.connect(func():
		sel["home"] = not sel["home"]
		venue.text = "Venue: " + ("Home" if sel["home"] else "Away"))
	opts.add_child(venue)
	var tod := UI.button("Kickoff: Evening", Callable(), "ghost", 260)
	tod.pressed.connect(func():
		sel["tod"] = (sel["tod"] + 1) % 3
		tod.text = "Kickoff: " + ["Day", "Evening", "Night"][sel["tod"]])
	opts.add_child(tod)
	v.add_child(opts)
	refresh.call()
	var go := UI.button("KICK OFF", func():
		var you: String = teams[sel["you"]]["id"]
		var opp: String = teams[sel["opp"]]["id"]
		var settings := {"difficulty": Settings.get_value("difficulty"), "assist": Settings.get_value("assist"), "game_length": Settings.get_value("game_length")}
		App.start_quick_match(you if sel["home"] else opp, opp if sel["home"] else you, sel["home"], ["day", "evening", "night"][sel["tod"]], settings), "primary", 300)
	var h := UI.hbox(12)
	h.add_child(go)
	h.add_child(UI.button("BACK", func():
		_clear_panel()
		_first.grab_focus(), "ghost", 180))
	v.add_child(h)
	go.call_deferred("grab_focus")
