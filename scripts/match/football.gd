class_name Football
extends Node3D
## The football. Possession is exclusive: only `carrier` holds the ball and
## it changes only through give_to()/launch()/fumble(). Flight is integrated
## deterministically; visuals spin around the velocity axis.

enum State { HELD, FLIGHT, LOOSE, DEAD }

signal landed(pos: Vector3)

var state: State = State.DEAD
var carrier: Node3D = null ## FieldAgent
var velocity := Vector3.ZERO
var spin_angle := 0.0
var spin_rate := 0.0
var flight_time := 0.0
var launch_pos := Vector3.ZERO
var touched_by: Array = [] ## agents that already attempted this pass
var intended: Node3D = null
var wobble := 0.0
var is_kick := false
var mesh_root: Node3D

func _ready() -> void:
	mesh_root = Node3D.new()
	add_child(mesh_root)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 18
	sm.rings = 10
	body.mesh = sm
	body.scale = Vector3(0.17, 0.17, 0.3)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#7A3E1D")
	m.roughness = 0.55
	m.rim_enabled = true
	m.rim = 0.3
	body.material_override = m
	mesh_root.add_child(body)
	var laces := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.012, 0.12)
	laces.mesh = bm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("#F5F0E5")
	laces.material_override = lm
	laces.position = Vector3(0, 0.083, 0)
	mesh_root.add_child(laces)
	for zs in [-1.0, 1.0]:
		var stripe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 1.0
		stripe.mesh = cm
		stripe.material_override = lm
		stripe.scale = Vector3(0.145, 0.012, 0.145)
		stripe.rotation = Vector3(PI / 2, 0, 0)
		stripe.position = Vector3(0, 0, zs * 0.095)
		mesh_root.add_child(stripe)

func give_to(agent: Node3D) -> void:
	carrier = agent
	state = State.HELD
	velocity = Vector3.ZERO
	intended = null
	touched_by.clear()
	is_kick = false

func launch(from: Vector3, vel: Vector3, target_agent: Node3D = null, kick: bool = false) -> void:
	carrier = null
	state = State.FLIGHT
	global_position = from
	launch_pos = from
	velocity = vel
	flight_time = 0.0
	spin_rate = 22.0 if not kick else 9.0
	intended = target_agent
	touched_by.clear()
	is_kick = kick
	wobble = 0.0

func fumble(from: Vector3, vel: Vector3) -> void:
	carrier = null
	state = State.LOOSE
	global_position = from
	velocity = vel
	spin_rate = 14.0
	touched_by.clear()

func kill() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO

func is_free() -> bool:
	return state == State.FLIGHT or state == State.LOOSE

func step(dt: float) -> void:
	match state:
		State.HELD:
			if carrier != null and carrier.has_method("ball_hold_point"):
				global_position = carrier.ball_hold_point()
				var fwd: Vector3 = carrier.facing
				mesh_root.basis = Basis.looking_at(fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		State.FLIGHT:
			flight_time += dt
			velocity.y -= PassMath.GRAVITY * dt
			global_position += velocity * dt
			spin_angle += spin_rate * dt
			if velocity.length() > 0.5:
				var b := Basis.looking_at(velocity.normalized(), Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
				if is_kick:
					b = b * Basis(Vector3.RIGHT, spin_angle)
				else:
					b = b * Basis(Vector3.BACK, spin_angle) * Basis(Vector3.RIGHT, sin(flight_time * 5.0) * wobble)
				mesh_root.basis = b
			if global_position.y <= 0.12:
				global_position.y = 0.12
				landed.emit(global_position)
		State.LOOSE:
			velocity.y -= PassMath.GRAVITY * dt
			global_position += velocity * dt
			spin_angle += spin_rate * dt
			mesh_root.basis = Basis(Vector3(0.3, 1, 0.2).normalized(), spin_angle)
			if global_position.y <= 0.1:
				global_position.y = 0.1
				if absf(velocity.y) > 1.0:
					velocity.y = -velocity.y * 0.45
					velocity.x *= 0.7
					velocity.z *= 0.7
					# Footballs bounce unpredictably.
					var r := velocity.length() * 0.4
					velocity.x += randf_range(-r, r)
					velocity.z += randf_range(-r, r)
					spin_rate *= 0.8
				else:
					velocity.y = 0.0
					velocity.x = move_toward(velocity.x, 0.0, 6.0 * dt)
					velocity.z = move_toward(velocity.z, 0.0, 6.0 * dt)
		State.DEAD:
			pass
