class_name Fmt
## Dependency-free formatting helpers shared by game logic and UI.

static func money(m: float) -> String:
	if absf(m) >= 1.0:
		return "$%.1fM" % m
	return "$%dK" % int(round(m * 1000.0))

static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
