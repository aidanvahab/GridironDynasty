class_name PlayerRig
extends Node3D
## Procedural stylized football player ("Modern Retro Sports").
## Built from rounded primitives with a joint hierarchy animated procedurally.
## Faces -Z (Godot convention). Root sits at the feet. ~2 yards tall.

enum Pose { IDLE, STANCE3, STANCE2, QB_SET, RUN, THROW, CATCH, BLOCK, DIVE, DOWN, CELEBRATE, KICK, SNAP, HANDOFF, PUSH }

const SKIN_TONES := [Color("#F2C9A0"), Color("#E0A87A"), Color("#C68A5A"), Color("#9C6440"), Color("#6E4428"), Color("#4A2C1A")]

const LIMBS := {"shoulder_l": true, "shoulder_r": true, "elbow_l": true, "elbow_r": true, "hip_l": true, "hip_r": true, "knee_l": true, "knee_r": true, "ankle_l": true, "ankle_r": true}

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

var pose: Pose = Pose.IDLE
var speed: float = 0.0 ## current ground speed (yd/s) drives the run cycle
var lean: float = 0.0 ## forward lean from acceleration
var carrying: bool = false
var pose_time: float = 0.0
var run_phase: float = 0.0
var fall_side: float = 1.0

var j: Dictionary = {} ## joint name -> Node3D
var _ang: Dictionary = {} ## joint -> current Vector3 (euler, radians)
var hips_height: float = 1.0
var hand_r: Node3D
var hand_l: Node3D
var body_root: Node3D
var _labels: Array[Label3D] = []

