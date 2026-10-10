class_name FieldAgent
extends Node3D
## One player on the field during a live play. Movement is kinematic and
## rating-driven (no rigid bodies): acceleration, top speed and turning come
## from the player's attributes; contact is resolved by gameplay rules.

enum Unit { OFFENSE, DEFENSE }
enum Mode { IDLE, STANCE, ROUTE, BLOCK, RUSH, COVER, ZONE, PURSUE, CARRY, BALL_HAWK, FAKE, DOWN, STUMBLE, CELEBRATE, SPECTATE, KICK }

const HISTORY_LEN := 64 ## ~1 second at 60 Hz

var player: Player
var unit: Unit = Unit.OFFENSE
var slot: String = "" ## X, Z, LT, CB1, ...
var role: String = "" ## position group
var rig: PlayerRig
var mode: Mode = Mode.IDLE
var vel := Vector3.ZERO
var facing := Vector3.FORWARD
var top_speed: float = 8.0
var accel: float = 14.0
var agility: float = 70.0
var stamina: float = 1.0 ## sprint energy 0..1
var route: Array[Vector3] = []
var route_idx: int = 0
var route_continue: bool = false
var route_delay: float = 0.0
var assignment: FieldAgent = null ## man-coverage target / block target
var zone_point := Vector3.ZERO
var zone_radius: float = 8.0
var engaged: FieldAgent = null
var shed_cooldown: float = 0.0
var stumble_t: float = 0.0
var tackle_cd: float = 0.0
var react_t: float = 0.0
var juke_t: float = 0.0
var juke_cd: float = 0.0
var dive_t: float = -1.0
var is_user: bool = false
var blitz: bool = false
var down_t: float = 0.0
var history: PackedVector3Array = PackedVector3Array()
var hist_head: int = 0
var desired := Vector3.ZERO
var highlight: MeshInstance3D
var target_ring: MeshInstance3D
var label3d: Label3D
var note: String = "" ## debug assignment text

func setup(p: Player, u: Unit, p_slot: String, p_role: String, jersey: Color, pants: Color, helmet: Color, trim: Color, mask: Color, font: Font) -> void:
	player = p
	unit = u
	slot = p_slot
	role = p_role
	rig = PlayerRig.new()
	add_child(rig)
	rig.build(jersey, pants, helmet, trim, mask, p.number, p.skin, p.build, font)
	refresh_ratings()
	history.resize(HISTORY_LEN)
	_build_markers(font)

func refresh_ratings() -> void:
	top_speed = player.top_speed()
	accel = 9.0 + player.effective("accel") * 0.11 ## 13.4 .. 19.9 yd/s^2
	agility = player.effective("agility")

func _build_markers(font: Font) -> void:
	highlight = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.72
	tm.rings = 24
	tm.ring_segments = 6
	highlight.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#F28C38")
	m.emission_enabled = true
	m.emission = Color("#F28C38")
	m.emission_energy_multiplier = 1.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight.material_override = m
	highlight.scale = Vector3(1, 0.05, 1)
	highlight.position.y = 0.03
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	add_child(highlight)
	label3d = Label3D.new()
	label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label3d.no_depth_test = true
	label3d.fixed_size = true
	label3d.pixel_size = 0.0016
	label3d.font_size = 34
	label3d.outline_size = 10
	if font != null:
		label3d.font = font
	label3d.modulate = Color("#F5F0E5")
	label3d.outline_modulate = Color("#101B2B")
	label3d.position = Vector3(0, 2.6, 0)
	label3d.visible = false
	add_child(label3d)

func set_highlight(on: bool, color: Color = Color("#F28C38")) -> void:
	highlight.visible = on
	if on:
		var m: StandardMaterial3D = highlight.material_override
		m.albedo_color = color
		m.emission = color

func show_tag(text: String, color: Color = Color("#F5F0E5")) -> void:
	label3d.visible = text != ""
	label3d.text = text
	label3d.modulate = color

func reset_for_play(pos: Vector3, face: Vector3) -> void:
	global_position = pos
	vel = Vector3.ZERO
	facing = face.normalized()
	rotation = Vector3(0, atan2(-facing.x, -facing.z), 0)
	mode = Mode.STANCE
	route.clear()
	route_idx = 0
	route_delay = 0.0
	assignment = null
	engaged = null
	shed_cooldown = 0.0
	stumble_t = 0.0
	tackle_cd = 0.0
	react_t = 0.0
	juke_t = 0.0
	juke_cd = 0.0
	dive_t = -1.0
	blitz = false
	down_t = 0.0
	desired = Vector3.ZERO
	note = ""
	visible = true
	for i in HISTORY_LEN:
		history[i] = pos
	if rig != null:
		rig.carrying = false
		rig.speed = 0.0

