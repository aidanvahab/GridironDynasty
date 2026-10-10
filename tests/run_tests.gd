extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd [-- filter]
## Runs every test_* method in res://tests/test_*.gd and exits non-zero on
## failure. Script errors raised while a test runs also fail that test.

class ErrorCounter extends Logger:
	var count := 0
	var last := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		last = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
	func _log_message(_message: String, _error: bool) -> void:
		pass

var counter := ErrorCounter.new()

func _init() -> void:
	OS.add_logger(counter)
	call_deferred("_run")

func _run() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var dir := DirAccess.open("res://tests")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var asserts := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		if filter != "" and not f.contains(filter.split(":")[0]) and not filter.contains(":"):
			pass
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("  FAIL [parse error] ", f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + name).contains(filter):
				continue
			var inst: TestCase = script.new()
			inst.current_test = f + ":" + name
			total += 1
			var errors_before := counter.count
			var ret = inst.call(name)
			if ret != null and typeof(ret) == TYPE_OBJECT:
				await ret
			if counter.count > errors_before:
				inst.failures.append("%d script error(s), last: %s" % [counter.count - errors_before, counter.last])
			asserts += inst.assertions
			if inst.failures.is_empty():
				print("  ok   ", inst.current_test)
			else:
				failed += 1
				print("  FAIL ", inst.current_test)
				for msg in inst.failures:
					print("        ", msg)
	print("\n%d tests, %d assertions, %d failed (%d ms)" % [total, asserts, failed, Time.get_ticks_msec() - t0])
	quit(1 if failed > 0 else 0)
