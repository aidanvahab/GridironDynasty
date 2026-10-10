class_name FieldBuilder
extends Node3D
## Builds the playing surface, markings, yard numbers, goalposts and pylons,
## plus the dynamic broadcast markers (line of scrimmage, first-down line,
## sideline down marker and target ring).

var field_mat: ShaderMaterial
var los_line: MeshInstance3D
var fd_line: MeshInstance3D
var down_marker: Node3D
var down_label: Label3D
var font: Font
var _endzone_labels: Array[Label3D] = []

func build(home_color: Color, away_color: Color, home_name: String, away_name: String, p_font: Font) -> void:
	font = p_font
	_build_surface(home_color, away_color)
	_build_numbers()
	_build_endzone_text(home_name, away_name, home_color, away_color)
	for sx in [-1.0, 1.0]:
		_build_goalpost(sx)
		for sz in [-1.0, 1.0]:
			for gx in [50.0, 60.0]:
				_build_pylon(Vector3(sx * gx, 0, sz * 26.75))
	_build_markers()

func _build_surface(home_color: Color, away_color: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 84)
	plane.subdivide_width = 2
	plane.subdivide_depth = 2
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	field_mat = ShaderMaterial.new()
	field_mat.shader = load("res://assets/shaders/field.gdshader")
	field_mat.set_shader_parameter("endzone_a", home_color.darkened(0.15))
	field_mat.set_shader_parameter("endzone_b", away_color.darkened(0.15))
	mi.material_override = field_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "FieldSurface"
	add_child(mi)

