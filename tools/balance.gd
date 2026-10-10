extends SceneTree
## Balance harness: runs many bot-driven live plays and prints outcome stats.
## godot --headless --path . -s res://tools/balance.gd -- [n=200] [mode=pass|run|all]

var result: PlayResult
var info: Dictionary

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var n := int(args.get("n", "120"))
	var mode: String = args.get("mode", "all")
	var lg := League.create_new({"coach": "T", "team_id": "IWF"}, 77)
	var root := Node3D.new()
	get_root().add_child(root)
	var off_team: Team = lg.teams[args.get("off", "KFM")]
	var def_team: Team = lg.teams[args.get("def", "HBG")]
	var off_pool := Lineup.build_offense(root, lg, off_team, true, null)
	var def_pool := Lineup.build_defense(root, lg, def_team, false, null)
	var ball := Football.new()
	root.add_child(ball)
	var play := LivePlay.new()
	root.add_child(play)
	play.rng.seed = 1234
	var diff: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/difficulty.json"))["levels"][int(args.get("diff", "1"))]
	play.tune = diff
	play.assist = int(args.get("assist", "1"))
	play.play_over.connect(func(r, i): result = r; info = i)
	var pass_ids := ["quick_slants", "curl_flat", "outs", "post_dig", "corner_strike", "four_verts", "mesh", "rb_screen", "pa_post", "pa_boot", "rz_snag"]
	var run_ids := ["inside_zone", "outside_stretch", "power_dive", "hb_draw", "qb_keeper"]
	var defs := ["cover2", "cover3", "man1", "blitz", "nickel3"]
	var ids: Array = pass_ids + run_ids
	if mode == "pass": ids = pass_ids
	if mode == "run": ids = run_ids
	var stats := {"att": 0, "cmp": 0, "int": 0, "sack": 0, "pass_yds": 0.0, "runs": 0, "run_yds": 0.0, "run_big": 0, "run_neg": 0, "td": 0, "fum": 0}
	var reasons := {}
	var run_hist := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in n:
		var pid: String = ids[i % ids.size()]
		var did: String = defs[rng.randi_range(0, defs.size() - 1)]
		var is_run := Playbook.is_run(Playbook.play(pid))
		var plan := {"snap_at": 0.2, "throw_at": rng.randf_range(1.2, 2.4), "auto": true, "power": rng.randf_range(0.45, 0.8), "run": is_run, "weave": rng.randf_range(0.0, 0.5)}
		result = null
		play.input = BotInput.new(plan)
		play.setup(Playbook.play(pid), rng.randf() < 0.5, Playbook.defense_call(did), 30.0, 0.0, 1, 40.0, off_pool, def_pool, ball)
		for s in 2400:
			play._physics_process(1.0 / 60.0)
			if result != null:
				break
		if result == null:
			reasons["STALL"] = reasons.get("STALL", 0) + 1
			continue
		if info.get("touchdown", false): stats["td"] += 1
		match result.kind:
			PlayResult.Kind.PASS_COMPLETE:
				stats["att"] += 1; stats["cmp"] += 1; stats["pass_yds"] += result.gain
			PlayResult.Kind.PASS_INCOMPLETE:
				stats["att"] += 1
				var why := "incomplete"
				var pi: Dictionary = info.get("pass", {})
				if pi.has("breakup"): why = "breakup"
				elif pi.has("drop"): why = "drop"
				elif pi.get("underthrown", false): why = "underthrown"
				elif absf(float(pi.get("err_along", 0.0))) > 1.4: why = "along_error"
				elif absf(float(pi.get("err_lat", 0.0))) > 1.2: why = "lat_error"
				else: why = "no_reach"
				reasons[why] = reasons.get(why, 0) + 1
			PlayResult.Kind.INTERCEPTION:
				stats["att"] += 1; stats["int"] += 1
			PlayResult.Kind.SACK:
				stats["sack"] += 1
			PlayResult.Kind.RUN:
				stats["runs"] += 1; stats["run_yds"] += result.gain
				var b := int(clampf(floor(result.gain / 3.0) * 3.0, -6, 30))
				run_hist[b] = run_hist.get(b, 0) + 1
				if result.gain >= 15.0: stats["run_big"] += 1
				if result.gain < 0.0: stats["run_neg"] += 1
			PlayResult.Kind.FUMBLE_LOST:
				stats["fum"] += 1
	print("PASS: att %d cmp %d (%.0f%%) int %d sacks %d ypa %.1f" % [stats["att"], stats["cmp"], 100.0 * stats["cmp"] / maxf(stats["att"], 1), stats["int"], stats["sack"], stats["pass_yds"] / maxf(stats["att"], 1)])
	print("RUN: %d att %.1f ypc, 15+: %d, negative: %d" % [stats["runs"], stats["run_yds"] / maxf(stats["runs"], 1), stats["run_big"], stats["run_neg"]])
	print("TD %d fumbles lost %d" % [stats["td"], stats["fum"]])
	print("incomplete reasons: ", reasons)
	var keys := run_hist.keys(); keys.sort()
	var h := ""
	for k in keys: h += "%d:%d " % [k, run_hist[k]]
	print("run histogram: ", h)
	quit()
