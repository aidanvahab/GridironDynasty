extends RefCounted
## Scenario implementations for tools/e2e.gd (loaded at runtime, after the
## autoload singletons exist).

var tree: SceneTree
var drv: Object

func app() -> Node:
	return tree.root.get_node("App")

func sm() -> Node:
	return tree.root.get_node("SaveManager")

func st() -> Node:
	return tree.root.get_node("Settings")

func wait(sec: float) -> void:
	await drv.wait(sec)

func shot(name: String) -> void:
	await drv.shot(name)

func expect(cond: bool, msg: String) -> void:
	drv.expect(cond, msg)

var out_dir: String:
	get: return drv.out_dir

var args: Dictionary:
	get: return drv.args

# ================================================================= scenarios

func scenario_smoke() -> void:
	app().boot()
	await wait(4.0)
	await shot("main_menu")
	expect(app().screen is MainMenu, "main menu is shown")

func _new_career(slot: int = 0) -> void:
	sm().delete_slot(slot)
	app().start_career({"coach": "E2E Coach", "team_id": "IWF", "settings": {"season_games": 10, "difficulty": 1, "game_length": 0}}, slot)
	await wait(2.0)

func scenario_career() -> void:
	## TEST A: start the game, create a career, enter the hub.
	app().boot()
	await wait(3.0)
	app().go_new_career()
	await wait(1.5)
	await shot("new_career_step1")
	var nc: NewCareerScreen = app().screen
	expect(nc != null, "new career wizard opened")
	nc.step = 1
	nc._render()
	await wait(0.5)
	await shot("new_career_franchise")
	nc.step = 2
	nc.cfg["custom"] = true
	nc.cfg["city"] = "Westhaven"
	nc.cfg["name"] = "Comets"
	nc.cfg["abbr"] = "WHC"
	nc._render()
	await wait(0.5)
	await shot("new_career_identity")
	nc._recommended()
	await wait(0.5)
	await shot("new_career_confirm")
	nc.cfg["slot"] = 0
	nc._start()
	await wait(3.0)
	expect(app().screen is Hub, "hub shown after career creation")
	expect(app().league != null and app().league.user_team().full_name() == "Westhaven Comets", "custom identity applied")
	expect(sm().has_save(0), "career saved to slot 0")
	await shot("hub_onboarding")
	var hub: Hub = app().screen
	hub._onboarding(99)
	for t in ["home", "roster", "depth", "schedule", "standings", "league", "fa", "trades", "draft", "staff", "history"]:
		hub.show_tab(t)
		await wait(0.4)
		await shot("hub_" + t)

func scenario_match() -> void:
	## TESTS B-G (live): an autoplayed full match through the real controller.
	await _new_career(1)
	var lg: League = app().league
	lg.settings["game_length"] = 0
	var g := Season.user_game(lg)
	expect(not g.is_empty(), "user has a week-1 game")
	app().start_franchise_match(g)
	await wait(2.0)
	var mc: MatchController = app().screen
	expect(mc != null, "match controller started")
	mc.autoplay = true
	mc.live.input = null
	var shot_tags := {}
	var t := 0.0
	var max_t := float(args.get("match_seconds", "900"))
	var state_seen := {}
	while t < max_t and app().screen == mc:
		await wait(0.5)
		t += 0.5
		state_seen[mc.state_tag] = true
		if not shot_tags.has(mc.state_tag) and mc.state_tag in ["play_select", "presnap", "live", "drive", "kick", "kick_show", "halftime", "post", "result"]:
			shot_tags[mc.state_tag] = true
			await shot("match_" + mc.state_tag)
		if mc.state_tag == "live" and not shot_tags.has("live2") and mc.live.t > 1.2:
			shot_tags["live2"] = true
			await shot("match_live_mid")
	expect(app().screen is Hub or app().screen is ChampionshipScreen, "returned to hub after the match (states seen: %s)" % ", ".join(state_seen.keys()))
	var played: Dictionary = Season.find_game(lg, g["id"])
	expect(played.get("played", false), "user game recorded as played")
	print("final: %s %d - %s %d" % [played["home"], played["hs"], played["away"], played["as"]])
	expect(lg.week == 1, "week advanced to 2")
	var qb: Player = lg.starters(lg.user_team(), "QB", 1)[0]
	expect(qb.stat("gp") >= 1.0, "player stats recorded")
	await wait(1.0)
	await shot("hub_after_match")

