class_name StadiumBuilder
extends Node3D
## Procedural stadium generated from data/stadiums.json: stepped seating tiers,
## instanced animated crowd, facades, light towers or roof canopy, benches,
## tunnels, video boards and time-of-day lighting.

var style: Dictionary = {}
var style_id: String = "classic"
var home_color: Color
var home_alt: Color
var away_color: Color
var crowd_mat: ShaderMaterial
var crowd_count: int = 0
var scoreboard_viewport: SubViewport
var env: WorldEnvironment
var sun: DirectionalLight3D
var tower_lights: Array[Light3D] = []
var rng := RandomNumberGenerator.new()
var _excitement: float = 0.25
var _excitement_target: float = 0.25
var density: float = 1.0

static func styles() -> Dictionary:
	var f := FileAccess.open("res://data/stadiums.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func build(p_style_id: String, p_home: Color, p_home_alt: Color, p_away: Color, time_of_day: String, p_density: float, seed_value: int = 1) -> void:
	style_id = p_style_id
	var all := styles()
	style = all.get(style_id, all["classic"])
	home_color = p_home
	home_alt = p_home_alt
	away_color = p_away
	density = p_density
	rng.seed = seed_value
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = load("res://assets/shaders/crowd.gdshader")
	_build_ground()
	var setback: float = style["setback"]
	var side_len := 2.0 * (60.0 + setback + _tiers_depth(style["end_tiers"])) + 4.0
	var crowd_xforms: Array = []
	var crowd_colors: Array = []
	# Long sides (z+ and z-).
	for sz in [-1.0, 1.0]:
		_build_stand(Vector3(0, 0, sz * (FieldCoords.HALF_WIDTH + setback)), Vector3(0, 0, sz), side_len, style["tiers"], crowd_xforms, crowd_colors, sz < 0.0)
	# End zones.
	for sx in [-1.0, 1.0]:
		if style.get("open_end", false) and sx > 0.0:
			_build_trees(sx)
			continue
		_build_stand(Vector3(sx * (60.0 + setback), 0, 0), Vector3(sx, 0, 0), 2.0 * (FieldCoords.HALF_WIDTH + setback) - 1.0, style["end_tiers"], crowd_xforms, crowd_colors, false)
	_build_crowd(crowd_xforms, crowd_colors)
	_build_sidelines()
	_build_scoreboards()
	if style.get("light_towers", false):
		_build_light_towers()
	if style.get("roof", false):
		_build_roof(side_len)
	setup_lighting(time_of_day)

func _tiers_depth(tiers: Array) -> float:
	var d := 0.0
	for t in tiers:
		d += float(t["rows"]) * float(t["depth"]) + float(t.get("gap", 0.0))
	return d

func _vc_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.88
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	## a-b-c-d counter-clockwise when viewed from the front.
	var n := (b - a).cross(c - a).normalized()
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

## Builds one grandstand. `origin` is the front-center of the lowest row,
## `outward` points away from the field, `length` runs perpendicular.
func _build_stand(origin: Vector3, outward: Vector3, length: float, tiers: Array, xforms: Array, colors: Array, has_tunnel: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := Vector3.UP.cross(outward).normalized()
	var half := length * 0.5
	var concrete := Color(style["concrete"])
	var facade := Color(style["facade"])
	var seat_a := home_color.darkened(0.15)
	var seat_b := home_alt.darkened(0.2) if style["seat_mix"] < 0.5 else home_color.darkened(0.35)
	var dist := 0.0
	var y := 1.2
	# Front padded wall.
	var wall_top := y
	_quad(st, origin + along * -half, origin + along * half, origin + along * half + Vector3(0, wall_top, 0), origin + along * -half + Vector3(0, wall_top, 0), home_color.darkened(0.45))
	var tier_index := 0
	for tier in tiers:
		var gap: float = tier.get("gap", 0.0)
		if gap > 0.0:
			# Facade band between tiers (suites / concourse).
			var f0 := origin + outward * dist
			var band_h := gap * 0.8
			_quad(st, f0 + along * -half + Vector3(0, y, 0), f0 + along * half + Vector3(0, y, 0), f0 + along * half + Vector3(0, y + band_h, 0), f0 + along * -half + Vector3(0, y + band_h, 0), facade)
			_quad(st, f0 + along * half + Vector3(0, y + band_h, 0), f0 + along * -half + Vector3(0, y + band_h, 0), f0 + outward * gap * 0.6 + along * -half + Vector3(0, y + band_h, 0), f0 + outward * gap * 0.6 + along * half + Vector3(0, y + band_h, 0), concrete.darkened(0.2))
			if style.get("ribbon", false):
				_add_ribbon(f0 + Vector3(0, y + band_h * 0.5, 0) - outward * 0.05, along, length, band_h * 0.35)
			dist += gap * 0.6
			y += band_h
		var rows: int = tier["rows"]
		var depth: float = tier["depth"]
		var rise: float = tier["rise"]
		for r in rows:
			var p0 := origin + outward * dist + Vector3(0, y, 0)
			# Riser.
			_quad(st, p0 + along * -half, p0 + along * half, p0 + along * half + Vector3(0, rise, 0), p0 + along * -half + Vector3(0, rise, 0), concrete.darkened(0.25))
			y += rise
			var t0 := origin + outward * dist + Vector3(0, y, 0)
			var t1 := t0 + outward * depth
			# Tread split into sections with aisles.
			var sec_len := 11.0
			var x := -half
			var sec_i := 0
			while x < half:
				var x_end := minf(x + sec_len, half)
				var seat_col := seat_a if (sec_i + tier_index) % 2 == 0 else seat_b
				_quad(st, t0 + along * x, t1 + along * x, t1 + along * x_end, t0 + along * x_end, seat_col)
				# Spectators.
				var sx := x + 0.6
				while sx < x_end - 0.9:
					if rng.randf() < 0.9 * density:
						var pos := t0 + along * (sx + rng.randf_range(-0.08, 0.08)) + outward * (depth * 0.45)
						var basis := Basis.looking_at(-outward, Vector3.UP)
						basis = basis.scaled(Vector3.ONE * rng.randf_range(0.92, 1.08))
						xforms.append(Transform3D(basis, pos))
						colors.append(_fan_color())
					sx += 0.78
				var aisle_end := minf(x_end + 1.2, half)
				if aisle_end > x_end:
					_quad(st, t0 + along * x_end, t1 + along * x_end, t1 + along * aisle_end, t0 + along * aisle_end, concrete.lightened(0.1))
				x = aisle_end
				sec_i += 1
			dist += depth
		tier_index += 1
	# Back wall / facade.
	var back := origin + outward * dist
	var top_h := y + 3.0
	_quad(st, back + along * half + Vector3(0, 0, 0), back + along * -half, back + along * -half + Vector3(0, top_h, 0), back + along * half + Vector3(0, top_h, 0), facade.darkened(0.2))
	_quad(st, back + along * -half + Vector3(0, y, 0), back + along * half + Vector3(0, y, 0), back + along * half + Vector3(0, top_h, 0), back + along * -half + Vector3(0, top_h, 0), facade)
	# Side caps.
	for sgn in [-1.0, 1.0]:
		var e0: Vector3 = origin + along * sgn * half
		var e1: Vector3 = back + along * sgn * half
		if sgn < 0.0:
			_quad(st, e0, e1, e1 + Vector3(0, top_h, 0), e0 + Vector3(0, wall_top, 0), facade.darkened(0.3))
		else:
			_quad(st, e1, e0, e0 + Vector3(0, wall_top, 0), e1 + Vector3(0, top_h, 0), facade.darkened(0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vc_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	if style.get("brick", false):
		_add_pillars(back, along, outward, length, top_h)
	if has_tunnel:
		_build_tunnel(origin, outward)

func _fan_color() -> Color:
	var r := rng.randf()
	var c: Color
	if r < 0.42:
		c = home_color
	elif r < 0.62:
		c = home_alt
	elif r < 0.76:
		c = away_color
	else:
		c = [Color("#F5F0E5"), Color("#2B2F36"), Color("#5A6B82"), Color("#B9A27A"), Color("#7A4A4A")][rng.randi_range(0, 4)]
	return c.darkened(rng.randf_range(0.0, 0.25))

func _spectator_mesh() -> Mesh:
	## Low-poly seated fan facing -Z. Arms at |x| > 0.21, head above y 0.62.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 0.32, 0), Vector3(0.38, 0.44, 0.24))
	_box(st, Vector3(0, 0.74, -0.01), Vector3(0.2, 0.22, 0.2))
	_box(st, Vector3(-0.26, 0.38, -0.02), Vector3(0.09, 0.36, 0.1))
	_box(st, Vector3(0.26, 0.38, -0.02), Vector3(0.09, 0.36, 0.1))
	_box(st, Vector3(0, 0.08, -0.16), Vector3(0.34, 0.14, 0.3))
	st.generate_normals()
	return st.commit()

func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var v := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f in faces:
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[1]]); st.add_vertex(v[f[2]])
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[2]]); st.add_vertex(v[f[3]])