func build(jersey: Color, pants: Color, helmet: Color, trim: Color, mask: Color, number: int, skin_idx: int, build_scale: float, font: Font = null) -> void:
	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	var height_s := 0.88 * clampf(0.97 + (build_scale - 1.0) * 0.25, 0.94, 1.04)
	body_root.scale = Vector3(height_s * clampf(build_scale, 0.9, 1.3), height_s, height_s * clampf(0.9 + build_scale * 0.1, 0.95, 1.15))
	var skin: Color = SKIN_TONES[clampi(skin_idx, 0, SKIN_TONES.size() - 1)]
	var m_jersey := _mat(jersey, 0.75, 0.0)
	var m_pants := _mat(pants, 0.7, 0.0)
	var m_helmet := _mat(helmet, 0.22, 0.25, true)
	var m_trim := _mat(trim, 0.6, 0.0)
	var m_mask := _mat(mask, 0.35, 0.5)
	var m_skin := _mat(skin, 0.8, 0.0)
	var m_dark := _mat(Color("#14161A"), 0.6, 0.0)
	var m_sock := _mat(jersey.lerp(Color.WHITE, 0.1), 0.8, 0.0)

	var hips := _joint("hips", body_root, Vector3(0, hips_height, 0))
	_part(hips, _sphere(0.5), m_pants, Vector3(0, 0, 0), Vector3(0.44, 0.26, 0.3))
	var spine := _joint("spine", hips, Vector3(0, 0.08, 0))
	_part(spine, _capsule(0.5, 1.0), m_jersey, Vector3(0, 0.36, 0), Vector3(0.56, 0.72, 0.4))
	_part(spine, _sphere(0.5), m_jersey, Vector3(0, 0.66, 0), Vector3(0.98, 0.34, 0.56)) # shoulder pads
	_part(spine, _sphere(0.5), m_trim, Vector3(0, 0.7, 0), Vector3(0.9, 0.3, 0.5)) # pad trim
	_part(spine, _sphere(0.5), m_jersey, Vector3(0, 0.71, 0), Vector3(0.96, 0.3, 0.54))
	var neck := _joint("neck", spine, Vector3(0, 0.78, 0))
	_part(neck, _cylinder(), m_skin, Vector3(0, 0.05, 0), Vector3(0.15, 0.14, 0.15))
	var head := _joint("head", neck, Vector3(0, 0.12, 0))
	_part(head, _sphere(0.5), m_helmet, Vector3(0, 0.12, 0.01), Vector3(0.42, 0.42, 0.47))
	_part(head, _sphere(0.5), m_trim, Vector3(0, 0.125, 0.02), Vector3(0.08, 0.43, 0.48)) # center stripe
	_part(head, _sphere(0.5), m_skin, Vector3(0, 0.08, -0.12), Vector3(0.24, 0.26, 0.2)) # face
	for i in 3:
		_part(head, _cylinder(), m_mask, Vector3(0, 0.0 + i * 0.075, -0.235), Vector3(0.03, 0.34, 0.03), Vector3(0, 0, PI / 2))
	_part(head, _cylinder(), m_mask, Vector3(0, 0.06, -0.24), Vector3(0.026, 0.18, 0.026))
	for sx in [-1.0, 1.0]:
		_part(head, _sphere(0.5), m_helmet, Vector3(sx * 0.2, 0.08, 0.0), Vector3(0.08, 0.16, 0.16)) # ear holes area
	for side in [["l", -1.0], ["r", 1.0]]:
		var s: String = side[0]
		var sx: float = side[1]
		var sh := _joint("shoulder_" + s, spine, Vector3(sx * 0.4, 0.6, 0))
		_part(sh, _capsule(0.5, 1.0), m_jersey, Vector3(0, -0.1, 0), Vector3(0.21, 0.26, 0.21))
		_part(sh, _capsule(0.5, 1.0), m_skin, Vector3(0, -0.22, 0), Vector3(0.16, 0.28, 0.16))
		var el := _joint("elbow_" + s, sh, Vector3(0, -0.34, 0))
		_part(el, _capsule(0.5, 1.0), m_skin, Vector3(0, -0.15, 0), Vector3(0.15, 0.32, 0.15))
		var hand := _joint("hand_" + s, el, Vector3(0, -0.32, 0))
		_part(hand, _sphere(0.5), m_dark, Vector3.ZERO, Vector3(0.16, 0.16, 0.16))
		if s == "r":
			hand_r = hand
		else:
			hand_l = hand
		var hip := _joint("hip_" + s, hips, Vector3(sx * 0.13, -0.06, 0))
		_part(hip, _capsule(0.5, 1.0), m_pants, Vector3(0, -0.22, 0), Vector3(0.25, 0.52, 0.27))
		var knee := _joint("knee_" + s, hip, Vector3(0, -0.46, 0))
		_part(knee, _capsule(0.5, 1.0), m_sock, Vector3(0, -0.2, 0), Vector3(0.18, 0.46, 0.19))
		_part(knee, _box(), m_trim, Vector3(0, -0.12, 0), Vector3(0.185, 0.04, 0.195))
		var ankle := _joint("ankle_" + s, knee, Vector3(0, -0.45, 0))
		_part(ankle, _box(), m_dark, Vector3(0, -0.02, -0.06), Vector3(0.14, 0.09, 0.3))
	# Jersey numbers (front and back).
	for zs in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.text = str(number)
		lbl.pixel_size = 0.0042
		lbl.font_size = 64
		if font != null:
			lbl.font = font
		lbl.modulate = trim
		lbl.outline_modulate = jersey.darkened(0.5)
		lbl.outline_size = 8
		lbl.position = Vector3(0, 0.4, zs * 0.205)
		lbl.rotation = Vector3(0, 0.0 if zs > 0 else PI, 0)
		lbl.double_sided = false
		lbl.shaded = true
		lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		spine.add_child(lbl)
		_labels.append(lbl)
	for k in j:
		_ang[k] = Vector3.ZERO

# ---------------------------------------------------------------- building

func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	j[n] = node
	return node

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if mesh == _mesh_cache.get("capsule"):
		scl = Vector3(scl.x / 0.7, scl.y, scl.z / 0.7)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _sphere(r: float) -> Mesh:
	if not _mesh_cache.has("sphere"):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 16
		m.rings = 10
		_mesh_cache["sphere"] = m
	return _mesh_cache["sphere"]

static func _capsule(r: float, h: float) -> Mesh:
	## Unit capsule: 0.7 wide, 1.0 long. _part() compensates the width so part
	## scales read as real (width, length, depth) sizes.
	if not _mesh_cache.has("capsule"):
		var m := CapsuleMesh.new()
		m.radius = 0.35
		m.height = 1.0
		m.radial_segments = 14
		m.rings = 6
		_mesh_cache["capsule"] = m
	return _mesh_cache["capsule"]

static func _cylinder() -> Mesh:
	if not _mesh_cache.has("cyl"):
		var m := CylinderMesh.new()
		m.top_radius = 0.5
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = 10
		m.rings = 1
		_mesh_cache["cyl"] = m
	return _mesh_cache["cyl"]

