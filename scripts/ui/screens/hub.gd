class_name Hub
extends Control
## Franchise hub: every management screen for the active career.

const TABS := [
	["home", "Home"], ["roster", "Roster"], ["depth", "Depth Chart"], ["schedule", "Schedule"],
	["standings", "Standings"], ["league", "League Leaders"], ["fa", "Free Agency"], ["trades", "Trades"],
	["draft", "Draft"], ["staff", "Staff & Facilities"], ["history", "History"],
]

var initial_tab: String = "home"
var lg: League
var ut: Team
var _tab: String = "home"
var _content: VBoxContainer
var _nav: VBoxContainer
var _nav_buttons: Dictionary = {}
var _overlay: Control
var _header_record: Label
var _roster_sort: String = "ovr"
var _roster_filter: String = "ALL"
var _fa_filter: String = "ALL"
var _trade_team: String = ""
var _trade_give: Array = []
var _trade_get: Array = []
var _compare: Array = []
var _draft_filter: String = "ALL"
var _focus_target: Control

func _ready() -> void:
	lg = App.league
	ut = lg.user_team()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Audio.music("music_menu")
	Audio.crowd_stop()
	var bg := ColorRect.new()
	bg.color = Palette.NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var accent := ColorRect.new()
	accent.color = ut.primary.darkened(0.55)
	accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent.offset_bottom = 150
	add_child(accent)
	var root := UI.hbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_sidebar(root)
	var main := UI.vbox(14)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.margin(main, 30, 26, 36, 24))
	main.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_header(main)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(sc)
	_content = UI.vbox(16)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_content)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	show_tab(initial_tab)
	if lg.meta.get("onboarding", false):
		call_deferred("_onboarding", 0)
	elif not App.last_report.is_empty():
		call_deferred("_show_week_report")

# ================================================================= frame

func _build_sidebar(root: HBoxContainer) -> void:
	var side := UI.panel(Color("#0C1522"), 0, Color(0, 0, 0, 0), 18)
	side.custom_minimum_size = Vector2(300, 0)
	root.add_child(side)
	var v := UI.vbox(8)
	side.add_child(v)
	var logo := TeamLogo.from_team(ut, 120)
	v.add_child(logo)
	v.add_child(UI.label(ut.city.to_upper(), 18, Palette.CREAM_DIM, "heading"))
	v.add_child(UI.label(ut.name.to_upper(), 34, Palette.CREAM, "heading"))
	v.add_child(UI.label("Coach " + lg.coach_name, 18, Palette.TEAL, "body_bold"))
	v.add_child(UI.spacer(0, 8))
	_nav = UI.vbox(6)
	v.add_child(_nav)
	for t in TABS:
		var b := UI.button(t[1], func(): show_tab(t[0]), "ghost", 260)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(260, 44)
		b.add_theme_font_size_override("font_size", 22)
		_nav.add_child(b)
		_nav_buttons[t[0]] = b
	v.add_child(UI.expand(UI.spacer()))
	var save := UI.button("SAVE", func():
		if App.save():
			App.toast("Career saved"), "secondary", 260)
	v.add_child(save)
	v.add_child(UI.button("SETTINGS", func():
		var sp := SettingsPanel.new()
		add_child(sp), "ghost", 260))
	v.add_child(UI.button("MAIN MENU", func():
		App.save()
		App.go_main_menu(), "ghost", 260))

func _build_header(main: VBoxContainer) -> void:
	var h := UI.hbox(20)
	var phase: String = ["REGULAR SEASON · WEEK %d OF %d" % [mini(lg.week + 1, Season.season_weeks(lg)), Season.season_weeks(lg)], "PLAYOFFS · " + Season.round_name(lg, int(lg.playoffs.get("round", 0))).to_upper(), "OFFSEASON · " + _stage_name(lg.offseason_stage).to_upper()][int(lg.phase)]
	var v := UI.vbox(0)
	v.add_child(UI.label("%d SEASON" % lg.year, 20, Palette.GOLD, "heading"))
	v.add_child(UI.label(phase, 40, Palette.CREAM, "heading"))
	h.add_child(v)
	h.add_child(UI.expand(UI.spacer()))
	var stats := UI.hbox(24)
	_header_record = UI.label(ut.record_string(), 48, Palette.CREAM, "display")
	stats.add_child(_stat_block("RECORD", _header_record))
	var place := Season.division_standings(lg, ut.conf, ut.div).find(ut) + 1
	stats.add_child(_stat_block("DIVISION", UI.label(UI.ordinal(place), 48, Palette.CREAM, "display")))
	stats.add_child(_stat_block("TEAM OVR", UI.label(str(lg.team_overall(ut)), 48, Palette.rating_color(lg.team_overall(ut)), "display")))
	stats.add_child(_stat_block("CAP SPACE", UI.label(UI.money(lg.cap_space(ut)), 40, Palette.GREEN if lg.cap_space(ut) >= 0 else Palette.RED, "display")))
	stats.add_child(_stat_block("BUDGET", UI.label(UI.money(ut.funds), 40, Palette.GOLD, "display")))
	h.add_child(stats)
	main.add_child(h)

func _stat_block(title: String, value: Label) -> Control:
	var v := UI.vbox(-6)
	v.add_child(UI.label(title, 16, Palette.CREAM_DIM, "heading"))
	v.add_child(value)
	return v

func _stage_name(s: String) -> String:
	return {"review": "Season Review", "resign": "Re-sign Players", "draft": "Draft", "free_agency": "Free Agency", "camp": "Training Camp"}.get(s, s)

func refresh() -> void:
	App.go_hub(_tab)

func show_tab(t: String) -> void:
	_tab = t
	for k in _nav_buttons:
		var b: Button = _nav_buttons[k]
		var on: bool = k == t
		b.add_theme_stylebox_override("normal", UI.box(Palette.ORANGE if on else Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 0, 14))
		b.add_theme_color_override("font_color", Palette.NAVY if on else Palette.CREAM)
	for c in _content.get_children():
		c.queue_free()
	_focus_target = null
	match t:
		"home": _tab_home()
		"roster": _tab_roster()
		"depth": _tab_depth()
		"schedule": _tab_schedule()
		"standings": _tab_standings()
		"league": _tab_league()
		"fa": _tab_fa()
		"trades": _tab_trades()
		"draft": _tab_draft()
		"staff": _tab_staff()
		"history": _tab_history()
	if _focus_target != null and not Settings.last_input_was_mouse:
		_focus_target.call_deferred("grab_focus")
	elif not Settings.last_input_was_mouse:
		(_nav_buttons[t] as Button).call_deferred("grab_focus")

func _section(title: String, subtitle: String = "") -> VBoxContainer:
	var p := UI.panel(Palette.PANEL, 16, Color(1, 1, 1, 0.05), 22)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(10)
	p.add_child(v)
	var h := UI.hbox(12)
	h.add_child(UI.heading(title, 30, Palette.CREAM))
	if subtitle != "":
		h.add_child(UI.label(subtitle, 18, Palette.CREAM_DIM, "semi"))
	v.add_child(h)
	_content.add_child(p)
	return v

# ================================================================= overlays

func _clear_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _modal(width: int = 900) -> VBoxContainer:
	_clear_overlay()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var p := UI.panel(Palette.NAVY, 20, Palette.PANEL_LIGHT, 28)
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	UI.pop_in(p)
	return v

func _close_btn(text: String = "CLOSE") -> Button:
	var b := UI.button(text, func():
		_clear_overlay()
		show_tab(_tab), "primary", 220)
	b.call_deferred("grab_focus")
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _overlay.get_child_count() > 0:
		_clear_overlay()
		get_viewport().set_input_as_handled()

