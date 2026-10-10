class_name Palette
## "Modern Retro Sports" palette shared by UI, HUD and world presentation.

const NAVY := Color("#101B2B")
const DEEP_BLUE := Color("#1A2C45")
const PANEL := Color("#16263B")
const PANEL_LIGHT := Color("#223754")
const CREAM := Color("#F5F0E5")
const CREAM_DIM := Color("#BFB8AA")
const ORANGE := Color("#F28C38")
const TEAL := Color("#42B7AD")
const GOLD := Color("#F4C95D")
const GREEN := Color("#65C987")
const RED := Color("#E75A5A")
const MUTED := Color("#7D8BA0")
const SHADOW := Color(0, 0, 0, 0.45)

static func rating_color(r: float) -> Color:
	if r >= 85.0: return GOLD
	if r >= 75.0: return GREEN
	if r >= 65.0: return TEAL
	if r >= 55.0: return CREAM_DIM
	return RED

static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
