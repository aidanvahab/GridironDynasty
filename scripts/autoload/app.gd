extends Node
## Application flow: screens, transitions, the active career, and hand-off
## between the franchise hub and live matches.

signal toast_requested(text: String)

var league: League = null
var slot: int = -1
var screen: Node = null
var last_report: Dictionary = {}
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _busy := false
var _toast: Label
var _quick_cfg: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Palette.NAVY
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade_layer.add_child(_fade)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.custom_minimum_size = Vector2(800, 0)
	UI.place_at(_toast, Vector2(-400, -110))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_override("font", UI.font("sub"))
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Palette.GOLD)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Palette.NAVY)
	_toast.modulate.a = 0.0
	_fade_layer.add_child(_toast)
	SaveManager.saved.connect(func(_s, ok, msg):
		if not ok:
			toast("Save failed: " + msg))

func boot() -> void:
	var qa := _qa_args()
	if qa.has("qa_flow"):
		_run_qa(qa)
		return
	go_main_menu()
	if qa.has("qa_shot"):
		_run_qa(qa)

## QA switches for verifying exported builds (ignored unless passed):
##   -- qa_shot=<png> qa_delay=<sec> qa_quit=1 qa_flow=quickmatch|career
func _qa_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0].begins_with("qa_"):
			out[kv[0]] = kv[1]
	return out

func _run_qa(qa: Dictionary) -> void:
	var flow: String = qa.get("qa_flow", "")
	if flow == "quickmatch":
		league = null
		var lg := League.create_new({"coach": "QA", "team_id": "KFM", "quick": true, "settings": {"game_length": 0}}, 99)
		var mc := MatchController.new()
		change_screen(mc)
		await get_tree().process_frame
		while _busy:
			await get_tree().process_frame
		mc.match_finished.connect(func(s):
			print("QA match finished: ", s.get("state").score if s.has("state") else s)
			if qa.get("qa_quit", "0") == "1":
				get_tree().quit())
		mc.start({"league": lg, "home_id": "KFM", "away_id": "HBG", "user_side": 0, "game": {}, "tod": "evening", "title": "QA", "seed": 5, "autoplay": true})
	elif flow == "career":
		start_career({"coach": "QA Coach", "team_id": "IWF"}, 2)
	var delay := float(qa.get("qa_delay", "8"))
	await get_tree().create_timer(delay).timeout
	if qa.has("qa_shot"):
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(qa["qa_shot"])
		print("QA screenshot: ", qa["qa_shot"], " ", error_string(err))
	print("QA screen: ", screen.get_class() if screen != null else "none", " ", (screen.get_script() as Script).get_global_name() if screen != null and screen.get_script() != null else "")
	if qa.get("qa_quit", "0") == "1" and flow != "quickmatch":
		get_tree().quit()

func toast(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	_toast.modulate.a = 1.0
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)

func change_screen(node: Node) -> void:
	if _busy:
		node.queue_free()
		return
	_busy = true
	get_tree().paused = false
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.22)
	await tw.finished
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
		await get_tree().process_frame
	screen = node
	get_tree().root.add_child(node)
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "modulate:a", 0.0, 0.3)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false

# ================================================================= navigation

func go_main_menu() -> void:
	change_screen(MainMenu.new())

func go_hub(tab: String = "home") -> void:
	var h := Hub.new()
	h.initial_tab = tab
	change_screen(h)

func go_new_career() -> void:
	change_screen(NewCareerScreen.new())

func go_records() -> void:
	change_screen(RecordsScreen.new())

func quit_game() -> void:
	if league != null and slot >= 0:
		save()
	get_tree().quit()

# ================================================================= careers

func start_career(config: Dictionary, p_slot: int) -> void:
	league = League.create_new(config, int(Time.get_unix_time_from_system()) % 1000000 + randi() % 1000)
	slot = p_slot
	league.meta["onboarding"] = true
	league.add_news("%s takes over the %s. The rebuild starts now." % [league.coach_name, league.user_team().full_name()], "season")
	save()
	go_hub("home")

func load_career(p_slot: int) -> bool:
	var lg: League = SaveManager.load_league(p_slot)
	if lg == null:
		toast(SaveManager.last_error)
		return false
	league = lg
	slot = p_slot
	if SaveManager.last_error != "":
		toast(SaveManager.last_error)
	go_hub("home")
	return true

