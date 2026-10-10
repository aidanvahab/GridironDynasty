class_name MatchHUD
extends Control
## In-match interface. Pure presentation: it reads state passed in by the
## MatchController and reports the player's choices through signals.

signal play_chosen(play_id: String, flip: bool, tempo: int)
signal special_chosen(kind: String)
signal try_chosen(kind: String)
signal continue_pressed(tag: String)
signal pause_action(action: String)

var home: Team
var away: Team
var user_side: int = 0
var _bug: PanelContainer
var _bug_labels: Dictionary = {}
var _feedback: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _hints: Label
var _charge: ProgressBar
var _charge_box: Control
var _pressure: Label
var _playselect: Control
var _ps_grid: GridContainer
var _ps_detail_diag: PlayDiagram
var _ps_detail_name: Label
var _ps_detail_desc: Label
var _ps_detail_sit: Label
var _ps_detail_rr: Label
var _ps_situation: Label
var _ps_tabs: HBoxContainer
var _ps_special: HBoxContainer
var _ps_selected: String = ""
var _ps_flip: bool = false
var _ps_tempo: int = RulesEngine.Tempo.NORMAL
var _ps_tempo_btn: Button
var _ps_category: String = "suggested"
var _ps_ctx: Dictionary = {}
var _ps_call_btn: Button
var _drive: PanelContainer
var _drive_title: Label
var _drive_list: VBoxContainer
var _drive_bar: Control
var _overlay: Control
var _pause: Control
var _debug: Label
var _kick_panel: PanelContainer
var _kick_aim: Label
var _kick_meter: ProgressBar
var _kick_info: Label
var _toast: Label
var _modal_open: bool = false

func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_scorebug()
	_build_feedback()
	_build_hints()
	_build_charge()
	_build_play_select()
	_build_drive()
	_build_kick_panel()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_debug = UI.label("", 16, Palette.GREEN, "body_bold")
	_debug.position = Vector2(20, 120)
	_debug.visible = false
	add_child(_debug)
	_toast = UI.label("", 24, Palette.GOLD, "sub")
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.custom_minimum_size = Vector2(600, 0)
	UI.place_at(_toast, Vector2(-300, 140))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)

func set_teams(h: Team, a: Team, p_user_side: int) -> void:
	home = h
	away = a
	user_side = p_user_side
	for side in 2:
		var t := home if side == 0 else away
		var box: Dictionary = _bug_labels["side%d" % side]
		(box["logo"] as TeamLogo).configure(t.logo, t.primary, t.secondary, t.accent, t.name.substr(0, 1))
		(box["abbr"] as Label).text = t.abbr
		(box["panel"] as PanelContainer).add_theme_stylebox_override("panel", UI.box(t.primary.darkened(0.25), 8, t.secondary, 0, 10))

# ================================================================= scorebug

func _build_scorebug() -> void:
	_bug = UI.panel(Color(Palette.NAVY, 0.92), 12, Color(1, 1, 1, 0.08), 8)
	_bug.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bug.custom_minimum_size = Vector2(940, 0)
	UI.place_at(_bug, Vector2(-470, 18))
	add_child(_bug)
	var row := UI.hbox(8)
	_bug.add_child(row)
	for side in [1, 0]: # away first, then home
		var p := UI.panel(Palette.PANEL_LIGHT, 8, Color(0, 0, 0, 0), 8)
		var h := UI.hbox(8)
		p.add_child(h)
		var logo := TeamLogo.new()
		logo.custom_minimum_size = Vector2(40, 40)
		h.add_child(logo)
		var abbr := UI.label("---", 30, Palette.CREAM, "heading")
		h.add_child(abbr)
		var poss := UI.label("•", 40, Palette.ORANGE, "heading")
		poss.visible = false
		h.add_child(poss)
		var score := UI.label("0", 38, Palette.CREAM, "display")
		score.custom_minimum_size = Vector2(52, 0)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(score)
		var to := UI.label("", 14, Palette.GOLD, "heading")
		h.add_child(to)
		row.add_child(p)
		_bug_labels["side%d" % side] = {"panel": p, "logo": logo, "abbr": abbr, "score": score, "poss": poss, "to": to}
	var mid := UI.vbox(0)
	mid.custom_minimum_size = Vector2(110, 0)
	var q := UI.label("Q1", 22, Palette.GOLD, "heading")
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var clock := UI.label("15:00", 30, Palette.CREAM, "display")
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(q)
	mid.add_child(clock)
	row.add_child(mid)
	var dd := UI.vbox(0)
	dd.custom_minimum_size = Vector2(190, 0)
	var down := UI.label("", 26, Palette.ORANGE, "heading")
	var spot := UI.label("", 18, Palette.CREAM_DIM, "semi")
	dd.add_child(down)
	dd.add_child(spot)
	row.add_child(dd)
	_bug_labels["q"] = q
	_bug_labels["clock"] = clock
	_bug_labels["down"] = down
	_bug_labels["spot"] = spot

