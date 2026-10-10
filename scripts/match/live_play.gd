class_name LivePlay
extends Node3D
## Runs one real-time offensive snap: alignment, snap, routes, blocking,
## coverage, passing, catching, running, tackling and turnovers. When the ball
## is dead it emits `play_over` with a PlayResult; the rules engine — not this
## class — decides downs, scores and possession.

signal play_over(result: PlayResult, info: Dictionary)
signal feedback(text: String, color: Color, big: bool)
signal sfx(name: String, pos: Vector3, strength: float)

enum Stage { IDLE, PRESNAP, LIVE, DEAD }

const CHARGE_TIME := 0.9 ## seconds of holding for full power
const RECEIVER_SLOTS := ["X", "Z", "S", "Y", "B"]
const SLOT_COLORS := {"X": Color("#F28C38"), "Z": Color("#42B7AD"), "S": Color("#F4C95D"), "Y": Color("#F5F0E5"), "B": Color("#65C987")}
const TACKLE_RANGE := 1.05
const MAX_PLAY_TIME := 30.0

var stage: Stage = Stage.IDLE
var offense: Array[FieldAgent] = []
var defense: Array[FieldAgent] = []
var slots: Dictionary = {}
var dslots: Dictionary = {}
var receivers: Array[FieldAgent] = []
var ball: Football
var camera: Camera3D
var input: PlayInput
var rng := RandomNumberGenerator.new()
var tune: Dictionary = {}
var assist: int = 1
var separation_bonus: float = 0.0 ## offensive coordinator effect
var dir: int = 1
var los: float = 25.0
var lat0: float = 0.0
var fd_line: float = 35.0
var play_def: Dictionary = {}
var flip: bool = false
var def_call: Dictionary = {}
var t: float = 0.0
var qb: FieldAgent
var user: FieldAgent
var thrown: bool = false
var pass_target: FieldAgent
var pass_land := Vector3.ZERO
var pass_info: Dictionary = {}
var pass_resolved: bool = false
var completed: bool = false
var handed_off: bool = false
var handoff_target: FieldAgent
var ran_past_los: bool = false
var charge: float = 0.0
var target_idx: int = -1
var end_reason: String = ""
var dead_t: float = 0.0
var credit: Dictionary = {}
var turnover_kind: String = "" ## "", "int", "fumble"
var turnover_spot: float = 0.0
var end_spot: float = 0.0
var end_lateral: float = 0.0
var out_of_bounds: bool = false
var touchdown: bool = false
var defensive_td: bool = false
var designed_run: bool = false
var qb_run: bool = false
var playaction: bool = false
var special: String = ""
var pressure: float = 0.0
var user_took_control: bool = false
var run_path_world: Array[Vector3] = []
var run_path_idx: int = 0
var loose_t: float = 0.0
var recorder: ReplayRecorder
var route_overlay: Node3D
var aim_marker: MeshInstance3D
var land_marker: MeshInstance3D
var broken_tackles: int = 0
var max_speed_seen: float = 0.0
var celebrated: bool = false
var two_point: bool = false
var debug_text: String = ""
var _emitted: bool = false
var _snap_t: float = 0.0
var _blocks_engaged: bool = false
var _qb_spot := Vector3.ZERO
var _pa_faked: bool = false
var _throw_away_pending: bool = false

# ================================================================= setup

func _ready() -> void:
	recorder = ReplayRecorder.new()
	route_overlay = Node3D.new()
	add_child(route_overlay)
	aim_marker = _ring_mesh(Color("#F28C38"), 0.9)
	land_marker = _ring_mesh(Color("#F5F0E5"), 0.6)

