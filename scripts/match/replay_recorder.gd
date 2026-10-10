class_name ReplayRecorder
extends RefCounted
## Records every physics frame of a live play (agent transforms, poses, ball)
## so replays show exactly what happened — never an invented result.

const MAX_FRAMES := 2400

var frames: Array = []
var agents: Array = []

func clear() -> void:
	frames.clear()
	agents.clear()

func capture(t: float, list: Array, ball: Football) -> void:
	if agents.is_empty():
		agents = list.duplicate()
	var n := agents.size()
	var p := PackedVector3Array()
	p.resize(n)
	var r := PackedFloat32Array()
	r.resize(n)
	var pose := PackedInt32Array()
	pose.resize(n)
	var spd := PackedFloat32Array()
	spd.resize(n)
	var carry := PackedByteArray()
	carry.resize(n)
	for i in n:
		var a: FieldAgent = agents[i]
		p[i] = a.global_position
		r[i] = a.rotation.y
		pose[i] = a.rig.pose
		spd[i] = a.speed()
		carry[i] = 1 if a.rig.carrying else 0
	frames.append({"t": t, "p": p, "r": r, "pose": pose, "spd": spd, "carry": carry, "bp": ball.global_position, "bb": ball.mesh_root.basis, "bv": ball.visible})
	if frames.size() > MAX_FRAMES:
		frames.pop_front()

func duration() -> float:
	if frames.size() < 2:
		return 0.0
	return float(frames[frames.size() - 1]["t"]) - float(frames[0]["t"])

## Applies frame i. Poses are re-animated by the caller via rig.animate().
func apply(i: int, ball: Football) -> void:
	if frames.is_empty():
		return
	var f: Dictionary = frames[clampi(i, 0, frames.size() - 1)]
	var p: PackedVector3Array = f["p"]
	for k in agents.size():
		var a: FieldAgent = agents[k]
		a.global_position = p[k]
		a.rotation.y = f["r"][k]
		a.rig.set_pose(f["pose"][k])
		a.rig.speed = f["spd"][k]
		a.rig.carrying = f["carry"][k] == 1
	ball.global_position = f["bp"]
	ball.mesh_root.basis = f["bb"]
	ball.visible = f["bv"]