func update_scorebug(rules: RulesEngine, live_elapsed: float = 0.0) -> void:
	var s := rules.state
	for side in 2:
		var b: Dictionary = _bug_labels["side%d" % side]
		(b["score"] as Label).text = str(s.score[side])
		(b["poss"] as Label).visible = s.phase == GameState.Phase.SCRIMMAGE and s.possession == side
		(b["to"] as Label).text = "•".repeat(s.timeouts[side])
	(_bug_labels["q"] as Label).text = rules.quarter_label()
	# During a live snap the broadcast clock ticks down in real time; the rules
	# engine charges the exact elapsed time when the play ends.
	(_bug_labels["clock"] as Label).text = RulesEngine.format_clock(maxf(0.0, s.clock - live_elapsed))
	var down_txt := rules.describe_down()
	if s.phase == GameState.Phase.KICKOFF:
		down_txt = "KICKOFF"
	elif s.phase == GameState.Phase.GAME_OVER:
		down_txt = "FINAL"
	(_bug_labels["down"] as Label).text = down_txt
	var spot_txt := ""
	if s.phase == GameState.Phase.SCRIMMAGE:
		var off := home if s.possession == 0 else away
		var dfn := away if s.possession == 0 else home
		spot_txt = "Ball on " + FieldCoords.describe_spot(s.ball_on, off.abbr, dfn.abbr)
	(_bug_labels["spot"] as Label).text = spot_txt

# ================================================================= feedback

func _build_feedback() -> void:
	_feedback = UI.label("", 34, Palette.CREAM, "heading")
	_feedback.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_feedback.custom_minimum_size = Vector2(900, 0)
	UI.place_at(_feedback, Vector2(-450, 128))
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_constant_override("outline_size", 10)
	_feedback.add_theme_color_override("font_outline_color", Palette.NAVY)
	_feedback.modulate.a = 0.0
	add_child(_feedback)
	_banner = UI.panel(Palette.NAVY, 16, Palette.ORANGE, 24)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.custom_minimum_size = Vector2(760, 0)
	UI.place_at(_banner, Vector2(-380, -170))
	var v := UI.vbox(2)
	_banner_title = UI.label("", 84, Palette.CREAM, "display")
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub = UI.label("", 26, Palette.CREAM_DIM, "sub")
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_title)
	v.add_child(_banner_sub)
	_banner.add_child(v)
	_banner.visible = false
	add_child(_banner)

func show_feedback(text: String, color: Color = Palette.CREAM, big: bool = false) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", color)
	_feedback.add_theme_font_size_override("font_size", 46 if big else 34)
	var tw := create_tween()
	_feedback.modulate.a = 1.0
	_feedback.scale = Vector2(1.08, 1.08)
	_feedback.pivot_offset = _feedback.size * 0.5
	tw.tween_property(_feedback, "scale", Vector2.ONE, 0.18)
	tw.tween_interval(1.6)
	tw.tween_property(_feedback, "modulate:a", 0.0, 0.5)

func show_banner(title: String, sub: String, color: Color, duration: float = 2.4) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	_banner.add_theme_stylebox_override("panel", UI.box(Color(Palette.NAVY, 0.94), 16, color, 3, 24))
	_banner.visible = true
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(0.6, 0.6)
	_banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): _banner.visible = false)