func _ring_mesh(c: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.78
	tm.outer_radius = r
	tm.rings = 28
	tm.ring_segments = 4
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.no_depth_test = true
	m.render_priority = 2
	mi.material_override = m
	mi.scale = Vector3(1, 0.02, 1)
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Prepares a play. off_pool/def_pool map slot -> FieldAgent.
func setup(p_play: Dictionary, p_flip: bool, p_def_call: Dictionary, p_los: float, p_lat: float, p_dir: int, p_fd: float, off_pool: Dictionary, def_pool: Dictionary, p_ball: Football) -> void:
	play_def = p_play
	flip = p_flip
	def_call = p_def_call
	los = p_los
	lat0 = FieldCoords.hash_lateral(p_lat)
	dir = p_dir
	fd_line = p_fd
	ball = p_ball
	stage = Stage.PRESNAP
	t = 0.0
	thrown = false
	pass_target = null
	pass_info = {}
	pass_resolved = false
	completed = false
	handed_off = false
	handoff_target = null
	ran_past_los = false
	charge = 0.0
	target_idx = -1
	end_reason = ""
	dead_t = 0.0
	credit = {}
	turnover_kind = ""
	out_of_bounds = false
	touchdown = false
	defensive_td = false
	user_took_control = false
	run_path_idx = 0
	broken_tackles = 0
	max_speed_seen = 0.0
	celebrated = false
	_emitted = false
	_blocks_engaged = false
	_pa_faked = false
	_throw_away_pending = false
	pressure = 0.0
	special = str(play_def.get("special", ""))
	designed_run = Playbook.is_run(play_def)
	qb_run = bool(play_def.get("qb_run", false))
	playaction = bool(play_def.get("playaction", false))
	recorder.clear()
	_align_offense(off_pool)
	_align_defense(def_pool)
	_assign_defense()
	qb = slots["QB"]
	user = qb
	qb.is_user = true
	ball.give_to(slots["C"])
	ball.visible = true
	ball.step(0.0)
	_build_route_overlay()
	_update_highlights()

func _world(down: float, lat: float) -> Vector3:
	return FieldCoords.to_world(los + down, lat0 + lat, dir)

func _field(p: Vector3) -> Vector2:
	return FieldCoords.to_field(p, dir)

func ball_on_of(p: Vector3) -> float:
	return FieldCoords.ball_on_from_world_x(p.x, dir)

func _align_offense(pool: Dictionary) -> void:
	offense.clear()
	slots.clear()
	receivers.clear()
	var fwd := FieldCoords.forward(dir)
	for slot in ["LT", "LG", "C", "RG", "RT", "QB", "X", "Z", "S", "Y", "B"]:
		var a: FieldAgent = pool[slot]
		var al := Playbook.alignment(play_def, slot, flip)
		var lat := clampf(lat0 + al.y, -FieldCoords.HALF_WIDTH + 1.5, FieldCoords.HALF_WIDTH - 1.5) - lat0
		a.reset_for_play(_world(al.x, lat), fwd)
		a.is_user = false
		a.set_highlight(false)
		a.show_tag("")
		offense.append(a)
		slots[slot] = a
		var p := PlayerRig.Pose.STANCE3 if slot in ["LT", "LG", "C", "RG", "RT"] else PlayerRig.Pose.STANCE2
		if slot == "QB":
			p = PlayerRig.Pose.QB_SET if al.x < -2.5 else PlayerRig.Pose.STANCE2
		if slot == "C":
			p = PlayerRig.Pose.SNAP
			a.rig.pose_time = -100.0
		a.rig.set_pose(p)
		if slot in RECEIVER_SLOTS:
			receivers.append(a)
	# Hide unused offensive pool members (e.g. special teams).
	for k in pool:
		if not slots.has(k):
			pool[k].visible = false

func _align_defense(pool: Dictionary) -> void:
	defense.clear()
	dslots.clear()
	var front := Playbook.front(def_call.get("front", "base"))
	var back := Vector3(-FieldCoords.forward(dir))
	var used: Array[String] = []
	var dl: Array = front["DL"]
	for i in dl.size():
		var key := "DL%d" % (i + 1)
		var v := Playbook.v2(dl[i])
		_place_def(pool[key], key, Vector2(v.x, v.y * (-1.0 if flip else 1.0)), back, PlayerRig.Pose.STANCE3)
		used.append(key)
	var lbs: Array = front["LB"]
	for i in lbs.size():
		var key := "LB%d" % (i + 1)
		var v := Playbook.v2(lbs[i])
		_place_def(pool[key], key, v, back, PlayerRig.Pose.STANCE2)
		used.append(key)
	var cover: String = def_call.get("coverage", "man")
	var x_lat := _field(slots["X"].global_position).y - lat0
	var z_lat := _field(slots["Z"].global_position).y - lat0
	var s_lat := _field(slots["S"].global_position).y - lat0
	var cb_depth := 6.5 if cover in ["zone3", "prevent"] else (5.0 if cover == "zone2" else 4.5)
	if cover == "prevent":
		cb_depth = 11.0
	_place_def(pool["CB1"], "CB1", Vector2(cb_depth, x_lat + signf(x_lat) * -0.6), back, PlayerRig.Pose.STANCE2)
	_place_def(pool["CB2"], "CB2", Vector2(cb_depth, z_lat + signf(z_lat) * -0.6), back, PlayerRig.Pose.STANCE2)
	used.append_array(["CB1", "CB2"])
	if lbs.size() < 3:
		_place_def(pool["CB3"], "CB3", Vector2(4.5, s_lat - signf(s_lat) * 0.8), back, PlayerRig.Pose.STANCE2)
		used.append("CB3")
	var s_depth := 13.0
	if cover == "zone2":
		_place_def(pool["S1"], "S1", Vector2(s_depth, -10.0), back, PlayerRig.Pose.STANCE2)
		_place_def(pool["S2"], "S2", Vector2(s_depth, 10.0), back, PlayerRig.Pose.STANCE2)
	elif cover == "prevent":
		_place_def(pool["S1"], "S1", Vector2(20.0, -7.0), back, PlayerRig.Pose.STANCE2)
		_place_def(pool["S2"], "S2", Vector2(20.0, 7.0), back, PlayerRig.Pose.STANCE2)
	else:
		_place_def(pool["S1"], "S1", Vector2(s_depth + 1.0, 0.0), back, PlayerRig.Pose.STANCE2)
		var strong := 1.0 if s_lat > 0.0 else -1.0
		_place_def(pool["S2"], "S2", Vector2(8.0, strong * 6.0), back, PlayerRig.Pose.STANCE2)
	used.append_array(["S1", "S2"])
	if def_call.get("front", "") == "goal":
		for key in ["S1", "S2", "CB1", "CB2"]:
			var a: FieldAgent = dslots[key]
			var f := _field(a.global_position)
			var depth := minf(f.x - los, maxf(100.0 - los + 2.0, 2.0))
			a.global_position = _world(minf(depth, 6.0), f.y - lat0)
	for k in pool:
		if not used.has(k):
			pool[k].visible = false

func _place_def(a: FieldAgent, key: String, at: Vector2, face: Vector3, pose: PlayerRig.Pose) -> void:
	var lat := clampf(lat0 + at.y, -FieldCoords.HALF_WIDTH + 1.0, FieldCoords.HALF_WIDTH - 1.0) - lat0
	# Never line up inside the offense's end zone beyond the end line.
	var depth := minf(at.x, 109.0 - los)
	a.reset_for_play(_world(depth, lat), face)
	a.is_user = false
	a.set_highlight(false)
	a.show_tag("")
	a.rig.set_pose(pose)
	a.react_t = float(tune.get("react", 0.3)) * lerpf(1.25, 0.75, a.player.effective("awareness") / 99.0) + rng.randf_range(0.0, 0.08)
	defense.append(a)
	dslots[key] = a

func _assign_defense() -> void:
	var cover: String = def_call.get("coverage", "man")
	var blitzers: int = def_call.get("blitz", 0)
	for a in defense:
		a.blitz = false
		a.assignment = null
		if a.role == "DL":
			a.mode = FieldAgent.Mode.RUSH
			a.note = "Rush"
	var lbs: Array[FieldAgent] = []
	for k in ["LB1", "LB2", "LB3"]:
		if dslots.has(k):
			lbs.append(dslots[k])
	# Blitzers come from the linebackers.
	for i in mini(blitzers, lbs.size()):
		var lb: FieldAgent = lbs[lbs.size() - 1 - i]
		lb.blitz = true
		lb.mode = FieldAgent.Mode.RUSH
		lb.note = "Blitz"
	var cbs: Array[FieldAgent] = []
	for k in ["CB1", "CB2", "CB3"]:
		if dslots.has(k):
			cbs.append(dslots[k])
	var fs: FieldAgent = dslots["S1"]
	var ss: FieldAgent = dslots["S2"]
	var free_lbs: Array[FieldAgent] = []
	for lb in lbs:
		if not lb.blitz:
			free_lbs.append(lb)
	if cover == "man":
		_man(cbs[0], slots["X"])
		_man(cbs[1], slots["Z"])
		if cbs.size() > 2:
			_man(cbs[2], slots["S"])
			_man(ss, slots["Y"])
		else:
			_man(ss, slots["S"])
			if free_lbs.size() > 0:
				_man(free_lbs.pop_front(), slots["Y"])
		if free_lbs.size() > 0:
			_man(free_lbs.pop_front(), slots["B"])
		for lb in free_lbs:
			_zone(lb, Vector2(5.0, 0.0), 7.0, "Hook")
		_zone(fs, Vector2(16.0, 0.0), 18.0, "Deep Middle")
	elif cover == "zone3":
		_zone(cbs[0], Vector2(16.0, -16.0), 11.0, "Deep 1/3")
		_zone(cbs[1], Vector2(16.0, 16.0), 11.0, "Deep 1/3")
		_zone(fs, Vector2(18.0, 0.0), 11.0, "Deep 1/3")
		var unders: Array[FieldAgent] = []
		unders.append(ss)
		if cbs.size() > 2:
			unders.append(cbs[2])
		unders.append_array(free_lbs)
		var spots: Array[Vector2] = [Vector2(5.0, 12.0), Vector2(5.0, -12.0), Vector2(7.0, -4.0), Vector2(7.0, 4.0), Vector2(6.0, 0.0)]
		for i in unders.size():
			_zone(unders[i], spots[i % spots.size()], 8.0, "Flat" if i < 2 else "Curl")
	elif cover == "zone2":
		_zone(cbs[0], Vector2(4.0, -16.0), 8.0, "Flat")
		_zone(cbs[1], Vector2(4.0, 16.0), 8.0, "Flat")
		_zone(fs, Vector2(17.0, -10.0), 13.0, "Deep 1/2")
		_zone(ss, Vector2(17.0, 10.0), 13.0, "Deep 1/2")
		var spots2: Array[Vector2] = [Vector2(7.0, -6.0), Vector2(7.0, 6.0), Vector2(9.0, 0.0)]
		var unders2: Array[FieldAgent] = []
		if cbs.size() > 2:
			unders2.append(cbs[2])
		unders2.append_array(free_lbs)
		for i in unders2.size():
			_zone(unders2[i], spots2[i % spots2.size()], 8.0, "Hook")
	else: # prevent
		_zone(cbs[0], Vector2(20.0, -15.0), 12.0, "Deep")
		_zone(cbs[1], Vector2(20.0, 15.0), 12.0, "Deep")
		_zone(fs, Vector2(28.0, -6.0), 14.0, "Deep")
		_zone(ss, Vector2(28.0, 6.0), 14.0, "Deep")
		if cbs.size() > 2:
			_zone(cbs[2], Vector2(12.0, 0.0), 12.0, "Mid")
		for lb in free_lbs:
			_zone(lb, Vector2(9.0, (rng.randf() - 0.5) * 10.0), 10.0, "Mid")
	# Mirror zone landmarks with play side.
	for a in defense:
		if a.mode == FieldAgent.Mode.ZONE:
			var f := _field(a.zone_point)
			a.zone_point = FieldCoords.to_world(minf(f.x, 108.0), f.y, dir)

func _man(d: FieldAgent, r: FieldAgent) -> void:
	d.mode = FieldAgent.Mode.COVER
	d.assignment = r
	d.note = "Man #%d" % r.player.number

func _zone(d: FieldAgent, landmark: Vector2, radius: float, label: String) -> void:
	d.mode = FieldAgent.Mode.ZONE
	d.zone_point = _world(landmark.x, landmark.y)
	d.zone_radius = radius
	d.note = label

# ================================================================= overlay

func _build_route_overlay() -> void:
	for c in route_overlay.get_children():
		c.queue_free()
	route_overlay.visible = true
	if special != "":
		return
	if designed_run or qb_run:
		var path := Playbook.run_path(play_def, flip)
		var pts: Array[Vector3] = []
		var carrier_slot := "QB" if qb_run else "B"
		pts.append(slots[carrier_slot].global_position)
		for p in path:
			pts.append(_world(p.x, p.y))
		run_path_world = pts.slice(1)
		_ribbon(pts, Color("#65C987"), 0.32, true)
	for i in receivers.size():
		var r: FieldAgent = receivers[i]
		var pts := Playbook.route_points(play_def, r.slot, flip)
		var rname: String = play_def.get("routes", {}).get(r.slot, "block")
		if pts.is_empty() or rname in ["stalk", "block", "lead", "fake", "run"]:
			continue
		var w: Array[Vector3] = [r.global_position]
		for p in pts:
			w.append(_world(p.x, p.y))
		_ribbon(w, SLOT_COLORS[r.slot], 0.2, true)
		r.show_tag(str(i + 1), SLOT_COLORS[r.slot])

func _ribbon(pts: Array[Vector3], c: Color, width: float, arrow: bool) -> void:
	if pts.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a)
		d.y = 0.0
		if d.length() < 0.01:
			continue
		var n := Vector3(-d.z, 0, d.x).normalized() * width * 0.5
		var y := Vector3(0, 0.035, 0)
		st.add_vertex(a + n + y); st.add_vertex(b + n + y); st.add_vertex(b - n + y)
		st.add_vertex(a + n + y); st.add_vertex(b - n + y); st.add_vertex(a - n + y)
	if arrow:
		var a := pts[pts.size() - 2]
		var b := pts[pts.size() - 1]
		var d := (b - a)
		d.y = 0.0
		if d.length() > 0.01:
			d = d.normalized()
			var n := Vector3(-d.z, 0, d.x)
			var y := Vector3(0, 0.036, 0)
			st.add_vertex(b + d * 0.8 + y); st.add_vertex(b + n * 0.55 + y); st.add_vertex(b - n * 0.55 + y)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	route_overlay.add_child(mi)

func set_overlay_visible(v: bool) -> void:
	route_overlay.visible = v
	for r in receivers:
		if not v:
			r.show_tag("")

func _update_highlights() -> void:
	for a in offense:
		a.set_highlight(false)
	if user != null and stage != Stage.DEAD:
		user.set_highlight(true, Color("#F28C38"))
	if target_idx >= 0 and target_idx < receivers.size() and not thrown:
		receivers[target_idx].set_highlight(true, SLOT_COLORS[receivers[target_idx].slot])

# ================================================================= snap

func snap() -> void:
	if stage != Stage.PRESNAP:
		return
	stage = Stage.LIVE
	t = 0.0
	_snap_t = 0.0
	sfx.emit("snap", slots["C"].global_position, 1.0)
	set_overlay_visible(assist >= 1 and false)
	for r in receivers:
		r.show_tag("")
	route_overlay.visible = false
	var c: FieldAgent = slots["C"]
	c.rig.set_pose(PlayerRig.Pose.SNAP)
	c.rig.pose_time = 0.0
	# Shotgun snaps travel; under-center exchanges are immediate.
	var qbp := qb.global_position
	if (qbp - c.global_position).length() > 2.0:
		ball.launch(c.global_position + Vector3(0, 0.4, 0), (qbp + Vector3(0, 1.3, 0) - c.global_position - Vector3(0, 0.4, 0)) / 0.32 + Vector3(0, PassMath.GRAVITY * 0.16, 0), qb)
		ball.touched_by = defense.duplicate()
	else:
		ball.give_to(qb)
	_qb_spot = qbp
	# Assign offensive modes.
	for a in offense:
		a.rig.set_pose(PlayerRig.Pose.RUN)
		if a.slot in ["LT", "LG", "C", "RG", "RT"]:
			a.mode = FieldAgent.Mode.BLOCK
		elif a.slot in RECEIVER_SLOTS:
			var rname: String = play_def.get("routes", {}).get(a.slot, "block")
			var rd := Playbook.route_def(rname)
			if rname in ["block", "stalk", "lead"] or (designed_run and a.slot == "Y"):
				a.mode = FieldAgent.Mode.BLOCK
				if rname == "stalk":
					a.route.clear()
					a.route.append(_world(Playbook.alignment(play_def, a.slot, flip).x + 3.0, Playbook.alignment(play_def, a.slot, flip).y))
				if rname == "lead":
					a.note = "Lead"
			elif rname in ["run", "fake"]:
				a.mode = FieldAgent.Mode.FAKE
			else:
				a.mode = FieldAgent.Mode.ROUTE
				a.route.clear()
				for p in Playbook.route_points(play_def, a.slot, flip):
					var lat := clampf(lat0 + p.y, -FieldCoords.HALF_WIDTH + 0.6, FieldCoords.HALF_WIDTH - 0.6) - lat0
					var depth := minf(p.x, 109.5 - los)
					a.route.append(_world(depth, lat))
				a.route_idx = 0
				a.route_continue = bool(rd.get("continue", false))
				a.route_delay = float(rd.get("delay", 0.0))
				# Natural variation in timing and stems.
				a.route_delay += rng.randf_range(0.0, 0.06)
				for i in a.route.size():
					a.route[i] += Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	for a in defense:
		a.rig.set_pose(PlayerRig.Pose.RUN)
	if special == "kneel":
		_end_play("kneel")
	if special == "spike":
		qb.rig.set_pose(PlayerRig.Pose.THROW)

