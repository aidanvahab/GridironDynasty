class_name Portrait
extends Control
## Stylized helmeted player bust drawn in 2D for roster cards and profiles.

var helmet: Color = Palette.ORANGE
var stripe: Color = Palette.CREAM
var jersey: Color = Palette.ORANGE
var skin: Color = Color("#C68A5A")
var number: int = 0
var mask: Color = Color("#C8CED6")
var bg: Color = Palette.DEEP_BLUE

static func for_player(p: Player, t: Team, size: float = 96.0) -> Portrait:
	var pr := Portrait.new()
	pr.custom_minimum_size = Vector2(size, size)
	pr.number = p.number
	pr.skin = PlayerRig.SKIN_TONES[clampi(p.skin, 0, 5)]
	if t != null:
		pr.helmet = t.primary
		pr.jersey = t.primary
		pr.stripe = t.secondary if t.secondary.get_luminance() > 0.3 else t.accent
	else:
		pr.helmet = Palette.MUTED
		pr.jersey = Palette.MUTED
		pr.stripe = Palette.CREAM
	return pr

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	draw_rect(Rect2(o, Vector2(s, s)), bg)
	# Gradient glow.
	draw_circle(o + Vector2(s * 0.5, s * 0.55), s * 0.45, bg.lightened(0.08))
	# Shoulders / jersey.
	var sh := PackedVector2Array([o + Vector2(0.06, 1.0) * s, o + Vector2(0.12, 0.78) * s, o + Vector2(0.3, 0.68) * s, o + Vector2(0.7, 0.68) * s, o + Vector2(0.88, 0.78) * s, o + Vector2(0.94, 1.0) * s])
	draw_colored_polygon(sh, jersey.darkened(0.1))
	draw_polyline(PackedVector2Array([o + Vector2(0.12, 0.78) * s, o + Vector2(0.3, 0.68) * s, o + Vector2(0.7, 0.68) * s, o + Vector2(0.88, 0.78) * s]), stripe, s * 0.025, true)
	# Neck.
	draw_rect(Rect2(o + Vector2(0.42, 0.58) * s, Vector2(0.16, 0.14) * s), skin.darkened(0.15))
	# Helmet shell.
	var hc := o + Vector2(0.5, 0.4) * s
	var r := s * 0.26
	draw_circle(hc, r, helmet)
	draw_circle(hc + Vector2(-r * 0.25, -r * 0.3), r * 0.35, helmet.lightened(0.25))
	draw_line(hc + Vector2(0, -r), hc + Vector2(0, r * 0.2), stripe, s * 0.035)
	# Face opening.
	var face := Rect2(hc + Vector2(-r * 0.55, -r * 0.05), Vector2(r * 1.1, r * 0.95))
	draw_rect(face, skin)
	draw_circle(hc + Vector2(-r * 0.22, r * 0.25), r * 0.07, Color("#1A1A1A"))
	draw_circle(hc + Vector2(r * 0.22, r * 0.25), r * 0.07, Color("#1A1A1A"))
	# Facemask bars.
	for i in 3:
		var y := hc.y + r * (0.18 + i * 0.28)
		draw_line(Vector2(hc.x - r * 0.62, y), Vector2(hc.x + r * 0.62, y), mask, s * 0.022, true)
	draw_line(hc + Vector2(0, r * 0.1), hc + Vector2(0, r * 0.95), mask, s * 0.022, true)
	# Ear hole.
	draw_circle(hc + Vector2(-r * 0.78, r * 0.1), r * 0.12, helmet.darkened(0.4))
	# Number on chest.
	if number > 0:
		var f := UI.font("heading")
		var fs := int(s * 0.2)
		var txt := str(number)
		var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, o + Vector2(s * 0.5 - ts.x * 0.5, s * 0.96), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, stripe)