func toast(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	_toast.modulate.a = 1.0
	tw.tween_interval(1.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)

# ================================================================= hints / meters

func _build_hints() -> void:
	var p := UI.panel(Color(Palette.NAVY, 0.8), 10, Color(0, 0, 0, 0), 10)
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.custom_minimum_size = Vector2(1200, 0)
	UI.place_at(p, Vector2(-600, -62))
	_hints = UI.label("", 20, Palette.CREAM, "semi")
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(_hints)
	p.name = "Hints"
	add_child(p)

func set_hints(text: String) -> void:
	_hints.text = text
	(_hints.get_parent() as Control).visible = text != ""

func _build_charge() -> void:
	_charge_box = UI.vbox(2)
	_charge_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_charge_box.custom_minimum_size = Vector2(400, 0)
	UI.place_at(_charge_box, Vector2(-200, -150))
	var l := UI.label("THROW POWER", 18, Palette.CREAM_DIM, "heading")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_box.add_child(l)
	_charge = UI.stat_bar(0.0, 1.0, Palette.ORANGE, 400)
	_charge.custom_minimum_size = Vector2(400, 18)
	_charge_box.add_child(_charge)
	_pressure = UI.label("PRESSURE!", 26, Palette.RED, "heading")
	_pressure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pressure.visible = false
	_charge_box.add_child(_pressure)
	_charge_box.visible = false
	add_child(_charge_box)

func set_charge(v: float, visible_now: bool, pressure: float) -> void:
	_charge_box.visible = visible_now
	_charge.value = v
	var col := Palette.ORANGE if v < 0.86 else Palette.RED
	_charge.add_theme_stylebox_override("fill", UI.box(col, 5, Color(0, 0, 0, 0), 0, 0))
	_pressure.visible = pressure > 0.55
	_pressure.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)

var _tip: PanelContainer

## Non-blocking coaching tip shown on the left side of the screen.
func show_tip(text: String) -> void:
	if _tip != null:
		_tip.queue_free()
	_tip = UI.panel(Color(Palette.DEEP_BLUE, 0.95), 12, Palette.TEAL, 16)
	_tip.position = Vector2(30, 260)
	_tip.custom_minimum_size = Vector2(420, 0)
	var v := UI.vbox(6)
	v.add_child(UI.label("COACH'S TIP", 20, Palette.TEAL, "heading"))
	var l := UI.label(text, 19, Palette.CREAM, "body_bold")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(390, 0)
	v.add_child(l)
	_tip.add_child(v)
	add_child(_tip)
	UI.pop_in(_tip)
	var tip := _tip
	var tw := create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(tip, "modulate:a", 0.0, 0.6)
	tw.tween_callback(tip.queue_free)

func set_debug(text: String) -> void:
	_debug.visible = text != ""
	_debug.text = text

# ================================================================= play select

func _build_play_select() -> void:
	_playselect = UI.panel(Color(Palette.NAVY, 0.95), 18, Color(1, 1, 1, 0.07), 18)
	_playselect.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_playselect.custom_minimum_size = Vector2(1800, 500)
	UI.place_at(_playselect, Vector2(-900, -520))
	add_child(_playselect)
	var root := UI.hbox(18)
	_playselect.add_child(root)
	var left := UI.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var top := UI.hbox(14)
	_ps_situation = UI.label("", 28, Palette.GOLD, "heading")
	top.add_child(_ps_situation)
	top.add_child(UI.expand(UI.spacer()))
	_ps_tabs = UI.hbox(8)
	top.add_child(_ps_tabs)
	left.add_child(top)
	for cat in [["suggested", "Suggested"], ["pass", "Pass"], ["run", "Run"], ["redzone", "Red Zone"], ["clock", "Clock"]]:
		var b := UI.button(cat[1], func(): _set_category(cat[0]), "ghost", 0)
		b.custom_minimum_size = Vector2(120, 44)
		b.set_meta("cat", cat[0])
		_ps_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_ps_grid = GridContainer.new()
	_ps_grid.columns = 4
	_ps_grid.add_theme_constant_override("h_separation", 12)
	_ps_grid.add_theme_constant_override("v_separation", 12)
	_ps_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ps_grid)
	_ps_special = UI.hbox(10)
	left.add_child(_ps_special)
	# Detail column.
	var right := UI.panel(Palette.PANEL, 14, Color(1, 1, 1, 0.05), 16)
	right.custom_minimum_size = Vector2(440, 0)
	root.add_child(right)
	var rv := UI.vbox(8)
	right.add_child(rv)
	_ps_detail_name = UI.label("", 34, Palette.CREAM, "heading")
	rv.add_child(_ps_detail_name)
	_ps_detail_diag = PlayDiagram.new()
	_ps_detail_diag.custom_minimum_size = Vector2(400, 190)
	rv.add_child(_ps_detail_diag)
	_ps_detail_sit = UI.label("", 18, Palette.TEAL, "body_bold")
	rv.add_child(_ps_detail_sit)
	_ps_detail_desc = UI.label("", 18, Palette.CREAM_DIM, "body")
	_ps_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ps_detail_desc.custom_minimum_size = Vector2(400, 0)
	rv.add_child(_ps_detail_desc)
	_ps_detail_rr = UI.label("", 18, Palette.GOLD, "sub")
	rv.add_child(_ps_detail_rr)
	rv.add_child(UI.expand(UI.spacer(0, 4)))
	var btns := UI.hbox(8)
	_ps_call_btn = UI.button("CALL PLAY", _confirm_play, "primary", 190)
	btns.add_child(_ps_call_btn)
	btns.add_child(UI.button("FLIP [F]", func(): _ps_flip = not _ps_flip; _refresh_detail(), "secondary", 110))
	_ps_tempo_btn = UI.button("TEMPO: NORMAL", _cycle_tempo, "ghost", 110)
	_ps_tempo_btn.tooltip_text = "Hurry-up saves clock between plays. Chew burns it."
	rv.add_child(btns)
	rv.add_child(_ps_tempo_btn)
	_playselect.visible = false