func _confirm(title: String, body: String, yes_text: String, on_yes: Callable, danger: bool = false) -> void:
	var v := _modal(720)
	v.add_child(UI.heading(title, 42, Palette.RED if danger else Palette.GOLD))
	var l := UI.label(body, 21, Palette.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(660, 0)
	v.add_child(l)
	var h := UI.hbox(12)
	var no := UI.button("CANCEL", func(): _clear_overlay(), "secondary", 200)
	h.add_child(no)
	h.add_child(UI.button(yes_text, func():
		_clear_overlay()
		on_yes.call(), "danger" if danger else "primary", 240))
	v.add_child(h)
	no.call_deferred("grab_focus")

func _message(title: String, body: String) -> void:
	var v := _modal(760)
	v.add_child(UI.heading(title, 42, Palette.GOLD))
	var l := UI.label(body, 21, Palette.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(700, 0)
	v.add_child(l)
	v.add_child(_close_btn("OK"))

# ================================================================= onboarding

const ONBOARD := [
	["Welcome, Coach", "You've taken over the %s — an overlooked franchise with a thin roster. Your goal: win games now, develop talent, and build a dynasty that lasts for decades."],
	["Your Roster", "Check the Roster tab. Your veteran starters will keep you competitive, but the future is a raw young quarterback prospect. Playing time, coaching and facilities help young players grow."],
	["Game Day", "On game day you call every offensive play. Pick a play from the diagrams, read the defense, and press SPACE to snap. Defensive possessions are simulated drive-by-drive."],
	["Passing", "Press 1-5 (or point with the mouse) to pick a receiver, hold the left mouse button to charge the throw and release to pass. More power = a faster, flatter ball. Lead receivers into open space."],
	["Running", "On runs the back follows the designed lane until you take over. WASD to steer, SHIFT to sprint, SPACE to juke, C to dive for extra yards."],
	["The Objective", "Score more points than your opponent: touchdowns are worth 6 (plus a try), field goals 3. You have four downs to gain ten yards. Make the playoffs, win the %s, and do it again."],
]

func _onboarding(i: int) -> void:
	if i >= ONBOARD.size():
		lg.meta.erase("onboarding")
		App.save()
		_clear_overlay()
		return
	var v := _modal(860)
	v.add_child(UI.label("GETTING STARTED  ·  %d / %d" % [i + 1, ONBOARD.size()], 18, Palette.TEAL, "heading"))
	v.add_child(UI.heading(ONBOARD[i][0], 50, Palette.GOLD))
	var txt: String = ONBOARD[i][1]
	if i == 0:
		txt = txt % ut.full_name()
	elif i == ONBOARD.size() - 1:
		txt = txt % lg.championship_name
	var l := UI.label(txt, 23, Palette.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(800, 0)
	v.add_child(l)
	if i == 2:
		var ug := Season.user_game(lg)
		if not ug.is_empty():
			var opp: Team = lg.teams[ug["away"] if ug["home"] == ut.id else ug["home"]]
			v.add_child(UI.label("First opponent: %s (%s, OVR %d)" % [opp.full_name(), "home" if ug["home"] == ut.id else "away", lg.team_overall(opp)], 21, Palette.ORANGE, "sub"))
	var h := UI.hbox(12)
	var next := UI.button("NEXT" if i < ONBOARD.size() - 1 else "LET'S PLAY", func(): _onboarding(i + 1), "primary", 240)
	h.add_child(next)
	h.add_child(UI.button("SKIP TUTORIAL", func(): _onboarding(ONBOARD.size()), "ghost", 240))
	v.add_child(h)
	next.call_deferred("grab_focus")

# ================================================================= home

func _tab_home() -> void:
	if lg.phase == League.Phase.OFFSEASON:
		_home_offseason()
	else:
		_home_season()
	if not lg.pending_event.is_empty():
		_event_card()
	if not lg.trade_offers.is_empty() and Trades.trade_window_open(lg):
		_offers_card()
	var row := UI.hbox(16)
	_content.add_child(row)
	var news := UI.panel(Palette.PANEL, 16, Color(1, 1, 1, 0.05), 22)
	news.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nv := UI.vbox(6)
	news.add_child(nv)
	nv.add_child(UI.heading("League News", 28))
	for n in lg.news.slice(0, 9):
		var col: Color = {"injury": Palette.RED, "champion": Palette.GOLD, "award": Palette.GOLD, "record": Palette.GOLD, "trade": Palette.TEAL, "alert": Palette.ORANGE}.get(n.get("kind", ""), Palette.CREAM)
		var l := UI.label("•  " + str(n["text"]), 19, col, "body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(700, 0)
		nv.add_child(l)
	row.add_child(news)
	var tr := UI.panel(Palette.PANEL, 16, Color(1, 1, 1, 0.05), 22)
	tr.custom_minimum_size = Vector2(520, 0)
	var tv := UI.vbox(8)
	tr.add_child(tv)
	tv.add_child(UI.heading("Team Strength", 28))
	var r := lg.team_ratings(ut)
	var base := lg.rating_baseline()
	for pair in [["Passing Offense", "qb"], ["Receivers", "recv"], ["Offensive Line", "ol"], ["Run Game", "rb"], ["Pass Rush", "pass_rush"], ["Coverage", "coverage"], ["Run Defense", "run_def"]]:
		var h := UI.hbox(10)
		var lbl := UI.label(pair[0], 19, Palette.CREAM, "body_bold")
		lbl.custom_minimum_size = Vector2(200, 0)
		h.add_child(lbl)
		var val := float(r[pair[1]])
		h.add_child(UI.stat_bar(val, 99.0, Color(0, 0, 0, 0), 200))
		var rel := val - float(base.get(pair[1], val))
		h.add_child(UI.label("%+.0f vs avg" % rel, 17, Palette.GREEN if rel >= 0 else Palette.RED, "sub"))
		tv.add_child(h)
	tv.add_child(UI.label("Chemistry %d  ·  Fans %d  ·  Prestige %d" % [int(ut.chemistry), int(ut.fans), int(ut.prestige)], 18, Palette.CREAM_DIM, "body_bold"))
	row.add_child(tr)

func _home_season() -> void:
	var g := Season.user_game(lg)
	var v := _section("Next Game" if not g.is_empty() else "This Week")
	if g.is_empty():
		var txt := "No game for your team this round."
		if lg.phase == League.Phase.PLAYOFFS:
			txt = "Your season is over. Watch the rest of the playoffs unfold."
		v.add_child(UI.label(txt, 22, Palette.CREAM_DIM))
		var adv := UI.button("ADVANCE", func():
			App.sim_user_week()
			App.go_hub("home"), "primary", 260)
		v.add_child(adv)
		_focus_target = adv
		return
	var home_g: bool = g["home"] == ut.id
	var opp: Team = lg.teams[g["away"] if home_g else g["home"]]
	var row := UI.hbox(30)
	row.add_child(TeamLogo.from_team(ut, 110))
	var mid := UI.vbox(2)
	var title := "WEEK %d" % (int(g["week"]) + 1)
	if g.get("playoff", false):
		title = Season.round_name(lg, int(g["round"])).to_upper()
	mid.add_child(UI.label(title, 22, Palette.GOLD, "heading"))
	mid.add_child(UI.label("%s %s %s" % [ut.abbr, "vs" if home_g else "@", opp.full_name().to_upper()], 40, Palette.CREAM, "heading"))
	mid.add_child(UI.label("%s  ·  Opponent OVR %d  ·  %s offense, %s defense" % [opp.record_string(), lg.team_overall(opp), opp.offense_style.capitalize(), opp.defense_style], 19, Palette.CREAM_DIM, "body_bold"))
	var venue := lg.teams[g["home"]] as Team
	mid.add_child(UI.label("%s · %s" % [venue.city, StadiumBuilder.styles().get(venue.stadium, {}).get("name", "")], 17, Palette.MUTED, "semi"))
	row.add_child(mid)
	row.add_child(UI.expand(UI.spacer()))
	row.add_child(TeamLogo.from_team(opp, 110))
	v.add_child(row)
	var issues := _lineup_issues()
	if not issues.is_empty():
		v.add_child(UI.label("⚠ " + issues, 19, Palette.ORANGE, "body_bold"))
	var btns := UI.hbox(12)
	var play := UI.button("PLAY GAME", func(): App.start_franchise_match(g), "primary", 280)
	play.custom_minimum_size = Vector2(280, 64)
	play.add_theme_font_size_override("font_size", 30)
	btns.add_child(play)
	var simb := UI.button("SIMULATE GAME", func():
		var rep := App.sim_user_week()
		if rep.get("events", []).has("champion") and lg.history["champions"].back()["team"] == ut.id:
			App.change_screen(ChampionshipScreen.new())
		else:
			App.go_hub("home"), "secondary", 260)
	simb.tooltip_text = "Resolve your game with the statistical model and advance the week."
	btns.add_child(simb)
	if lg.phase == League.Phase.REGULAR and lg.week < Season.season_weeks(lg) - 1:
		var sim_all := UI.button("SIM TO PLAYOFFS", func():
			_confirm("Simulate the regular season?", "All of your remaining regular-season games will be simulated.", "SIMULATE", func():
				var guard := 0
				while lg.phase == League.Phase.REGULAR and guard < 30:
					guard += 1
					App.sim_user_week()
				App.go_hub("home")), "ghost", 240)
		btns.add_child(sim_all)
	v.add_child(btns)
	_focus_target = play

func _lineup_issues() -> String:
	for pos in Team.STARTERS:
		var healthy := lg.depth_players(ut, pos).filter(func(p): return p.is_available())
		if healthy.size() < int(Team.STARTERS[pos]):
			return "Not enough healthy %s — the next available player will fill in." % pos
	return ""

func _home_offseason() -> void:
	var st := lg.offseason_stage
	var v := _section("Offseason", _stage_name(st))
	var info := {
		"review": "The %d season is in the books. Review awards and your season, then open the re-signing period. Veterans may retire." % lg.year,
		"resign": "Contracts have expired. Re-sign the players you want to keep from the Roster tab (expiring players are marked). Anyone left unsigned becomes a free agent when you continue.",
		"draft": "The draft is live. Scout prospects and make your picks in the Draft tab. Continuing auto-drafts any remaining picks for you.",
		"free_agency": "Free agency is open. Sign veterans to fill holes in the Free Agency tab. Continuing runs player development for the new season.",
		"camp": "Training camp: development results are in. Make sure your roster is legal (33-40 players, under the cap) before starting the season.",
	}
	var l := UI.label(info.get(st, ""), 21, Palette.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1100, 0)
	v.add_child(l)
	if st == "review":
		var aw: Array = lg.history["awards"].back()["list"] if not lg.history["awards"].is_empty() else []
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 30)
		for a in aw:
			grid.add_child(UI.label(str(a["award"]).to_upper(), 18, Palette.GOLD, "heading"))
			var t: Team = lg.teams.get(a["team"])
			grid.add_child(UI.label("%s, %s (%s)" % [a["name"], a["pos"], t.abbr if t != null else "FA"], 20, Palette.CREAM, "body_bold"))
		v.add_child(grid)
		var champ: Dictionary = lg.history["champions"].back() if not lg.history["champions"].is_empty() else {}
		if not champ.is_empty():
			v.add_child(UI.label("%d %s champion: %s" % [lg.year, lg.championship_name, champ["name"]], 24, Palette.ORANGE, "heading"))
	if st == "camp":
		var issues := FranchiseOps.user_roster_issues(lg)
		for iss in issues:
			v.add_child(UI.label("⚠ " + iss, 20, Palette.ORANGE, "body_bold"))
		var notes: Array = lg.meta.get("camp_notes", [])
		if not notes.is_empty():
			v.add_child(UI.label("DEVELOPMENT REPORT", 20, Palette.TEAL, "heading"))
			for n in notes.slice(0, 10):
				var p: Player = lg.players.get(n["player"])
				if p == null:
					continue
				var up: bool = int(n["to"]) > int(n["from"])
				v.add_child(UI.label("%s %s (%s): %d → %d" % ["▲" if up else "▼", p.full_name(), p.pos, n["from"], n["to"]], 19, Palette.GREEN if up else Palette.RED, "body_bold"))
	var next_txt: String = {"review": "OPEN RE-SIGNING PERIOD", "resign": "START THE DRAFT", "draft": "FINISH DRAFT", "free_agency": "BEGIN TRAINING CAMP", "camp": "START %d SEASON" % (lg.year + 1)}.get(st, "CONTINUE")
	var cont := UI.button(next_txt, _advance_offseason, "primary", 360)
	v.add_child(cont)
	_focus_target = cont

func _advance_offseason() -> void:
	if lg.offseason_stage == "camp":
		var issues := FranchiseOps.user_roster_issues(lg)
		if not issues.is_empty():
			_confirm("Roster isn't legal", "\n".join(issues) + "\n\nAuto-fix will release your lowest-value players and sign minimum-salary depth as needed.", "AUTO-FIX & START", func():
				var guard := 0
				while (ut.roster.size() > Team.ROSTER_MAX or (Contracts.cap_on(lg) and lg.payroll(ut) > League.SALARY_CAP)) and guard < 40:
					guard += 1
					var w := Contracts._worst_value(lg, ut)
					if w == null:
						break
					Contracts.release(lg, ut, w, true)
				Contracts.ensure_legal(lg, ut)
				_do_advance_offseason())
			return
	if lg.offseason_stage == "resign":
		var exp := Contracts.expiring_for(lg, ut)
		if not exp.is_empty():
			_confirm("Let players walk?", "%d expiring player%s will leave as free agents." % [exp.size(), "s" if exp.size() != 1 else ""], "CONTINUE", _do_advance_offseason)
			return
	_do_advance_offseason()

func _do_advance_offseason() -> void:
	var out := FranchiseOps.advance_offseason(lg)
	if out.has("progress"):
		lg.meta["camp_notes"] = out["progress"]
	if out.has("new_season"):
		lg.meta.erase("camp_notes")
	App.save()
	App.go_hub("draft" if lg.offseason_stage == "draft" else "home")

func _event_card() -> void:
	var ev := lg.pending_event
	var v := _section("Decision: " + str(ev["title"]))
	var l := UI.label(str(ev["text"]), 21, Palette.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1100, 0)
	v.add_child(l)
	var h := UI.hbox(12)
	var opts: Array = ev["options"]
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := UI.button(str(o["label"]), func():
			var msg := FranchiseOps.resolve_event(lg, i)
			App.save()
			_message("Decision made", msg), "secondary")
		b.tooltip_text = str(o["effect"])
		var box := UI.vbox(2)
		box.add_child(b)
		box.add_child(UI.label(str(o["effect"]), 16, Palette.CREAM_DIM))
		h.add_child(box)
	v.add_child(h)

func _offers_card() -> void:
	var v := _section("Trade Offers")
	for i in lg.trade_offers.size():
		var o: Dictionary = lg.trade_offers[i]
		var cpu: Team = lg.teams.get(o["team"])
		if cpu == null:
			continue
		var want := ", ".join(o["want"].map(func(pid): return _pname(pid)))
		var give := ", ".join(o["give"].map(func(pid): return _pname(pid)))
		var h := UI.hbox(12)
		h.add_child(UI.label("%s offer %s for %s" % [cpu.full_name(), give, want], 20, Palette.CREAM, "body_bold"))
		h.add_child(UI.expand(UI.spacer()))
		h.add_child(UI.button("ACCEPT", func():
			var err := Trades.execute(lg, ut, cpu, o["want"], o["give"])
			lg.trade_offers.remove_at(i)
			App.save()
			if err != "":
				_message("Trade failed", err)
			else:
				show_tab("home"), "primary", 140))
		h.add_child(UI.button("DECLINE", func():
			lg.trade_offers.remove_at(i)
			show_tab("home"), "ghost", 140))
		v.add_child(h)

func _pname(pid: String) -> String:
	var p: Player = lg.players.get(pid)
	return "%s (%s %d)" % [p.full_name(), p.pos, p.overall()] if p != null else "?"

func _show_week_report() -> void:
	var rep := App.last_report
	App.last_report = {}
	if rep.is_empty():
		return
	var g: Dictionary = rep.get("user_game", {})
	var v := _modal(980)
	if not g.is_empty():
		var home_g: bool = g["home"] == ut.id
		var mine := int(g["hs"]) if home_g else int(g["as"])
		var theirs := int(g["as"]) if home_g else int(g["hs"])
		var opp: Team = lg.teams[g["away"] if home_g else g["home"]]
		var res := "WIN" if mine > theirs else ("LOSS" if mine < theirs else "TIE")
		v.add_child(UI.heading("%s  %d – %d" % [res, mine, theirs], 56, Palette.GREEN if res == "WIN" else (Palette.RED if res == "LOSS" else Palette.GOLD)))
		v.add_child(UI.label("vs %s%s" % [opp.full_name(), "  (OT)" if g.get("ot", false) else ""], 24, Palette.CREAM_DIM, "sub"))
		var pog: String = g.get("pog", "")
		if lg.players.has(pog):
			v.add_child(UI.label("Player of the Game: %s" % lg.players[pog].full_name(), 20, Palette.TEAL, "body_bold"))
	v.add_child(UI.label("AROUND THE LEAGUE", 20, Palette.GOLD, "heading"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 50)
	for r in rep.get("results", []):
		if r == g:
			continue
		var h: Team = lg.teams[r["home"]]
		var a: Team = lg.teams[r["away"]]
		grid.add_child(UI.label("%s %d  @  %s %d%s" % [a.abbr, int(r["as"]), h.abbr, int(r["hs"]), " OT" if r.get("ot", false) else ""], 19, Palette.CREAM, "body_bold"))
	v.add_child(grid)
	if rep.get("events", []).has("playoffs"):
		var made: bool = ut.record.get("playoff", false)
		v.add_child(UI.label("THE PLAYOFFS ARE SET — " + ("YOU'RE IN!" if made else "your season is over."), 24, Palette.GREEN if made else Palette.RED, "heading"))
	if rep.get("events", []).has("decision"):
		v.add_child(UI.label("A new decision needs your attention on the Home tab.", 19, Palette.ORANGE, "body_bold"))
	v.add_child(_close_btn("CONTINUE"))

# ================================================================= roster

func _tab_roster() -> void:
	var v := _section("Roster", "%d players  ·  payroll %s of %s" % [ut.roster.size(), UI.money(lg.payroll(ut)), UI.money(League.SALARY_CAP)])
	var filters := UI.hbox(6)
	for f in ["ALL", "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]:
		var b := UI.button(f, func():
			_roster_filter = f
			show_tab("roster"), "primary" if _roster_filter == f else "ghost", 64)
		b.custom_minimum_size = Vector2(64, 42)
		filters.add_child(b)
	filters.add_child(UI.spacer(20))
	if _compare.size() == 2:
		filters.add_child(UI.button("COMPARE (2)", func(): _show_compare(), "secondary", 180))
	elif _compare.size() == 1:
		filters.add_child(UI.label("Select one more player to compare", 17, Palette.TEAL, "body_bold"))
	v.add_child(filters)
	var expiring := Contracts.expiring_for(lg, ut) if lg.phase == League.Phase.OFFSEASON and lg.offseason_stage == "resign" else []
	var players := lg.roster_players(ut).filter(func(p): return _roster_filter == "ALL" or p.pos == _roster_filter)
	match _roster_sort:
		"ovr": players.sort_custom(func(a, b): return a.overall() > b.overall())
		"age": players.sort_custom(func(a, b): return a.age < b.age)
		"salary": players.sort_custom(func(a, b): return a.salary > b.salary)
		"pos": players.sort_custom(func(a, b): return Player.POSITIONS.find(a.pos) < Player.POSITIONS.find(b.pos) or (a.pos == b.pos and a.overall() > b.overall()))
		"pot": players.sort_custom(func(a, b): return a.potential > b.potential)
		"morale": players.sort_custom(func(a, b): return a.morale > b.morale)
	var table := GridContainer.new()
	table.columns = 9
	table.add_theme_constant_override("h_separation", 22)
	table.add_theme_constant_override("v_separation", 4)
	for col in [["", ""], ["PLAYER", "pos"], ["POS", "pos"], ["AGE", "age"], ["OVR", "ovr"], ["POT", "pot"], ["CONTRACT", "salary"], ["MORALE", "morale"], ["STATUS", ""]]:
		if col[1] != "":
			var hb := UI.button(col[0] + (" ▼" if _roster_sort == col[1] else ""), func():
				_roster_sort = col[1]
				show_tab("roster"), "ghost", 0)
			hb.custom_minimum_size = Vector2(0, 36)
			hb.add_theme_font_size_override("font_size", 17)
			table.add_child(hb)
		else:
			table.add_child(UI.label(col[0], 17, Palette.CREAM_DIM, "heading"))
	for p in players:
		var cb := CheckBox.new()
		cb.button_pressed = _compare.has(p.id)
		cb.tooltip_text = "Select to compare"
		cb.toggled.connect(func(on):
			if on and not _compare.has(p.id):
				_compare.append(p.id)
				if _compare.size() > 2:
					_compare.pop_front()
			elif not on:
				_compare.erase(p.id)
			show_tab("roster"))
		table.add_child(cb)
		var nb := UI.button(p.full_name() + ("  #%d" % p.number), func(): _player_detail(p), "ghost", 300)
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.custom_minimum_size = Vector2(300, 40)
		nb.add_theme_font_size_override("font_size", 20)
		table.add_child(nb)
		if _focus_target == null:
			_focus_target = nb
		table.add_child(UI.label(p.pos, 20, Palette.TEAL, "heading"))
		table.add_child(UI.label(str(p.age), 20, Palette.CREAM))
		table.add_child(UI.rating_badge(p.overall(), 22))
		table.add_child(UI.label(_pot_grade(p), 20, Palette.GOLD, "heading"))
		table.add_child(UI.label("%s × %d" % [UI.money(p.salary), p.years], 19, Palette.CREAM_DIM, "body_bold"))
		table.add_child(UI.stat_bar(p.morale, 100.0, Palette.GREEN if p.morale >= 60 else (Palette.GOLD if p.morale >= 40 else Palette.RED), 90))
		var status := ""
		var scol := Palette.CREAM_DIM
		if p.injury_weeks > 0:
			status = "INJURED %dw" % p.injury_weeks
			scol = Palette.RED
		elif expiring.has(p.id):
			status = "EXPIRING"
			scol = Palette.ORANGE
		elif p.fatigue > 30.0:
			status = "TIRED"
			scol = Palette.GOLD
		elif p.experience == 0:
			status = "ROOKIE"
			scol = Palette.TEAL
		table.add_child(UI.label(status, 17, scol, "heading"))
	v.add_child(table)

func _pot_grade(p: Player) -> String:
	## Own-team potential is shown as a scouting grade, not an exact number.
	var gap := p.potential - p.overall()
	if p.age >= 30:
		return "—"
	if gap >= 15: return "A"
	if gap >= 9: return "B"
	if gap >= 4: return "C"
	return "D"

func _player_detail(p: Player) -> void:
	var v := _modal(1180)
	var top := UI.hbox(20)
	var t: Team = lg.teams.get(p.team_id)
	top.add_child(Portrait.for_player(p, t, 170))
	var info := UI.vbox(2)
	info.add_child(UI.label("#%d  %s" % [p.number, p.pos], 22, Palette.TEAL, "heading"))
	info.add_child(UI.heading(p.full_name(), 48))
	info.add_child(UI.label("Age %d  ·  %d yr%s experience  ·  %s  ·  %s" % [p.age, p.experience, "s" if p.experience != 1 else "", p.personality, t.full_name() if t != null else "Free Agent"], 20, Palette.CREAM_DIM, "body_bold"))
	var line := UI.hbox(16)
	line.add_child(UI.rating_badge(p.overall(), 34))
	line.add_child(UI.label("Potential: %s" % (_pot_grade(p) if t == ut else "?"), 22, Palette.GOLD, "sub"))
	line.add_child(UI.label("Contract: %s × %d yr" % [UI.money(p.salary), p.years], 22, Palette.CREAM, "sub"))
	line.add_child(UI.label("Morale %d" % int(p.morale), 22, Palette.GREEN if p.morale >= 60 else Palette.ORANGE, "sub"))
	info.add_child(line)
	if p.injury_weeks > 0:
		info.add_child(UI.label("Injured: out %d week%s" % [p.injury_weeks, "s" if p.injury_weeks > 1 else ""], 20, Palette.RED, "body_bold"))
	if not p.draft_info.is_empty():
		info.add_child(UI.label("Drafted %d, round %d (#%d)" % [p.draft_info.get("year", 0), p.draft_info.get("round", 0), p.draft_info.get("pick", 0)], 18, Palette.MUTED, "body_bold"))
	if not p.awards.is_empty():
		info.add_child(UI.label("Awards: " + ", ".join(p.awards.map(func(a): return "%s %d" % [a["award"], a["year"]])), 18, Palette.GOLD, "body_bold"))
	top.add_child(info)
	v.add_child(top)
	var body := UI.hbox(30)
	var attrs := GridContainer.new()
	attrs.columns = 3
	attrs.add_theme_constant_override("h_separation", 14)
	var key_attrs: Array = Player.WEIGHTS[p.pos].keys()
	var shown: Array = key_attrs.duplicate()
	for k in ["speed", "accel", "agility", "strength", "awareness", "stamina"]:
		if not shown.has(k):
			shown.append(k)
	for k in shown:
		var is_key := key_attrs.has(k)
		attrs.add_child(UI.label(Player.ATTR_LABELS[k], 19, Palette.CREAM if is_key else Palette.CREAM_DIM, "body_bold" if is_key else "body"))
		attrs.add_child(UI.stat_bar(p.a(k), 99.0, Color(0, 0, 0, 0), 180))
		attrs.add_child(UI.label(str(int(p.a(k))), 19, Palette.rating_color(p.a(k)), "heading"))
	body.add_child(attrs)
	var st := UI.vbox(4)
	st.add_child(UI.label("SEASON  /  CAREER", 18, Palette.GOLD, "heading"))
	for pair in _stat_lines(p):
		st.add_child(UI.label(pair, 19, Palette.CREAM, "body_bold"))
	if not p.history.is_empty():
		st.add_child(UI.label("DEVELOPMENT", 18, Palette.GOLD, "heading"))
		var hist := ""
		for h in p.history.slice(-6):
			hist += "%d: %d   " % [h["year"], h["ovr"]]
		hist += "Now: %d" % p.overall()
		var hl := UI.label(hist, 18, Palette.CREAM_DIM, "body_bold")
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.custom_minimum_size = Vector2(440, 0)
		st.add_child(hl)
	body.add_child(st)
	v.add_child(body)
	var actions := UI.hbox(12)
	if t == ut:
		if p.years <= 1:
			actions.add_child(UI.button("NEGOTIATE CONTRACT", func(): _negotiate(p), "secondary", 280))
		var rel := UI.button("RELEASE", func():
			_confirm("Release %s?" % p.full_name(), "He will become a free agent and his salary comes off your cap.", "RELEASE", func():
				var err := Contracts.release(lg, ut, p)
				App.save()
				if err != "":
					_message("Can't release", err)
				else:
					show_tab(_tab), true), "danger", 180)
		actions.add_child(rel)
	elif p.team_id == "":
		actions.add_child(UI.button("OFFER CONTRACT", func(): _negotiate(p), "primary", 260))
	actions.add_child(_close_btn())
	v.add_child(actions)

func _stat_lines(p: Player) -> Array:
	var s := p.season_stats
	var c := p.career_stats
	var out: Array = []
	var gp := "GP %d / %d" % [int(s.get("gp", 0)), int(c.get("gp", 0))]
	out.append(gp)
	if c.get("pass_att", 0) > 0:
		out.append("Passing: %d/%d %d yds %d TD %d INT  /  %d yds %d TD" % [s.get("pass_cmp", 0), s.get("pass_att", 0), s.get("pass_yds", 0), s.get("pass_td", 0), s.get("int_thrown", 0), c.get("pass_yds", 0), c.get("pass_td", 0)])
	if c.get("rush_att", 0) > 0:
		out.append("Rushing: %d car %d yds %d TD  /  %d yds %d TD" % [s.get("rush_att", 0), s.get("rush_yds", 0), s.get("rush_td", 0), c.get("rush_yds", 0), c.get("rush_td", 0)])
	if c.get("rec", 0) > 0:
		out.append("Receiving: %d rec %d yds %d TD  /  %d yds %d TD" % [s.get("rec", 0), s.get("rec_yds", 0), s.get("rec_td", 0), c.get("rec_yds", 0), c.get("rec_td", 0)])
	if c.get("tackles", 0) > 0 or c.get("sacks", 0) > 0 or c.get("def_int", 0) > 0:
		out.append("Defense: %d tkl %d sacks %d INT  /  %d tkl %d sacks %d INT" % [s.get("tackles", 0), s.get("sacks", 0), s.get("def_int", 0), c.get("tackles", 0), c.get("sacks", 0), c.get("def_int", 0)])
	if c.get("fg_att", 0) > 0:
		out.append("Kicking: FG %d/%d  /  %d/%d" % [s.get("fg_made", 0), s.get("fg_att", 0), c.get("fg_made", 0), c.get("fg_att", 0)])
	return out

func _show_compare() -> void:
	var a: Player = lg.players.get(_compare[0])
	var b: Player = lg.players.get(_compare[1])
	if a == null or b == null:
		return
	var v := _modal(1000)
	v.add_child(UI.heading("Player Comparison", 44))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 40)
	g.add_child(UI.label("", 18))
	g.add_child(UI.label("%s (%s)" % [a.full_name(), a.pos], 22, Palette.ORANGE, "heading"))
	g.add_child(UI.label("%s (%s)" % [b.full_name(), b.pos], 22, Palette.TEAL, "heading"))
	var rows := [["Overall", a.overall(), b.overall()], ["Age", a.age, b.age], ["Salary", a.salary, b.salary]]
	for k in Player.ATTRS:
		rows.append([Player.ATTR_LABELS[k], int(a.a(k)), int(b.a(k))])
	for r in rows:
		g.add_child(UI.label(str(r[0]), 19, Palette.CREAM_DIM, "body_bold"))
		var av: float = float(r[1])
		var bv: float = float(r[2])
		var better_a := av > bv if r[0] not in ["Age", "Salary"] else av < bv
		g.add_child(UI.label(UI.money(av) if r[0] == "Salary" else str(int(av)), 20, Palette.GREEN if better_a and av != bv else Palette.CREAM, "heading"))
		g.add_child(UI.label(UI.money(bv) if r[0] == "Salary" else str(int(bv)), 20, Palette.GREEN if not better_a and av != bv else Palette.CREAM, "heading"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(940, 560)
	sc.add_child(g)
	v.add_child(sc)
	v.add_child(_close_btn())

func _negotiate(p: Player) -> void:
	var ask := Contracts.asking(lg, ut, p)
	var v := _modal(820)
	v.add_child(UI.heading("Contract: " + p.full_name(), 40))
	v.add_child(UI.label("%s · %d OVR · age %d · %s" % [p.pos, p.overall(), p.age, p.personality], 20, Palette.CREAM_DIM, "body_bold"))
	v.add_child(UI.label("His camp is asking for about %s per year over %d years." % [UI.money(ask["salary"]), ask["years"]], 21, Palette.GOLD, "sub"))
	var cap_txt := "Cap space: %s" % UI.money(lg.cap_space(ut) + (p.salary if p.team_id == ut.id else 0.0))
	v.add_child(UI.label(cap_txt, 19, Palette.TEAL, "body_bold"))
	var offer := {"salary": float(ask["salary"]), "years": int(ask["years"])}
	var sal_label := UI.label("", 26, Palette.CREAM, "heading")
	var s := HSlider.new()
	s.min_value = 0.6
	s.max_value = maxf(2.0, float(ask["salary"]) * 1.6)
	s.step = 0.05
	s.value = offer["salary"]
	s.custom_minimum_size = Vector2(600, 30)
	var upd := func(val: float):
		offer["salary"] = val
		sal_label.text = "Offer: %s per year" % UI.money(val)
	upd.call(s.value)
	s.value_changed.connect(upd)
	v.add_child(sal_label)
	v.add_child(s)
	var yrs := UI.hbox(8)
	for y in [1, 2, 3, 4, 5]:
		var yb := UI.button("%d yr" % y, Callable(), "primary" if y == offer["years"] else "secondary", 100)
		yb.pressed.connect(func():
			offer["years"] = y
			for c in yrs.get_children():
				c.add_theme_stylebox_override("normal", UI.box(Palette.PANEL_LIGHT, 10, Color(1, 1, 1, 0.06), 1, 18))
			yb.add_theme_stylebox_override("normal", UI.box(Palette.ORANGE, 10, Palette.ORANGE, 1, 18)))
		yrs.add_child(yb)
	v.add_child(yrs)
	var result := UI.label("", 21, Palette.CREAM, "body_bold")
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size = Vector2(760, 0)
	v.add_child(result)
	var h := UI.hbox(12)
	var send := UI.button("MAKE OFFER", func():
		var res := Contracts.negotiate(lg, ut, p, offer["salary"], offer["years"])
		result.text = str(res["message"])
		result.add_theme_color_override("font_color", Palette.GREEN if res["accepted"] else Palette.ORANGE)
		if res["accepted"]:
			Audio.ui("confirm")
			App.save()
		else:
			Audio.ui("error"), "primary", 220)
	h.add_child(send)
	h.add_child(_close_btn("DONE"))
	v.add_child(h)
	s.call_deferred("grab_focus")

# ================================================================= depth chart

func _tab_depth() -> void:
	var v := _section("Depth Chart", "Starters are the top players at each position. Injured players are skipped automatically.")
	var h := UI.hbox(10)
	h.add_child(UI.button("AUTO-SORT BY RATING", func():
		lg.auto_depth(ut)
		App.save()
		show_tab("depth"), "secondary", 300))
	v.add_child(h)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 16)
	for pos in Player.POSITIONS:
		var box := UI.panel(Palette.PANEL_LIGHT, 12, Color(0, 0, 0, 0), 14)
		box.custom_minimum_size = Vector2(640, 0)
		var bv := UI.vbox(4)
		box.add_child(bv)
		bv.add_child(UI.label("%s  ·  %d starter%s" % [pos, Team.STARTERS[pos], "s" if Team.STARTERS[pos] > 1 else ""], 22, Palette.GOLD, "heading"))
		var ids: Array = ut.depth.get(pos, [])
		for i in ids.size():
			var p: Player = lg.players.get(ids[i])
			if p == null:
				continue
			var row := UI.hbox(8)
			var starter: bool = i < int(Team.STARTERS[pos])
			row.add_child(UI.label("%d." % (i + 1), 19, Palette.ORANGE if starter else Palette.MUTED, "heading"))
			var nl := UI.label("%s  (%d)%s" % [p.full_name(), p.overall(), "  INJ" if p.injury_weeks > 0 else ""], 19, Palette.CREAM if starter else Palette.CREAM_DIM, "body_bold")
			nl.custom_minimum_size = Vector2(380, 0)
			row.add_child(nl)
			var up := UI.button("▲", func(): _move_depth(pos, i, -1), "ghost", 50)
			up.custom_minimum_size = Vector2(50, 34)
			up.disabled = i == 0
			var dn := UI.button("▼", func(): _move_depth(pos, i, 1), "ghost", 50)
			dn.custom_minimum_size = Vector2(50, 34)
			dn.disabled = i == ids.size() - 1
			row.add_child(up)
			row.add_child(dn)
			bv.add_child(row)
			if _focus_target == null and not up.disabled:
				_focus_target = up
		grid.add_child(box)
	v.add_child(grid)

func _move_depth(pos: String, i: int, d: int) -> void:
	var ids: Array = ut.depth.get(pos, [])
	var j := i + d
	if j < 0 or j >= ids.size():
		return
	var tmp: String = ids[i]
	ids[i] = ids[j]
	ids[j] = tmp
	ut.depth[pos] = ids
	# Promotions and demotions affect morale.
	if j < int(Team.STARTERS[pos]) and i >= int(Team.STARTERS[pos]):
		lg.players[ids[j]].morale = minf(100.0, lg.players[ids[j]].morale + 4.0)
		lg.players[ids[i]].morale = maxf(5.0, lg.players[ids[i]].morale - 4.0)
	show_tab("depth")

# ================================================================= schedule & standings

func _tab_schedule() -> void:
	var v := _section("Schedule", ut.full_name())
	for wk in lg.schedule:
		for g in wk:
			if g["home"] != ut.id and g["away"] != ut.id:
				continue
			v.add_child(_game_row(g, "WEEK %d" % (int(g["week"]) + 1)))
	if not lg.playoffs.is_empty():
		var pv := _section("Playoff Bracket")
		for r in 3:
			var games: Array = lg.playoffs.get("games", []).filter(func(g): return int(g["round"]) == r)
			if games.is_empty():
				continue
			pv.add_child(UI.label(Season.round_name(lg, r).to_upper(), 22, Palette.GOLD, "heading"))
			for g in games:
				pv.add_child(_game_row(g, ""))
		var ch: String = lg.playoffs.get("champion", "")
		if ch != "":
			pv.add_child(UI.label("CHAMPION: " + lg.teams[ch].full_name().to_upper(), 28, Palette.ORANGE, "heading"))

func _game_row(g: Dictionary, label: String) -> Control:
	var h := UI.hbox(14)
	if label != "":
		var wl := UI.label(label, 18, Palette.CREAM_DIM, "heading")
		wl.custom_minimum_size = Vector2(110, 0)
		h.add_child(wl)
	var home: Team = lg.teams[g["home"]]
	var away: Team = lg.teams[g["away"]]
	h.add_child(TeamLogo.from_team(away, 34))
	var t := UI.label("%s  @  %s" % [away.full_name(), home.full_name()], 20, Palette.CREAM, "body_bold")
	t.custom_minimum_size = Vector2(560, 0)
	h.add_child(t)
	h.add_child(TeamLogo.from_team(home, 34))
	if g["played"]:
		var mine_home: bool = g["home"] == ut.id
		var involved: bool = g["home"] == ut.id or g["away"] == ut.id
		var res := ""
		var col := Palette.CREAM
		if involved:
			var mine := int(g["hs"]) if mine_home else int(g["as"])
			var theirs := int(g["as"]) if mine_home else int(g["hs"])
			res = "W " if mine > theirs else ("L " if mine < theirs else "T ")
			col = Palette.GREEN if mine > theirs else (Palette.RED if mine < theirs else Palette.GOLD)
		h.add_child(UI.label("%s%d – %d%s" % [res, int(g["as"]), int(g["hs"]), " OT" if g.get("ot", false) else ""], 22, col, "heading"))
	else:
		h.add_child(UI.label("—", 22, Palette.MUTED, "heading"))
	return h

func _tab_standings() -> void:
	for conf in 2:
		var v := _section(lg.conferences[conf] + " Conference")
		var grid := GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 28)
		for div in 2:
			for hdr in [lg.divisions[conf][div].to_upper() + " DIVISION", "W", "L", "T", "PCT", "PF", "PA", "STRK"]:
				grid.add_child(UI.label(hdr, 17, Palette.GOLD, "heading"))
			for t in Season.division_standings(lg, conf, div):
				var name := UI.label(t.full_name() + ("  *" if t.record.get("playoff", false) else ""), 20, Palette.ORANGE if t == ut else Palette.CREAM, "body_bold")
				name.custom_minimum_size = Vector2(380, 0)
				grid.add_child(name)
				for k in ["w", "l", "t"]:
					grid.add_child(UI.label(str(int(t.record.get(k, 0))), 20, Palette.CREAM))
				grid.add_child(UI.label("%.3f" % t.win_pct(), 20, Palette.CREAM))
				grid.add_child(UI.label(str(int(t.record.get("pf", 0))), 20, Palette.CREAM_DIM))
				grid.add_child(UI.label(str(int(t.record.get("pa", 0))), 20, Palette.CREAM_DIM))
				var s := int(t.record.get("streak", 0))
				grid.add_child(UI.label(("W%d" % s) if s > 0 else (("L%d" % -s) if s < 0 else "-"), 20, Palette.GREEN if s > 0 else Palette.RED if s < 0 else Palette.MUTED))
		v.add_child(grid)
		var seeds: Array = Season.playoff_seeds(lg, conf) if lg.phase == League.Phase.REGULAR else lg.playoffs.get("seeds", {}).get(str(conf), [])
		if not seeds.is_empty():
			v.add_child(UI.label(("Projected playoff seeds: " if lg.phase == League.Phase.REGULAR else "Playoff seeds: ") + ", ".join(seeds.map(func(id): return lg.teams[id].abbr)), 18, Palette.TEAL, "body_bold"))

func _tab_league() -> void:
	var cats := [["pass_yds", "Passing Yards"], ["pass_td", "Passing TDs"], ["rush_yds", "Rushing Yards"], ["rec_yds", "Receiving Yards"], ["rec_td", "Receiving TDs"], ["tackles", "Tackles"], ["sacks", "Sacks"], ["def_int", "Interceptions"]]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 16)
	_content.add_child(grid)
	for c in cats:
		var box := UI.panel(Palette.PANEL, 14, Color(1, 1, 1, 0.05), 18)
		box.custom_minimum_size = Vector2(700, 0)
		var bv := UI.vbox(4)
		box.add_child(bv)
		bv.add_child(UI.label(str(c[1]).to_upper(), 22, Palette.GOLD, "heading"))
		var ps: Array = lg.players.values().filter(func(p): return not p.retired and p.team_id != "" and p.stat(c[0]) > 0)
		ps.sort_custom(func(a, b): return a.stat(c[0]) > b.stat(c[0]))
		for i in mini(5, ps.size()):
			var p: Player = ps[i]
			var t: Team = lg.teams.get(p.team_id)
			bv.add_child(UI.label("%d. %s (%s, %s)  —  %d" % [i + 1, p.full_name(), p.pos, t.abbr if t else "", int(p.stat(c[0]))], 19, Palette.ORANGE if t == ut else Palette.CREAM, "body_bold"))
		if ps.is_empty():
			bv.add_child(UI.label("No games played yet.", 18, Palette.MUTED))
		grid.add_child(box)

# ================================================================= free agency

func _tab_fa() -> void:
	var resign := lg.phase == League.Phase.OFFSEASON and lg.offseason_stage == "resign"
	if resign:
		var rv := _section("Expiring Contracts", "Re-sign the players you want to keep")
		var exp := Contracts.expiring_for(lg, ut)
		if exp.is_empty():
			rv.add_child(UI.label("No expiring contracts.", 20, Palette.CREAM_DIM))
		for pid in exp:
			var p: Player = lg.players[pid]
			rv.add_child(_fa_row(p, "RE-SIGN"))
	var v := _section("Free Agents", "Cap space %s  ·  Roster %d/%d" % [UI.money(lg.cap_space(ut)), ut.roster.size(), Team.ROSTER_MAX])
	var filters := UI.hbox(6)
	for f in ["ALL", "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]:
		var b := UI.button(f, func():
			_fa_filter = f
			show_tab("fa"), "primary" if _fa_filter == f else "ghost", 64)
		b.custom_minimum_size = Vector2(64, 42)
		filters.add_child(b)
	v.add_child(filters)
	var fas: Array = lg.free_agents.map(func(pid): return lg.players.get(pid)).filter(func(p): return p != null and (_fa_filter == "ALL" or p.pos == _fa_filter))
	fas.sort_custom(func(a, b): return a.overall() > b.overall())
	for p in fas.slice(0, 40):
		v.add_child(_fa_row(p, "NEGOTIATE"))
	if fas.is_empty():
		v.add_child(UI.label("No free agents at this position.", 20, Palette.CREAM_DIM))

func _fa_row(p: Player, action: String) -> Control:
	var h := UI.hbox(14)
	h.add_child(UI.rating_badge(p.overall(), 22))
	var nb := UI.button("%s  ·  %s  ·  age %d" % [p.full_name(), p.pos, p.age], func(): _player_detail(p), "ghost", 520)
	nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	nb.custom_minimum_size = Vector2(520, 42)
	h.add_child(nb)
	var ask := Contracts.asking(lg, ut, p)
	h.add_child(UI.label("asks %s × %d" % [UI.money(ask["salary"]), ask["years"]], 19, Palette.CREAM_DIM, "body_bold"))
	h.add_child(UI.expand(UI.spacer()))
	var b := UI.button(action, func(): _negotiate(p), "secondary", 200)
	h.add_child(b)
	if _focus_target == null:
		_focus_target = b
	return h

# ================================================================= trades

func _tab_trades() -> void:
	if not Trades.trade_window_open(lg):
		var v0 := _section("Trades")
		v0.add_child(UI.label("The trade window is closed. Trades are allowed through week %d of the regular season and during the offseason re-sign, free agency and camp periods." % int(ceil(Season.season_weeks(lg) * 0.67)), 20, Palette.CREAM_DIM))
		return
	if _trade_team == "" or not lg.teams.has(_trade_team) or _trade_team == ut.id:
		for id in lg.team_order:
			if id != ut.id:
				_trade_team = id
				break
	var cpu: Team = lg.teams[_trade_team]
	var v := _section("Trade Builder", "Select players from each side, then propose")
	var tsel := UI.hbox(8)
	var ob := OptionButton.new()
	var others: Array = lg.team_order.filter(func(id): return id != ut.id)
	for id in others:
		ob.add_item(lg.teams[id].full_name())
	ob.selected = others.find(_trade_team)
	ob.custom_minimum_size = Vector2(420, 48)
	ob.add_theme_font_override("font", UI.font("sub"))
	ob.add_theme_font_size_override("font_size", 22)
	ob.item_selected.connect(func(i):
		_trade_team = others[i]
		_trade_get.clear()
		show_tab("trades"))
	tsel.add_child(UI.label("Trade partner:", 22, Palette.CREAM, "sub"))
	tsel.add_child(ob)
	v.add_child(tsel)
	_focus_target = ob
	var cols := UI.hbox(24)
	cols.add_child(_trade_list(ut, _trade_give, "YOU SEND"))
	cols.add_child(_trade_list(cpu, _trade_get, "YOU RECEIVE"))
	v.add_child(cols)
	var res := UI.label("", 21, Palette.CREAM, "body_bold")
	var btns := UI.hbox(12)
	btns.add_child(UI.button("EVALUATE", func():
		var ev := Trades.evaluate(lg, ut, cpu, _trade_give, _trade_get)
		res.text = "%s  (their view: value in %.0f vs out %.0f)" % [ev["reason"], ev["in"], ev["out"]]
		res.add_theme_color_override("font_color", Palette.GREEN if ev["accepted"] else Palette.ORANGE), "secondary", 200))
	btns.add_child(UI.button("PROPOSE TRADE", func():
		var ev := Trades.evaluate(lg, ut, cpu, _trade_give, _trade_get)
		if not ev["accepted"]:
			res.text = "%s rejected: %s" % [cpu.abbr, ev["reason"]]
			res.add_theme_color_override("font_color", Palette.RED)
			Audio.ui("error")
			return
		var err := Trades.execute(lg, ut, cpu, _trade_give, _trade_get)
		if err != "":
			res.text = err
			return
		_trade_give.clear()
		_trade_get.clear()
		App.save()
		Audio.ui("confirm")
		_message("Trade complete", "The deal with the %s is done." % cpu.full_name()), "primary", 240))
	v.add_child(btns)
	v.add_child(res)

func _trade_list(t: Team, sel: Array, title: String) -> Control:
	var box := UI.panel(Palette.PANEL_LIGHT, 12, Color(0, 0, 0, 0), 14)
	box.custom_minimum_size = Vector2(700, 0)
	var bv := UI.vbox(3)
	box.add_child(bv)
	bv.add_child(UI.label("%s  ·  %s" % [title, t.abbr], 20, Palette.GOLD, "heading"))
	var ps := lg.roster_players(t)
	ps.sort_custom(func(a, b): return a.overall() > b.overall())
	for p in ps:
		var c := CheckBox.new()
		c.text = "%s  %s  %d OVR  age %d  %s" % [p.pos, p.full_name(), p.overall(), p.age, UI.money(p.salary)]
		c.button_pressed = sel.has(p.id)
		c.add_theme_font_size_override("font_size", 18)
		c.toggled.connect(func(on):
			if on and not sel.has(p.id):
				sel.append(p.id)
			elif not on:
				sel.erase(p.id))
		bv.add_child(c)
	return box

# ================================================================= draft

func _tab_draft() -> void:
	if lg.phase != League.Phase.OFFSEASON or lg.offseason_stage != "draft" or lg.draft_state.is_empty():
		var v0 := _section("Draft")
		v0.add_child(UI.label("The rookie draft takes place during the offseason. Draft order follows the standings: the worst teams pick first, the champion picks last.", 20, Palette.CREAM_DIM))
		var drafts: Array = lg.history.get("drafts", [])
		if not drafts.is_empty():
			var last: Dictionary = drafts.back()
			v0.add_child(UI.label("%d DRAFT — YOUR PICKS" % int(last["year"]), 20, Palette.GOLD, "heading"))
			for pk in last["picks"]:
				if pk["team"] == ut.id:
					v0.add_child(UI.label("Round %d (#%d): %s, %s" % [pk["round"], pk["pick"], pk["name"], pk["pos"]], 19, Palette.CREAM, "body_bold"))
		return
	var ds := lg.draft_state
	var clock := Draft.on_clock(lg)
	var my_turn := clock == ut.id
	var pts: int = int(ds.get("points", {}).get(ut.id, 0))
	var head := "Round %d · Pick %d · %s on the clock" % [int(ds["round"]) + 1, Draft.overall_pick(lg), lg.teams[clock].abbr if clock != "" else "-"]
	if ds.get("done", false):
		head = "The draft is complete"
	var v := _section("Draft Room", head)
	var h := UI.hbox(12)
	h.add_child(UI.label("Scouting points: %d" % pts, 22, Palette.TEAL, "sub"))
	if not ds.get("done", false) and not my_turn:
		h.add_child(UI.button("SIM TO MY PICK", func():
			Draft.sim_to_user(lg)
			App.save()
			show_tab("draft"), "secondary", 240))
	if my_turn:
		h.add_child(UI.label("YOU'RE ON THE CLOCK", 26, Palette.ORANGE, "heading"))
		h.add_child(UI.button("AUTO PICK", func():
			Draft.auto_pick_user(lg)
			Draft.sim_to_user(lg)
			App.save()
			show_tab("draft"), "ghost", 180))
	v.add_child(h)
	var filters := UI.hbox(6)
	for f in ["ALL", "QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]:
		var b := UI.button(f, func():
			_draft_filter = f
			show_tab("draft"), "primary" if _draft_filter == f else "ghost", 64)
		b.custom_minimum_size = Vector2(64, 42)
		filters.add_child(b)
	v.add_child(filters)
	v.add_child(UI.label("Your needs: " + _needs_text(), 18, Palette.CREAM_DIM, "body_bold"))
	var pros: Array = lg.prospects.map(func(pid): return lg.players[pid]).filter(func(p): return _draft_filter == "ALL" or p.pos == _draft_filter)
	var reports := {}
	for p in pros:
		reports[p.id] = Draft.report(lg, p, ut)
	pros.sort_custom(func(a, b): return int(reports[a.id]["est"]) + int(reports[a.id]["pot_est"]) > int(reports[b.id]["est"]) + int(reports[b.id]["pot_est"]))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 20)
	for hdr in ["PROSPECT", "POS", "AGE", "PROJ OVR", "POTENTIAL", "", ""]:
		grid.add_child(UI.label(hdr, 17, Palette.GOLD, "heading"))
	for p in pros.slice(0, 40):
		var r: Dictionary = reports[p.id]
		var scouted: bool = ds.get("scouted", {}).get(p.id, false)
		grid.add_child(UI.label(p.full_name() + ("  ✓" if scouted else ""), 19, Palette.CREAM, "body_bold"))
		grid.add_child(UI.label(p.pos, 19, Palette.TEAL, "heading"))
		grid.add_child(UI.label(str(p.age), 19, Palette.CREAM))
		grid.add_child(UI.label("%d – %d" % [r["low"], r["high"]], 19, Palette.CREAM, "sub"))
		grid.add_child(UI.label(str(r["grade"]), 22, Palette.GOLD, "heading"))
		var sb := UI.button("SCOUT", func():
			var err := Draft.scout(lg, ut, p)
			if err != "":
				App.toast(err)
			show_tab("draft"), "ghost", 110)
		sb.disabled = scouted or pts <= 0
		sb.tooltip_text = "Spend a scouting point for a precise report."
		grid.add_child(sb)
		var db := UI.button("DRAFT", func():
			var err := Draft.make_pick(lg, ut.id, p.id)
			if err != "":
				App.toast(err)
				return
			Audio.ui("confirm")
			Draft.sim_to_user(lg)
			App.save()
			show_tab("draft"), "primary", 120)
		db.disabled = not my_turn
		grid.add_child(db)
		if _focus_target == null and my_turn:
			_focus_target = db
	v.add_child(grid)
	var log_v := _section("Draft Log")
	for pk in ds.get("picks", []).slice(-12):
		var t: Team = lg.teams[pk["team"]]
		log_v.add_child(UI.label("#%d  %s — %s, %s" % [pk["pick"], t.abbr, pk["name"], pk["pos"]], 19, Palette.ORANGE if t == ut else Palette.CREAM, "body_bold"))

func _needs_text() -> String:
	var needs: Array = []
	for pos in Team.STARTERS:
		var group := lg.players_at(ut, pos)
		var good := group.filter(func(p): return p.overall() >= 68).size()
		if good < int(Team.STARTERS[pos]):
			needs.append(pos)
	return ", ".join(needs) if not needs.is_empty() else "No glaring holes — take the best player available."

# ================================================================= staff

func _tab_staff() -> void:
	var v := _section("Coaching Staff", "Budget %s" % UI.money(ut.funds))
	for role in League.STAFF_ROLES:
		var s: Dictionary = ut.staff.get(role, {})
		var row := UI.hbox(14)
		var title := UI.label(League.STAFF_TITLES[role].to_upper(), 19, Palette.GOLD, "heading")
		title.custom_minimum_size = Vector2(300, 0)
		row.add_child(title)
		var nm := UI.label("%s  %s" % [s.get("name", "Vacant"), _stars(float(s.get("rating", 1.0)))], 21, Palette.CREAM, "body_bold")
		nm.custom_minimum_size = Vector2(420, 0)
		row.add_child(nm)
		row.add_child(UI.label("%s/yr" % UI.money(float(s.get("salary", 0.0))), 19, Palette.CREAM_DIM))
		row.add_child(UI.expand(UI.spacer()))
		var hb := UI.button("FIND REPLACEMENT", func(): _hire_modal(role), "secondary", 260)
		row.add_child(hb)
		if _focus_target == null:
			_focus_target = hb
		v.add_child(row)
		var eff := UI.label(FranchiseOps.ROLE_EFFECTS[role], 17, Palette.MUTED)
		v.add_child(eff)
	var fv := _section("Facilities")
	for key in Finance.FACILITY_INFO:
		var info: Dictionary = Finance.FACILITY_INFO[key]
		var lvl := int(ut.facilities.get(key, 1))
		var row := UI.hbox(14)
		var n := UI.label(str(info["name"]).to_upper(), 19, Palette.GOLD, "heading")
		n.custom_minimum_size = Vector2(300, 0)
		row.add_child(n)
		row.add_child(UI.label("Level %d / 5  %s" % [lvl, "■".repeat(lvl) + "□".repeat(5 - lvl)], 21, Palette.CREAM, "body_bold"))
		row.add_child(UI.label(str(info["effect"]), 17, Palette.CREAM_DIM))
		row.add_child(UI.expand(UI.spacer()))
		var cost := Finance.upgrade_cost(ut, key)
		var ub := UI.button("UPGRADE (%s)" % UI.money(cost) if cost >= 0.0 else "MAXED", func():
			_confirm("Upgrade %s?" % info["name"], "Cost: %s. Effect: %s." % [UI.money(cost), info["effect"]], "UPGRADE", func():
				var err := Finance.upgrade(lg, ut, key)
				App.save()
				if err != "":
					_message("Upgrade failed", err)
				else:
					refresh()), "primary", 240)
		ub.disabled = cost < 0.0 or ut.funds < cost
		row.add_child(ub)
		fv.add_child(row)
	var money := _section("Finances")
	money.add_child(UI.label("Operating budget: %s  ·  Staff payroll: %s/season" % [UI.money(ut.funds), UI.money(ut.staff.values().reduce(func(a, s): return a + float(s.get("salary", 0.0)), 0.0))], 20, Palette.CREAM, "body_bold"))
	money.add_child(UI.label("Player payroll: %s of %s cap (%s space)" % [UI.money(lg.payroll(ut)), UI.money(League.SALARY_CAP), UI.money(lg.cap_space(ut))], 20, Palette.CREAM, "body_bold"))
	money.add_child(UI.label("Revenue comes from home games (fans × stadium level) and the season-end league revenue share. Player salaries count against the cap, not the operating budget.", 18, Palette.CREAM_DIM))

func _stars(r: float) -> String:
	var full := int(floor(r))
	var half := r - full >= 0.5
	return "★".repeat(full) + ("½" if half else "") + "☆".repeat(maxi(0, 5 - full - (1 if half else 0)))

func _hire_modal(role: String) -> void:
	var v := _modal(900)
	v.add_child(UI.heading("Hire " + League.STAFF_TITLES[role], 40))
	v.add_child(UI.label(FranchiseOps.ROLE_EFFECTS[role], 19, Palette.CREAM_DIM))
	var cands := FranchiseOps.staff_candidates(lg, role)
	var first: Button = null
	for i in cands.size():
		var c: Dictionary = cands[i]
		var row := UI.hbox(12)
		var l := UI.label("%s  %s  ·  %s/yr  ·  fee %s" % [c["name"], _stars(float(c["rating"])), UI.money(float(c["salary"])), UI.money(FranchiseOps.hire_fee(c))], 21, Palette.CREAM, "body_bold")
		l.custom_minimum_size = Vector2(620, 0)
		row.add_child(l)
		var b := UI.button("HIRE", func():
			var err := FranchiseOps.hire(lg, ut, role, i)
			App.save()
			if err != "":
				_message("Can't hire", err)
			else:
				refresh(), "primary", 140)
		b.disabled = ut.funds < FranchiseOps.hire_fee(c)
		row.add_child(b)
		v.add_child(row)
		if first == null and not b.disabled:
			first = b
	v.add_child(_close_btn())
	if first != null:
		first.call_deferred("grab_focus")

# ================================================================= history

func _tab_history() -> void:
	var v := _section("Your Seasons")
	if lg.history["user_seasons"].is_empty():
		v.add_child(UI.label("Your first season is underway. History is written at the end of each season.", 20, Palette.CREAM_DIM))
	for s in lg.history["user_seasons"]:
		var res: String = s.get("result", "")
		v.add_child(UI.label("%d  ·  %s  ·  PF %d PA %d  ·  OVR %d  %s" % [s["year"], s["record"], s["pf"], s["pa"], s.get("ovr", 0), ("· " + res) if res != "" else "· Missed playoffs"], 21, Palette.GOLD if res == "Champion" else Palette.CREAM, "body_bold"))
	var cv := _section("Champions")
	for c in lg.history["champions"]:
		cv.add_child(UI.label("%d  —  %s" % [c["year"], c["name"]], 21, Palette.ORANGE if c["team"] == ut.id else Palette.CREAM, "body_bold"))
	if lg.history["champions"].is_empty():
		cv.add_child(UI.label("No champions crowned yet.", 19, Palette.CREAM_DIM))
	var av := _section("Award Winners")
	for yr in lg.history["awards"]:
		av.add_child(UI.label(str(yr["year"]), 20, Palette.GOLD, "heading"))
		for a in yr["list"]:
			av.add_child(UI.label("   %s: %s (%s)" % [a["award"], a["name"], lg.teams[a["team"]].abbr if lg.teams.has(a["team"]) else ""], 19, Palette.CREAM, "body"))
	var rv := _section("League Records")
	var rec: Dictionary = lg.history.get("records", {})
	for key in Awards.RECORD_STATS:
		var s: Dictionary = rec.get("season", {}).get(key, {})
		var c: Dictionary = rec.get("career", {}).get(key, {})
		if s.is_empty():
			continue
		rv.add_child(UI.label("%s — season: %d by %s (%d)   ·   career: %d by %s" % [Awards.RECORD_STATS[key], int(s["value"]), s["name"], s["year"], int(c.get("value", 0)), c.get("name", "-")], 19, Palette.CREAM, "body_bold"))
	var tw: Dictionary = rec.get("team", {}).get("wins", {})
	if not tw.is_empty():
		rv.add_child(UI.label("Most wins in a season: %d — %s (%d)" % [tw["value"], tw["name"], tw["year"]], 19, Palette.CREAM, "body_bold"))
	var hv := _section("Hall of Legends")
	if lg.history["hall"].is_empty():
		hv.add_child(UI.label("Retired greats will be enshrined here.", 19, Palette.CREAM_DIM))
	for h in lg.history["hall"]:
		hv.add_child(UI.label("%s (%s) — retired %d, %d awards" % [h["name"], h["pos"], h["year"], h["awards"]], 19, Palette.CREAM, "body_bold"))
	var dv := _section("Draft History")
	for d in lg.history["drafts"]:
		var mine: Array = d["picks"].filter(func(pk): return pk["team"] == ut.id)
		dv.add_child(UI.label("%d: %s" % [d["year"], ", ".join(mine.map(func(pk): return "%s %s (#%d)" % [pk["pos"], pk["name"], pk["pick"]]))], 19, Palette.CREAM, "body"))
	var tx := _section("Recent Transactions")
	for t in lg.history.get("transactions", []).slice(0, 12):
		tx.add_child(UI.label("%d wk %d — %s" % [t["year"], int(t["week"]) + 1, t["text"]], 18, Palette.CREAM_DIM))