# ================================================================= tick

func _physics_process(dt: float) -> void:
	match stage:
		Stage.PRESNAP:
			if input != null:
				input.poll(self, dt)
				if input.snap:
					snap()
			for a in offense:
				a.rig.animate(dt)
			for a in defense:
				a.rig.animate(dt)
			ball.step(dt)
		Stage.LIVE:
			_tick(dt)
		Stage.DEAD:
			dead_t += dt
			for a in offense + defense:
				if a.mode != FieldAgent.Mode.DOWN and a.mode != FieldAgent.Mode.CELEBRATE:
					a.steer(Vector3.ZERO, dt)
				a.integrate(dt)
				if a.mode != FieldAgent.Mode.DOWN and a.mode != FieldAgent.Mode.CELEBRATE:
					a.rig.set_pose(PlayerRig.Pose.RUN)
				a.rig.animate(dt)
			ball.step(dt)
			_record(dt)
			if dead_t > (1.6 if touchdown or turnover_kind != "" else 1.1) and not _emitted:
				_emitted = true
				play_over.emit(_build_result(), _build_info())

func _tick(dt: float) -> void:
	t += dt
	if input != null:
		input.poll(self, dt)
	_update_pressure()
	_handle_user(dt)
	for a in offense:
		if a != user or not _user_controls(a):
			_ai_offense(a, dt)
	for a in defense:
		if a != user or not _user_controls(a):
			_ai_defense(a, dt)
	_ball_logic(dt)
	if stage != Stage.LIVE:
		return
	_contacts(dt)
	if stage != Stage.LIVE:
		return
	_separate()
	for a in offense + defense:
		a.integrate(dt)
		a.rig.animate(dt)
	ball.step(dt)
	_check_boundaries()
	_update_markers()
	_record(dt)
	_update_highlights()
	if t > MAX_PLAY_TIME:
		_end_play("timeout")

func _user_controls(a: FieldAgent) -> bool:
	return a == user and a.can_act()

func _carrier() -> FieldAgent:
	return ball.carrier as FieldAgent

# ================================================================= user

func _move_world(v: Vector2) -> Vector3:
	return FieldCoords.forward(dir) * v.y + FieldCoords.offense_right(dir) * v.x

func _handle_user(dt: float) -> void:
	if input == null or user == null:
		return
	var carrier := _carrier()
	# Control follows the ball.
	if carrier != null and carrier.unit == FieldAgent.Unit.OFFENSE and carrier != user and carrier.can_act():
		_set_user(carrier)
	var a := user
	if not a.can_act():
		return
	if a == qb and carrier == qb and not thrown and not ran_past_los:
		_handle_passing(dt)
	var mv := input.move
	if input.any_move:
		user_took_control = true
	var is_carrier := carrier == a
	if a == qb and carrier != qb and not handed_off and not thrown:
		return # still receiving the snap
	if a == qb and (handed_off or (designed_run and not qb_run)):
		_ai_qb(a, dt) # handoff mesh and fake are automatic
		return
	if is_carrier and not input.any_move and not user_took_control and (designed_run or qb_run) and run_path_idx < run_path_world.size():
		_follow_run_path(a, dt)
		return
	if a == qb and not input.any_move and not user_took_control and carrier == qb and not designed_run:
		_qb_auto_drop(a, dt)
		return
	var spd := a.top_speed * (1.0 if (input.sprint and a.stamina > 0.05) else 0.86)
	if input.sprint and mv.length() > 0.1:
		a.stamina = maxf(0.0, a.stamina - dt * 0.22 * (1.6 - a.player.effective("stamina") / 99.0))
	else:
		a.stamina = minf(1.0, a.stamina + dt * 0.12)
	if a == qb and carrier == qb and not thrown and charge > 0.0:
		spd *= 0.55
	var want := _move_world(mv.limit_length(1.0)) * spd
	if is_carrier and input.juke and a.juke_cd <= 0.0:
		_juke(a, mv)
	if is_carrier and input.dive and a.dive_t < 0.0:
		_dive(a)
		return
	a.steer(want, dt)
	if a.rig.pose not in [PlayerRig.Pose.THROW, PlayerRig.Pose.DIVE, PlayerRig.Pose.CATCH] or a.rig.pose_time > 0.45:
		a.rig.set_pose(PlayerRig.Pose.QB_SET if (a == qb and carrier == qb and not thrown and not ran_past_los and a.speed() < 1.5) else PlayerRig.Pose.RUN)
	a.rig.carrying = is_carrier and a != qb or (is_carrier and ran_past_los)

func _set_user(a: FieldAgent) -> void:
	if user != null:
		user.is_user = false
	user = a
	a.is_user = true
	user_took_control = user_took_control and a == qb

func _juke(a: FieldAgent, mv: Vector2) -> void:
	a.juke_t = 0.35
	a.juke_cd = 1.1
	var side := 1.0 if mv.x >= 0.0 else -1.0
	if absf(mv.x) < 0.2:
		side = 1.0 if rng.randf() < 0.5 else -1.0
	var lateral := FieldCoords.offense_right(dir) * side
	var burst := 3.2 + a.agility * 0.035
	a.vel = a.vel * 0.55 + lateral * burst
	a.stamina = maxf(0.0, a.stamina - 0.12)
	sfx.emit("juke", a.global_position, 0.6)

func _dive(a: FieldAgent) -> void:
	a.dive_t = 0.0
	a.rig.set_pose(PlayerRig.Pose.DIVE)
	var fwd := a.facing
	a.vel = fwd * maxf(a.speed(), 4.0) * 1.1

func _follow_run_path(a: FieldAgent, dt: float) -> void:
	var target := run_path_world[run_path_idx]
	if a.flat_pos().distance_to(Vector3(target.x, 0, target.z)) < 1.2:
		run_path_idx += 1
		if run_path_idx >= run_path_world.size():
			return
		target = run_path_world[run_path_idx]
	a.seek(target, 0.92, dt, 0.2)
	a.rig.set_pose(PlayerRig.Pose.RUN)
	a.rig.carrying = true

func _qb_auto_drop(a: FieldAgent, dt: float) -> void:
	## Without input the QB takes a 3-step drop and sets in the pocket.
	var depth := 4.5 if _field(_qb_spot).x - los > -2.5 else 0.6
	var drop_spot := _qb_spot - FieldCoords.forward(dir) * depth
	if playaction and not _pa_faked and t < 0.7:
		var b: FieldAgent = slots["B"]
		a.seek(b.global_position.lerp(a.global_position, 0.6), 0.6, dt, 0.3)
		a.rig.set_pose(PlayerRig.Pose.HANDOFF)
		if t > 0.5:
			_pa_faked = true
			sfx.emit("fake", a.global_position, 0.5)
		return
	a.seek(drop_spot, 0.7, dt, 0.3)
	if a.flat_pos().distance_to(Vector3(drop_spot.x, 0, drop_spot.z)) < 0.6:
		a.face_toward(a.global_position + FieldCoords.forward(dir))
	if a.rig.pose != PlayerRig.Pose.THROW or a.rig.pose_time > 0.45:
		a.rig.set_pose(PlayerRig.Pose.QB_SET if a.speed() < 2.0 else PlayerRig.Pose.RUN)

# ================================================================= passing

func _handle_passing(dt: float) -> void:
	if special == "spike":
		if t > 0.35:
			_throw_spike()
		return
	if designed_run and not qb_run:
		return
	if input.target >= 0 and input.target < receivers.size():
		var r: FieldAgent = receivers[input.target]
		if _eligible(r):
			target_idx = input.target
			sfx.emit("ui_target", r.global_position, 0.3)
	if input.cancel:
		target_idx = -1
		charge = 0.0
	if input.throw_away:
		_throw_away()
		return
	if assist >= 2 and input.target >= 0 and not input.charging:
		# Full assist: selecting a receiver throws immediately with ideal power.
		_throw(-1.0, receivers[target_idx] if target_idx >= 0 else null)
		return
	if input.charging:
		charge = minf(1.0, charge + dt / CHARGE_TIME)
	if input.release and charge > 0.0:
		var tgt: FieldAgent = receivers[target_idx] if target_idx >= 0 else null
		if tgt == null and not input.has_aim:
			tgt = _nearest_receiver_to_aim()
		var p := charge
		if assist >= 2:
			p = -1.0
		_throw(p, tgt)
		charge = 0.0
		return
	_update_aim_markers()

func _eligible(r: FieldAgent) -> bool:
	return r.mode == FieldAgent.Mode.ROUTE or (r.mode == FieldAgent.Mode.FAKE and playaction) or r.slot == "B" and r.mode != FieldAgent.Mode.BLOCK

func _nearest_receiver_to_aim() -> FieldAgent:
	var best: FieldAgent = null
	var bd := 6.0
	for r in receivers:
		if not _eligible(r):
			continue
		var d := r.flat_pos().distance_to(input.aim_world)
		if d < bd:
			bd = d
			best = r
	return best