func _build_crowd(xforms: Array, colors: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _spectator_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = crowd_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "Crowd"
	add_child(mmi)
	crowd_count = xforms.size()

func _add_ribbon(center: Vector3, along: Vector3, length: float, h: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length * 0.96, h, 0.08)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = home_color
	m.emission_enabled = true
	m.emission = home_color.lightened(0.2)
	m.emission_energy_multiplier = 1.4
	mi.material_override = m
	mi.position = center
	mi.basis = Basis(along, Vector3.UP, along.cross(Vector3.UP))
	add_child(mi)

func _add_pillars(back: Vector3, along: Vector3, outward: Vector3, length: float, h: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(style["facade"]).darkened(0.25)
	m.roughness = 0.95
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, h + 2.0, 1.0)
	var n := int(length / 9.0)
	for i in n + 1:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = m
		mi.position = back + along * (-length * 0.5 + i * length / n) + outward * 0.4 + Vector3(0, (h + 2.0) * 0.5, 0)
		mi.basis = Basis(along, Vector3.UP, along.cross(Vector3.UP))
		add_child(mi)

func _build_tunnel(origin: Vector3, outward: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#0A0F17")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.0, 3.0, 0.3)
	mi.mesh = bm
	mi.material_override = m
	mi.position = origin + Vector3(-22.0, 1.5, 0) - outward * 0.05
	add_child(mi)
	var arch := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(7.0, 0.6, 0.5)
	arch.mesh = am
	var am2 := StandardMaterial3D.new()
	am2.albedo_color = home_color
	am2.emission_enabled = true
	am2.emission = home_color
	am2.emission_energy_multiplier = 0.5
	arch.material_override = am2
	arch.position = origin + Vector3(-22.0, 3.2, 0) - outward * 0.3
	add_child(arch)

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#1E2A1F")
	m.roughness = 1.0
	mi.material_override = m
	mi.position.y = -0.05
	add_child(mi)

func _build_sidelines() -> void:
	for sz in [-1.0, 1.0]:
		var team_c := home_color if sz < 0.0 else away_color
		var bench_m := StandardMaterial3D.new()
		bench_m.albedo_color = team_c.darkened(0.2)
		bench_m.roughness = 0.6
		for i in 4:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(7.0, 0.5, 0.7)
			b.mesh = bm
			b.material_override = bench_m
			b.position = Vector3(-15.0 + i * 8.0, 0.25, sz * (FieldCoords.HALF_WIDTH + 5.5))
			add_child(b)
			var back := MeshInstance3D.new()
			var backm := BoxMesh.new()
			backm.size = Vector3(7.0, 0.5, 0.15)
			back.mesh = backm
			back.material_override = bench_m
			back.position = b.position + Vector3(0, 0.45, sz * 0.35)
			add_child(back)
		# Coolers and equipment.
		var cooler_m := StandardMaterial3D.new()
		cooler_m.albedo_color = Color("#F28C38")
		for i in 3:
			var c := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.3
			cm.bottom_radius = 0.3
			cm.height = 0.7
			c.mesh = cm
			c.material_override = cooler_m
			c.position = Vector3(18.0 + i * 0.8, 0.35, sz * (FieldCoords.HALF_WIDTH + 5.0))
			add_child(c)
		# Sideline wall/advert boards.
		var board := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(110.0, 0.9, 0.2)
		board.mesh = bbm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color("#1A2C45")
		bmat.emission_enabled = true
		bmat.emission = Color("#1A2C45").lerp(home_color, 0.35)
		bmat.emission_energy_multiplier = 0.35
		board.material_override = bmat
		board.position = Vector3(0, 0.45, sz * (FieldCoords.HALF_WIDTH + float(style["setback"]) - 0.2))
		add_child(board)

func _build_scoreboards() -> void:
	scoreboard_viewport = SubViewport.new()
	scoreboard_viewport.size = Vector2i(768, 288)
	scoreboard_viewport.transparent_bg = false
	scoreboard_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(scoreboard_viewport)
	var boards: int = style.get("boards", 1)
	var setback: float = style["setback"]
	var depth := _tiers_depth(style["end_tiers"])
	for i in boards:
		var sx := -1.0 if i == 0 else 1.0
		var root := Node3D.new()
		var x := sx * (60.0 + setback + depth * 0.55)
		if style.get("open_end", false) and sx > 0.0:
			x = sx * (70.0 + setback)
		root.position = Vector3(x, 26.0 if style_id == "modern" else 20.0, 0)
		root.rotation.y = -PI / 2 * sx
		add_child(root)
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(30.0, 12.0, 1.0)
		frame.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color("#101B2B")
		frame.material_override = fmat
		root.add_child(frame)
		var screen := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(28.0, 10.5)
		screen.mesh = q
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = scoreboard_viewport.get_texture()
		sm.emission_enabled = true
		sm.emission_texture = scoreboard_viewport.get_texture()
		sm.emission_energy_multiplier = 1.1
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		screen.material_override = sm
		screen.position = Vector3(0, 0, 0.51)
		root.add_child(screen)
		if style_id != "modern":
			for px in [-10.0, 10.0]:
				var leg := MeshInstance3D.new()
				var lm := CylinderMesh.new()
				lm.top_radius = 0.5
				lm.bottom_radius = 0.5
				lm.height = root.position.y
				leg.mesh = lm
				leg.material_override = fmat
				leg.position = Vector3(px, -root.position.y * 0.5 - 6.0, -0.6)
				root.add_child(leg)

func _build_light_towers() -> void:
	var setback: float = style["setback"]
	var pole_m := StandardMaterial3D.new()
	pole_m.albedo_color = Color("#5C6470")
	pole_m.metallic = 0.5
	pole_m.roughness = 0.5
	var lamp_m := StandardMaterial3D.new()
	lamp_m.albedo_color = Color("#FFF6DD")
	lamp_m.emission_enabled = true
	lamp_m.emission = Color("#FFF6DD")
	lamp_m.emission_energy_multiplier = 2.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base := Vector3(sx * (60.0 + setback + 18.0), 0, sz * (FieldCoords.HALF_WIDTH + setback + 22.0))
			var h := 52.0
			var pole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.9
			cm.height = h
			pole.mesh = cm
			pole.material_override = pole_m
			pole.position = base + Vector3(0, h * 0.5, 0)
			add_child(pole)
			var bank := Node3D.new()
			bank.position = base + Vector3(0, h + 2.5, 0)
			add_child(bank)
			bank.look_at(Vector3(0, 0, 0), Vector3.UP)
			var frame := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(9.0, 5.0, 0.6)
			frame.mesh = fm
			frame.material_override = pole_m
			bank.add_child(frame)
			var lamps := MeshInstance3D.new()
			var lmesh := BoxMesh.new()
			lmesh.size = Vector3(8.4, 4.4, 0.2)
			lamps.mesh = lmesh
			lamps.material_override = lamp_m
			lamps.position = Vector3(0, 0, -0.35)
			bank.add_child(lamps)
			var spot := SpotLight3D.new()
			spot.spot_range = 190.0
			spot.spot_angle = 32.0
			spot.light_energy = 0.0
			spot.light_color = Color("#FFF3D6")
			spot.shadow_enabled = false
			bank.add_child(spot)
			tower_lights.append(spot)

func _build_roof(side_len: float) -> void:
	var setback: float = style["setback"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.9, 0.95, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	m.metallic = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var depth := _tiers_depth(style["tiers"])
	for sz in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(side_len, 0.3, depth * 0.75)
		mi.mesh = bm
		mi.material_override = m
		mi.position = Vector3(0, 46.0, sz * (FieldCoords.HALF_WIDTH + setback + depth * 0.62))
		mi.rotation.x = sz * 0.12
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Truss ring.
		var truss := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(side_len, 1.2, 1.2)
		truss.mesh = tm
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color("#C8CED6")
		tmat.metallic = 0.6
		truss.material_override = tmat
		truss.position = Vector3(0, 45.5, sz * (FieldCoords.HALF_WIDTH + setback + depth * 0.27))
		add_child(truss)
		# Downlights along the truss.
		for i in 3:
			var l := SpotLight3D.new()
			l.position = Vector3(-40.0 + i * 40.0, 44.5, sz * (FieldCoords.HALF_WIDTH + setback + depth * 0.27))
			l.rotation = Vector3(-PI / 2 + sz * -0.55, 0, 0)
			l.spot_range = 90.0
			l.spot_angle = 45.0
			l.light_energy = 0.0
			add_child(l)
			tower_lights.append(l)

func _build_trees(sx: float) -> void:
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color("#2E5A35")
	leaf.roughness = 0.95
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = Color("#4A3628")
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 3.5
	cone.height = 11.0
	cone.radial_segments = 8
	var tm := CylinderMesh.new()
	tm.top_radius = 0.4
	tm.bottom_radius = 0.5
	tm.height = 3.0
	for i in 26:
		var p := Vector3(sx * rng.randf_range(78.0, 110.0), 0, rng.randf_range(-60.0, 60.0))
		var t := MeshInstance3D.new()
		t.mesh = tm
		t.material_override = trunk
		t.position = p + Vector3(0, 1.5, 0)
		add_child(t)
		var c := MeshInstance3D.new()
		c.mesh = cone
		c.material_override = leaf
		var s := rng.randf_range(0.8, 1.4)
		c.scale = Vector3(s, s, s)
		c.position = p + Vector3(0, 3.0 + 5.5 * s, 0)
		add_child(c)
	# A low brick wall closing the open end.
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.0, 2.5, 70.0)
	wall.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(style["facade"])
	wall.material_override = wmat
	wall.position = Vector3(sx * 70.0, 1.25, 0)
	add_child(wall)

# ---------------------------------------------------------------- lighting

func setup_lighting(time_of_day: String) -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	var tower_energy := 0.0
	match time_of_day:
		"night":
			sm.sky_top_color = Color("#0A1020")
			sm.sky_horizon_color = Color("#1A2C45")
			sm.ground_horizon_color = Color("#101B2B")
			sm.ground_bottom_color = Color("#05080F")
			sm.sun_angle_max = 0.0
			sun.light_color = Color("#AFC6FF")
			sun.light_energy = 0.35
			sun.rotation_degrees = Vector3(-62, 35, 0)
			e.ambient_light_energy = 0.35
			tower_energy = 5.0
		"evening":
			sm.sky_top_color = Color("#2C4A7A")
			sm.sky_horizon_color = Color("#F2A65A")
			sm.ground_horizon_color = Color("#8A5A3A")
			sm.ground_bottom_color = Color("#1A140F")
			sun.light_color = Color("#FFC58A")
			sun.light_energy = 1.0
			sun.rotation_degrees = Vector3(-22, -60, 0)
			e.ambient_light_energy = 0.55
			tower_energy = 2.5
		_:
			sm.sky_top_color = Color("#3D7CC9")
			sm.sky_horizon_color = Color("#BFD9F2")
			sm.ground_horizon_color = Color("#7D8F7A")
			sm.ground_bottom_color = Color("#2A3328")
			sun.light_color = Color("#FFF4E0")
			sun.light_energy = 1.35
			sun.rotation_degrees = Vector3(-50, -35, 0)
			e.ambient_light_energy = 0.6
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.1
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.fog_enabled = true
	e.fog_light_color = sm.sky_horizon_color.darkened(0.2)
	e.fog_density = 0.0016 if time_of_day == "day" else 0.0024
	e.fog_sky_affect = 0.2
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.05
	env.environment = e
	add_child(env)
	add_child(sun)
	for l in tower_lights:
		l.light_energy = tower_energy

func apply_quality(level: int) -> void:
	## 0 low, 1 medium, 2 high
	if env == null:
		return
	var e := env.environment
	e.ssao_enabled = level >= 1
	e.glow_enabled = level >= 1
	sun.shadow_enabled = level >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL

# ---------------------------------------------------------------- crowd

func set_excitement(v: float) -> void:
	_excitement_target = clampf(v, 0.0, 1.0)

func pulse(v: float) -> void:
	_excitement = maxf(_excitement, clampf(v, 0.0, 1.0))

func _process(delta: float) -> void:
	_excitement = lerpf(_excitement, _excitement_target, 1.0 - exp(-delta * 0.8))
	if crowd_mat != null:
		crowd_mat.set_shader_parameter("excitement", _excitement)

func excitement() -> float:
	return _excitement
