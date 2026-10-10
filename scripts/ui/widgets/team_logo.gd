class_name TeamLogo
extends Control
## Procedurally drawn team logo: a badge shape with an emblem in team colors.
## Used in menus, scorebug and (via LogoBaker) on the field.

var shape: String = "shield"
var emblem: String = "star"
var primary: Color = Palette.ORANGE
var secondary: Color = Palette.CREAM
var accent: Color = Palette.NAVY
var letter: String = "G"

static func from_team(t: Team, size: float = 64.0) -> TeamLogo:
	var l := TeamLogo.new()
	l.configure(t.logo, t.primary, t.secondary, t.accent, t.name.substr(0, 1))
	l.custom_minimum_size = Vector2(size, size)
	return l

func configure(logo: Dictionary, p: Color, s: Color, a: Color, ltr: String = "G") -> void:
	shape = str(logo.get("shape", "shield"))
	emblem = str(logo.get("emblem", "star"))
	primary = p
	secondary = s
	accent = a
	letter = ltr.to_upper()
	queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var outline := _shape_points(c, s * 0.5)
	var inner := _shape_points(c, s * 0.5 * 0.86)
	draw_colored_polygon(outline, secondary)
	draw_colored_polygon(inner, primary)
	_draw_emblem(c, s * 0.3)

func _shape_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		"circle":
			for i in 40:
				var a := TAU * i / 40.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
		"diamond":
			pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		"hex":
			for i in 6:
				var a := TAU * i / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
		"pennant":
			pts = PackedVector2Array([c + Vector2(-r, -r * 0.8), c + Vector2(r, -r * 0.2), c + Vector2(r, r * 0.2), c + Vector2(-r, r * 0.8)])
		_: # shield
			pts.append(c + Vector2(-r * 0.85, -r * 0.9))
			pts.append(c + Vector2(r * 0.85, -r * 0.9))
			pts.append(c + Vector2(r * 0.85, r * 0.1))
			for i in 9:
				var a := PI * i / 8.0
				pts.append(c + Vector2(cos(a) * r * 0.85, r * 0.1 + sin(a) * r * 0.9))
			pts.append(c + Vector2(-r * 0.85, r * 0.1))
	return pts

func _star(c: Vector2, r: float, points: int = 5, inner_ratio: float = 0.45) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var rr := r if i % 2 == 0 else r * inner_ratio
		var a := -PI / 2.0 + PI * i / points
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts

func _draw_emblem(c: Vector2, r: float) -> void:
	var col := secondary
	var dark := accent
	match emblem:
		"star":
			draw_colored_polygon(_star(c, r), col)
		"bolt":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0.15, -1) * r, c + Vector2(-0.45, 0.1) * r, c + Vector2(-0.02, 0.1) * r, c + Vector2(-0.2, 1) * r, c + Vector2(0.5, -0.15) * r, c + Vector2(0.05, -0.15) * r]), col)
		"wing":
			for i in 4:
				var y := -0.55 + i * 0.32
				draw_colored_polygon(PackedVector2Array([c + Vector2(-0.8, y) * r, c + Vector2(0.9 - i * 0.18, y - 0.25) * r, c + Vector2(0.7 - i * 0.18, y + 0.12) * r, c + Vector2(-0.8, y + 0.2) * r]), col)
		"flame":
			var pts := PackedVector2Array()
			for i in 13:
				var a := PI * i / 12.0
				var rr := r * (0.55 + 0.45 * absf(sin(a * 3.0)))
				pts.append(c + Vector2(-cos(a) * rr * 0.8, -sin(a) * rr * 1.2 + r * 0.5))
			pts.append(c + Vector2(0, r * 0.8))
			draw_colored_polygon(pts, col)
			draw_circle(c + Vector2(0, r * 0.35), r * 0.25, dark)
		"crown":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.85, 0.6) * r, c + Vector2(-0.85, -0.5) * r, c + Vector2(-0.4, 0.05) * r, c + Vector2(0, -0.75) * r, c + Vector2(0.4, 0.05) * r, c + Vector2(0.85, -0.5) * r, c + Vector2(0.85, 0.6) * r]), col)
			for x in [-0.85, 0.0, 0.85]:
				draw_circle(c + Vector2(x, x * 0.0 - (0.75 if x == 0.0 else 0.5)) * r, r * 0.12, col)
		"horn":
			for sx in [-1.0, 1.0]:
				var pts2 := PackedVector2Array()
				for i in 10:
					var a := PI * i / 9.0
					pts2.append(c + Vector2(sx * (0.2 + 0.7 * sin(a * 0.5)) * r, (0.5 - a / PI * 1.3) * r))
				for i in range(9, -1, -1):
					var a := PI * i / 9.0
					pts2.append(c + Vector2(sx * (0.2 + 0.45 * sin(a * 0.5)) * r, (0.5 - a / PI * 1.0) * r))
				draw_colored_polygon(pts2, col)
		"anchor":
			draw_rect(Rect2(c + Vector2(-0.1, -0.7) * r, Vector2(0.2, 1.4) * r), col)
			draw_rect(Rect2(c + Vector2(-0.5, -0.45) * r, Vector2(1.0, 0.18) * r), col)
			draw_arc(c + Vector2(0, 0.2) * r, r * 0.6, 0.1, PI - 0.1, 20, col, r * 0.18)
			draw_circle(c + Vector2(0, -0.85) * r, r * 0.17, col)
		"wave":
			for k in 3:
				var pts3 := PackedVector2Array()
				for i in 21:
					var x := -0.9 + i * 0.09
					pts3.append(c + Vector2(x, (k - 1) * 0.42 + sin(x * 5.0) * 0.14) * r)
				draw_polyline(pts3, col, r * 0.17, true)
		"pine":
			for k in 3:
				var y := -0.8 + k * 0.45
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, y) * r, c + Vector2(0.35 + k * 0.2, y + 0.55) * r, c + Vector2(-0.35 - k * 0.2, y + 0.55) * r]), col)
			draw_rect(Rect2(c + Vector2(-0.1, 0.7) * r, Vector2(0.2, 0.3) * r), col)
		"hammer":
			draw_rect(Rect2(c + Vector2(-0.1, -0.3) * r, Vector2(0.2, 1.25) * r), col)
			draw_rect(Rect2(c + Vector2(-0.65, -0.75) * r, Vector2(1.3, 0.48) * r), col)
		"fang":
			for sx in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([c + Vector2(sx * 0.1, -0.7) * r, c + Vector2(sx * 0.65, -0.7) * r, c + Vector2(sx * 0.3, 0.9) * r]), col)
		"flake":
			for i in 3:
				var a := PI * i / 3.0
				var d := Vector2(cos(a), sin(a)) * r * 0.9
				draw_line(c - d, c + d, col, r * 0.16, true)
			draw_circle(c, r * 0.22, col)
		_:
			var f := UI.font("heading")
			var fs := int(r * 1.9)
			var sz := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, c + Vector2(-sz.x * 0.5, sz.y * 0.32), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