func scenario_season() -> void:
	## TEST H: advance through the whole season, playoffs and into the offseason.
	await _new_career(2)
	var lg: League = app().league
	var guard := 0
	while lg.phase != League.Phase.OFFSEASON and guard < 40:
		guard += 1
		app().sim_user_week()
	expect(lg.phase == League.Phase.OFFSEASON, "season reached the offseason")
	expect(lg.history["champions"].size() == 1, "champion recorded")
	app().go_hub("standings")
	await wait(2.0)
	await shot("season_standings")
	(app().screen as Hub).show_tab("schedule")
	await wait(0.5)
	await shot("season_bracket")
	(app().screen as Hub).show_tab("home")
	await wait(0.5)
	await shot("offseason_review")
	# Walk the offseason through the UI's own handlers.
	for stage in ["review", "resign", "draft", "free_agency", "camp"]:
		var hub: Hub = app().screen
		expect(lg.offseason_stage == stage, "offseason stage %s" % stage)
		if stage == "draft":
			hub.show_tab("draft")
			await wait(0.5)
			await shot("draft_room")
		if stage == "camp":
			var ut := lg.user_team()
			var g2 := 0
			while ut.roster.size() > Team.ROSTER_MAX and g2 < 30:
				g2 += 1
				Contracts.release(lg, ut, Contracts._worst_value(lg, ut), true)
		hub._do_advance_offseason()
		await wait(1.2)
	expect(lg.phase == League.Phase.REGULAR and lg.year == League.START_YEAR + 1, "next season started")
	await shot("next_season_home")

func scenario_persist_a() -> void:
	## TEST I (part 1): create, play some weeks, save, record a fingerprint.
	await _new_career(0)
	var lg: League = app().league
	for i in 3:
		app().sim_user_week()
	var ut := lg.user_team()
	var fp := {"team": ut.full_name(), "record": ut.record_string(), "week": lg.week, "roster": ut.roster.size(),
		"qb_ovr": lg.starters(ut, "QB", 1)[0].overall(), "qb_gp": lg.starters(ut, "QB", 1)[0].stat("gp"),
		"sched": "%d-%d" % [lg.schedule[0][0]["hs"], lg.schedule[0][0]["as"]], "players": lg.players.size()}
	expect(app().save(), "saved")
	var f := FileAccess.open(out_dir + "/fingerprint.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(fp))
	print("fingerprint ", fp)

func scenario_persist_b() -> void:
	## TEST I (part 2): fresh process — continue the career and compare.
	app().boot()
	await wait(3.0)
	await shot("menu_with_save")
	var slot: int = sm().latest_slot()
	expect(slot == 0, "latest save detected in slot 0")
	app().load_career(slot)
	await wait(2.5)
	var lg: League = app().league
	expect(lg != null, "career loaded")
	var fp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out_dir + "/fingerprint.json"))
	var ut := lg.user_team()
	expect(ut.full_name() == fp["team"], "team restored")
	expect(ut.record_string() == fp["record"], "record restored (%s)" % ut.record_string())
	expect(lg.week == int(fp["week"]), "week restored")
	expect(ut.roster.size() == int(fp["roster"]), "roster restored")
	expect(lg.starters(ut, "QB", 1)[0].overall() == int(fp["qb_ovr"]), "player ratings restored")
	expect(lg.starters(ut, "QB", 1)[0].stat("gp") == float(fp["qb_gp"]), "player stats restored")
	expect("%d-%d" % [lg.schedule[0][0]["hs"], lg.schedule[0][0]["as"]] == fp["sched"], "schedule results restored")
	expect(lg.players.size() == int(fp["players"]), "player pool restored")
	await shot("hub_after_reload")

func scenario_settings_a() -> void:
	## TEST J (part 1): change settings.
	st().set_value("music_volume", 0.25)
	st().set_value("quality", 1)
	st().set_value("camera_shake", false)
	st().set_value("ui_scale", 1.1)
	st().set_value("difficulty", 2)
	expect(true, "settings changed")

func scenario_settings_b() -> void:
	## TEST J (part 2): new process sees persisted settings.
	expect(is_equal_approx(float(st().get_value("music_volume")), 0.25), "music volume persisted")
	expect(int(st().get_value("quality")) == 1, "quality persisted")
	expect(st().get_value("camera_shake") == false, "camera shake persisted")
	expect(is_equal_approx(float(st().get_value("ui_scale")), 1.1), "ui scale persisted")
	expect(int(st().get_value("difficulty")) == 2, "difficulty persisted")
	var idx := AudioServer.get_bus_index("Music")
	expect(absf(AudioServer.get_bus_volume_db(idx) - linear_to_db(0.25)) < 0.1, "music bus volume applied")
	# Restore defaults for other runs.
	st().set_value("music_volume", 0.6)
	st().set_value("quality", 2)
	st().set_value("camera_shake", true)
	st().set_value("ui_scale", 1.0)
	st().set_value("difficulty", 1)

func scenario_screens() -> void:
	app().boot()
	await wait(3.0)
	var menu: MainMenu = app().screen
	menu._show_quick_match()
	await wait(0.6)
	await shot("quick_match")
	menu._clear_panel()
	menu._show_settings()
	await wait(0.6)
	await shot("settings")
	app().go_records()
	await wait(1.5)
	await shot("records")

func scenario_sizes() -> void:
	app().boot()
	await wait(2.0)
	var vp := tree.root
	print("window size: ", DisplayServer.window_get_size(), " root size: ", vp.size, " visible rect: ", vp.get_visible_rect(), " csf: ", vp.content_scale_factor, " content size: ", vp.content_scale_size)
	app().go_records()
	await wait(1.5)
	var c: Control = app().screen
	print("records control size: ", c.size, " pos ", c.position, " anchors ", c.anchor_right, ",", c.anchor_bottom)