func play_select_visible() -> bool:
	return _playselect.visible

## ctx: {down, togo, ball_on, clock, quarter, diff, timeouts, fg_dist, fg_pct, can_kneel, can_spike, situation, last_play}
func show_play_select(ctx: Dictionary) -> void:
	_ps_ctx = ctx
	_ps_flip = false
	_playselect.visible = true
	_ps_situation.text = str(ctx.get("situation", ""))
	_ps_category = "suggested"
	_build_special_buttons()
	_set_category("redzone" if float(ctx.get("ball_on", 0.0)) >= 80.0 and not ctx.get("try", false) else "suggested")
	if ctx.get("try", false):
		_set_category("redzone")
	_playselect.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_playselect, "modulate:a", 1.0, 0.18)

func hide_play_select() -> void:
	_playselect.visible = false

func _build_special_buttons() -> void:
	for c in _ps_special.get_children():
		c.queue_free()
	if _ps_ctx.get("try", false):
		return
	var fg_dist: float = _ps_ctx.get("fg_dist", 99.0)
	var fg_pct: float = _ps_ctx.get("fg_pct", 0.0)
	if fg_pct > 0.02:
		var fb := UI.button("FIELD GOAL  %d yd · %d%%" % [int(round(fg_dist)), int(round(fg_pct * 100.0))], func(): special_chosen.emit("fg"), "secondary")
		fb.tooltip_text = "Kick a field goal. Estimated success for your kicker in calm air."
		_ps_special.add_child(fb)
	var pb := UI.button("PUNT", func(): special_chosen.emit("punt"), "secondary")
	pb.tooltip_text = "Flip field position. The receiving team takes over where the punt is downed."
	_ps_special.add_child(pb)
	var to_left: int = _ps_ctx.get("timeouts", 0)
	var tb := UI.button("TIMEOUT (%d) [T]" % to_left, func(): special_chosen.emit("timeout"), "ghost")
	tb.disabled = to_left <= 0 or not _ps_ctx.get("clock_running", false)
	tb.tooltip_text = "Stops the clock so no time runs off before the next snap."
	_ps_special.add_child(tb)
	if _ps_ctx.get("can_run_out", false):
		var rb := UI.button("RUN OUT THE CLOCK", func(): special_chosen.emit("run_out"), "primary")
		_ps_special.add_child(rb)