func _update_aim_markers() -> void:
	if user != qb or thrown:
		aim_marker.visible = false
		land_marker.visible = false
		return
	var aim := _current_aim(charge if charge > 0.0 else 0.6)
	if aim.is_empty():
		aim_marker.visible = false
		land_marker.visible = false
		return
	aim_marker.visible = true
	aim_marker.global_position = Vector3(aim["point"].x, 0.05, aim["point"].z)
	var s := 0.7 + charge * 0.6
	aim_marker.scale = Vector3(s, 0.02, s)
	var mat: StandardMaterial3D = aim_marker.material_override
	var col := Color("#F28C38").lerp(Color("#E75A5A"), maxf(0.0, charge - 0.85) * 6.0)
	mat.albedo_color = col
	mat.emission = col
	land_marker.visible = assist >= 1 and charge > 0.0
	if land_marker.visible:
		var sol: Dictionary = aim["solution"]
		var start: Vector3 = aim["start"]
		var tt := PassMath.flight_time(start.y, sol["velocity"].y, PassMath.CATCH_HEIGHT)
		var land := PassMath.position_at(start, sol["velocity"], tt)
		land_marker.global_position = Vector3(land.x, 0.05, land.z)

## Returns {point, start, solution, target} for a hypothetical throw.
func _current_aim(power: float) -> Dictionary:
	var tgt: FieldAgent = receivers[target_idx] if target_idx >= 0 else null
	var start := qb.global_position + Vector3(0, 2.0, 0) + qb.facing * 0.25
	var arm := qb.player.effective("throw_power")
	var spd := PassMath.throw_speed(power, arm)
	var point := Vector3.ZERO
	if tgt != null:
		point = _lead_point(tgt, start, spd)
		if input != null and input.has_aim and assist < 2:
			var off := input.aim_world - point
			off.y = 0.0
			point += off.limit_length(4.0) * 0.55
		if input != null and input.aim_nudge.length() > 0.1:
			point += _move_world(input.aim_nudge) * 3.0
	elif input != null and input.has_aim:
		point = input.aim_world
	else:
		return {}
	point.y = 0.0
	var sol := PassMath.solve(start, point + Vector3(0, PassMath.CATCH_HEIGHT, 0), spd)
	return {"point": point, "start": start, "solution": sol, "target": tgt}

## Where the receiver will be when a ball thrown now at `spd` arrives.
func _lead_point(r: FieldAgent, start: Vector3, spd: float) -> Vector3:
	var tt := 0.6
	var p := r.global_position
	for i in 5:
		p = predict(r, tt)
		var sol := PassMath.solve(start, p + Vector3(0, PassMath.CATCH_HEIGHT, 0), spd)
		tt = clampf(float(sol["time"]), 0.1, 4.5)
	return p

## Predicts an agent's position `dt` seconds ahead along its route.
func predict(a: FieldAgent, dt: float) -> Vector3:
	var spd := maxf(a.speed(), a.top_speed * 0.82)
	if a.mode == FieldAgent.Mode.ROUTE and a.route_idx < a.route.size():
		var remain := spd * maxf(0.0, dt - maxf(0.0, a.route_delay - t))
		var p := a.flat_pos()
		var i := a.route_idx
		while i < a.route.size() and remain > 0.0:
			var nxt := Vector3(a.route[i].x, 0, a.route[i].z)
			var seg := p.distance_to(nxt)
			if seg >= remain:
				return p + (nxt - p).normalized() * remain
			remain -= seg
			p = nxt
			i += 1
		if remain > 0.0 and a.route_continue and a.route.size() >= 2:
			var last_dir := (a.route[a.route.size() - 1] - a.route[a.route.size() - 2])
			last_dir.y = 0.0
			p += last_dir.normalized() * remain
		return _clamp_field(p)
	return _clamp_field(a.flat_pos() + Vector3(a.vel.x, 0, a.vel.z) * dt)

func _clamp_field(p: Vector3) -> Vector3:
	p.z = clampf(p.z, -FieldCoords.HALF_WIDTH + 0.3, FieldCoords.HALF_WIDTH - 0.3)
	p.x = clampf(p.x, -59.5, 59.5)
	return p

func _throw(power: float, tgt: FieldAgent) -> void:
	if thrown or _carrier() != qb:
		return
	var arm := qb.player.effective("throw_power")
	var acc := qb.player.effective("throw_acc")
	if power < 0.0:
		# Full assist: ideal power for the distance.
		var guess := tgt.global_position if tgt != null else (input.aim_world if input.has_aim else qb.global_position + FieldCoords.forward(dir) * 12.0)
		power = PassMath.ideal_power(qb.flat_pos().distance_to(Vector3(guess.x, 0, guess.z)), arm)
	if tgt != null:
		target_idx = receivers.find(tgt)
	var aim := _current_aim(power)
	if aim.is_empty():
		var start0 := qb.global_position + Vector3(0, 2.0, 0)
		aim = {"point": qb.flat_pos() + FieldCoords.forward(dir) * 12.0, "start": start0, "target": null}
	var start: Vector3 = aim["start"]
	var point: Vector3 = aim["point"]
	var d := Vector2(point.x - start.x, point.z - start.z).length()
	var moving := clampf(qb.speed() / 6.0, 0.0, 1.0)
	var sigma := PassMath.error_sigma(d, acc, pressure, moving, power, assist)
	var flat_dir := Vector3(point.x - start.x, 0, point.z - start.z).normalized()
	var perp := Vector3(-flat_dir.z, 0, flat_dir.x)
	var e_along := rng.randfn(0.0, sigma * 0.9)
	var e_lat := rng.randfn(0.0, sigma * 0.7)
	var landing := point + flat_dir * e_along + perp * e_lat
	var spd := PassMath.throw_speed(power, arm)
	var sol := PassMath.solve(start, landing + Vector3(0, PassMath.CATCH_HEIGHT, 0), spd)
	thrown = true
	pass_target = aim.get("target")
	ball.launch(start, sol["velocity"], pass_target)
	ball.wobble = clampf(sigma * 0.08, 0.0, 0.3)
	var tt := PassMath.flight_time(start.y, sol["velocity"].y, PassMath.CATCH_HEIGHT)
	pass_land = PassMath.position_at(start, sol["velocity"], tt)
	pass_land.y = 0.0
	pass_info = {
		"target": pass_target, "power": power, "speed": spd, "dist": d, "sigma": sigma,
		"err_along": e_along, "err_lat": e_lat, "underthrown": not sol["reachable"], "pressure": pressure,
		"land": pass_land, "air_time": tt, "thrown_at": t, "from_ball_on": ball_on_of(start),
	}
	credit["passer"] = qb.player.id
	qb.rig.set_pose(PlayerRig.Pose.THROW)
	aim_marker.visible = false
	land_marker.visible = assist >= 1
	land_marker.global_position = pass_land + Vector3(0, 0.05, 0)
	if pass_target != null:
		pass_target.mode = FieldAgent.Mode.BALL_HAWK
	sfx.emit("throw", start, clampf(spd / 30.0, 0.3, 1.0))
	# Defenders react to the throw after their reaction delay.
	for dfd in defense:
		dfd.react_t = t + float(tune.get("react", 0.3)) * lerpf(1.3, 0.7, dfd.player.effective("awareness") / 99.0)

func _throw_away() -> void:
	## Intentional incompletion over the nearest sideline.
	var sz := 1.0 if qb.global_position.z >= 0.0 else -1.0
	var target := Vector3(qb.global_position.x + FieldCoords.forward(dir).x * 8.0, 0, sz * (FieldCoords.HALF_WIDTH + 6.0))
	var start := qb.global_position + Vector3(0, 2.0, 0)
	var sol := PassMath.solve(start, target + Vector3(0, 1.0, 0), 24.0)
	thrown = true
	pass_target = null
	ball.launch(start, sol["velocity"], null)
	ball.touched_by = offense.duplicate() + defense.duplicate()
	pass_info = {"target": null, "throwaway": true, "land": target}
	credit["passer"] = qb.player.id
	qb.rig.set_pose(PlayerRig.Pose.THROW)
	feedback.emit("Thrown away", Color("#BFB8AA"), false)
	sfx.emit("throw", start, 0.6)

func _throw_spike() -> void:
	thrown = true
	var start := qb.global_position + Vector3(0, 1.8, 0)
	ball.launch(start, Vector3(0, -12.0, 0) + FieldCoords.forward(dir) * 2.0, null)
	ball.touched_by = offense.duplicate() + defense.duplicate()
	pass_info = {"spike": true}
	qb.rig.set_pose(PlayerRig.Pose.THROW)

func most_open_receiver() -> int:
	var best := 0
	var best_sep := -1.0
	for i in receivers.size():
		var r: FieldAgent = receivers[i]
		if not _eligible(r):
			continue
		var sep := 99.0
		for d in defense:
			sep = minf(sep, d.flat_pos().distance_to(r.flat_pos()))
		var depth := _field(r.global_position).x - los
		var score := sep + clampf(depth, -2.0, 15.0) * 0.15
		if score > best_sep:
			best_sep = score
			best = i
	return best

# ================================================================= offense AI

func _ai_offense(a: FieldAgent, dt: float) -> void:
	if not a.can_act():
		a.steer(Vector3.ZERO, dt)
		return
	var carrier := _carrier()
	if a == carrier:
		# AI-controlled carrier (user not controlling): run upfield.
		_ai_carrier(a, dt)
		return
	if carrier != null and carrier.unit == FieldAgent.Unit.DEFENSE:
		_ai_pursue(a, carrier, dt, 0.95)
		return
	var past_los := carrier != null and carrier != qb
	match a.mode:
		FieldAgent.Mode.BLOCK:
			_ai_block(a, dt)
		FieldAgent.Mode.ROUTE:
			if past_los and completed:
				_ai_downfield_block(a, dt)
			else:
				_ai_route(a, dt)
		FieldAgent.Mode.BALL_HAWK:
			_ai_ball_hawk(a, dt)
		FieldAgent.Mode.FAKE:
			_ai_back(a, dt)
		_:
			if a == qb:
				_ai_qb(a, dt)
			else:
				a.steer(Vector3.ZERO, dt)

func _ai_qb(a: FieldAgent, dt: float) -> void:
	if handed_off:
		# Carry out the fake away from the run.
		var away := -FieldCoords.forward(dir) * 3.0 + FieldCoords.offense_right(dir) * (-2.0 if not flip else 2.0)
		a.seek(_qb_spot + away, 0.5, dt)
		a.rig.set_pose(PlayerRig.Pose.RUN)
	elif designed_run and not qb_run:
		var b: FieldAgent = slots["B"]
		a.seek(b.global_position.lerp(a.global_position, 0.5), 0.7, dt, 0.2)
		a.rig.set_pose(PlayerRig.Pose.HANDOFF)
	else:
		a.steer(Vector3.ZERO, dt)

