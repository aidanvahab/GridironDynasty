class_name MatchController
extends Node3D
## Runs a complete game. The user controls the offense in real time; opponent
## possessions are simulated play-by-play through the same RulesEngine.
##
## cfg keys: league, home_id, away_id, user_side (0 home / 1 away), playoff,
##           game (schedule entry or {}), tod ("day"/"evening"/"night"),
##           seed, autoplay (bot plays the user's downs; for demos/tests),
##           title (e.g. "Week 3", "Crown Bowl")

signal match_finished(summary: Dictionary)

var cfg: Dictionary = {}
var league: League
var home: Team
var away: Team
var user_side: int = 0
var user_team: Team
var opp_team: Team
var rules: RulesEngine
var sim: DriveSimulator
var stats: StatsRecorder
var rng := RandomNumberGenerator.new()
var tune: Dictionary = {}
var assist: int = 1
var font: Font
var stadium: StadiumBuilder
var field: FieldBuilder
var off_pool: Dictionary = {}
var def_pool: Dictionary = {}
var kicker: FieldAgent
var opp_kicker: FieldAgent
var ball: Football
var live: LivePlay
var cam: BroadcastCamera
var hud: MatchHUD
var hud_layer: CanvasLayer
var kick: KickGame
var lateral: float = 0.0
var wind_mph: float = 0.0
var wind_angle: float = 0.0
var state_tag: String = "intro"
var sim_rest: bool = false
var autoplay: bool = false
var paused: bool = false
var quitting: bool = false
var replay_available: bool = false
var _choice: Dictionary = {}
var _continue_tag: String = ""
var _skip: bool = false
var _live_done: bool = false
var _live_result: PlayResult
var _live_info: Dictionary = {}
var _kick_done: bool = false
var _kick_made: bool = false
var _kick_info: Dictionary = {}
var _pending_halftime: bool = false
var _sideline: Array[PlayerRig] = []
var _scoreboard_labels: Dictionary = {}
var _replaying: bool = false
var _last_play_id: String = "inside_zone"
var _crowd_home_favor: float = 1.0
var _bot_rng := RandomNumberGenerator.new()
var _logo_vp: SubViewport

# ================================================================= setup