func _flat_label(text: String, pos: Vector3, yaw: float, size: float, color: Color, outline: Color = Color(0, 0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if font != null:
		l.font = font
	l.font_size = 128
	l.pixel_size = size / 128.0
	l.modulate = color
	l.outline_size = 0 if outline.a == 0.0 else 12
	l.outline_modulate = outline
	l.position = pos
	l.rotation = Vector3(-PI / 2, yaw, 0)
	l.shaded = true
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	add_child(l)
	return l

func _build_numbers() -> void:
	var white := Color(0.97, 0.96, 0.93)
	for k in range(1, 10):
		var x := -50.0 + k * 10.0
		var num := k * 10 if k <= 5 else (10 - k) * 10
		for sz in [-1.0, 1.0]:
			# Numbers read upright from their own sideline.
			var yaw := 0.0 if sz > 0.0 else PI
			_flat_label(str(num), Vector3(x, 0.02, sz * 17.5), yaw, 2.4, white)
			if num != 50:
				_arrow(Vector3(x + (-1.0 if x < 0.0 else 1.0) * 2.0, 0.02, sz * 18.3), -1.0 if x < 0.0 else 1.0)

## Small painted triangle pointing toward the nearest goal line.
func _arrow(p: Vector3, point_x: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var tip := Vector3(point_x * 0.45, 0, 0)
	var b1 := Vector3(-point_x * 0.25, 0, -0.32)
	var b2 := Vector3(-point_x * 0.25, 0, 0.32)
	if point_x > 0.0:
		st.add_vertex(tip); st.add_vertex(b1); st.add_vertex(b2)
	else:
		st.add_vertex(tip); st.add_vertex(b2); st.add_vertex(b1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.96, 0.93)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_endzone_text(home_name: String, away_name: String, hc: Color, ac: Color) -> void:
	for side in [[-55.0, home_name, hc], [55.0, away_name, ac]]:
		var x: float = side[0]
		var c: Color = side[2]
		var txt := String(side[1]).to_upper()
		# Letters read upright from the field of play (tops toward the end line).
		var yaw := PI / 2 if x < 0.0 else -PI / 2
		var l := _flat_label(txt, Vector3(x, 0.02, 0), yaw, 5.2, Color(0.97, 0.96, 0.93, 0.95), c.darkened(0.5))
		_endzone_labels.append(l)

func set_midfield_logo(tex: Texture2D) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(9, 9)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.material_override = m
	mi.rotation = Vector3(-PI / 2, 0, 0)
	mi.position = Vector3(0, 0.015, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_goalpost(sx: float) -> void:
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color("#F4C95D")
	yellow.roughness = 0.35
	yellow.metallic = 0.3
	var root := Node3D.new()
	root.name = "Goalpost"
	root.position = Vector3(sx * 60.0, 0, 0)
	add_child(root)
	var x_back := sx * 1.6 ## base pole sits behind the end line
	var cb := FieldCoords.CROSSBAR_HEIGHT
	_cyl(root, Vector3(x_back, cb * 0.5, 0), 0.12, cb, yellow) # base pole
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color("#1A2C45")
	_cyl(root, Vector3(x_back, 1.0, 0), 0.22, 2.0, pad)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(1.6, 0.16, 0.16)
	arm.mesh = am
	arm.material_override = yellow
	arm.position = Vector3(x_back * 0.5, cb, 0)
	root.add_child(arm)
	var bar := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.07
	bm.bottom_radius = 0.07
	bm.height = FieldCoords.GOAL_POST_WIDTH
	bar.mesh = bm
	bar.material_override = yellow
	bar.rotation = Vector3(PI / 2, 0, 0)
	bar.position = Vector3(0, cb, 0)
	root.add_child(bar)
	for sz in [-1.0, 1.0]:
		var h := FieldCoords.UPRIGHT_HEIGHT - cb
		_cyl(root, Vector3(0, cb + h * 0.5, sz * FieldCoords.GOAL_POST_WIDTH * 0.5), 0.06, h, yellow)
		var ribbon := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.05, 1.2, 0.18)
		ribbon.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color("#F28C38")
		ribbon.material_override = rmat
		ribbon.position = Vector3(0, FieldCoords.UPRIGHT_HEIGHT - 0.4, sz * FieldCoords.GOAL_POST_WIDTH * 0.5)
		root.add_child(ribbon)

func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_pylon(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.13, 0.5, 0.13)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#F28C38")
	m.emission_enabled = true
	m.emission = Color("#F28C38")
	m.emission_energy_multiplier = 0.15
	mi.material_override = m
	mi.position = p + Vector3(0, 0.25, 0)
	add_child(mi)

func _build_markers() -> void:
	los_line = _line_mesh(Color(0.25, 0.55, 1.0, 0.85), 0.2)
	fd_line = _line_mesh(Color(1.0, 0.86, 0.2, 0.9), 0.24)
	down_marker = Node3D.new()
	add_child(down_marker)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.04
	pm.height = 2.6
	pole.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color("#101B2B")
	pole.material_override = pmat
	pole.position = Vector3(0, 1.3, 0)
	down_marker.add_child(pole)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.6, 0.08)
	board.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("#F28C38")
	bmat.emission_enabled = true
	bmat.emission = Color("#F28C38")
	bmat.emission_energy_multiplier = 0.3
	board.material_override = bmat
	board.position = Vector3(0, 2.75, 0)
	down_marker.add_child(board)
	down_label = Label3D.new()
	down_label.text = "1"
	if font != null:
		down_label.font = font
	down_label.font_size = 96
	down_label.pixel_size = 0.005
	down_label.modulate = Color("#101B2B")
	down_label.position = Vector3(0, 2.75, -0.05)
	down_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	down_marker.add_child(down_label)

func _line_mesh(c: Color, width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.01, FieldCoords.FIELD_WIDTH)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 0.4
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.02
	add_child(mi)
	return mi

## Places the broadcast lines for the current down.
func show_down_markers(ball_on: float, first_down_line: float, dir: int, down: int, show_fd: bool) -> void:
	los_line.visible = true
	los_line.position.x = FieldCoords.world_x(ball_on, dir)
	fd_line.visible = show_fd and first_down_line < 100.0
	fd_line.position.x = FieldCoords.world_x(first_down_line, dir)
	down_marker.visible = true
	down_marker.position = Vector3(FieldCoords.world_x(ball_on, dir), 0, -(FieldCoords.HALF_WIDTH + 2.2))
	down_label.text = str(down)

func hide_down_markers() -> void:
	los_line.visible = false
	fd_line.visible = false
	down_marker.visible = false
