extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd [-- filter]
## Runs every test_* method in res://tests/test_*.gd and exits non-zero on failure.

func _init() -> void:
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
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			print("[LOAD FAIL] ", f)
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
			var ret = inst.call(name)
			if ret is Object and ret.has_method("is_valid"):
				pass
			if ret != null and typeof(ret) == TYPE_OBJECT:
				await ret
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