func save() -> bool:
	if league == null or slot < 0:
		return false
	var ok := SaveManager.save_league(league, slot)
	if ok:
		_update_global_records()
	return ok

func _update_global_records() -> void:
	var rec := SaveManager.load_records()
	var ut := league.user_team()
	var key := "%s|%d" % [league.coach_name, league.seed]
	var careers: Array = rec.get("careers", [])
	var entry := {"key": key, "coach": league.coach_name, "team": ut.full_name(), "abbr": ut.abbr,
		"seasons": league.history["user_seasons"].size(), "titles": league.history["champions"].filter(func(c): return c["team"] == ut.id).size(),
		"wins": league.history["user_seasons"].reduce(func(acc, s): return acc + int(s["w"]), 0),
		"losses": league.history["user_seasons"].reduce(func(acc, s): return acc + int(s["l"]), 0),
		"year": league.year, "primary": ut.primary.to_html(false), "secondary": ut.secondary.to_html(false), "logo": ut.logo}
	var found := false
	for i in careers.size():
		if careers[i].get("key", "") == key:
			careers[i] = entry
			found = true
	if not found:
		careers.append(entry)
	rec["careers"] = careers
	SaveManager.save_records(rec)

# ================================================================= matches

func difficulty_settings() -> Dictionary:
	return {"difficulty": Settings.get_value("difficulty"), "assist": Settings.get_value("assist"), "game_length": Settings.get_value("game_length")}

func start_franchise_match(g: Dictionary) -> void:
	var user_side := 0 if g["home"] == league.user_team_id else 1
	var title := "Week %d" % (int(g["week"]) + 1)
	if g.get("playoff", false):
		title = Season.round_name(league, int(g["round"]))
	var tod: String = "night" if g.get("playoff", false) else ["day", "evening", "night"][int(g["week"]) % 3]
	league.settings["assist"] = Settings.get_value("assist")
	var mc := MatchController.new()
	change_screen(mc)
	await get_tree().process_frame
	while _busy:
		await get_tree().process_frame
	mc.match_finished.connect(_on_franchise_match_finished.bind(g))
	mc.start({"league": league, "home_id": g["home"], "away_id": g["away"], "user_side": user_side,
		"playoff": g.get("playoff", false), "game": g, "tod": tod, "title": title, "seed": hash(g["id"]) + league.seed})

func _on_franchise_match_finished(summary: Dictionary, g: Dictionary) -> void:
	if summary.get("quit", false):
		# Abandoned games are not recorded; the week can be replayed or simulated.
		go_hub("home")
		return
	var st: GameState = summary["state"]
	var stats: StatsRecorder = summary["stats"]
	Season.finalize_game(league, g, st, stats)
	var won := st.winner == (0 if g["home"] == league.user_team_id else 1)
	FranchiseOps.after_user_game(league, won)
	last_report = Season.advance(league)
	last_report["user_game"] = g
	save()
	if last_report.get("events", []).has("champion") and league.history["champions"].back()["team"] == league.user_team_id:
		change_screen(ChampionshipScreen.new())
	else:
		go_hub("home")

func sim_user_week() -> Dictionary:
	var g := Season.user_game(league)
	if g.is_empty():
		last_report = Season.advance(league)
	else:
		var st := Season.sim_user_game(league, g)
		var won := st.winner == (0 if g["home"] == league.user_team_id else 1)
		FranchiseOps.after_user_game(league, won)
		last_report = Season.advance(league)
		last_report["user_game"] = g
	save()
	return last_report

func start_quick_match(home_id: String, away_id: String, user_home: bool, tod: String, settings: Dictionary) -> void:
	var lg := League.create_new({"coach": "Quick Match", "team_id": home_id if user_home else away_id, "settings": settings, "quick": true}, randi())
	# Quick Match uses established franchises at full strength.
	var mc := MatchController.new()
	change_screen(mc)
	await get_tree().process_frame
	while _busy:
		await get_tree().process_frame
	mc.match_finished.connect(func(_s): go_main_menu())
	mc.start({"league": lg, "home_id": home_id, "away_id": away_id, "user_side": 0 if user_home else 1, "playoff": false, "game": {}, "tod": tod, "title": "Quick Match", "seed": randi()})