func _set_category(cat: String) -> void:
	_ps_category = cat
	for b in _ps_tabs.get_children():
		var on: bool = b.get_meta("cat") == cat
		b.add_theme_stylebox_override("normal", UI.box(Palette.ORANGE if on else Color(0, 0, 0, 0), 8, Color(1, 1, 1, 0.12), 1, 14))
		b.add_theme_color_override("font_color", Palette.NAVY if on else Palette.CREAM)
	for c in _ps_grid.get_children():
		c.queue_free()
	var ids: Array = []
	var suggested: Array = _ps_ctx.get("suggested", [])
	for p in Playbook.plays():
		var cat_p: String = p.get("category", "")
		var tags: Array = p.get("tags", [])
		var include := false
		match cat:
			"suggested":
				include = suggested.has(p["id"])
			"pass":
				include = cat_p in ["pass", "screen", "play_action"]
			"run":
				include = cat_p in ["run", "qb_run"]
			"redzone":
				include = tags.has("redzone") or tags.has("goal_line") or tags.has("short_yardage")
			"clock":
				include = cat_p == "clock" or tags.has("clock") or tags.has("desperation")
		if _ps_ctx.get("try", false) and cat_p == "clock":
			include = false
		if p.get("special", "") == "kneel" and not _ps_ctx.get("can_kneel", false):
			include = false
		if p.get("special", "") == "spike" and not _ps_ctx.get("can_spike", false):
			include = false
		if include:
			ids.append(p["id"])
	if ids.is_empty():
		for p in Playbook.plays():
			if p.get("special", "") == "":
				ids.append(p["id"])
	var first: Button = null
	for id in ids:
		var card := _play_card(Playbook.play(id))
		_ps_grid.add_child(card)
		if first == null:
			first = card
	if first != null:
		_select_play(ids[0])
		first.call_deferred("grab_focus")

func _play_card(p: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(296, 176)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", UI.box(Palette.PANEL, 12, Color(1, 1, 1, 0.06), 1, 8))
	b.add_theme_stylebox_override("hover", UI.box(Palette.PANEL_LIGHT, 12, Palette.ORANGE, 2, 8))
	b.add_theme_stylebox_override("focus", UI.box(Color(0, 0, 0, 0), 12, Palette.GOLD, 3, 8))
	b.add_theme_stylebox_override("pressed", UI.box(Palette.PANEL_LIGHT, 12, Palette.ORANGE, 3, 8))
	var v := UI.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	var d := PlayDiagram.new()
	d.compact = true
	d.custom_minimum_size = Vector2(280, 112)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.set_play(p)
	v.add_child(d)
	var n := UI.label(str(p["name"]).to_upper(), 22, Palette.CREAM, "heading")
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var f := UI.label(Playbook.formation_name(p["formation"]) + "  ·  " + str(p.get("category", "")).replace("_", " ").capitalize(), 15, Palette.CREAM_DIM, "semi")
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(f)
	b.add_child(v)
	b.focus_entered.connect(func(): _select_play(p["id"]))
	b.mouse_entered.connect(func(): _select_play(p["id"]))
	b.pressed.connect(func():
		_select_play(p["id"])
		_confirm_play())
	return b

func _select_play(id: String) -> void:
	if _ps_selected != id:
		_ps_flip = false
	_ps_selected = id
	_refresh_detail()

func _refresh_detail() -> void:
	var p := Playbook.play(_ps_selected)
	if p.is_empty():
		return
	_ps_detail_name.text = str(p["name"]).to_upper()
	_ps_detail_diag.set_play(p, _ps_flip)
	_ps_detail_sit.text = "Best: " + str(p.get("situation", ""))
	_ps_detail_desc.text = str(p.get("desc", ""))
	var risk: int = p.get("risk", 1)
	var reward: int = p.get("reward", 1)
	var lvl := ["None", "Low", "Medium", "High"]
	_ps_detail_rr.text = "RISK: %s   ·   REWARD: %s%s" % [lvl[clampi(risk, 0, 3)], lvl[clampi(reward, 0, 3)], "   (flipped)" if _ps_flip else ""]

func _cycle_tempo() -> void:
	_ps_tempo = (_ps_tempo + 1) % 3
	_ps_tempo_btn.text = "TEMPO: " + ["HURRY-UP", "NORMAL", "CHEW CLOCK"][_ps_tempo]

func _confirm_play() -> void:
	if _ps_selected == "":
		return
	Audio.ui("confirm")
	play_chosen.emit(_ps_selected, _ps_flip, _ps_tempo)

func _unhandled_input(event: InputEvent) -> void:
	if _playselect.visible:
		if event.is_action_pressed("flip_play"):
			_ps_flip = not _ps_flip
			_refresh_detail()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("timeout"):
			special_chosen.emit("timeout")
			get_viewport().set_input_as_handled()

# ================================================================= drive summary

func _build_drive() -> void:
	_drive = UI.panel(Color(Palette.NAVY, 0.93), 16, Color(1, 1, 1, 0.07), 18)
	_drive.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_drive.custom_minimum_size = Vector2(600, 600)
	UI.place_at(_drive, Vector2(-640, -330))
	add_child(_drive)
	var v := UI.vbox(10)
	_drive.add_child(v)
	_drive_title = UI.label("OPPONENT DRIVE", 32, Palette.CREAM, "heading")
	v.add_child(_drive_title)
	_drive_bar = FieldBar.new()
	_drive_bar.custom_minimum_size = Vector2(560, 56)
	v.add_child(_drive_bar)
	_drive_list = UI.vbox(4)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 380)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(_drive_list)
	v.add_child(sc)
	var skip := UI.button("SKIP  [Space]", func(): continue_pressed.emit("drive_skip"), "ghost")
	skip.name = "Skip"
	v.add_child(skip)
	_drive.visible = false

