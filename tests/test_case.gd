class_name TestCase
extends RefCounted
## Minimal assertion base for the headless test runner (tests/run_tests.gd).

var failures: Array[String] = []
var current_test: String = ""
var assertions: int = 0

func _fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])

func check(cond: bool, msg: String = "condition false") -> void:
	assertions += 1
	if not cond:
		_fail(msg)

func eq(a: Variant, b: Variant, msg: String = "") -> void:
	assertions += 1
	if typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
		if absf(float(a) - float(b)) > 0.001:
			_fail("expected %s == %s %s" % [str(a), str(b), msg])
		return
	if a != b:
		_fail("expected %s == %s %s" % [str(a), str(b), msg])

func near(a: float, b: float, tol: float, msg: String = "") -> void:
	assertions += 1
	if absf(a - b) > tol:
		_fail("expected %f ~= %f (tol %f) %s" % [a, b, tol, msg])

func has_event(events: Array, type: String) -> bool:
	for e in events:
		if e.get("type", "") == type:
			return true
	return false