static func _box() -> Mesh:
	if not _mesh_cache.has("box"):
		_mesh_cache["box"] = BoxMesh.new()
	return _mesh_cache["box"]

static func _mat(c: Color, rough: float, metal: float, clearcoat: bool = false) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%s" % [c.to_html(), rough, metal, clearcoat]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if clearcoat:
		m.clearcoat_enabled = true
		m.clearcoat = 0.6
		m.clearcoat_roughness = 0.2
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.4
	_mat_cache[key] = m
	return m

# ---------------------------------------------------------------- animation

func set_pose(p: Pose) -> void:
	if p != pose:
		pose = p
		pose_time = 0.0

func hand_position() -> Vector3:
	return hand_r.global_position if hand_r != null else global_position + Vector3(0, 1.2, 0)

## Ball carry point: tucked against the chest on the right side.
func carry_position() -> Vector3:
	var b := global_transform.basis
	return global_position + Vector3(0, 1.25 * body_root.scale.y, 0) + b * Vector3(0.22, 0, -0.18)

func animate(dt: float) -> void:
	pose_time += dt
	var t := {} ## joint -> target euler
	var hip_y := hips_height
	var body_pitch := 0.0
	var body_roll := 0.0
	var body_y := 0.0
	match pose:
		Pose.IDLE:
			var br := sin(pose_time * 2.0) * 0.03
			t["spine"] = Vector3(0.05 + br, 0, 0)
			t["shoulder_l"] = Vector3(0.1, 0, -0.18)
			t["shoulder_r"] = Vector3(0.1, 0, 0.18)
			t["elbow_l"] = Vector3(-0.3, 0, 0)
			t["elbow_r"] = Vector3(-0.3, 0, 0)
			t["hip_l"] = Vector3(0, 0, -0.06)
			t["hip_r"] = Vector3(0, 0, 0.06)
		Pose.STANCE3:
			hip_y = 0.72
			t["spine"] = Vector3(-1.15, 0, 0)
			t["neck"] = Vector3(0.9, 0, 0)
			t["shoulder_r"] = Vector3(-1.9, 0, 0.1)
			t["elbow_r"] = Vector3(0.1, 0, 0)
			t["shoulder_l"] = Vector3(-0.6, 0, -0.3)
			t["elbow_l"] = Vector3(-1.1, 0, 0)
			t["hip_l"] = Vector3(-1.2, 0, -0.25)
			t["hip_r"] = Vector3(-0.9, 0, 0.25)
			t["knee_l"] = Vector3(1.7, 0, 0)
			t["knee_r"] = Vector3(1.5, 0, 0)
		Pose.STANCE2:
			hip_y = 0.82
			t["spine"] = Vector3(-0.7, 0, 0)
			t["neck"] = Vector3(0.55, 0, 0)
			t["shoulder_l"] = Vector3(-0.9, 0, -0.15)
			t["shoulder_r"] = Vector3(-0.9, 0, 0.15)
			t["elbow_l"] = Vector3(-0.5, 0, 0)
			t["elbow_r"] = Vector3(-0.5, 0, 0)
			t["hip_l"] = Vector3(-0.85, 0, -0.18)
			t["hip_r"] = Vector3(-0.85, 0, 0.18)
			t["knee_l"] = Vector3(1.25, 0, 0)
			t["knee_r"] = Vector3(1.25, 0, 0)
		Pose.QB_SET:
			hip_y = 0.93
			t["spine"] = Vector3(-0.15, 0.25, 0)
			t["shoulder_r"] = Vector3(-1.2, 0, 0.3)
			t["elbow_r"] = Vector3(-1.3, 0, 0)
			t["shoulder_l"] = Vector3(-0.9, 0, -0.1)
			t["elbow_l"] = Vector3(-1.2, 0, 0)
			t["hip_l"] = Vector3(-0.35, 0, -0.12)
			t["hip_r"] = Vector3(-0.2, 0, 0.12)
			t["knee_l"] = Vector3(0.5, 0, 0)
			t["knee_r"] = Vector3(0.45, 0, 0)
		Pose.SNAP:
			hip_y = 0.72
			t["spine"] = Vector3(-1.1, 0, 0)
			t["neck"] = Vector3(0.85, 0, 0)
			var k := clampf(pose_time / 0.2, 0.0, 1.0)
			t["shoulder_r"] = Vector3(-1.9 + k * 2.2, 0, 0.1)
			t["shoulder_l"] = Vector3(-0.6, 0, -0.3)
			t["hip_l"] = Vector3(-1.1, 0, -0.3)
			t["hip_r"] = Vector3(-1.1, 0, 0.3)
			t["knee_l"] = Vector3(1.6, 0, 0)
			t["knee_r"] = Vector3(1.6, 0, 0)
		Pose.RUN, Pose.BLOCK, Pose.PUSH, Pose.HANDOFF:
			_run_targets(t, dt)
			if pose == Pose.BLOCK or pose == Pose.PUSH:
				hip_y = 0.86
				t["spine"] = Vector3(-0.55 - (0.15 if pose == Pose.PUSH else 0.0), 0, 0)
				t["neck"] = Vector3(0.45, 0, 0)
				t["shoulder_l"] = Vector3(-1.45, 0, -0.1)
				t["shoulder_r"] = Vector3(-1.45, 0, 0.1)
				t["elbow_l"] = Vector3(-0.35, 0, 0)
				t["elbow_r"] = Vector3(-0.35, 0, 0)
			elif pose == Pose.HANDOFF:
				t["shoulder_r"] = Vector3(-1.0, 0, 0.5)
				t["elbow_r"] = Vector3(-0.6, 0, 0)
				t["shoulder_l"] = Vector3(-0.9, 0, -0.5)
				t["elbow_l"] = Vector3(-0.6, 0, 0)
			body_y = absf(sin(run_phase)) * 0.06 * clampf(speed / 6.0, 0.0, 1.0)
		Pose.THROW:
			var k := pose_time / 0.38
			t["spine"] = Vector3(-0.1, lerpf(0.6, -0.5, clampf(k * 1.4, 0, 1)), 0)
			var arm := lerpf(-2.9, -0.9, clampf((k - 0.25) * 1.8, 0, 1)) if k > 0.25 else lerpf(-1.4, -2.9, k * 4.0)
			t["shoulder_r"] = Vector3(arm, 0, 0.35)
			t["elbow_r"] = Vector3(-1.6 + clampf(k, 0, 1) * 1.4, 0, 0)
			t["shoulder_l"] = Vector3(-1.2, 0, -0.4)
			t["elbow_l"] = Vector3(-1.0, 0, 0)
			t["hip_l"] = Vector3(-0.35, 0, -0.1)
			t["hip_r"] = Vector3(0.15, 0, 0.1)
			t["knee_l"] = Vector3(0.25, 0, 0)
			t["knee_r"] = Vector3(0.3, 0, 0)
		Pose.CATCH:
			_run_targets(t, dt)
			t["shoulder_l"] = Vector3(-2.6, 0, -0.2)
			t["shoulder_r"] = Vector3(-2.6, 0, 0.2)
			t["elbow_l"] = Vector3(-0.3, 0, 0)
			t["elbow_r"] = Vector3(-0.3, 0, 0)
			t["neck"] = Vector3(-0.3, 0, 0)
		Pose.DIVE:
			var k := clampf(pose_time / 0.3, 0.0, 1.0)
			body_pitch = -1.35 * k
			hip_y = lerpf(0.95, 0.4, k)
			t["shoulder_l"] = Vector3(-2.9, 0, -0.2)
			t["shoulder_r"] = Vector3(-2.9, 0, 0.2)
			t["hip_l"] = Vector3(0.3, 0, 0)
			t["hip_r"] = Vector3(0.5, 0, 0)
			t["knee_l"] = Vector3(0.6, 0, 0)
			t["knee_r"] = Vector3(0.4, 0, 0)
		Pose.DOWN:
			var k := clampf(pose_time / 0.35, 0.0, 1.0)
			body_pitch = -1.45 * k
			body_roll = 0.25 * fall_side * k
			hip_y = lerpf(0.9, 0.3, k)
			t["shoulder_l"] = Vector3(-1.4, 0, -0.6)
			t["shoulder_r"] = Vector3(-1.6, 0, 0.5)
			t["elbow_l"] = Vector3(-0.8, 0, 0)
			t["hip_l"] = Vector3(0.2, 0, -0.1)
			t["knee_l"] = Vector3(0.9, 0, 0)
			t["knee_r"] = Vector3(0.4, 0, 0)
		Pose.CELEBRATE:
			var hop := absf(sin(pose_time * 7.0))
			body_y = hop * 0.35
			t["shoulder_l"] = Vector3(-2.9 + sin(pose_time * 7.0) * 0.2, 0, -0.4)
			t["shoulder_r"] = Vector3(-2.9 - sin(pose_time * 7.0) * 0.2, 0, 0.4)
			t["elbow_l"] = Vector3(-0.2, 0, 0)
			t["elbow_r"] = Vector3(-0.2, 0, 0)
			t["knee_l"] = Vector3(0.6 * hop, 0, 0)
			t["knee_r"] = Vector3(0.6 * hop, 0, 0)
			t["hip_l"] = Vector3(-0.3 * hop, 0, 0)
			t["hip_r"] = Vector3(-0.3 * hop, 0, 0)
		Pose.KICK:
			var k := clampf(pose_time / 0.45, 0.0, 1.0)
			var swing := lerpf(0.9, -1.9, clampf((k - 0.3) / 0.5, 0, 1)) if k > 0.3 else lerpf(0.0, 0.9, k / 0.3)
			t["hip_r"] = Vector3(swing, 0, 0.1)
			t["knee_r"] = Vector3(0.9 if k < 0.5 else 0.1, 0, 0)
			t["hip_l"] = Vector3(0.1, 0, -0.1)
			t["spine"] = Vector3(0.25 if k > 0.4 else -0.1, 0, 0)
			t["shoulder_l"] = Vector3(-0.6, 0, -0.9)
			t["shoulder_r"] = Vector3(0.4, 0, 0.7)
	if carrying and pose in [Pose.RUN, Pose.IDLE, Pose.DIVE, Pose.HANDOFF]:
		t["shoulder_r"] = Vector3(-0.55, 0, 0.12)
		t["elbow_r"] = Vector3(-1.9, 0, 0)
	# Smoothly blend every joint toward its target.
	var blend := 1.0 - exp(-dt * 16.0)
	for k in j:
		var target: Vector3 = t.get(k, Vector3.ZERO)
		var cur: Vector3 = _ang[k]
		cur = cur.lerp(target, blend)
		_ang[k] = cur
		if k != "hips":
			# Pose tables use "negative pitch = swing forward" for every joint. Limbs
			# hang downward, so their sign is flipped to get the same visual meaning.
			if LIMBS.has(k):
				j[k].rotation = Vector3(-cur.x, cur.y, cur.z)
			else:
				j[k].rotation = cur
	var hips: Node3D = j["hips"]
	hips.position.y = lerpf(hips.position.y, hip_y + body_y, blend)
	var root_target := Vector3(body_pitch + lean * 0.12, 0, body_roll)
	var cur_root: Vector3 = _ang.get("_root", Vector3.ZERO)
	cur_root = cur_root.lerp(root_target, blend)
	_ang["_root"] = cur_root
	hips.rotation = cur_root