func _ai_carrier(a: FieldAgent, dt: float) -> void:
	if (designed_run or qb_run) and run_path_idx < run_path_world.size() and not user_took_control:
		_follow_run_path(a, dt)
		return
	var goal := a.flat_pos() + FieldCoords.forward(dir) * 10.0
	if a.unit == FieldAgent.Unit.DEFENSE:
		goal = a.flat_pos() - FieldCoords.forward(dir) * 10.0
	# Avoid the nearest pursuer.
	var threat: FieldAgent = null
	var td := 6.0
	for o in (defense if a.unit == FieldAgent.Unit.OFFENSE else offense):
		if not o.can_act():
			continue
		var d := o.flat_pos().distance_to(a.flat_pos())
		if d < td:
			td = d
			threat = o
	var want := (goal - a.flat_pos()).normalized()
	if threat != null:
		var away := (a.flat_pos() - threat.flat_pos()).normalized()
		want = (want + away * (6.0 - td) / 6.0 * 0.9).normalized()
	a.steer(want * a.top_speed * 0.97, dt)
	a.rig.set_pose(PlayerRig.Pose.RUN)
	a.rig.carrying = true

func _ai_route(a: FieldAgent, dt: float) -> void:
	if t < a.route_delay:
		# Delayed release (checkdowns, screens): help block first.
		_ai_block(a, dt)
		return
	if a.route_idx >= a.route.size():
		if a.route_continue and a.route.size() >= 2:
			var dvec := a.route[a.route.size() - 1] - a.route[a.route.size() - 2]
			dvec.y = 0.0
			var tgt := _clamp_field(a.flat_pos() + dvec.normalized() * 5.0)
			a.seek(tgt, 0.95, dt, 0.1)
		else:
			# Settle in the soft spot and face the quarterback.
			a.steer(Vector3.ZERO, dt)
			if not thrown:
				a.face_toward(qb.global_position)
		a.rig.set_pose(PlayerRig.Pose.RUN)
		return
	var target := a.route[a.route_idx]
	var urgency := 0.95 + separation_bonus * 0.01
	a.seek(target, urgency, dt, 0.15)
	if a.flat_pos().distance_to(Vector3(target.x, 0, target.z)) < 0.7:
		a.route_idx += 1
	a.rig.set_pose(PlayerRig.Pose.RUN)

func _ai_ball_hawk(a: FieldAgent, dt: float) -> void:
	## Targeted receiver adjusts to the ball in flight.
	if ball.state != Football.State.FLIGHT:
		a.mode = FieldAgent.Mode.ROUTE
		return
	var spot := pass_land
	var tt := maxf(0.0, float(pass_info.get("air_time", 1.0)) - (t - float(pass_info.get("thrown_at", 0.0))))
	var d := a.flat_pos().distance_to(spot)
	var urgency := 1.0 if d > a.top_speed * tt * 0.8 else clampf(d / maxf(tt, 0.1) / a.top_speed, 0.3, 1.0)
	a.seek(spot, urgency, dt, 0.1)
	if tt < 0.45:
		a.rig.set_pose(PlayerRig.Pose.CATCH)
	else:
		a.rig.set_pose(PlayerRig.Pose.RUN)

func _ai_back(a: FieldAgent, dt: float) -> void:
	## Running back: handoffs, fakes, and pass protection.
	var b := a
	if designed_run and not qb_run:
		var path := run_path_world
		if not handed_off:
			var mesh := path[0] if path.size() > 0 else qb.global_position
			b.seek(mesh, 0.75, dt, 0.2)
			b.rig.set_pose(PlayerRig.Pose.HANDOFF)
			var ht := float(play_def.get("handoff_time", 0.65))
			if t >= ht and b.flat_pos().distance_to(qb.flat_pos()) < 1.8 and _carrier() == qb:
				_handoff(b)
			elif t >= ht + 0.6 and _carrier() == qb:
				_handoff(b) # never leave a run play stuck
		return
	if playaction and t < 0.9:
		var mesh2 := _world(-3.5, 0.6 if not flip else -0.6)
		b.seek(mesh2 + FieldCoords.forward(dir) * 3.0, 0.8, dt)
		b.rig.set_pose(PlayerRig.Pose.HANDOFF)
		return
	_ai_block(b, dt)

func _handoff(rb: FieldAgent) -> void:
	handed_off = true
	handoff_target = rb
	ball.give_to(rb)
	rb.rig.carrying = true
	credit["rusher"] = rb.player.id
	sfx.emit("handoff", rb.global_position, 0.5)
	# Linebackers read the run after their reaction time.
	for d in defense:
		d.react_t = t + float(tune.get("react", 0.3)) * lerpf(1.5, 0.8, d.player.effective("awareness") / 99.0)

func _protect_point() -> Vector3:
	var c := _carrier()
	if c != null and c != qb:
		return c.flat_pos()
	return qb.flat_pos()

func _ai_block(a: FieldAgent, dt: float) -> void:
	var scheme: String = play_def.get("blocking", "pass_pro")
	if a.engaged != null:
		_hold_block(a, dt)
		return
	var carrier := _carrier()
	var run_live := carrier != null and carrier != qb and carrier.unit == FieldAgent.Unit.OFFENSE
	if scheme == "screen" and t > 0.8 and a.role == "OL":
		# Release downfield toward the screen side to lead the back.
		var side := float(play_def.get("screen_side", 1)) * (-1.0 if flip else 1.0)
		var spot := _world(4.0, side * 8.0 + _field(a.global_position).y * 0.2 - lat0 * 0.0)
		var target := _nearest_defender(spot, 7.0, true)
		if target != null:
			_engage_or_approach(a, target, dt)
		else:
			a.seek(spot, 0.8, dt)
		a.rig.set_pose(PlayerRig.Pose.RUN)
		return
	var threat: FieldAgent = null
	if designed_run or run_live:
		threat = _run_block_target(a)
	else:
		threat = _pass_pro_target(a)
	if threat != null:
		_engage_or_approach(a, threat, dt)
	else:
		# Nobody to block: hold position in the pocket or climb to the next level.
		if designed_run or run_live:
			a.seek(a.flat_pos() + FieldCoords.forward(dir) * 2.0, 0.6, dt)
		else:
			var home := a.flat_pos() - FieldCoords.forward(dir) * 0.6 * minf(t, 1.0) * dt
			a.seek(home, 0.3, dt)
		a.rig.set_pose(PlayerRig.Pose.BLOCK)

func _pass_pro_target(a: FieldAgent) -> FieldAgent:
	## Pick the nearest unblocked rusher, preferring those in front of this blocker.
	var best: FieldAgent = null
	var bd := 7.5 if a.role == "OL" else 5.0
	var my_lat := _field(a.global_position).y
	for d in defense:
		if not d.can_act() or d.engaged != null or d.shed_cooldown > 0.0:
			continue
		if d.mode != FieldAgent.Mode.RUSH and d.mode != FieldAgent.Mode.PURSUE:
			continue
		var f := _field(d.global_position)
		var score := absf(f.y - my_lat) * 1.3 + a.flat_pos().distance_to(d.flat_pos()) * 0.5
		if score < bd:
			bd = score
			best = d
	return best

func _run_block_target(a: FieldAgent) -> FieldAgent:
	var best: FieldAgent = null
	var bd := 9.0
	var my := _field(a.global_position)
	var scheme: String = play_def.get("blocking", "inside")
	var flow := 0.0
	if scheme == "zone_right":
		flow = 2.0 * (-1.0 if flip else 1.0)
	elif scheme == "zone_left":
		flow = -2.0 * (-1.0 if flip else 1.0)
	for d in defense:
		if not d.can_act() or d.engaged != null or d.shed_cooldown > 0.0:
			continue
		var f := _field(d.global_position)
		var ahead := f.x - my.x
		if ahead < -1.5 or ahead > 9.0:
			continue
		var score := absf(f.y - (my.y + flow)) * 1.0 + maxf(ahead, 0.0) * 0.6
		if a.slot in ["X", "Z", "S"]:
			score = a.flat_pos().distance_to(d.flat_pos())
		if score < bd:
			bd = score
			best = d
	return best

func _nearest_defender(p: Vector3, radius: float, unengaged: bool) -> FieldAgent:
	var best: FieldAgent = null
	var bd := radius
	for d in defense:
		if not d.can_act() or (unengaged and d.engaged != null):
			continue
		var dist := d.flat_pos().distance_to(p)
		if dist < bd:
			bd = dist
			best = d
	return best

func _engage_or_approach(a: FieldAgent, d: FieldAgent, dt: float) -> void:
	var dist := a.flat_pos().distance_to(d.flat_pos())
	if dist < 1.15 and d.engaged == null and d.shed_cooldown <= 0.0:
		a.engaged = d
		d.engaged = a
		sfx.emit("block", a.global_position, 0.4)
		return
	# Get between the defender and the point we protect.
	var protect := _protect_point()
	var to_def := (d.flat_pos() - protect)
	var spot := d.flat_pos() - to_def.normalized() * 0.9
	a.seek(spot, 1.0, dt, 0.1)
	a.rig.set_pose(PlayerRig.Pose.BLOCK)

func _hold_block(a: FieldAgent, dt: float) -> void:
	var d := a.engaged
	if d == null or d.engaged != a or not d.can_act():
		a.engaged = null
		return
	# Blocker mirrors the rusher; resolution happens in _defense block logic.
	var protect := _protect_point()
	var to_def := (d.flat_pos() - protect)
	var spot := d.flat_pos() - to_def.normalized() * 0.85
	a.seek(spot, 0.9, dt, 0.05)
	a.face_toward(d.global_position)
	a.rig.set_pose(PlayerRig.Pose.PUSH)

func _ai_downfield_block(a: FieldAgent, dt: float) -> void:
	var c := _carrier()
	if c == null:
		a.steer(Vector3.ZERO, dt)
		return
	var target := _nearest_defender(c.flat_pos(), 12.0, true)
	if target != null and target.flat_pos().distance_to(a.flat_pos()) < 10.0:
		if a.engaged != null:
			_hold_block(a, dt)
		else:
			_engage_or_approach(a, target, dt)
	else:
		a.seek(c.flat_pos() + FieldCoords.forward(dir) * 4.0, 0.8, dt)
		a.rig.set_pose(PlayerRig.Pose.RUN)

# ================================================================= defense AI