func start(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	league = cfg["league"]
	home = league.teams[cfg["home_id"]]
	away = league.teams[cfg["away_id"]]
	user_side = int(cfg.get("user_side", 0))
	user_team = home if user_side == 0 else away
	opp_team = away if user_side == 0 else home
	autoplay = bool(cfg.get("autoplay", false))
	rng.seed = int(cfg.get("seed", Time.get_ticks_usec()))
	_bot_rng.seed = rng.seed + 7
	var diffs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/difficulty.json"))
	var dlevel := clampi(int(league.settings.get("difficulty", 1)), 0, 3)
	tune = diffs["levels"][dlevel]
	var gl: Dictionary = diffs["game_lengths"][clampi(int(league.settings.get("game_length", 1)), 0, 3)]
	assist = int(league.settings.get("assist", 1))
	rules = RulesEngine.new(float(gl["quarter"]), float(gl["runoff"]), bool(cfg.get("playoff", false)), rng)
	stats = StatsRecorder.new()
	sim = DriveSimulator.new(rules, league, home, away, rng, stats)
	sim.apply_difficulty(user_side, float(tune["sim_bonus"]), float(tune["cpu_turnovers"]))
	font = UI.font("heading")
	wind_mph = maxf(0.0, rng.randfn(4.0, 4.0))
	wind_angle = rng.randf() * TAU
	_crowd_home_favor = 1.0 if user_side == 0 else -1.0
	_build_world()
	_build_hud()
	Audio.stop_music(1.5)
	Audio.crowd_start(0.35)
	_run_flow()

func _build_world() -> void:
	var quality := int(Settings.get_value("quality"))
	stadium = StadiumBuilder.new()
	add_child(stadium)
	stadium.build(home.stadium, home.primary, home.secondary, away.primary, str(cfg.get("tod", "day")), [0.35, 0.65, 1.0][quality], rng.randi())
	stadium.apply_quality(quality)
	field = FieldBuilder.new()
	add_child(field)
	field.build(home.primary, away.primary, home.name, away.name, font)
	field.set_midfield_logo(_bake_logo(home))
	_build_scoreboard_ui()
	off_pool = Lineup.build_offense(self, league, user_team, user_side == 0, font)
	def_pool = Lineup.build_defense(self, league, opp_team, user_side != 0, font)
	var uni_u := Lineup.uniform(user_team, user_side == 0)
	var uni_o := Lineup.uniform(opp_team, user_side != 0)
	kicker = _make_agent(league.starters(user_team, "K", 1)[0], FieldAgent.Unit.OFFENSE, "K", uni_u)
	opp_kicker = _make_agent(league.starters(opp_team, "K", 1)[0], FieldAgent.Unit.DEFENSE, "K", uni_o)
	kicker.visible = false
	opp_kicker.visible = false
	ball = Football.new()
	add_child(ball)
	live = LivePlay.new()
	add_child(live)
	live.tune = tune
	live.assist = assist
	live.separation_bonus = (league.staff_rating(user_team, "oc") - 2.5) * 2.0
	live.rng.seed = rng.randi()
	live.play_over.connect(_on_play_over)
	live.feedback.connect(func(t, c, b): hud.show_feedback(t, c, b))
	live.sfx.connect(_on_sfx)
	if autoplay:
		live.input = null
	else:
		live.input = HumanInput.new()
	kick = KickGame.new()
	add_child(kick)
	kick.rng.seed = rng.randi()
	kick.kicked.connect(func(_p): Audio.play("kick", 1.0))
	kick.finished.connect(func(made, info):
		_kick_done = true
		_kick_made = made
		_kick_info = info)
	cam = BroadcastCamera.new()
	add_child(cam)
	cam.play = live
	live.camera = cam ## mouse aiming projects through the broadcast camera
	cam.assist = bool(Settings.get_value("camera_assist"))
	cam.shake_enabled = bool(Settings.get_value("camera_shake"))
	cam.set_mode(BroadcastCamera.Mode.ORBIT, true)
	_build_sideline()

func _make_agent(p: Player, unit: FieldAgent.Unit, slot: String, uni: Dictionary) -> FieldAgent:
	var a := FieldAgent.new()
	add_child(a)
	a.setup(p, unit, slot, p.pos, uni["jersey"], uni["pants"], uni["helmet"], uni["trim"], uni["mask"], font)
	return a

func _bake_logo(t: Team) -> Texture2D:
	_logo_vp = SubViewport.new()
	_logo_vp.size = Vector2i(512, 512)
	_logo_vp.transparent_bg = true
	_logo_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var logo := TeamLogo.new()
	logo.configure(t.logo, t.primary, t.secondary, t.accent, t.name.substr(0, 1))
	logo.size = Vector2(512, 512)
	_logo_vp.add_child(logo)
	add_child(_logo_vp)
	return _logo_vp.get_texture()

func _build_scoreboard_ui() -> void:
	var vp := stadium.scoreboard_viewport
	var root := ColorRect.new()
	root.color = Palette.NAVY
	root.size = Vector2(vp.size)
	vp.add_child(root)
	var title := UI.label(league.league_name.to_upper(), 30, Palette.GOLD, "heading")
	title.position = Vector2(0, 10)
	title.size = Vector2(vp.size.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	for side in 2:
		var t := home if side == 0 else away
		var x := 40.0 if side == 1 else vp.size.x * 0.5 + 40.0
		var name_l := UI.label(t.abbr, 64, t.primary.lightened(0.35), "display")
		name_l.position = Vector2(x, 60)
		root.add_child(name_l)
		var sc := UI.label("0", 110, Palette.CREAM, "display")
		sc.position = Vector2(x + 170, 40)
		root.add_child(sc)
		_scoreboard_labels["s%d" % side] = sc
	var clock := UI.label("", 46, Palette.ORANGE, "display")
	clock.position = Vector2(0, 200)
	clock.size = Vector2(vp.size.x, 60)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(clock)
	_scoreboard_labels["clock"] = clock

func _update_scoreboard() -> void:
	if _scoreboard_labels.is_empty():
		return
	for side in 2:
		(_scoreboard_labels["s%d" % side] as Label).text = str(rules.state.score[side])
	var s := rules.state
	(_scoreboard_labels["clock"] as Label).text = "%s  %s   %s" % [rules.quarter_label(), RulesEngine.format_clock(s.clock), rules.describe_down()]

func _build_sideline() -> void:
	for side in 2:
		var t := home if side == 0 else away
		var uni := Lineup.uniform(t, side == 0)
		var z := -(FieldCoords.HALF_WIDTH + 4.2) if side == 0 else (FieldCoords.HALF_WIDTH + 4.2)
		for i in 9:
			var r := PlayerRig.new()
			add_child(r)
			r.build(uni["jersey"], uni["pants"], uni["helmet"], uni["trim"], uni["mask"], rng.randi_range(2, 98), rng.randi_range(0, 5), rng.randf_range(0.95, 1.2), font)
			r.position = Vector3(-18.0 + i * 4.5 + rng.randf_range(-1, 1), 0, z + rng.randf_range(-0.6, 0.6))
			r.rotation.y = 0.0 if side == 0 else PI
			r.set_pose(PlayerRig.Pose.IDLE)
			r.pose_time = rng.randf() * 3.0
			r.set_meta("side", side)
			_sideline.append(r)

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud_layer)
	hud = MatchHUD.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(hud)
	hud.set_teams(home, away, user_side)
	hud.play_chosen.connect(func(id, f, tempo): _choice = {"type": "play", "id": id, "flip": f, "tempo": tempo})
	hud.special_chosen.connect(func(k): _choice = {"type": "special", "kind": k})
	hud.try_chosen.connect(func(k): _choice = {"type": "try", "kind": k})
	hud.continue_pressed.connect(func(tag):
		_continue_tag = tag
		if tag == "drive_skip":
			_skip = true)
	hud.pause_action.connect(_on_pause_action)
	hud.update_scorebug(rules)

# ================================================================= frame

func _process(delta: float) -> void:
	if rules == null:
		return
	var running := live.t if (live != null and live.stage == LivePlay.Stage.LIVE and state_tag == "live") else 0.0
	hud.update_scorebug(rules, running)
	_update_scoreboard()
	for r in _sideline:
		r.animate(delta)
	if state_tag == "live" or state_tag == "presnap":
		var charging := live.charge > 0.0 and live.stage == LivePlay.Stage.LIVE and not live.thrown
		hud.set_charge(live.charge, charging, live.pressure)
		if live.stage == LivePlay.Stage.LIVE:
			var c := live.ball.carrier as FieldAgent
			if c == live.qb and not live.thrown and not live.ran_past_los:
				if live.designed_run:
					hud.set_hints("")
				elif assist >= 2:
					hud.set_hints("[1-5] / Receiver button: throw   ·   [WASD] move   ·   [E] throw away")
				else:
					hud.set_hints("[1-5] pick receiver   ·   Hold/Release [Mouse] to throw   ·   [WASD] move   ·   [E] throw away")
			elif c != null and c.unit == FieldAgent.Unit.OFFENSE:
				hud.set_hints("[WASD] run   ·   [Shift] sprint   ·   [Space] juke   ·   [C] dive")
			else:
				hud.set_hints("")
	else:
		hud.set_charge(0.0, false, 0.0)
	if state_tag == "kick":
		hud.update_kick(kick)
	if bool(Settings.get_value("debug_overlay")) and OS.is_debug_build():
		hud.set_debug(_debug_text())
	else:
		hud.set_debug("")
	if autoplay and state_tag == "presnap" and live.stage == LivePlay.Stage.PRESNAP and live.input == null:
		live.input = _bot_input_for(live.play_def)

func _debug_text() -> String:
	var s := rules.state
	var t := "phase=%s state=%s q=%d clock=%.1f poss=%d ball_on=%.1f down=%d fd=%.1f dir=%d lat=%.1f\nsave=%s\n" % [GameState.Phase.keys()[s.phase], state_tag, s.quarter, s.clock, s.possession, s.ball_on, s.down, s.first_down_line, s.offense_dir(), lateral, SaveManager.last_error if SaveManager.last_error != "" else "ok"]
	if state_tag in ["live", "presnap"]:
		t += live.debug_info()
	return t

func _bot_input_for(p: Dictionary) -> BotInput:
	var is_run := Playbook.is_run(p)
	return BotInput.new({"snap_at": 0.4, "throw_at": _bot_rng.randf_range(1.3, 2.3), "auto": true, "power": _bot_rng.randf_range(0.5, 0.75), "run": is_run, "weave": _bot_rng.randf_range(0.0, 0.4)})

# ================================================================= input

func _input(event: InputEvent) -> void:
	if live != null and live.input is HumanInput and not paused:
		(live.input as HumanInput).push_event(event)

func _unhandled_input(event: InputEvent) -> void:
	if quitting:
		return
	if event.is_action_pressed("pause") and not hud.modal_open() and state_tag != "post":
		_open_pause()
		get_viewport().set_input_as_handled()
		return
	if paused:
		return
	if event.is_action_pressed("debug_toggle") and OS.is_debug_build():
		Settings.set_value("debug_overlay", not bool(Settings.get_value("debug_overlay")))
	if state_tag == "presnap" and live.stage == LivePlay.Stage.PRESNAP:
		if event.is_action_pressed("flip_play"):
			_setup_snap(live.play_def["id"], not live.flip)
			hud.toast("Play flipped")
		elif event.is_action_pressed("audible"):
			var alt: String = live.play_def.get("audible", "")
			if alt != "" and rules.state.phase == GameState.Phase.SCRIMMAGE:
				_setup_snap(alt, false)
				hud.toast("Audible: " + str(Playbook.play(alt)["name"]))
		elif event.is_action_pressed("timeout"):
			if rules.call_timeout(user_side):
				hud.toast("Timeout %s — %d left" % [user_team.abbr, rules.state.timeouts[user_side]])
				Audio.play("whistle", 0.6)
			else:
				hud.toast("No timeouts / clock already stopped")
		elif event.is_action_pressed("toggle_routes"):
			live.set_overlay_visible(not live.route_overlay.visible)
	if (state_tag == "drive" or state_tag == "replay") and (event.is_action_pressed("snap") or event.is_action_pressed("ui_accept")):
		_skip = true
	if event.is_action_pressed("replay") and replay_available and state_tag == "play_select":
		hud.hide_play_select()
		_choice = {"type": "replay"}

func _open_pause() -> void:
	paused = true
	get_tree().paused = true
	hud.show_pause(true)
	Audio.ui("click")

func _on_pause_action(action: String) -> void:
	match action:
		"resume":
			hud.close_overlay()
			paused = false
			get_tree().paused = false
		"controls":
			hud.show_controls()
		"back":
			hud.show_pause(true)
		"settings":
			var panel := SettingsPanel.new()
			panel.closed.connect(func(): hud.show_pause(true))
			hud.close_overlay()
			hud_layer.add_child(panel)
			cam.assist = bool(Settings.get_value("camera_assist"))
		"sim":
			hud.close_overlay()
			paused = false
			get_tree().paused = false
			sim_rest = true
			hud.hide_play_select()
			_choice = {"type": "sim"}
			if state_tag == "presnap" and live.stage == LivePlay.Stage.PRESNAP:
				live.stage = LivePlay.Stage.IDLE
				_live_done = true
				_live_result = null
		"quit":
			hud.close_overlay()
			paused = false
			get_tree().paused = false
			quitting = true
			match_finished.emit({"quit": true})

# ================================================================= helpers

func _wait(sec: float, skippable: bool = false) -> void:
	var t := 0.0
	while t < sec:
		if quitting:
			return
		if skippable and _skip:
			return
		await get_tree().process_frame
		if not paused:
			t += get_process_delta_time()

func _wait_continue(tag: String) -> void:
	_continue_tag = ""
	while _continue_tag != tag and not quitting:
		if autoplay:
			await _wait(0.6)
			_continue_tag = tag
			break
		await get_tree().process_frame
	hud.close_overlay()

func _side_team(side: int) -> Team:
	return home if side == 0 else away

func _dir_for(side: int) -> int:
	return rules.state.dir_for(side)

func _update_markers() -> void:
	var s := rules.state
	if s.phase == GameState.Phase.SCRIMMAGE:
		field.show_down_markers(s.ball_on, s.first_down_line, s.offense_dir(), s.down, true)
	else:
		field.hide_down_markers()

func _crowd_for(side_benefits: int, strength: float) -> void:
	## React to an event that benefits `side_benefits`, scaled by home favoritism.
	var home_good := side_benefits == 0
	if home_good:
		Audio.crowd_react("roar" if strength > 0.75 else "cheer", strength)
		stadium.pulse(clampf(0.5 + strength * 0.5, 0.0, 1.0))
	else:
		Audio.crowd_react("groan", 0.5 + strength * 0.4)
		stadium.pulse(0.15)

func _update_crowd_level() -> void:
	var s := rules.state
	var lvl := 0.3
	var diff := absi(s.score[0] - s.score[1])
	if s.quarter >= 4 and diff <= 8:
		lvl += 0.25
	if s.phase == GameState.Phase.SCRIMMAGE and s.ball_on >= 80.0:
		lvl += 0.15
	if s.is_overtime():
		lvl = 0.8
	Audio.crowd_level(lvl)
	stadium.set_excitement(lvl * 0.8)

func _on_sfx(name: String, _pos: Vector3, strength: float) -> void:
	match name:
		"snap": Audio.play("snap", 0.8)
		"throw": Audio.play("throw", 0.7 * strength + 0.3)
		"catch": Audio.play("catch", 0.9)
		"tackle":
			Audio.play("tackle", 0.6 + strength * 0.4)
			cam.add_shake(strength * 0.6)
		"sack":
			Audio.play("tackle", 1.0)
			cam.add_shake(0.8)
		"hit_light", "block": Audio.play("hit_light", 0.5 * strength)
		"whistle": Audio.play("whistle", 0.7)
		"deflect": Audio.play("hit_light", 0.6)
		"juke": Audio.play("juke", 0.7)
		"interception", "turnover", "fumble": Audio.play("turnover", 0.8)
		"incomplete": pass
		"touchdown": pass

# ================================================================= flow

func _run_flow() -> void:
	await _intro()
	var guard := 0
	while not rules.state.is_over() and not quitting and guard < 2000:
		guard += 1
		_update_crowd_level()
		match rules.state.phase:
			GameState.Phase.KICKOFF:
				await _kickoff()
			GameState.Phase.TRY:
				await _try()
			GameState.Phase.SCRIMMAGE:
				if rules.state.possession == user_side and not sim_rest:
					await _user_down()
				else:
					await _sim_drive()
		if _pending_halftime and not quitting:
			_pending_halftime = false
			await _halftime()
	if not quitting:
		await _postgame()

func _intro() -> void:
	state_tag = "intro"
	cam.set_mode(BroadcastCamera.Mode.ORBIT, true)
	field.hide_down_markers()
	for a in off_pool.values() + def_pool.values():
		a.visible = false
	var title: String = cfg.get("title", "")
	hud.show_banner("%s  vs  %s" % [away.abbr, home.abbr], (title + "  ·  " if title != "" else "") + "%s Stadium" % home.city, Palette.GOLD, 2.2)
	Audio.play("horn", 0.6)
	await _wait(3.0, true)
	_skip = false
	# Coin toss: the winner elects to receive.
	var receiver := rng.randi_range(0, 1)
	var winner := _side_team(receiver)
	hud.show_banner("COIN TOSS", "%s win the toss and will receive" % winner.name, Palette.CREAM, 1.6)
	await _wait(2.0, true)
	_skip = false
	rules.start_game(receiver)

func _process_events(events: Array) -> void:
	for e in events:
		match e["type"]:
			"first_down":
				Audio.play("first_down", 0.6)
			"two_minute_warning":
				hud.show_banner("TWO-MINUTE WARNING", "", Palette.GOLD, 1.2)
				Audio.play("whistle", 0.5)
			"quarter_end":
				hud.show_banner("END OF Q%d" % e["quarter"], "Teams switch ends", Palette.CREAM, 1.2)
				Audio.play("whistle_long", 0.7)
			"halftime":
				_pending_halftime = true
				Audio.play("whistle_long", 0.8)
			"overtime":
				hud.show_banner("OVERTIME", "%s receive" % _side_team(e["receiver"]).name, Palette.ORANGE, 2.0)
				Audio.play("whistle_long", 0.8)
			"score":
				var t := _side_team(e["side"])
				var kind: String = e["kind"]
				var title: String = {"touchdown": "TOUCHDOWN!", "defensive_td": "TOUCHDOWN!", "field_goal": "FIELD GOAL", "safety": "SAFETY!", "xp": "", "two_point": "TWO-POINT GOOD"}.get(kind, "")
				if title != "":
					hud.show_banner(title, t.full_name().to_upper(), t.primary.lightened(0.3) if t.primary.get_luminance() < 0.35 else t.primary, 1.8)
				if kind in ["touchdown", "defensive_td"]:
					Audio.play("horn", 0.8)
					_crowd_for(e["side"], 1.0)
					_sideline_celebrate(e["side"])
				elif kind in ["field_goal", "safety", "two_point"]:
					_crowd_for(e["side"], 0.6)
			"turnover":
				_crowd_for(1 - e["side"], 0.8)
			"turnover_on_downs":
				hud.show_banner("TURNOVER ON DOWNS", "", Palette.RED, 1.2)
				_crowd_for(1 - e["side"], 0.6)
			"game_over":
				Audio.play("whistle_long", 1.0)

func _sideline_celebrate(side: int) -> void:
	for r in _sideline:
		if r.get_meta("side") == side:
			r.set_pose(PlayerRig.Pose.CELEBRATE)
			r.pose_time = randf()
	await _wait(3.0)
	for r in _sideline:
		r.set_pose(PlayerRig.Pose.IDLE)

# ================================================================= kickoffs & punts

func _kickoff() -> void:
	state_tag = "kick_show"
	var kicking := rules.state.kicking_side
	var dir_k := _dir_for(kicking)
	var free := rules.state.free_kick
	hud.set_hints("")
	field.hide_down_markers()
	for a in off_pool.values() + def_pool.values():
		a.visible = false
	var res := sim.simulate_kickoff()
	var from := FieldCoords.to_world(20.0 if free else 35.0, 0.0, dir_k)
	var land_k := clampf((20.0 if free else 35.0) + float(res.get("kick_yards", 60.0)), 70.0, 108.0)
	var land := FieldCoords.to_world(land_k, rng.randf_range(-6.0, 6.0), dir_k)
	var end_k := 100.0 - float(res["receiver_ball_on"])
	if res["touchback"]:
		end_k = 100.0 - RulesEngine.KICKOFF_TOUCHBACK
	var end := FieldCoords.to_world(end_k, rng.randf_range(-8.0, 8.0), dir_k)
	await _show_kick(from, land, end, kicking, not res["touchback"], 2.6)
	var recv_team := _side_team(1 - kicking)
	var msg := "Touchback" if res["touchback"] else "Kickoff returned %d yards" % int(round(res.get("return_yards", 0.0)))
	if res["return_td"]:
		msg = "KICKOFF RETURN TOUCHDOWN!"
	hud.show_feedback("%s — %s" % [recv_team.abbr, msg], Palette.CREAM, false)
	_process_events(res["events"])
	lateral = 0.0
	await _wait(1.0)

## Visible kick: ball arcs from `from` to `land`; a returner fields it and
## carries to `end` while the coverage team converges.
func _show_kick(from: Vector3, land: Vector3, end: Vector3, kicking_side: int, returned: bool, hang: float) -> void:
	var kicker_agent := kicker if kicking_side == user_side else opp_kicker
	var dir_k := _dir_for(kicking_side)
	kicker_agent.visible = true
	kicker_agent.reset_for_play(from - FieldCoords.forward(dir_k) * 3.0, FieldCoords.forward(dir_k))
	# Returner and coverage come from the agent pools.
	var ret_pool := off_pool if (1 - kicking_side) == user_side else def_pool
	var cov_pool := off_pool if kicking_side == user_side else def_pool
	var returner: FieldAgent = ret_pool["S"] if ret_pool.has("S") else ret_pool["CB3"]
	returner.visible = true
	returner.reset_for_play(Vector3(land.x, 0, land.z), -FieldCoords.forward(dir_k))
	var cover: Array[FieldAgent] = []
	var i := 0
	for k in cov_pool:
		if i >= 8:
			break
		var a: FieldAgent = cov_pool[k]
		if a == returner:
			continue
		a.visible = true
		a.reset_for_play(from + FieldCoords.offense_right(dir_k) * (-14.0 + i * 4.0) - FieldCoords.forward(dir_k) * 1.0, FieldCoords.forward(dir_k))
		a.rig.set_pose(PlayerRig.Pose.RUN)
		cover.append(a)
		i += 1
	cam.anchor = from
	cam.kick_target = land
	cam.dir = dir_k
	cam.tracked = ball
	cam.set_mode(BroadcastCamera.Mode.KICK, true)
	ball.visible = true
	ball.global_position = from + Vector3(0, 0.2, 0)
	await _wait(0.3)
	kicker_agent.rig.set_pose(PlayerRig.Pose.KICK)
	kicker_agent.vel = FieldCoords.forward(dir_k) * 6.0
	Audio.play("kick", 1.0)
	# Choose a launch speed that gives roughly the requested hang time.
	var dist := Vector2(land.x - from.x, land.z - from.z).length()
	var vy := PassMath.GRAVITY * hang * 0.5
	var vh := dist / hang
	var vel := Vector3(land.x - from.x, 0, land.z - from.z).normalized() * vh + Vector3.UP * vy
	ball.launch(from + Vector3(0, 0.3, 0), vel, null, true)
	var t := 0.0
	while t < hang and not quitting:
		var dt := get_process_delta_time()
		if not paused:
			t += dt
			ball.step(dt)
			for a in cover:
				a.seek(Vector3(land.x, 0, land.z), 0.9, dt)
				a.integrate(dt)
				a.rig.animate(dt)
			kicker_agent.steer(Vector3.ZERO, dt)
			kicker_agent.integrate(dt)
			kicker_agent.rig.animate(dt)
			returner.face_toward(from)
			returner.rig.set_pose(PlayerRig.Pose.CATCH if hang - t < 0.6 else PlayerRig.Pose.IDLE)
			returner.rig.animate(dt)
		await get_tree().process_frame
	ball.give_to(returner)
	returner.rig.carrying = true
	if returned:
		cam.set_mode(BroadcastCamera.Mode.LIVE)
		live.ball = ball
		var run_t := 0.0
		var dur := clampf(Vector2(end.x - land.x, end.z - land.z).length() / 8.0, 0.6, 4.0)
		while run_t < dur and not quitting:
			var dt := get_process_delta_time()
			if not paused:
				run_t += dt
				returner.seek(Vector3(end.x, 0, end.z), 1.0, dt, 0.2)
				returner.integrate(dt)
				returner.rig.set_pose(PlayerRig.Pose.RUN)
				returner.rig.animate(dt)
				ball.step(dt)
				for a in cover:
					a.seek(returner.flat_pos() + returner.vel * 0.3, 1.0, dt)
					a.integrate(dt)
					a.rig.animate(dt)
			await get_tree().process_frame
		returner.go_down()
		Audio.play("tackle", 0.7)
		for k2 in 30:
			returner.rig.animate(1.0 / 60.0)
	else:
		returner.rig.set_pose(PlayerRig.Pose.IDLE)
		returner.rig.carrying = true
	await _wait(0.6)
	kicker_agent.visible = false

func _punt() -> void:
	state_tag = "kick_show"
	var punting := rules.state.possession
	var dir_p := _dir_for(punting)
	var ball_on := rules.state.ball_on
	hud.hide_play_select()
	field.hide_down_markers()
	for a in off_pool.values() + def_pool.values():
		a.visible = false
	rules.pre_snap(RulesEngine.Tempo.NORMAL)
	var out := sim.simulate_punt()
	var pres: Dictionary = out["punt"]
	var from := FieldCoords.to_world(ball_on - 12.0, lateral, dir_p)
	var land := FieldCoords.to_world(minf(ball_on + float(pres["gross"]), 108.0), lateral + rng.randf_range(-6, 6), dir_p)
	var end_p := 100.0 - float(pres["receiver_ball_on"])
	var end := FieldCoords.to_world(end_p, lateral + rng.randf_range(-6, 6), dir_p)
	await _show_kick(from, land, end, punting, not pres["touchback"] and not pres["fair_catch"], 3.4)
	hud.show_feedback(out["text"], Palette.CREAM, false)
	_process_events(out["events"])
	lateral = 0.0
	await _wait(1.2)

# ================================================================= user offense

func _context() -> Dictionary:
	var s := rules.state
	var off := user_side
	var diff := s.score[off] - s.score[1 - off]
	var fg_dist := KickModel.fg_distance(s.ball_on)
	var kp := kicker.player.effective("kick_power")
	var ka := kicker.player.effective("kick_acc")
	var fg_pct := KickModel.fg_probability(fg_dist, kp, ka) if fg_dist <= KickModel.max_range(kp) + 4.0 else 0.0
	var late := (s.quarter == 2 or s.quarter >= 4) and s.clock < 120.0
	var sit := "%s  ·  %s" % [rules.describe_down(), FieldCoords.describe_spot(s.ball_on, user_team.abbr, opp_team.abbr)]
	if late:
		sit += "  ·  %s left" % RulesEngine.format_clock(s.clock)
	return {
		"down": s.down, "togo": s.yards_to_go(), "ball_on": s.ball_on, "clock": s.clock,
		"quarter": s.quarter, "diff": diff, "timeouts": s.timeouts[off], "fg_dist": fg_dist,
		"fg_pct": fg_pct, "can_kneel": diff > 0 and s.quarter >= 4 or (s.quarter == 2 and s.clock < 60.0),
		"can_spike": late and s.clock_running, "clock_running": s.clock_running,
		"can_run_out": s.quarter >= 4 and diff > 0 and s.clock <= float(5 - s.down) * 40.0 * rules.runoff_scale + 2.0,
		"situation": sit, "suggested": Playbook.suggested(s.down, s.yards_to_go(), s.ball_on, s.clock, s.quarter, diff),
	}

func _user_down() -> void:
	state_tag = "play_select"
	_update_markers()
	var s := rules.state
	var dir := s.offense_dir()
	# Preview the offense in the huddle-ish formation while choosing.
	_setup_snap(_last_play_id, false, true)
	cam.dir = dir
	cam.anchor = FieldCoords.to_world(s.ball_on, lateral, dir)
	cam.set_mode(BroadcastCamera.Mode.PRESNAP)
	_choice = {}
	if autoplay:
		_choice = _auto_choice()
	else:
		hud.show_play_select(_context())
		hud.set_hints("")
		if replay_available:
			hud.toast("Press [V] to watch the replay")
	while _choice.is_empty() and not quitting:
		await get_tree().process_frame
	hud.hide_play_select()
	if quitting:
		return
	var choice := _choice
	_choice = {}
	match choice["type"]:
		"sim":
			return
		"replay":
			await _replay()
			return
		"special":
			match choice["kind"]:
				"fg":
					await _field_goal()
				"punt":
					await _punt()
				"timeout":
					if rules.call_timeout(user_side):
						hud.toast("Timeout — %d left" % rules.state.timeouts[user_side])
						Audio.play("whistle", 0.6)
					else:
						hud.toast("Timeout not available")
				"run_out":
					_process_events(rules.run_out_clock())
			return
		"play":
			_last_play_id = choice["id"]
			await _run_snap(choice["id"], choice["flip"], choice["tempo"], false)

func _auto_choice() -> Dictionary:
	var s := rules.state
	var fg_dist := KickModel.fg_distance(s.ball_on)
	if s.down == 4:
		if fg_dist <= KickModel.max_range(kicker.player.effective("kick_power")) - 3.0:
			return {"type": "special", "kind": "fg"}
		if s.yards_to_go() > 2.0 or s.ball_on < 45.0:
			return {"type": "special", "kind": "punt"}
	var sug := Playbook.suggested(s.down, s.yards_to_go(), s.ball_on, s.clock, s.quarter, s.score[user_side] - s.score[1 - user_side])
	var id: String = sug[_bot_rng.randi_range(0, sug.size() - 1)] if not sug.is_empty() else "inside_zone"
	return {"type": "play", "id": id, "flip": _bot_rng.randf() < 0.5, "tempo": RulesEngine.Tempo.NORMAL}

func _setup_snap(play_id: String, flip: bool, preview: bool = false) -> void:
	var s := rules.state
	var p := Playbook.play(play_id)
	if p.is_empty():
		p = Playbook.play("inside_zone")
	var def_call := _choose_defense()
	var los := s.ball_on
	var fd := s.first_down_line
	live.setup(p, flip, def_call, los, lateral, s.offense_dir(), fd, off_pool, def_pool, ball)
	live.set_overlay_visible(bool(Settings.get_value("show_routes")) and not preview)
	if preview:
		live.stage = LivePlay.Stage.IDLE
		live.route_overlay.visible = false
		for r in live.receivers:
			r.show_tag("")
	if autoplay:
		live.input = null

## CPU defensive play-calling based on situation and the team's style.
func _choose_defense() -> Dictionary:
	var s := rules.state
	var togo := s.yards_to_go()
	var style := opp_team.defense_style
	var opts: Array[String] = []
	if s.ball_on >= 95.0:
		opts = ["goal_line", "goal_line", "blitz", "man1"]
	elif s.quarter >= 4 and s.clock < 90.0 and s.score[1 - user_side] > s.score[user_side] and togo > 5.0:
		opts = ["prevent", "cover3", "nickel3"]
	elif togo >= 8.0:
		opts = ["cover3", "cover2", "nickel3", "man1"]
	elif togo <= 2.0:
		opts = ["blitz", "cover3", "man1", "goal_line" if s.ball_on > 90.0 else "cover2"]
	else:
		opts = ["cover2", "cover3", "man1", "nickel3", "blitz"]
	if style == "aggressive":
		opts.append_array(["blitz", "man1"])
	elif style == "conservative":
		opts.append_array(["cover2", "cover3"])
	return Playbook.defense_call(opts[rng.randi_range(0, opts.size() - 1)])

func _run_snap(play_id: String, flip: bool, tempo: int, two_point: bool) -> void:
	var events: Array = []
	if not two_point:
		events = rules.pre_snap(tempo)
		_process_events(events)
	_setup_snap(play_id, flip)
	state_tag = "presnap"
	_update_markers()
	if two_point:
		field.show_down_markers(rules.state.ball_on, 100.0, rules.state.offense_dir(), 1, false)
	var s := rules.state
	cam.anchor = FieldCoords.to_world(s.ball_on, lateral, s.offense_dir())
	cam.set_mode(BroadcastCamera.Mode.PRESNAP)
	if not autoplay:
		var p := Playbook.play(play_id)
		var hint := "[Space] snap   ·   [F] flip   ·   [R] audible   ·   [T] timeout   ·   [Tab] routes"
		if p.get("special", "") != "":
			hint = "[Space] snap"
		hud.set_hints(hint)
		_tutorial_hint("presnap", "Defense is set. Read the coverage, then press SPACE to snap. Numbers above receivers are the keys to target them.")
	_live_done = false
	_live_result = null
	var snapped := false
	while not _live_done and not quitting:
		if not snapped and live.stage == LivePlay.Stage.LIVE:
			snapped = true
			state_tag = "live"
			cam.set_mode(BroadcastCamera.Mode.LIVE)
			if not autoplay:
				if Playbook.is_run(live.play_def) and not live.qb_run:
					_tutorial_hint("run", "Handoff! Steer the back with WASD, hold SHIFT to sprint, SPACE to juke and C to dive.")
				elif Playbook.is_pass(live.play_def):
					_tutorial_hint("pass", "Press 1-5 to pick a receiver (or point with the mouse). Hold the left mouse button to charge, release to throw. Lead your receiver!")
		if live.touchdown and live.celebrated and cam.mode != BroadcastCamera.Mode.CELEBRATE:
			cam.set_mode(BroadcastCamera.Mode.CELEBRATE)
		await get_tree().process_frame
	if quitting or _live_result == null:
		return
	state_tag = "result"
	hud.set_hints("")
	var r := _live_result
	var info := _live_info
	replay_available = live.recorder.frames.size() > 30
	if two_point:
		var success := bool(info.get("touchdown", false)) and str(info.get("turnover", "")) == ""
		hud.show_feedback("TWO-POINT CONVERSION GOOD!" if success else "Two-point try fails", Palette.GREEN if success else Palette.RED, true)
		_process_events(rules.apply_try("two", success))
	else:
		var los := rules.state.ball_on
		sim.record_play(user_side, 1 - user_side, r)
		var off_before := rules.state.possession
		var ev := rules.apply_scrimmage(r)
		_result_feedback(r, info, ev, los)
		_process_events(ev)
		if rules.state.possession == off_before and rules.state.phase == GameState.Phase.SCRIMMAGE:
			if r.kind != PlayResult.Kind.PASS_INCOMPLETE:
				lateral = FieldCoords.hash_lateral(float(info.get("end_lateral", lateral)))
		else:
			lateral = 0.0
	await _wait(0.9)
	# Automatic replay of touchdowns and turnovers.
	if (bool(info.get("touchdown", false)) or str(info.get("turnover", "")) != "") and not autoplay and not quitting:
		await _replay()

func _result_feedback(r: PlayResult, info: Dictionary, events: Array, los: float) -> void:
	var gain := int(round(r.gain))
	var fd := false
	for e in events:
		if e["type"] == "first_down":
			fd = true
	match r.kind:
		PlayResult.Kind.PASS_COMPLETE:
			if not info.get("touchdown", false):
				hud.show_feedback("Complete, %+d yards%s" % [gain, " — FIRST DOWN" if fd else ""], Palette.GREEN, fd)
				if gain >= 15:
					_crowd_for(user_side, 0.6)
		PlayResult.Kind.RUN:
			if not info.get("touchdown", false):
				var txt := "Run %+d yards" % gain if gain != 0 else "No gain"
				if gain < 0:
					txt = "Tackled for a loss of %d" % absi(gain)
				hud.show_feedback(txt + (" — FIRST DOWN" if fd else ""), Palette.GREEN if gain > 0 else Palette.CREAM, fd)
				if gain >= 12:
					_crowd_for(user_side, 0.6)
		PlayResult.Kind.SACK:
			_crowd_for(1 - user_side, 0.5)
		_:
			pass

func _on_play_over(r: PlayResult, info: Dictionary) -> void:
	_live_result = r
	_live_info = info
	_live_done = true

# ================================================================= kicking

func _field_goal() -> void:
	state_tag = "kick"
	var s := rules.state
	rules.pre_snap(RulesEngine.Tempo.NORMAL)
	for a in off_pool.values() + def_pool.values():
		a.visible = false
	var ok := await _kick_play(s.ball_on - RulesEngine.FG_SNAP_DEPTH, false)
	var k := kicker.player
	stats.add(k.id, "fg_att", 1.0, user_side)
	if ok:
		stats.add(k.id, "fg_made", 1.0, user_side)
	var why: String = _kick_info.get("reason", "")
	if not ok:
		hud.show_feedback({"short": "No good — short", "wide_left": "No good — wide left", "wide_right": "No good — wide right"}.get(why, "No good"), Palette.RED, true)
		_crowd_for(1 - user_side, 0.6)
	_process_events(rules.apply_field_goal(ok, 5.0))
	lateral = 0.0
	await _wait(1.0)

## Runs the kicking mini-game from `kick_ball_on` (offense frame). Returns made.
func _kick_play(kick_ball_on: float, xp: bool) -> bool:
	var s := rules.state
	var dir := s.offense_dir()
	field.hide_down_markers()
	kicker.visible = true
	kick.setup(kicker, ball, dir, kick_ball_on, lateral, wind_mph, wind_angle, xp)
	if autoplay:
		kick.auto_plan = {"aim": kick.ideal_aim() + _bot_rng.randfn(0.0, 0.02), "power": clampf(_bot_rng.randf_range(0.78, 0.95), 0.0, 1.0)}
	else:
		kick.auto_plan = {}
		hud.set_hints("[A]/[D] aim   ·   [Space] start power, [Space] again to kick")
		_tutorial_hint("kick", "Aim with A/D (wind drifts the ball!). Press SPACE to start the power meter, SPACE again to kick. Over-swinging past the gold zone costs accuracy.")
	cam.anchor = FieldCoords.to_world(kick_ball_on, FieldCoords.hash_lateral(lateral), dir)
	cam.kick_target = Vector3(float(dir) * 60.0, 0, 0)
	cam.dir = dir
	cam.tracked = ball
	cam.set_mode(BroadcastCamera.Mode.KICK, true)
	_kick_done = false
	while not _kick_done and not quitting:
		await get_tree().process_frame
	hud.update_kick(null)
	hud.set_hints("")
	await _wait(0.6)
	kicker.visible = false
	return _kick_made

func _try() -> void:
	var side := rules.state.try_side
	if side != user_side or sim_rest:
		state_tag = "drive"
		var out := sim.simulate_try()
		var t := _side_team(side)
		hud.show_feedback("%s %s %s" % [t.abbr, "extra point" if out["kind"] == "kick" else "two-point try", "GOOD" if out["success"] else "NO GOOD"], Palette.CREAM, false)
		_process_events(out["events"])
		await _wait(1.0)
		return
	state_tag = "try"
	_update_markers()
	var xp_pct := KickModel.xp_probability(kicker.player.effective("kick_acc"))
	_choice = {}
	if autoplay:
		_choice = {"type": "try", "kind": "kick"}
	else:
		hud.show_try_choice(user_team, xp_pct)
	while _choice.is_empty() and not quitting:
		await get_tree().process_frame
	hud.close_overlay()
	if quitting:
		return
	var kind: String = _choice.get("kind", "kick")
	_choice = {}
	if kind == "kick":
		var made := await _kick_play(RulesEngine.TRY_KICK_SPOT - RulesEngine.FG_SNAP_DEPTH, true)
		stats.add(kicker.player.id, "xp_att", 1.0, user_side)
		if made:
			stats.add(kicker.player.id, "xp_made", 1.0, user_side)
		hud.show_feedback("Extra point is GOOD" if made else "Extra point NO GOOD", Palette.GREEN if made else Palette.RED, false)
		_process_events(rules.apply_try("kick", made))
	else:
		rules.state.ball_on = RulesEngine.TRY_TWO_SPOT
		lateral = 0.0
		state_tag = "play_select"
		_setup_snap("rz_snag", false, true)
		cam.anchor = FieldCoords.to_world(rules.state.ball_on, 0.0, rules.state.offense_dir())
		cam.set_mode(BroadcastCamera.Mode.PRESNAP)
		_choice = {}
		var ctx := _context()
		ctx["try"] = true
		ctx["situation"] = "TWO-POINT TRY  ·  from the 2"
		if autoplay:
			_choice = {"type": "play", "id": "goal_dive", "flip": false, "tempo": 1}
		else:
			hud.show_play_select(ctx)
		while (_choice.is_empty() or _choice.get("type") != "play") and not quitting:
			if not _choice.is_empty() and _choice.get("type") != "play":
				_choice = {}
			await get_tree().process_frame
		hud.hide_play_select()
		var c := _choice
		_choice = {}
		await _run_snap(c["id"], c["flip"], RulesEngine.Tempo.NORMAL, true)
	lateral = 0.0
	await _wait(0.6)

# ================================================================= opponent drive

func _sim_drive() -> void:
	state_tag = "drive"
	var s := rules.state
	var side := s.possession
	var t := _side_team(side)
	_skip = false
	for a in off_pool.values() + def_pool.values():
		a.visible = false
	ball.visible = false
	cam.anchor = FieldCoords.to_world(s.ball_on, 0.0, s.offense_dir())
	cam.dir = s.offense_dir()
	cam.set_mode(BroadcastCamera.Mode.WIDE)
	hud.start_drive(t, s.ball_on, side == 0)
	hud.set_hints("[Space] skip")
	var guard := 0
	var result := ""
	var start_q := s.quarter
	while s.phase == GameState.Phase.SCRIMMAGE and s.possession == side and not quitting and guard < 40:
		guard += 1
		_update_markers()
		cam.anchor = FieldCoords.to_world(s.ball_on, 0.0, s.offense_dir())
		cam.dir = s.offense_dir()
		var before_q := s.quarter
		var out := sim.simulate_play()
		var txt: String = out.get("text", "")
		if txt != "":
			var col := Palette.CREAM
			for e in out["events"]:
				if e["type"] == "score":
					col = Palette.GOLD
				elif e["type"] in ["turnover", "turnover_on_downs"]:
					col = Palette.GREEN if side != user_side else Palette.RED
			var drive_ball := s.ball_on if s.possession == side else (100.0 if col == Palette.GOLD else 100.0 - s.ball_on)
			hud.add_drive_line(txt, drive_ball, col)
		for e in out["events"]:
			match e["type"]:
				"score":
					result = {"touchdown": "Touchdown", "field_goal": "Field Goal", "safety": "Safety", "defensive_td": "Defensive Touchdown"}.get(e["kind"], "Score")
				"turnover":
					result = "Interception" if e["kind"] == "INTERCEPTION" else "Fumble"
				"turnover_on_downs":
					result = "Turnover on Downs"
				"fg_missed":
					result = "Missed Field Goal"
				"punt":
					result = "Punt"
		_process_events(out["events"])
		if side != user_side and out.get("call", "") == "pass" and out.has("result"):
			var pr: PlayResult = out["result"]
			if pr.kind == PlayResult.Kind.SACK:
				_crowd_for(user_side, 0.5)
		if not _skip:
			await _wait(0.6, true)
		if s.quarter != before_q and (before_q == 2 or before_q >= 4):
			break
		if _pending_halftime:
			break
	if result == "":
		result = "End of Half" if _pending_halftime else ("End of Game" if s.is_over() else ("End of Quarter" if s.quarter != start_q else "Drive Over"))
	var good_for_user := side != user_side and result in ["Punt", "Interception", "Fumble", "Turnover on Downs", "Missed Field Goal", "End of Half"]
	hud.end_drive(result, Palette.GREEN if good_for_user else (Palette.RED if side != user_side else Palette.GOLD))
	if result in ["Punt", "Interception", "Turnover on Downs"] and side != user_side:
		hud.show_feedback("DEFENSIVE STOP!", Palette.GREEN, true)
	await _wait(1.2 if not _skip else 0.4, false)
	_skip = false
	hud.hide_drive()
	hud.set_hints("")
	lateral = 0.0

# ================================================================= breaks

func _halftime() -> void:
	state_tag = "halftime"
	Audio.music("music_halftime")
	cam.set_mode(BroadcastCamera.Mode.ORBIT)
	hud.show_stats_panel("HALFTIME", "", rules, _leaders(), "START SECOND HALF", "half")
	await _wait_continue("half")
	Audio.stop_music(1.0)
	cam.set_mode(BroadcastCamera.Mode.WIDE)

func _leaders() -> Array:
	var out: Array = []
	for side in 2:
		var t := _side_team(side)
		var pl: Array = stats.leader(side, "pass_yds")
		if pl[0] != "" and float(pl[1]) > 0.0:
			var p: Player = league.players[pl[0]]
			out.append([t.abbr + " PASS", "%s  %d/%d, %d yds, %d TD" % [p.short_name(), stats.get_stat(p.id, "pass_cmp"), stats.get_stat(p.id, "pass_att"), stats.get_stat(p.id, "pass_yds"), stats.get_stat(p.id, "pass_td")]])
		var rl: Array = stats.leader(side, "rush_yds")
		if rl[0] != "" and float(rl[1]) > 0.0:
			var p2: Player = league.players[rl[0]]
			out.append([t.abbr + " RUSH", "%s  %d car, %d yds" % [p2.short_name(), stats.get_stat(p2.id, "rush_att"), stats.get_stat(p2.id, "rush_yds")]])
		var rc: Array = stats.leader(side, "rec_yds")
		if rc[0] != "" and float(rc[1]) > 0.0:
			var p3: Player = league.players[rc[0]]
			out.append([t.abbr + " REC", "%s  %d rec, %d yds" % [p3.short_name(), stats.get_stat(p3.id, "rec"), stats.get_stat(p3.id, "rec_yds")]])
	return out

func _postgame() -> void:
	state_tag = "post"
	hud.hide_play_select()
	hud.hide_drive()
	hud.set_hints("")
	var s := rules.state
	var won := s.winner == user_side
	var tie := s.winner == 2
	cam.set_mode(BroadcastCamera.Mode.ORBIT)
	Audio.crowd_level(0.9 if won else 0.25)
	if won:
		Audio.music("music_victory")
	var pog := stats.top_impact(-1)
	var pog_text := ""
	if pog != "" and league.players.has(pog):
		var p: Player = league.players[pog]
		pog_text = "Player of the Game: %s (%s)" % [p.full_name(), p.pos]
	var title := "VICTORY" if won else ("TIE GAME" if tie else "FINAL")
	hud.show_stats_panel(title, pog_text, rules, _leaders(), "CONTINUE", "post")
	await _wait_continue("post")
	Audio.stop_music(1.0)
	Audio.crowd_stop()
	match_finished.emit({"state": s, "stats": stats, "rules": rules, "user_side": user_side, "home_id": home.id, "away_id": away.id, "pog": pog, "game": cfg.get("game", {})})

# ================================================================= replay

func _replay() -> void:
	var rec := live.recorder
	if rec.frames.size() < 30:
		return
	state_tag = "replay"
	_replaying = true
	_skip = false
	hud.show_banner("REPLAY", "", Palette.TEAL, 0.8)
	hud.set_hints("[Space] skip replay")
	for a in rec.agents:
		(a as FieldAgent).visible = true
	cam.replay_angle += 1
	cam.dir = live.dir
	cam.set_mode(BroadcastCamera.Mode.REPLAY)
	var n := rec.frames.size()
	var start := maxi(0, n - int(12.0 * 60.0))
	var f := float(start)
	cam.tracked = ball
	rec.apply(start, ball)
	cam.snap_to_target()
	while f < n - 1 and not _skip and not quitting:
		var dt := get_process_delta_time()
		if not paused:
			f += dt * 60.0 * 0.55
			rec.apply(int(f), ball)
			for a in rec.agents:
				(a as FieldAgent).rig.animate(dt * 0.55)
		await get_tree().process_frame
	_skip = false
	_replaying = false
	hud.set_hints("")
	state_tag = "result"

# ================================================================= tutorial

func _tutorial_hint(key: String, text: String) -> void:
	if not bool(Settings.get_value("tutorial_enabled")):
		return
	var seen: Dictionary = Settings.get_value("tutorials_seen")
	if seen.get("match_" + key, false):
		return
	seen["match_" + key] = true
	Settings.set_value("tutorials_seen", seen)
	hud.show_tip(text)
