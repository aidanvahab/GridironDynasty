extends SceneTree
## End-to-end driver for the real application (not the editor).
##   godot-gfx --path . -s res://tools/e2e.gd -- scenario=<name> out=<dir>
## Scenarios drive App the way a player would, take screenshots, and fail on
## any script/engine error. Exit code 0 = pass.

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var msg := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		# Audio device errors are expected on headless CI machines.
		if msg.contains("audio") or msg.contains("ALSA") or file.contains("audio_driver"):
			return
		errors.append(msg)
	func _log_message(_m: String, _e: bool) -> void:
		pass

var counter := ErrorCounter.new()
var args := {}
var out_dir := "/tmp/claude-0/e2e"
var shots := 0
var failures: Array[String] = []

func _init() -> void:
	OS.add_logger(counter)
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	out_dir = args.get("out", out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")

func app() -> Node:
	return root.get_node("App")

func sm() -> Node:
	return root.get_node("SaveManager")

func st() -> Node:
	return root.get_node("Settings")

func wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += maxf(root.get_process_delta_time(), 1.0 / 60.0)

func wait_frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await wait_frames(3)
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		shots += 1
		var path := "%s/%02d_%s.png" % [out_dir, shots, name]
		img.save_png(path)
		print("[shot] ", path)

func expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		print("[FAIL] ", msg)
	else:
		print("[ok] ", msg)

func _run() -> void:
	var scenario: String = args.get("scenario", "smoke")
	var timeout := float(args.get("timeout", "600"))
	create_timer(timeout).timeout.connect(func():
		print("[FAIL] scenario timed out")
		quit(3))
	var runner: RefCounted = load("res://tools/e2e_scenarios.gd").new()
	runner.set("tree", self)
	runner.set("drv", self)
	var fn := "scenario_" + scenario
	if runner.has_method(fn):
		await runner.call(fn)
	else:
		print("unknown scenario ", scenario)
		failures.append("unknown scenario")
	_finish()

func _finish() -> void:
	for e in counter.errors:
		print("[ERROR] ", e)
	var ok := failures.is_empty() and counter.errors.is_empty()
	print("E2E RESULT: %s (%d failures, %d errors, %d screenshots)" % ["PASS" if ok else "FAIL", failures.size(), counter.errors.size(), shots])
	quit(0 if ok else 1)