func _ai_defense(a: FieldAgent, dt: float) -> void:
	if not a.can_act():
		a.steer(Vector3.ZERO, dt)
		return
	var carrier := _carrier()
	if a == carrier:
		_ai_carrier(a, dt) # interception / fumble return
		return
	if carrier != null and carrier.unit == FieldAgent.Unit.DEFENSE:
		# Escort the returner: block the nearest chaser.
		var chaser: FieldAgent = null
		var cd := 12.0
		for o in offense:
			if o.can_act() and o.flat_pos().distance_to(carrier.flat_pos()) < cd:
				cd = o.flat_pos().distance_to(carrier.flat_pos())
				chaser = o
		if chaser != null:
			a.seek(chaser.flat_pos().lerp(carrier.flat_pos(), 0.35), 0.95, dt, 0.0)
		else:
			a.seek(carrier.flat_pos() - FieldCoords.forward(dir) * 5.0, 0.9, dt)
		a.rig.set_pose(PlayerRig.Pose.RUN)
		return
	if a.engaged != null:
		_rush_engaged(a, dt)
		return
	if carrier != null and carrier.unit == FieldAgent.Unit.OFFENSE:
		var run_mode := carrier != qb or ran_past_los or (qb_run and t > 0.25)
		if run_mode and t >= a.react_t:
			# CBs and deep safeties respect the pass a little longer.
			var past := _field(carrier.global_position).x > los + 1.0
			if a.mode in [FieldAgent.Mode.COVER, FieldAgent.Mode.ZONE] and not past and carrier.speed() < 3.0 and t < a.react_t + 0.5:
				pass
			else:
				_ai_pursue(a, carrier, dt, float(tune.get("pursuit", 1.0)))
				return
	if ball.state == Football.State.FLIGHT and thrown and t >= a.react_t and not pass_resolved:
		if _ai_play_ball(a, dt):
			return
	if ball.state == Football.State.LOOSE:
		a.seek(ball.global_position, 1.0, dt, 0.0)
		a.rig.set_pose(PlayerRig.Pose.RUN)
		return
	match a.mode:
		FieldAgent.Mode.RUSH:
			_ai_rush(a, dt)
		FieldAgent.Mode.COVER:
			_ai_man(a, dt)
		FieldAgent.Mode.ZONE:
			_ai_zone(a, dt)
		FieldAgent.Mode.PURSUE:
			if carrier != null:
				_ai_pursue(a, carrier, dt, 1.0)
		_:
			a.steer(Vector3.ZERO, dt)

func _ai_rush(a: FieldAgent, dt: float) -> void:
	var target := qb.flat_pos()
	var c := _carrier()
	if c != null and c != qb:
		target = c.flat_pos()
	if playaction and t < 0.7 and a.role == "LB":
		target = a.flat_pos() - FieldCoords.forward(dir) * 2.0
	var rush := float(tune.get("rush", 1.0))
	a.seek(target, 0.92 * rush, dt, 0.0)
	a.rig.set_pose(PlayerRig.Pose.RUN)

func _rush_engaged(a: FieldAgent, dt: float) -> void:
	## Defender locked with a blocker: grind toward the ball and try to shed.
	var b := a.engaged
	if b == null or b.engaged != a:
		a.engaged = null
		return
	var target := _protect_point()
	var rush := a.player.effective("pass_rush") * 0.6 + a.player.effective("strength") * 0.4
	if designed_run or (_carrier() != null and _carrier() != qb):
		rush = a.player.effective("strength") * 0.6 + a.player.effective("tackling") * 0.4
	var block := b.player.effective("blocking") * 0.6 + b.player.effective("strength") * 0.4
	var edge := (rush - block) / 100.0 * float(tune.get("rush", 1.0))
	var push := clampf(0.18 + edge * 0.9, 0.04, 0.5)
	var to := (target - a.flat_pos())
	to.y = 0.0
	a.vel = a.vel.move_toward(to.normalized() * a.top_speed * push, 10.0 * dt)
	b.vel = b.vel.move_toward(a.vel, 10.0 * dt)
	a.rig.set_pose(PlayerRig.Pose.PUSH)
	a.face_toward(b.global_position)
	# Shed attempts.
	var hold := 1.0 + clampf((t - 1.5) * 0.4, 0.0, 1.5)
	var p_shed := clampf(0.011 + edge * 0.05, 0.002, 0.06) * hold * dt * 60.0 / 10.0
	var c := _carrier()
	if c != null and c.flat_pos().distance_to(a.flat_pos()) < 2.0:
		p_shed *= 4.0
	if rng.randf() < p_shed:
		a.engaged = null
		b.engaged = null
		b.shed_cooldown = 0.9
		a.shed_cooldown = 0.6
		b.stumble_t = 0.25

func _ai_man(a: FieldAgent, dt: float) -> void:
	var r := a.assignment
	if r == null:
		a.steer(Vector3.ZERO, dt)
		return
	if r.mode == FieldAgent.Mode.BLOCK and t > 1.2:
		# Receiver stayed in to block; become a robber in the short middle.
		a.mode = FieldAgent.Mode.ZONE
		a.zone_point = _world(6.0, 0.0)
		a.zone_radius = 7.0
		return
	var cover := a.player.effective("coverage")
	var route := r.player.effective("route")
	var lag := clampf(0.22 + (route - cover) * 0.008 + separation_bonus * 0.006, 0.08, 0.6) * float(tune.get("coverage_lag", 1.0))
	if t < a.react_t:
		lag += a.react_t - t
	var lagged := r.lagged_position(lag)
	var fwd := FieldCoords.forward(dir)
	var cushion := maxf(0.0, 2.8 - t * 1.6)
	var spot := lagged + fwd * (cushion + 0.6)
	var lat := _field(lagged).y
	spot += FieldCoords.offense_right(dir) * (-signf(lat) * 0.5)
	var urgency := 1.0 if a.flat_pos().distance_to(spot) > 1.0 else 0.85
	a.seek(spot, urgency, dt, 0.15)
	if t < 0.9 and _field(a.global_position).x > _field(r.global_position).x:
		a.rig.set_pose(PlayerRig.Pose.RUN)
	else:
		a.rig.set_pose(PlayerRig.Pose.RUN)

func _ai_zone(a: FieldAgent, dt: float) -> void:
	var lag_mult := float(tune.get("coverage_lag", 1.0))
	var landmark := a.zone_point
	var threat: FieldAgent = null
	var td := a.zone_radius
	for r in receivers:
		if r.mode != FieldAgent.Mode.ROUTE and r.mode != FieldAgent.Mode.BALL_HAWK:
			continue
		var d := r.flat_pos().distance_to(landmark)
		if d < td:
			td = d
			threat = r
	var spot := landmark
	if threat != null and t > a.react_t:
		var lagged := threat.lagged_position(0.22 * lag_mult)
		spot = landmark.lerp(lagged, 0.7)
		# Deep defenders stay on top.
		if _field(landmark).x - los > 12.0:
			var depth_needed := _field(lagged).x + 2.5
			var f := _field(spot)
			if f.x < depth_needed:
				spot = FieldCoords.to_world(depth_needed, f.y, dir)
	var urgency := 0.95 if t < 1.5 else 0.8
	a.seek(spot, urgency, dt, 0.4)
	a.rig.set_pose(PlayerRig.Pose.RUN)

## Defender breaks on a thrown ball. Returns true if handled.
func _ai_play_ball(a: FieldAgent, dt: float) -> bool:
	var spot := pass_land
	var remaining := float(pass_info.get("air_time", 1.0)) - (t - float(pass_info.get("thrown_at", 0.0)))
	var d := a.flat_pos().distance_to(spot)
	var reach := a.top_speed * maxf(remaining, 0.0) + 2.5
	if d > reach + 3.0:
		return false
	a.seek(spot, 1.0, dt, 0.0)
	a.rig.set_pose(PlayerRig.Pose.CATCH if remaining < 0.4 else PlayerRig.Pose.RUN)
	return true

func _ai_pursue(a: FieldAgent, target: FieldAgent, dt: float, mult: float) -> void:
	if a.engaged != null:
		if a.unit == FieldAgent.Unit.DEFENSE:
			_rush_engaged(a, dt)
		else:
			_hold_block(a, dt)
		return
	var tp := target.flat_pos()
	var tv := Vector3(target.vel.x, 0, target.vel.z)
	var d := a.flat_pos().distance_to(tp)
	var lead := clampf(d / maxf(a.top_speed, 1.0), 0.0, 1.2) * (0.6 + a.player.effective("awareness") / 250.0)
	var aim := tp + tv * lead
	a.seek(aim, mult, dt, 0.0)
	a.rig.set_pose(PlayerRig.Pose.RUN)

# ================================================================= ball / catches

func _ball_logic(dt: float) -> void:
	match ball.state:
		Football.State.FLIGHT:
			if not thrown and ball.intended == qb:
				# Shotgun snap in the air.
				if ball.flight_time > 0.28 or ball.global_position.distance_to(qb.global_position + Vector3(0, 1.2, 0)) < 0.6:
					ball.give_to(qb)
				return
			if special == "spike":
				if ball.global_position.y <= 0.2:
					_end_play("spike")
				return
			_resolve_catches()
			if stage == Stage.LIVE and ball.state == Football.State.FLIGHT and ball.global_position.y <= 0.15:
				_incomplete("ground")
			elif stage == Stage.LIVE and ball.state == Football.State.FLIGHT and not FieldCoords.is_in_bounds(ball.global_position) and ball.global_position.y < 2.0:
				_incomplete("out_of_bounds")
		Football.State.LOOSE:
			loose_t += dt
			_resolve_loose()
		_:
			pass

func _resolve_catches() -> void:
	## A player attempts the catch at the ball's closest approach to him (not
	## the instant it enters his reach), so position and timing matter.
	var bp := ball.global_position
	if bp.y > 3.3:
		return
	var dt := 1.0 / 60.0
	var next := bp + ball.velocity * dt + Vector3.DOWN * (0.5 * PassMath.GRAVITY * dt * dt)
	var best: FieldAgent = null
	var best_d := 99.0
	for a in offense + defense:
		if a == qb or not a.can_act() or ball.touched_by.has(a):
			continue
		if bp.y < 0.3 or bp.y > 3.0 + a.agility * 0.003:
			continue
		var hd := Vector2(a.global_position.x - bp.x, a.global_position.z - bp.z).length()
		var reach := 1.3 if a.unit == FieldAgent.Unit.OFFENSE else 1.1
		if hd >= reach:
			continue
		# Still approaching and will remain catchable next frame: wait.
		var hd_next := Vector2(a.global_position.x + a.vel.x * dt - next.x, a.global_position.z + a.vel.z * dt - next.z).length()
		if hd_next < hd - 0.002 and next.y > 0.35:
			continue
		if hd < best_d:
			best_d = hd
			best = a
	if best != null:
		_attempt_catch(best, best_d, bp)

