class_name PlayDiagram
extends Control
## Chalkboard-style diagram of a play: formation, routes (color per receiver),
## blocking and run paths. Drawn from the same playbook data the game uses.

var play_def: Dictionary = {}
var flip: bool = false
var compact: bool = false

func set_play(p: Dictionary, f: bool = false) -> void:
	play_def = p
	flip = f
	queue_redraw()

func _to_px(v: Vector2) -> Vector2:
	## Offense frame (downfield, lateral) -> local pixels. Downfield is up.
	var w := size.x
	var h := size.y
	var los_y := h * 0.72
	var yd := h / 34.0
	var xd := w / 46.0
	return Vector2(w * 0.5 + v.y * xd, los_y - v.x * yd)

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("#14301F"))
	# Yard lines.
	for i in range(-2, 8):
		var y := _to_px(Vector2(i * 5.0, 0)).y
		draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.08 if i != 0 else 0.0), 1.0)
	var los := _to_px(Vector2(0, 0)).y
	draw_line(Vector2(0, los), Vector2(w, los), Color("#5AA0FF", 0.7), 2.0)
	if play_def.is_empty():
		return
	var special: String = play_def.get("special", "")
	# Offensive line.
	for slot in ["LT", "LG", "C", "RG", "RT"]:
		var p := _to_px(Playbook.alignment(play_def, slot, flip))
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Palette.CREAM.darkened(0.15))
	# Run path.
	if Playbook.is_run(play_def):
		var carrier := "QB" if play_def.get("qb_run", false) else "B"
		var pts := PackedVector2Array([_to_px(Playbook.alignment(play_def, carrier, flip))])
		for v in Playbook.run_path(play_def, flip):
			pts.append(_to_px(v))
		pts.append(pts[pts.size() - 1] + (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized() * 18.0)
		_arrow_line(pts, Palette.GREEN, 4.0)
	# Routes.
	for slot in LivePlay.RECEIVER_SLOTS:
		var start := _to_px(Playbook.alignment(play_def, slot, flip))
		var rname: String = play_def.get("routes", {}).get(slot, "block")
		var col: Color = LivePlay.SLOT_COLORS[slot]
		if rname in ["block", "stalk", "lead"]:
			var tip := start + Vector2(0, -10)
			draw_line(start, tip, Palette.CREAM_DIM, 2.0)
			draw_line(tip + Vector2(-6, 0), tip + Vector2(6, 0), Palette.CREAM_DIM, 2.0)
		elif rname in ["run", "fake"]:
			pass
		elif special == "":
			var pts := PackedVector2Array([start])
			for v in Playbook.route_points(play_def, slot, flip):
				pts.append(_to_px(v))
			if Playbook.route_def(rname).get("continue", false) and pts.size() >= 2:
				pts.append(pts[pts.size() - 1] + (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized() * 14.0)
			_arrow_line(pts, col, 3.0)
		draw_circle(start, 7.0, col)
		if not compact:
			var idx := LivePlay.RECEIVER_SLOTS.find(slot) + 1
			var f := UI.font("heading")
			draw_string(f, start + Vector2(-4, 5), str(idx), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.NAVY)
	var qb := _to_px(Playbook.alignment(play_def, "QB", flip))
	draw_circle(qb, 7.0, Palette.ORANGE)
	draw_arc(qb, 7.0, 0, TAU, 16, Palette.CREAM, 1.5)

func _arrow_line(pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, col, width, true)
	var a := pts[pts.size() - 2]
	var b := pts[pts.size() - 1]
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([b + d * 7.0, b - d * 3.0 + n * 6.0, b - d * 3.0 - n * 6.0]), col)