func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)

func flat_pos() -> Vector3:
	return Vector3(global_position.x, 0, global_position.z)

func speed() -> float:
	return Vector2(vel.x, vel.z).length()

func is_down() -> bool:
	return mode == Mode.DOWN

func can_act() -> bool:
	return mode != Mode.DOWN and stumble_t <= 0.0

## Lagged position from the history ring (used by coverage reaction).
func lagged_position(seconds: float) -> Vector3:
	var frames := clampi(int(round(seconds * 60.0)), 0, HISTORY_LEN - 1)
	var idx := (hist_head - frames + HISTORY_LEN) % HISTORY_LEN
	return history[idx]

## Moves toward a world-space destination. `urgency` scales top speed.
func seek(target: Vector3, urgency: float, dt: float, arrive_radius: float = 0.6) -> void:
	var to := target - global_position
	to.y = 0.0
	var d := to.length()
	var want := Vector3.ZERO
	if d > 0.05:
		var spd := top_speed * urgency
		if d < arrive_radius * 3.0:
			spd *= clampf(d / (arrive_radius * 3.0), 0.0, 1.0)
		want = to / d * spd
	steer(want, dt)

## Applies acceleration limits toward a desired velocity. Sharp cuts at
## speed cost momentum based on agility.
func steer(want: Vector3, dt: float) -> void:
	want.y = 0.0
	var slow := 1.0
	if stumble_t > 0.0:
		slow = 0.35
	elif engaged != null:
		slow = 0.3
	want *= slow
	desired = want
	var a := accel
	var cur_speed := speed()
	if cur_speed > 2.0 and want.length() > 0.5:
		var turn := vel.normalized().dot(want.normalized())
		if turn < 0.3:
			# Hard cuts bleed speed; agile players recover faster.
			a *= lerpf(0.55, 1.0, agility / 99.0)
	vel = vel.move_toward(want, a * dt)
	if juke_t > 0.0:
		vel *= 1.0

func integrate(dt: float) -> void:
	if mode == Mode.DOWN:
		vel = vel.move_toward(Vector3.ZERO, 12.0 * dt)
	global_position += vel * dt
	global_position.y = 0.0
	var sp := speed()
	if sp > 0.4 and mode != Mode.DOWN:
		var f := Vector3(vel.x, 0, vel.z).normalized()
		var turn_rate := 9.0 + agility * 0.08
		var cur := atan2(facing.x, facing.z)
		var tgt := atan2(f.x, f.z)
		var ang := lerp_angle(cur, tgt, clampf(turn_rate * dt, 0.0, 1.0))
		facing = Vector3(sin(ang), 0.0, cos(ang))
	if facing.length() > 0.1:
		rotation.y = atan2(-facing.x, -facing.z)
	hist_head = (hist_head + 1) % HISTORY_LEN
	history[hist_head] = global_position
	stumble_t = maxf(0.0, stumble_t - dt)
	tackle_cd = maxf(0.0, tackle_cd - dt)
	shed_cooldown = maxf(0.0, shed_cooldown - dt)
	juke_t = maxf(0.0, juke_t - dt)
	juke_cd = maxf(0.0, juke_cd - dt)
	if rig != null:
		rig.speed = sp
		var fwd_accel := 0.0
		rig.lean = fwd_accel

func face_toward(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.01:
		facing = d.normalized()
		rotation.y = atan2(-facing.x, -facing.z)

## World position where a held ball sits.
func ball_hold_point() -> Vector3:
	if rig == null:
		return global_position + Vector3(0, 1.2, 0)
	if rig.pose == PlayerRig.Pose.THROW or rig.pose == PlayerRig.Pose.QB_SET or rig.pose == PlayerRig.Pose.KICK:
		return rig.hand_position()
	return rig.carry_position()

func go_down(side: float = 1.0) -> void:
	mode = Mode.DOWN
	engaged = null
	if rig != null:
		rig.fall_side = side
		rig.set_pose(PlayerRig.Pose.DOWN)
