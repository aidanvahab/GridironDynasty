class_name RecordsScreen
extends Control
## Career summaries across all saves plus the latest career's league records.

func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 120
	sc.offset_right = -120
	sc.offset_top = 60
	sc.offset_bottom = -40
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var v := UI.vbox(16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var head := UI.hbox(20)
	head.add_child(UI.heading("Records", 64))
	head.add_child(UI.expand(UI.spacer()))
	var back := UI.button("BACK", func(): App.go_main_menu(), "primary", 200)
	head.add_child(back)
	v.add_child(head)
	back.call_deferred("grab_focus")
	var rec := SaveManager.load_records()
	var cp := UI.panel(Palette.PANEL, 16, Color(1, 1, 1, 0.05), 22)
	var cv := UI.vbox(8)
	cp.add_child(cv)
	cv.add_child(UI.heading("Coaching Careers", 30))
	var careers: Array = rec.get("careers", [])
	careers.sort_custom(func(a, b): return int(a.get("titles", 0)) * 100 + int(a.get("wins", 0)) > int(b.get("titles", 0)) * 100 + int(b.get("wins", 0)))
	if careers.is_empty():
		cv.add_child(UI.label("No careers yet. Start one from the main menu.", 20, Palette.CREAM_DIM))
	for c in careers:
		var h := UI.hbox(14)
		var logo := TeamLogo.new()
		logo.configure(c.get("logo", {}), Color(str(c.get("primary", "F28C38"))), Color(str(c.get("secondary", "F5F0E5"))), Palette.NAVY)
		logo.custom_minimum_size = Vector2(48, 48)
		h.add_child(logo)
		h.add_child(UI.label("Coach %s — %s" % [c.get("coach", ""), c.get("team", "")], 22, Palette.CREAM, "sub"))
		h.add_child(UI.label("%d seasons · %d-%d · %d title%s" % [int(c.get("seasons", 0)), int(c.get("wins", 0)), int(c.get("losses", 0)), int(c.get("titles", 0)), "s" if int(c.get("titles", 0)) != 1 else ""], 20, Palette.GOLD, "body_bold"))
		cv.add_child(h)
	v.add_child(cp)
	var latest := SaveManager.latest_slot()
	if latest < 0:
		return
	var lg: League = SaveManager.load_league(latest)
	if lg == null:
		return
	var lp := UI.panel(Palette.PANEL, 16, Color(1, 1, 1, 0.05), 22)
	var lv := UI.vbox(6)
	lp.add_child(lv)
	lv.add_child(UI.heading("%s Records" % lg.league_name, 30))
	lv.add_child(UI.label("From your most recent career (%s)" % lg.user_team().full_name(), 18, Palette.CREAM_DIM))
	var r: Dictionary = lg.history.get("records", {})
	if r.is_empty():
		lv.add_child(UI.label("Records are set at the end of each season.", 19, Palette.CREAM_DIM))
	for key in Awards.RECORD_STATS:
		var s: Dictionary = r.get("season", {}).get(key, {})
		if s.is_empty():
			continue
		var c: Dictionary = r.get("career", {}).get(key, {})
		lv.add_child(UI.label("%s: season %d (%s, %d)  ·  career %d (%s)" % [Awards.RECORD_STATS[key], int(s["value"]), s["name"], int(s["year"]), int(c.get("value", 0)), c.get("name", "-")], 20, Palette.CREAM, "body_bold"))
	lv.add_child(UI.heading("Champions", 26, Palette.GOLD))
	for ch in lg.history.get("champions", []):
		lv.add_child(UI.label("%d — %s" % [int(ch["year"]), ch["name"]], 20, Palette.CREAM, "body_bold"))
	lv.add_child(UI.heading("Hall of Legends", 26, Palette.GOLD))
	for h in lg.history.get("hall", []):
		lv.add_child(UI.label("%s (%s), retired %d" % [h["name"], h["pos"], int(h["year"])], 20, Palette.CREAM, "body_bold"))
	v.add_child(lp)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		App.go_main_menu()