func start_drive(team: Team, start_ball_on: float, dir_home: bool) -> void:
	_drive.visible = true
	_drive_title.text = "%s DRIVE" % team.name.to_upper()
	_drive_title.add_theme_color_override("font_color", team.primary.lightened(0.3))
	for c in _drive_list.get_children():
		c.queue_free()
	(_drive_bar as FieldBar).setup(team.primary, start_ball_on)

func add_drive_line(text: String, ball_on: float, color: Color = Palette.CREAM) -> void:
	var l := UI.label(text, 19, color, "body_bold")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	_drive_list.add_child(l)
	UI.pop_in(l)
	(_drive_bar as FieldBar).set_ball(ball_on)

func end_drive(result: String, color: Color) -> void:
	var l := UI.label(result.to_upper(), 30, color, "heading")
	_drive_list.add_child(l)
	UI.pop_in(l)

func hide_drive() -> void:
	_drive.visible = false

func drive_visible() -> bool:
	return _drive.visible

# ================================================================= kicking

func _build_kick_panel() -> void:
	_kick_panel = UI.panel(Color(Palette.NAVY, 0.9), 14, Palette.GOLD, 16)
	_kick_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_kick_panel.custom_minimum_size = Vector2(660, 0)
	UI.place_at(_kick_panel, Vector2(-330, -250))
	var v := UI.vbox(8)
	_kick_panel.add_child(v)
	_kick_info = UI.label("", 26, Palette.CREAM, "heading")
	_kick_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_kick_info)
	_kick_aim = UI.label("", 20, Palette.CREAM_DIM, "semi")
	_kick_aim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_kick_aim)
	_kick_meter = UI.stat_bar(0.0, 1.0, Palette.GOLD, 620)
	_kick_meter.custom_minimum_size = Vector2(620, 26)
	v.add_child(_kick_meter)
	_kick_panel.visible = false
	add_child(_kick_panel)

func update_kick(kg: KickGame) -> void:
	if kg == null or kg.stage == KickGame.Stage.DONE:
		_kick_panel.visible = false
		return
	_kick_panel.visible = true
	var wind_dir := "calm"
	if kg.wind_mph > 0.5:
		var w := Vector3(kg.wind.x, 0, kg.wind.y)
		var cross := w.dot(FieldCoords.offense_right(kg.dir))
		var along := w.dot(FieldCoords.forward(kg.dir))
		var parts: Array[String] = []
		if absf(along) > 0.05:
			parts.append("in your face" if along < 0.0 else "at your back")
		if absf(cross) > 0.05:
			parts.append("blowing " + ("right" if cross > 0.0 else "left"))
		wind_dir = "%d mph %s" % [int(round(kg.wind_mph)), ", ".join(parts)]
	_kick_info.text = "%s  ·  %d YARDS" % ["EXTRA POINT" if kg.is_xp else "FIELD GOAL", int(round(kg.distance))]
	var aim_deg := rad_to_deg(kg.aim)
	var ideal := rad_to_deg(kg.ideal_aim())
	_kick_aim.text = "Aim %+.1f° (center %+.1f°)   Wind: %s   Range ≈ %d yd" % [aim_deg, ideal, wind_dir, int(kg.max_range())]
	_kick_meter.value = kg.meter if kg.stage == KickGame.Stage.POWER else kg.power
	var col := Palette.GOLD if _kick_meter.value < 0.92 else Palette.RED
	_kick_meter.add_theme_stylebox_override("fill", UI.box(col, 5, Color(0, 0, 0, 0), 0, 0))