func _run_targets(t: Dictionary, dt: float) -> void:
	var sp := clampf(speed / 9.0, 0.0, 1.2)
	run_phase += dt * (5.0 + speed * 1.05)
	if sp < 0.05:
		t["shoulder_l"] = Vector3(0.1, 0, -0.18)
		t["shoulder_r"] = Vector3(0.1, 0, 0.18)
		t["elbow_l"] = Vector3(-0.3, 0, 0)
		t["elbow_r"] = Vector3(-0.3, 0, 0)
		return
	var amp := 0.35 + sp * 0.6
	var s := sin(run_phase)
	t["spine"] = Vector3(-0.12 - sp * 0.28, s * 0.08, 0)
	t["neck"] = Vector3(0.1 + sp * 0.2, 0, 0)
	t["hip_l"] = Vector3(-s * amp - 0.1, 0, -0.04)
	t["hip_r"] = Vector3(s * amp - 0.1, 0, 0.04)
	t["knee_l"] = Vector3(maxf(0.0, cos(run_phase)) * (0.6 + sp * 1.0) + 0.15, 0, 0)
	t["knee_r"] = Vector3(maxf(0.0, -cos(run_phase)) * (0.6 + sp * 1.0) + 0.15, 0, 0)
	t["shoulder_l"] = Vector3(s * amp * 0.9, 0, -0.15)
	t["shoulder_r"] = Vector3(-s * amp * 0.9, 0, 0.15)
	t["elbow_l"] = Vector3(-1.2, 0, 0)
	t["elbow_r"] = Vector3(-1.2, 0, 0)
