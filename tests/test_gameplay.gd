extends TestCase
## Headless live-play scenarios driven by BotInput. Physics is stepped manually.

var root: Node3D
var lg: League
var off_pool: Dictionary
var def_pool: Dictionary
var ball: Football
var play: LivePlay
var result: PlayResult
var info: Dictionary

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _setup(seed: int = 11) -> void:
	lg = League.create_new({"coach": "T", "team_id": "IWF"}, 77)
	root = Node3D.new()
	_tree().root.add_child(root)
	off_pool = Lineup.build_offense(root, lg, lg.teams["IWF"], true, null)
	def_pool = Lineup.build_defense(root, lg, lg.teams["HBG"], false, null)
	ball = Football.new()
	root.add_child(ball)
	play = LivePlay.new()
	root.add_child(play)
	play.rng.seed = seed
	play.tune = {"react": 0.3, "coverage_lag": 1.0, "tackle": 0.9, "rush": 0.9, "catch_bonus": 0.0, "int_mult": 0.85, "pursuit": 0.96}
	play.play_over.connect(func(r, i): result = r; info = i)

func _teardown() -> void:
	root.queue_free()

func _run(play_id: String, def_id: String, plan: Dictionary, los: float = 25.0, dir: int = 1, max_t: float = 40.0) -> void:
	result = null
	info = {}
	play.input = BotInput.new(plan)
	play.setup(Playbook.play(play_id), false, Playbook.defense_call(def_id), los, 0.0, dir, minf(los + 10.0, 100.0), off_pool, def_pool, ball)
	var steps := int(max_t * 60.0)
	for i in steps:
		play._physics_process(1.0 / 60.0)
		if result != null:
			return

func test_pass_play_produces_result() -> void:
	_setup()
	_run("quick_slants", "cover3", {"snap_at": 0.2, "throw_at": 1.3, "throw_to": 0, "power": 0.55})
	check(result != null, "play finished")
	if result:
		check(result.kind in [PlayResult.Kind.PASS_COMPLETE, PlayResult.Kind.PASS_INCOMPLETE, PlayResult.Kind.INTERCEPTION, PlayResult.Kind.SACK], "pass outcome %s" % result.kind_name())
		check(result.elapsed > 1.0 and result.elapsed < 30.0)
		print("        slant: %s gain %.1f (%s)" % [result.kind_name(), result.gain, info.get("reason")])
	_teardown()

func test_run_play_hands_off_and_gains() -> void:
	_setup()
	_run("inside_zone", "cover2", {"snap_at": 0.2, "run": false})
	check(result != null, "play finished")
	if result:
		eq(result.kind, PlayResult.Kind.RUN, "run play is a RUN")
		check(result.credit.has("rusher"))
		var rb: FieldAgent = off_pool["B"]
		eq(result.credit.get("rusher"), rb.player.id, "RB got the handoff")
		print("        inside zone: gain %.1f" % result.gain)
	_teardown()

func test_many_plays_never_stall_and_possession_is_exclusive() -> void:
	_setup(3)
	var ids := ["quick_slants", "curl_flat", "outs", "post_dig", "corner_strike", "four_verts", "mesh", "rb_screen", "inside_zone", "outside_stretch", "power_dive", "hb_draw", "pa_post", "pa_boot", "qb_keeper", "qb_sneak", "goal_dive", "rz_fade", "rz_snag", "hail_mary"]
	var defs := ["cover2", "cover3", "man1", "blitz", "nickel3", "prevent", "goal_line"]
	var kinds := {}
	var total_gain := 0.0
	var n := 0
	for k in 3:
		for i in ids.size():
			var pid: String = ids[i]
			var did: String = defs[(i + k) % defs.size()]
			var plan := {"snap_at": 0.2, "throw_at": 1.4 + 0.3 * (i % 4), "auto": true, "power": 0.5 + 0.1 * (i % 4), "run": Playbook.is_run(Playbook.play(pid)), "weave": 0.3 * (k % 2)}
			var los := 25.0 + float((i * 7) % 60)
			_run(pid, did, plan, los, 1 if (i + k) % 2 == 0 else -1)
			check(result != null, "%s vs %s finished" % [pid, did])
			if result == null:
				print("        STALL ", pid, " ", did, "\n", play.debug_info())
				continue
			kinds[result.kind_name()] = kinds.get(result.kind_name(), 0) + 1
			total_gain += result.gain
			n += 1
			check(result.gain > -25.0 and result.gain <= 100.0 - los + 0.01 or result.is_turnover(), "%s gain %.1f in range" % [pid, result.gain])
	print("        outcomes: ", kinds, " avg gain %.2f" % (total_gain / maxf(n, 1)))
	_teardown()

func test_kneel_and_spike() -> void:
	_setup()
	_run("kneel", "cover2", {"snap_at": 0.2})
	check(result != null)
	if result:
		eq(result.kind, PlayResult.Kind.KNEEL)
	_run("spike", "cover2", {"snap_at": 0.2})
	check(result != null)
	if result:
		eq(result.kind, PlayResult.Kind.SPIKE)
	_teardown()

func test_direction_minus_one_gains_are_positive_upfield() -> void:
	_setup(5)
	var gains := 0.0
	for i in 6:
		_run("inside_zone", "cover2", {"snap_at": 0.2}, 40.0, -1)
		if result:
			gains += result.gain
	check(gains > -6.0, "runs toward -X still gain yards (total %.1f)" % gains)
	_teardown()
