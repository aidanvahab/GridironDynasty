class_name UI
extends RefCounted
## Shared UI construction kit: theme, fonts, and factory helpers so every
## screen shares one premium "Modern Retro Sports" look.

static var _theme: Theme
static var _fonts: Dictionary = {}

static func font(kind: String) -> Font:
	if _fonts.is_empty():
		_fonts = {
			"display": load("res://assets/fonts/BarlowCondensed-BlackItalic.ttf"),
			"heading": load("res://assets/fonts/BarlowCondensed-ExtraBold.ttf"),
			"sub": load("res://assets/fonts/BarlowCondensed-Bold.ttf"),
			"semi": load("res://assets/fonts/BarlowCondensed-SemiBold.ttf"),
			"body": load("res://assets/fonts/Barlow-Regular.ttf"),
			"body_bold": load("res://assets/fonts/Barlow-SemiBold.ttf"),
			"strong": load("res://assets/fonts/Barlow-Bold.ttf"),
		}
	return _fonts.get(kind, _fonts["body"])

static func box(bg: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0, pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 22
	# Buttons.
	var normal := box(Palette.PANEL_LIGHT, 10, Color(1, 1, 1, 0.06), 1, 18)
	var hover := box(Palette.PANEL_LIGHT.lightened(0.12), 10, Palette.ORANGE, 2, 18)
	var pressed := box(Palette.ORANGE.darkened(0.15), 10, Palette.ORANGE, 2, 18)
	var focus := box(Color(0, 0, 0, 0), 10, Palette.GOLD, 3, 18)
	focus.draw_center = false
	var disabled := box(Palette.PANEL.darkened(0.2), 10, Color(1, 1, 1, 0.03), 1, 18)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", Palette.CREAM)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Palette.NAVY)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Palette.MUTED)
	t.set_font("font", "Button", font("sub"))
	t.set_font_size("font_size", "Button", 24)
	# Labels.
	t.set_color("font_color", "Label", Palette.CREAM)
	t.set_font("font", "Label", font("body"))
	# Panels.
	t.set_stylebox("panel", "PanelContainer", box(Palette.PANEL, 14, Color(1, 1, 1, 0.05), 1, 18))
	t.set_stylebox("panel", "Panel", box(Palette.PANEL, 14))
	# Tooltips.
	var tip := box(Palette.NAVY, 8, Palette.TEAL, 2, 12)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Palette.CREAM)
	t.set_font("font", "TooltipLabel", font("body"))
	t.set_font_size("font_size", "TooltipLabel", 18)
	# Line edits.
	var le := box(Palette.NAVY, 8, Palette.PANEL_LIGHT, 2, 12)
	var le_focus := box(Palette.NAVY, 8, Palette.ORANGE, 2, 12)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", Palette.CREAM)
	t.set_color("caret_color", "LineEdit", Palette.ORANGE)
	t.set_font("font", "LineEdit", font("body_bold"))
	t.set_font_size("font_size", "LineEdit", 24)
	# Sliders.
	var grab := box(Palette.ORANGE, 8)
	t.set_stylebox("slider", "HSlider", box(Palette.NAVY, 4, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area", "HSlider", box(Palette.ORANGE.darkened(0.2), 4, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Palette.ORANGE, 4, Color(0, 0, 0, 0), 0, 4))
	t.set_icon("grabber", "HSlider", _circle_icon(Palette.CREAM, 22))
	t.set_icon("grabber_highlight", "HSlider", _circle_icon(Palette.GOLD, 24))
	t.set_stylebox("focus", "HSlider", focus)
	# Option buttons / popups.
	t.set_stylebox("panel", "PopupMenu", box(Palette.NAVY, 8, Palette.PANEL_LIGHT, 2, 8))
	t.set_color("font_color", "PopupMenu", Palette.CREAM)
	t.set_color("font_hover_color", "PopupMenu", Palette.ORANGE)
	t.set_font("font", "PopupMenu", font("body_bold"))
	t.set_font_size("font_size", "PopupMenu", 20)
	t.set_stylebox("hover", "PopupMenu", box(Palette.PANEL_LIGHT, 6))
	# Check boxes.
	t.set_color("font_color", "CheckBox", Palette.CREAM)
	t.set_font("font", "CheckBox", font("body_bold"))
	t.set_stylebox("focus", "CheckBox", focus)
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	# Scrollbars.
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.2), 6, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber", "VScrollBar", box(Palette.PANEL_LIGHT.lightened(0.15), 6, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Palette.ORANGE, 6, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Palette.ORANGE, 6, Color(0, 0, 0, 0), 0, 2))
	# Tabs.
	t.set_stylebox("tab_selected", "TabBar", box(Palette.ORANGE, 8, Color(0, 0, 0, 0), 0, 16))
	t.set_stylebox("tab_unselected", "TabBar", box(Palette.PANEL_LIGHT, 8, Color(0, 0, 0, 0), 0, 16))
	t.set_stylebox("tab_hovered", "TabBar", box(Palette.PANEL_LIGHT.lightened(0.15), 8, Color(0, 0, 0, 0), 0, 16))
	t.set_stylebox("tab_focus", "TabBar", focus)
	t.set_color("font_selected_color", "TabBar", Palette.NAVY)
	t.set_color("font_unselected_color", "TabBar", Palette.CREAM)
	t.set_color("font_hovered_color", "TabBar", Color.WHITE)
	t.set_font("font", "TabBar", font("sub"))
	t.set_font_size("font_size", "TabBar", 22)
	_theme = t
	return t

static func _circle_icon(c: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)

static func _check_icon(on: bool) -> ImageTexture:
	var s := 26
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var border := x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			var c := Palette.ORANGE if on else Palette.NAVY
			if border:
				c = Palette.ORANGE if on else Palette.MUTED
			img.set_pixel(x, y, c)
	if on:
		for i in 9:
			for w in 3:
				img.set_pixel(clampi(6 + i / 2, 0, s - 1), clampi(13 + i / 2 + w - 1, 0, s - 1), Palette.NAVY)
				img.set_pixel(clampi(10 + i, 0, s - 1), clampi(17 - i + w - 1, 0, s - 1), Palette.NAVY)
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- factories

static func label(text: String, size: int = 22, color: Color = Palette.CREAM, kind: String = "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func heading(text: String, size: int = 44, color: Color = Palette.CREAM) -> Label:
	var l := label(text.to_upper(), size, color, "heading")
	return l

static func button(text: String, cb: Callable = Callable(), style: String = "secondary", min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(min_w, 54)
	if style == "primary":
		b.add_theme_stylebox_override("normal", box(Palette.ORANGE, 10, Palette.ORANGE.lightened(0.2), 1, 22))
		b.add_theme_stylebox_override("hover", box(Palette.ORANGE.lightened(0.12), 10, Palette.GOLD, 2, 22))
		b.add_theme_stylebox_override("pressed", box(Palette.ORANGE.darkened(0.2), 10, Palette.GOLD, 2, 22))
		b.add_theme_color_override("font_color", Palette.NAVY)
		b.add_theme_color_override("font_hover_color", Palette.NAVY)
		b.add_theme_color_override("font_focus_color", Palette.NAVY)
	elif style == "ghost":
		var g := box(Color(0, 0, 0, 0), 10, Color(1, 1, 1, 0.12), 1, 18)
		b.add_theme_stylebox_override("normal", g)
	elif style == "danger":
		b.add_theme_stylebox_override("normal", box(Palette.RED.darkened(0.35), 10, Palette.RED, 1, 18))
		b.add_theme_stylebox_override("hover", box(Palette.RED.darkened(0.15), 10, Palette.RED.lightened(0.2), 2, 18))
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func(): Audio.ui("click"))
	b.mouse_entered.connect(func(): Audio.ui("hover"))
	b.focus_entered.connect(func():
		if not Settings.last_input_was_mouse:
			Audio.ui("hover"))
	return b

static func panel(bg: Color = Palette.PANEL, radius: int = 14, border: Color = Color(1, 1, 1, 0.05), pad: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, radius, border, 1, pad))
	return p

static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func spacer(w: int = 0, h: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c

static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func margin(c: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(c)
	return m

static func rating_badge(ovr: int, size: int = 26) -> PanelContainer:
	var p := PanelContainer.new()
	var c := Palette.rating_color(ovr)
	p.add_theme_stylebox_override("panel", box(c.darkened(0.55), 6, c, 2, 6))
	var l := label(str(ovr), size, c, "heading")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(size * 1.6, 0)
	p.add_child(l)
	return p

static func stat_bar(value: float, max_v: float = 99.0, color: Color = Color(0, 0, 0, 0), w: int = 160) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = max_v
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(w, 12)
	var c := color if color.a > 0.0 else Palette.rating_color(value)
	pb.add_theme_stylebox_override("background", box(Palette.NAVY, 5, Color(0, 0, 0, 0), 0, 0))
	pb.add_theme_stylebox_override("fill", box(c, 5, Color(0, 0, 0, 0), 0, 0))
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pb

static func separator() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.07)
	c.custom_minimum_size = Vector2(0, 2)
	return c

static func money(m: float) -> String:
	if absf(m) >= 1.0:
		return "$%.1fM" % m
	return "$%dK" % int(round(m * 1000.0))

## Fades a control in from a slight offset.
static func pop_in(c: Control, delay: float = 0.0) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)

static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