# ================================================================= overlays

func _clear_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	_modal_open = false

func modal_open() -> bool:
	return _modal_open

func _modal(width: int = 900) -> VBoxContainer:
	_clear_overlay()
	_modal_open = true
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var p := UI.panel(Palette.NAVY, 20, Palette.PANEL_LIGHT, 28)
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	UI.pop_in(p)
	return v

func close_overlay() -> void:
	_clear_overlay()

func show_try_choice(team: Team, xp_pct: float) -> void:
	var v := _modal(760)
	v.add_child(UI.heading("Point After Touchdown", 44, Palette.GOLD))
	v.add_child(UI.label("Kick for one point, or run a play from the 2-yard line for two.", 22, Palette.CREAM_DIM))
	var h := UI.hbox(14)
	var kick := UI.button("KICK EXTRA POINT  (%d%%)" % int(round(xp_pct * 100.0)), func(): try_chosen.emit("kick"), "primary", 340)
	h.add_child(kick)
	h.add_child(UI.button("GO FOR TWO", func(): try_chosen.emit("two"), "secondary", 300))
	v.add_child(h)
	kick.call_deferred("grab_focus")

func show_message(title: String, body: String, button_text: String, tag: String, color: Color = Palette.GOLD) -> void:
	var v := _modal(820)
	v.add_child(UI.heading(title, 50, color))
	var b := UI.label(body, 22, Palette.CREAM)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(760, 0)
	v.add_child(b)
	var btn := UI.button(button_text, func(): continue_pressed.emit(tag), "primary", 260)
	v.add_child(btn)
	btn.call_deferred("grab_focus")

## stats: {home: {...team stats}, away: {...}, leaders: [[label, text]], title, button, tag}
func show_stats_panel(title: String, subtitle: String, rules: RulesEngine, leaders: Array, button_text: String, tag: String, extra_buttons: Array = []) -> void:
	var v := _modal(1100)
	v.add_child(UI.heading(title, 56, Palette.GOLD))
	if subtitle != "":
		v.add_child(UI.label(subtitle, 24, Palette.CREAM_DIM, "sub"))
	var s := rules.state
	var score_row := UI.hbox(30)
	for side in [1, 0]:
		var t := home if side == 0 else away
		var col := UI.hbox(12)
		col.add_child(TeamLogo.from_team(t, 72))
		var nv := UI.vbox(0)
		nv.add_child(UI.label(t.full_name().to_upper(), 26, Palette.CREAM, "heading"))
		nv.add_child(UI.label(str(s.score[side]), 56, t.primary.lightened(0.35) if t.primary.get_luminance() < 0.4 else t.primary, "display"))
		col.add_child(nv)
		score_row.add_child(col)
		score_row.add_child(UI.spacer(30))
	v.add_child(score_row)
	v.add_child(UI.separator())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 50)
	grid.add_theme_constant_override("v_separation", 4)
	grid.add_child(UI.label(away.abbr, 22, Palette.GOLD, "heading"))
	grid.add_child(UI.label("TEAM STATS", 22, Palette.CREAM_DIM, "heading"))
	grid.add_child(UI.label(home.abbr, 22, Palette.GOLD, "heading"))
	var rows := [["total_yards", "Total Yards"], ["pass_yards", "Passing"], ["rush_yards", "Rushing"], ["first_downs", "First Downs"], ["turnovers", "Turnovers"], ["top", "Possession"]]
	for r in rows:
		var key: String = r[0]
		var a: Variant = s.team_stats[1][key]
		var h: Variant = s.team_stats[0][key]
		var fa := RulesEngine.format_clock(a) if key == "top" else str(int(round(float(a))))
		var fh := RulesEngine.format_clock(h) if key == "top" else str(int(round(float(h))))
		grid.add_child(UI.label(fa, 22, Palette.CREAM, "sub"))
		grid.add_child(UI.label(r[1], 20, Palette.CREAM_DIM))
		grid.add_child(UI.label(fh, 22, Palette.CREAM, "sub"))
	grid.add_child(UI.label("%d/%d" % [s.team_stats[1]["third_conv"], s.team_stats[1]["third_att"]], 22, Palette.CREAM, "sub"))
	grid.add_child(UI.label("3rd Down", 20, Palette.CREAM_DIM))
	grid.add_child(UI.label("%d/%d" % [s.team_stats[0]["third_conv"], s.team_stats[0]["third_att"]], 22, Palette.CREAM, "sub"))
	var hb := UI.hbox(60)
	hb.add_child(grid)
	var lv := UI.vbox(6)
	lv.add_child(UI.label("LEADERS", 22, Palette.CREAM_DIM, "heading"))
	for l in leaders:
		var row := UI.hbox(10)
		row.add_child(UI.label(str(l[0]), 18, Palette.TEAL, "heading"))
		row.add_child(UI.label(str(l[1]), 20, Palette.CREAM, "body_bold"))
		lv.add_child(row)
	hb.add_child(lv)
	v.add_child(hb)
	var br := UI.hbox(12)
	var main := UI.button(button_text, func(): continue_pressed.emit(tag), "primary", 280)
	br.add_child(main)
	for eb in extra_buttons:
		br.add_child(UI.button(eb[0], func(): continue_pressed.emit(eb[1]), "secondary", 220))
	v.add_child(br)
	main.call_deferred("grab_focus")