func _attempt_catch(a: FieldAgent, hd: float, bp: Vector3) -> void:
	ball.touched_by.append(a)
	var contest := 0.0
	var contester: FieldAgent = null
	var opponents := defense if a.unit == FieldAgent.Unit.OFFENSE else offense
	for o in opponents:
		if not o.can_act():
			continue
		var od := Vector2(o.global_position.x - bp.x, o.global_position.z - bp.z).length()
		if od < 1.35:
			var c := (1.35 - od) / 1.35 * (o.player.effective("coverage") / 85.0 if o.unit == FieldAgent.Unit.DEFENSE else 0.4)
			if c > contest:
				contest = c
				contester = o
	var spd := ball.velocity.length()
	if a.unit == FieldAgent.Unit.OFFENSE:
		var p := 0.6 + a.player.effective("catching") / 99.0 * 0.38 + float(tune.get("catch_bonus", 0.0)) + float(assist - 1) * 0.03
		if hd > 0.75:
			p -= (hd - 0.75) * 0.55
			a.rig.set_pose(PlayerRig.Pose.DIVE)
		else:
			a.rig.set_pose(PlayerRig.Pose.CATCH)
		if bp.y > 2.5:
			p -= (bp.y - 2.5) * 0.45
		elif bp.y < 0.65:
			p -= 0.15
		if spd > 24.0:
			p -= (spd - 24.0) * 0.022
		p -= contest * 0.34
		if a != pass_target:
			p -= 0.06
		var in_bounds := FieldCoords.is_in_bounds(a.global_position)
		if rng.randf() < clampf(p, 0.05, 0.97):
			if not in_bounds:
				_incomplete("caught_oob")
				return
			_complete(a)
		else:
			if contest > 0.35 and contester != null:
				pass_info["breakup"] = contester
				credit["defended_by"] = contester.player.id
				_deflect(1.0)
			else:
				pass_info["drop"] = a
				_deflect(0.6)
	else:
		var p_int := (0.05 + a.player.effective("catching") / 99.0 * 0.3 - hd * 0.1) * float(tune.get("int_mult", 1.0))
		if pass_target != null and pass_target.flat_pos().distance_to(Vector3(bp.x, 0, bp.z)) < 1.2:
			p_int *= 0.5
		if bp.y > 2.6:
			p_int *= 0.6
		# Defenders trailing with their back to the throw rarely make a play.
		var to_qb := (qb.flat_pos() - a.flat_pos()).normalized()
		var sees_ball := a.facing.dot(to_qb) > -0.2
		if not sees_ball:
			p_int *= 0.35
		a.rig.set_pose(PlayerRig.Pose.CATCH)
		if rng.randf() < clampf(p_int, 0.02, 0.75):
			_intercept(a)
		elif rng.randf() < (0.3 + a.player.effective("coverage") / 300.0) * (1.0 if sees_ball else 0.6):
			pass_info["breakup"] = a
			credit["defended_by"] = a.player.id
			_deflect(1.0)

func _deflect(strength: float) -> void:
	var v := ball.velocity
	ball.velocity = Vector3(v.x * 0.25 + rng.randf_range(-2.0, 2.0) * strength, absf(v.y) * 0.15 + rng.randf_range(1.0, 3.5) * strength, v.z * 0.25 + rng.randf_range(-2.0, 2.0) * strength)
	ball.spin_rate = 30.0
	sfx.emit("deflect", ball.global_position, 0.7)

func _complete(a: FieldAgent) -> void:
	pass_resolved = true
	completed = true
	ball.give_to(a)
	credit["receiver"] = a.player.id
	pass_info["catch_spot"] = ball_on_of(a.global_position)
	a.mode = FieldAgent.Mode.CARRY
	a.rig.carrying = true
	land_marker.visible = false
	_set_user(a)
	var air := float(pass_info.get("catch_spot", los)) - los
	feedback.emit("Caught! %+d" % int(round(air)) if air >= 0.0 else "Caught!", Color("#65C987"), false)
	sfx.emit("catch", a.global_position, 0.8)
	for d in defense:
		d.react_t = t + 0.15
		if d.mode == FieldAgent.Mode.RUSH:
			d.mode = FieldAgent.Mode.PURSUE

func _intercept(a: FieldAgent) -> void:
	pass_resolved = true
	ball.give_to(a)
	turnover_kind = "int"
	turnover_spot = ball_on_of(a.global_position)
	credit["interceptor"] = a.player.id
	a.mode = FieldAgent.Mode.CARRY
	a.rig.carrying = true
	land_marker.visible = false
	feedback.emit("INTERCEPTED!", Color("#E75A5A"), true)
	sfx.emit("interception", a.global_position, 1.0)
	user.is_user = false
	for o in offense:
		o.engaged = null
		o.mode = FieldAgent.Mode.PURSUE
	for d in defense:
		d.engaged = null
		if d != a:
			d.mode = FieldAgent.Mode.BLOCK
	# A pick in the end zone with no return is a touchback; the rules engine handles it.

func _incomplete(reason: String) -> void:
	pass_resolved = true
	ball.kill()
	var msg := "Incomplete"
	if pass_info.get("throwaway", false):
		msg = "Thrown away"
	elif reason == "caught_oob":
		msg = "Incomplete — out of bounds"
	elif pass_info.has("breakup"):
		var b: FieldAgent = pass_info["breakup"]
		msg = "Broken up by #%d" % b.player.number
	elif pass_info.has("drop"):
		msg = "Dropped!"
	elif pass_info.get("underthrown", false):
		msg = "Underthrown — needed more power"
	elif pass_target != null:
		var along: float = pass_info.get("err_along", 0.0)
		var lat: float = pass_info.get("err_lat", 0.0)
		if float(pass_info.get("pressure", 0.0)) > 0.5:
			msg = "Off target under pressure"
		elif along > 1.4:
			msg = "Overthrown"
		elif along < -1.4:
			msg = "Underthrown"
		elif absf(lat) > 1.2:
			msg = "Off target"
		else:
			msg = "Incomplete — not enough lead"
	end_reason = "incomplete"
	feedback.emit(msg, Color("#F5F0E5"), false)
	sfx.emit("incomplete", ball.global_position, 0.6)
	_end_play("incomplete")

func _resolve_loose() -> void:
	if loose_t < 0.25:
		return
	var bp := ball.global_position
	if bp.y > 1.0:
		return
	if not FieldCoords.is_in_bounds(bp):
		# Out of bounds: last possession keeps it at the spot.
		end_spot = ball_on_of(bp)
		end_lateral = _field(bp).y
		_end_play("fumble_oob")
		return
	var best: FieldAgent = null
	var bd := 0.9
	for a in offense + defense:
		if not a.can_act():
			continue
		var d := Vector2(a.global_position.x - bp.x, a.global_position.z - bp.z).length()
		if d < bd:
			bd = d
			best = a
	if best != null and rng.randf() < 0.25:
		best.go_down()
		end_spot = ball_on_of(bp)
		end_lateral = _field(bp).y
		ball.give_to(best)
		if best.unit == FieldAgent.Unit.DEFENSE:
			turnover_kind = "fumble"
			turnover_spot = end_spot
			credit["recoverer"] = best.player.id
			feedback.emit("FUMBLE — recovered by the defense!", Color("#E75A5A"), true)
			sfx.emit("turnover", bp, 1.0)
			_end_play("fumble_lost")
		else:
			feedback.emit("Fumble — offense recovers", Color("#F4C95D"), false)
			_end_play("fumble_recovered")

# ================================================================= contact

func _contacts(dt: float) -> void:
	var c := _carrier()
	if c == null:
		return
	if c.dive_t >= 0.0:
		c.dive_t += dt
		if c.dive_t > 0.45:
			_tackled(c, null, "dive")
			return
	if c == qb and not thrown and not ran_past_los and _field(qb.global_position).x > los + 0.2:
		ran_past_los = true
		qb.rig.carrying = true
		aim_marker.visible = false
		land_marker.visible = false
		if not designed_run:
			feedback.emit("QB scramble!", Color("#F4C95D"), false)
	var tacklers := defense if c.unit == FieldAgent.Unit.OFFENSE else offense
	for d in tacklers:
		if not d.can_act() or d.engaged != null or d.tackle_cd > 0.0:
			continue
		if c.flat_pos().distance_to(d.flat_pos()) > TACKLE_RANGE:
			continue
		if c == slots["C"] and not thrown:
			continue
		d.tackle_cd = 0.7
		if _tackle_roll(d, c):
			if stage == Stage.LIVE:
				_tackled(c, d, "tackle")
			return
		else:
			broken_tackles += 1
			d.stumble_t = 0.55
			d.rig.set_pose(PlayerRig.Pose.DIVE)
			c.vel *= 0.8
			if c.unit == FieldAgent.Unit.OFFENSE:
				feedback.emit("Broken tackle!" if c.juke_t <= 0.0 else "Juke!", Color("#F4C95D"), false)
			sfx.emit("hit_light", c.global_position, 0.5)

func _tackle_roll(d: FieldAgent, c: FieldAgent) -> bool:
	var tk := d.player.effective("tackling")
	var elude := c.player.effective("balance") * 0.5 + c.player.effective("agility") * 0.3 + c.player.effective("strength") * 0.2
	var p := 0.67 + (tk - elude) / 100.0 * 0.85
	var mult := float(tune.get("tackle", 1.0)) if d.unit == FieldAgent.Unit.DEFENSE else 0.85
	p *= mult
	# Head-on contact is surer than an arm tackle from behind.
	var rel := (c.flat_pos() - d.flat_pos()).normalized()
	var cdir := Vector3(c.vel.x, 0, c.vel.z)
	if cdir.length() > 1.0:
		var from_behind := cdir.normalized().dot(rel) > 0.5
		if from_behind and c.speed() > d.speed():
			p -= 0.15
	if c.juke_t > 0.0:
		p -= 0.22 + c.agility / 99.0 * 0.15
	if c.speed() > c.top_speed * 0.92:
		p -= 0.05
	if c == qb and not ran_past_los and not thrown:
		p += 0.12 # quarterbacks in the pocket are easy to bring down
	if c.player.pos in ["OL", "DL"]:
		p += 0.2
	return rng.randf() < clampf(p, 0.18, 0.96)

