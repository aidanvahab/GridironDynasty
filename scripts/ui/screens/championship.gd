class_name ChampionshipScreen
extends Node3D
## Title celebration: trophy presentation at midfield with confetti.

var _cam: BroadcastCamera
var _rigs: Array[PlayerRig] = []
var _trophy: Node3D
var _t := 0.0

func _ready() -> void:
	var lg := App.league
	var ut := lg.user_team()
	var stadium := StadiumBuilder.new()
	add_child(stadium)
	stadium.build(ut.stadium, ut.primary, ut.secondary, Palette.GOLD, "night", [0.35, 0.65, 1.0][int(Settings.get_value("quality"))], 7)
	stadium.set_excitement(1.0)
	var field := FieldBuilder.new()
	add_child(field)
	field.build(ut.primary, ut.secondary, ut.name, lg.championship_name, UI.font("heading"))
	_build_trophy(ut)
	var uni := Lineup.uniform(ut, true)
	var roster := lg.roster_players(ut)
	roster.sort_custom(func(a, b): return a.overall() > b.overall())
	for i in mini(14, roster.size()):
		var p: Player = roster[i]
		var r := PlayerRig.new()
		add_child(r)
		r.build(uni["jersey"], uni["pants"], uni["helmet"], uni["trim"], uni["mask"], p.number, p.skin, p.build, UI.font("heading"))
		var ang := TAU * i / 14.0
		r.position = Vector3(cos(ang) * (4.5 + (i % 2) * 1.6), 0, sin(ang) * (4.5 + (i % 2) * 1.6))
		r.rotation.y = atan2(r.position.x, r.position.z)
		r.set_pose(PlayerRig.Pose.CELEBRATE)
		r.pose_time = randf() * 2.0
		_rigs.append(r)
	_add_confetti(ut)
	_cam = BroadcastCamera.new()
	add_child(_cam)
	_cam.orbit_radius = 16.0
	_cam.orbit_height = 5.0
	_cam.set_mode(BroadcastCamera.Mode.ORBIT, true)
	Audio.music("music_victory", 0.5)
	Audio.crowd_start(1.0)
	Audio.crowd_react("roar", 1.0)
	Audio.play("horn", 0.8)
	_build_ui(lg, ut)

func _build_trophy(ut: Team) -> void:
	_trophy = Node3D.new()
	add_child(_trophy)
	var gold := StandardMaterial3D.new()
	# Partly metallic with a warm emission so the trophy reads as gold even
	# under a dark night sky (which a pure mirror would reflect as black).
	gold.albedo_color = Color("#F4C95D")
	gold.metallic = 0.55
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color("#B8862B")
	gold.emission_energy_multiplier = 0.45
	gold.rim_enabled = true
	gold.rim = 0.6
	var base_m := StandardMaterial3D.new()
	base_m.albedo_color = Palette.NAVY
	base_m.roughness = 0.4
	var podium := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 2.2
	pm.bottom_radius = 2.4
	pm.height = 0.8
	podium.mesh = pm
	var podm := StandardMaterial3D.new()
	podm.albedo_color = ut.primary
	podium.material_override = podm
	podium.position.y = 0.4
	_trophy.add_child(podium)
	var parts := [[0.5, 0.55, 0.35, 1.0, base_m], [0.12, 0.18, 0.9, 1.6, gold], [0.75, 0.25, 0.8, 2.4, gold], [0.82, 0.75, 0.08, 2.84, gold]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = p[0]
		cm.bottom_radius = p[1]
		cm.height = p[2]
		cm.radial_segments = 32
		mi.mesh = cm
		mi.material_override = p[4]
		mi.position.y = p[3]
		_trophy.add_child(mi)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	ball.mesh = sm
	ball.scale = Vector3(0.55, 0.55, 0.9)
	ball.rotation = Vector3(0.5, 0.3, 0)
	ball.material_override = gold
	ball.position.y = 3.3
	_trophy.add_child(ball)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 6, 3)
	light.light_energy = 3.0
	light.omni_range = 14.0
	light.light_color = Color("#FFE7B0")
	_trophy.add_child(light)

func _add_confetti(ut: Team) -> void:
	var p := CPUParticles3D.new()
	p.amount = 500
	p.lifetime = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(16, 0.5, 16)
	p.position = Vector3(0, 12, 0)
	p.direction = Vector3(0, -1, 0)
	p.spread = 30.0
	p.gravity = Vector3(0, -1.6, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.24)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.55, 0.55, 0.55)
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	g.colors = PackedColorArray([ut.primary, ut.secondary, Palette.GOLD, Palette.CREAM])
	p.color_initial_ramp = g
	add_child(p)

func _process(delta: float) -> void:
	_t += delta
	for r in _rigs:
		r.animate(delta)
	if _trophy != null:
		_trophy.rotation.y += delta * 0.4

func _build_ui(lg: League, ut: Team) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.theme = UI.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var v := UI.vbox(4)
	v.set_anchors_preset(Control.PRESET_CENTER_TOP)
	v.custom_minimum_size = Vector2(1400, 0)
	UI.place_at(v, Vector2(-700, 50))
	root.add_child(v)
	var champ: Dictionary = lg.history["champions"].back()
	var t1 := UI.label("%d %s CHAMPIONS" % [int(champ["year"]), lg.championship_name.to_upper()], 46, Palette.GOLD, "heading")
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t2 := UI.label(ut.full_name().to_upper(), 104, Palette.CREAM, "display")
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.add_theme_constant_override("outline_size", 16)
	t2.add_theme_color_override("font_outline_color", Palette.NAVY)
	v.add_child(t1)
	v.add_child(t2)
	var titles: int = lg.history["champions"].filter(func(c): return c["team"] == ut.id).size()
	var mvp: Player = lg.players.get(champ.get("mvp", ""))
	var sub := "Season record %s  ·  Title #%d for Coach %s" % [ut.record_string(), titles, lg.coach_name]
	if mvp != null:
		sub += "  ·  %s MVP: %s" % [lg.championship_name, mvp.full_name()]
	var t3 := UI.label(sub, 26, Palette.CREAM, "sub")
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t3)
	if titles >= 2:
		var dyn := UI.label("DYNASTY STATUS: %d CHAMPIONSHIPS" % titles, 34, Palette.ORANGE, "heading")
		dyn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(dyn)
	var b := UI.button("CONTINUE TO OFFSEASON", func(): App.go_hub("home"), "primary", 420)
	b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	UI.place_at(b, Vector2(-210, -130))
	root.add_child(b)
	b.call_deferred("grab_focus")
	var bg := ColorRect.new()
	bg.color = Color(Palette.NAVY, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bg.offset_bottom = 290
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	root.move_child(bg, 0)