func show_pause(allow_sim: bool) -> void:
	var v := _modal(560)
	v.add_child(UI.heading("Paused", 56, Palette.CREAM))
	var resume := UI.button("RESUME", func(): pause_action.emit("resume"), "primary")
	v.add_child(resume)
	v.add_child(UI.button("CONTROLS", func(): pause_action.emit("controls")))
	v.add_child(UI.button("SETTINGS", func(): pause_action.emit("settings")))
	if allow_sim:
		var sb := UI.button("SIMULATE REST OF GAME", func(): pause_action.emit("sim"))
		sb.tooltip_text = "Your team's remaining drives are simulated with the statistical model."
		v.add_child(sb)
	v.add_child(UI.button("QUIT TO MENU", func(): pause_action.emit("quit"), "danger"))
	resume.call_deferred("grab_focus")

func show_controls() -> void:
	var v := _modal(980)
	v.add_child(UI.heading("Controls", 48, Palette.CREAM))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 40)
	g.add_child(UI.label("ACTION", 18, Palette.GOLD, "heading"))
	g.add_child(UI.label("KEYBOARD & MOUSE", 18, Palette.GOLD, "heading"))
	g.add_child(UI.label("CONTROLLER", 18, Palette.GOLD, "heading"))
	for b in Settings.BINDINGS:
		g.add_child(UI.label(b[0], 20, Palette.CREAM, "body_bold"))
		g.add_child(UI.label(b[1], 20, Palette.CREAM_DIM))
		g.add_child(UI.label(b[2], 20, Palette.CREAM_DIM))
	v.add_child(g)
	var back := UI.button("BACK", func(): pause_action.emit("back"), "primary", 200)
	v.add_child(back)
	back.call_deferred("grab_focus")


## Horizontal field strip showing drive progress.
class FieldBar extends Control:
	var color := Palette.ORANGE
	var start := 25.0
	var ball := 25.0

	func setup(c: Color, s: float) -> void:
		color = c
		start = s
		ball = s
		queue_redraw()

	func set_ball(b: float) -> void:
		ball = b
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color("#1F4D2B"))
		var ez := w / 12.0
		draw_rect(Rect2(0, 0, ez, h), Palette.PANEL_LIGHT)
		draw_rect(Rect2(w - ez, 0, ez, h), color.darkened(0.2))
		for i in range(1, 10):
			var x := ez + (w - 2 * ez) * i / 10.0
			draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.25), 1.0)
		var sx := ez + (w - 2 * ez) * clampf(start, 0, 100) / 100.0
		var bx := ez + (w - 2 * ez) * clampf(ball, 0, 100) / 100.0
		draw_rect(Rect2(minf(sx, bx), h * 0.4, absf(bx - sx), h * 0.2), Color(color, 0.8))
		draw_circle(Vector2(bx, h * 0.5), h * 0.22, Palette.ORANGE)
		draw_circle(Vector2(bx, h * 0.5), h * 0.22 - 3, Color("#7A3E1D"))