func _tackled(c: FieldAgent, by: FieldAgent, how: String) -> void:
	var fwd := FieldCoords.forward(dir) if c.unit == FieldAgent.Unit.OFFENSE else -FieldCoords.forward(dir)
	var moving_fwd := Vector3(c.vel.x, 0, c.vel.z).dot(fwd)
	var fall := clampf(moving_fwd * 0.08, 0.0, 0.8)
	if how == "dive":
		fall = 0.3
	var spot := c.flat_pos() + fwd * fall
	end_spot = ball_on_of(spot)
	end_lateral = _field(spot).y
	if by != null:
		credit["tackler"] = by.player.id
		by.go_down(rng.randf_range(-1.0, 1.0))
		sfx.emit("tackle", c.global_position, clampf((c.speed() + by.speed()) / 14.0, 0.4, 1.0))
	c.go_down(rng.randf_range(-1.0, 1.0))
	# Fumble check on solid hits.
	if by != null and c.unit == FieldAgent.Unit.OFFENSE and how == "tackle":
		var p_fum := 0.003 + maxf(0.0, 70.0 - c.player.effective("carrying")) * 0.0004 + by.player.effective("strength") * 0.00003
		if c == qb and not thrown and not ran_past_los:
			p_fum += 0.015
		if rng.randf() < p_fum:
			_fumble(c, by)
			return
	if c == qb and not thrown and not ran_past_los and not qb_run and _field(spot).x < los + 0.5 and turnover_kind == "":
		credit["sacker"] = by.player.id if by != null else ""
		feedback.emit("SACKED!", Color("#E75A5A"), true)
		sfx.emit("sack", c.global_position, 1.0)
		end_reason = "sack"
	_end_play("tackle")

func _fumble(c: FieldAgent, by: FieldAgent) -> void:
	credit["fumbler"] = c.player.id
	credit["forced_by"] = by.player.id
	var v := Vector3(rng.randf_range(-4, 4), rng.randf_range(2.0, 4.0), rng.randf_range(-4, 4))
	ball.fumble(c.global_position + Vector3(0, 1.0, 0), v)
	loose_t = 0.0
	feedback.emit("FUMBLE!", Color("#E75A5A"), true)
	sfx.emit("fumble", c.global_position, 1.0)

func _separate() -> void:
	var all := offense + defense
	var n := all.size()
	for i in n:
		var a: FieldAgent = all[i]
		if not a.visible or a.mode == FieldAgent.Mode.DOWN:
			continue
		for k in range(i + 1, n):
			var b: FieldAgent = all[k]
			if not b.visible or b.mode == FieldAgent.Mode.DOWN:
				continue
			var d := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
			var dist := d.length()
			var min_d := 0.8 if (a.engaged == b) else 0.75
			if dist < min_d and dist > 0.0001:
				var push := (min_d - dist) * 0.5
				var n2 := d / dist
				var wa := 0.5
				# The ball carrier is harder to displace (keeps runs fluid).
				if a == _carrier():
					wa = 0.25
				elif b == _carrier():
					wa = 0.75
				a.global_position -= Vector3(n2.x, 0, n2.y) * push * 2.0 * wa
				b.global_position += Vector3(n2.x, 0, n2.y) * push * 2.0 * (1.0 - wa)

# ================================================================= boundaries

func _check_boundaries() -> void:
	var c := _carrier()
	if c == null or stage != Stage.LIVE:
		return
	var p := c.flat_pos()
	var bo := ball_on_of(p)
	if c.unit == FieldAgent.Unit.OFFENSE:
		if (c != qb or ran_past_los or thrown or handed_off or qb_run or completed) and bo >= 100.0:
			touchdown = true
			end_spot = 100.0
			end_lateral = _field(p).y
			_score_celebration(c)
			_end_play("touchdown")
			return
	else:
		if bo <= 0.0:
			defensive_td = true
			end_spot = 0.0
			end_lateral = _field(p).y
			_score_celebration(c)
			feedback.emit("PICK SIX!", Color("#E75A5A"), true)
			_end_play("defensive_td")
			return
	if absf(p.z) > FieldCoords.HALF_WIDTH or absf(p.x) > 60.0:
		out_of_bounds = true
		var edge := Vector3(p.x, 0, clampf(p.z, -FieldCoords.HALF_WIDTH, FieldCoords.HALF_WIDTH))
		end_spot = ball_on_of(edge)
		end_lateral = _field(edge).y
		feedback.emit("Out of bounds", Color("#BFB8AA"), false)
		sfx.emit("whistle", p, 0.6)
		_end_play("out_of_bounds")

func _score_celebration(c: FieldAgent) -> void:
	c.mode = FieldAgent.Mode.CELEBRATE
	c.rig.set_pose(PlayerRig.Pose.CELEBRATE)
	celebrated = true
	var team := offense if c.unit == FieldAgent.Unit.OFFENSE else defense
	for a in team:
		if a != c and a.can_act() and a.flat_pos().distance_to(c.flat_pos()) < 25.0:
			a.mode = FieldAgent.Mode.CELEBRATE
			a.rig.set_pose(PlayerRig.Pose.CELEBRATE)
			a.rig.pose_time = rng.randf_range(0.0, 1.0)
	sfx.emit("touchdown", c.global_position, 1.0)

# ================================================================= end of play

func _end_play(reason: String) -> void:
	if stage != Stage.LIVE:
		return
	if end_reason == "" or reason in ["touchdown", "defensive_td", "fumble_lost"]:
		end_reason = reason
	stage = Stage.DEAD
	dead_t = 0.0
	aim_marker.visible = false
	land_marker.visible = false
	var c := _carrier()
	if reason in ["incomplete", "spike"]:
		end_lateral = lat0
	elif reason == "kneel":
		end_spot = los - 1.0
		end_lateral = lat0
		qb.go_down()
	elif reason == "timeout":
		if c != null:
			end_spot = ball_on_of(c.global_position)
			end_lateral = _field(c.global_position).y
		else:
			end_spot = los
			end_lateral = lat0
	if c != null and reason != "incomplete":
		c.rig.carrying = false
	if reason != "touchdown" and reason != "defensive_td":
		sfx.emit("whistle", ball.global_position, 0.8)
	for a in offense + defense:
		a.engaged = null
		a.set_highlight(false)

func _build_result() -> PlayResult:
	var r := PlayResult.new()
	r.elapsed = clampf(t + 0.5, 1.0, MAX_PLAY_TIME)
	r.credit = credit.duplicate()
	r.out_of_bounds = out_of_bounds
	match end_reason:
		"incomplete":
			r.kind = PlayResult.Kind.PASS_INCOMPLETE
			r.gain = 0.0
			r.description = "Pass incomplete"
		"spike":
			r.kind = PlayResult.Kind.SPIKE
			r.gain = 0.0
			r.description = "Spiked to stop the clock"
		"kneel":
			r.kind = PlayResult.Kind.KNEEL
			r.gain = -1.0
			r.description = "QB kneels"
		_:
			if turnover_kind == "int":
				r.kind = PlayResult.Kind.INTERCEPTION
				r.gain = turnover_spot - los
				r.return_yards = 100.0 if defensive_td else maxf(0.0, turnover_spot - end_spot)
				r.description = "Intercepted"
			elif turnover_kind == "fumble":
				r.kind = PlayResult.Kind.FUMBLE_LOST
				r.gain = turnover_spot - los
				r.return_yards = 0.0
				r.description = "Fumble lost"
			else:
				var gain := end_spot - los
				if touchdown:
					gain = maxf(gain, 100.0 - los)
				r.gain = gain
				if completed:
					r.kind = PlayResult.Kind.PASS_COMPLETE
					r.air_yards = float(pass_info.get("catch_spot", los)) - los
					r.description = "Pass complete for %d" % int(round(gain))
				elif end_reason == "sack":
					r.kind = PlayResult.Kind.SACK
					r.description = "Sacked for %d" % int(round(gain))
				else:
					r.kind = PlayResult.Kind.RUN
					if not credit.has("rusher") and _carrier() != null:
						credit["rusher"] = (_carrier() as FieldAgent).player.id
						r.credit["rusher"] = credit["rusher"]
					r.description = "Run for %d" % int(round(gain))
	return r

func _build_info() -> Dictionary:
	return {
		"reason": end_reason, "end_lateral": end_lateral, "touchdown": touchdown,
		"defensive_td": defensive_td, "turnover": turnover_kind, "broken_tackles": broken_tackles,
		"pass": pass_info, "completed": completed, "max_speed": max_speed_seen,
		"big_play": touchdown or turnover_kind != "" or (end_spot - los) >= 20.0 or end_reason == "sack",
	}

# ================================================================= misc

func _update_pressure() -> void:
	pressure = 0.0
	if qb == null or _carrier() != qb:
		return
	for d in defense:
		if d.engaged != null or not d.can_act():
			continue
		var dist := d.flat_pos().distance_to(qb.flat_pos())
		pressure = maxf(pressure, clampf(1.0 - (dist - 1.0) / 3.0, 0.0, 1.0))

func _update_markers() -> void:
	var c := _carrier()
	if c != null:
		max_speed_seen = maxf(max_speed_seen, c.speed())

func _record(_dt: float) -> void:
	recorder.capture(t if stage == Stage.LIVE else t + dead_t, offense + defense, ball)

func debug_info() -> String:
	var c := _carrier()
	var lines: Array[String] = []
	lines.append("stage=%s t=%.2f los=%.1f dir=%d" % [Stage.keys()[stage], t, los, dir])
	lines.append("play=%s def=%s flip=%s" % [play_def.get("id", ""), def_call.get("id", ""), flip])
	lines.append("ball=%s carrier=%s" % [Football.State.keys()[ball.state], (c.slot + " #" + str(c.player.number)) if c != null else "-"])
	lines.append("thrown=%s target=%s pressure=%.2f charge=%.2f" % [thrown, pass_target.slot if pass_target != null else "-", pressure, charge])
	for d in defense:
		lines.append("  %s %s %s" % [d.slot, FieldAgent.Mode.keys()[d.mode], d.note])
	return "\n".join(lines)
