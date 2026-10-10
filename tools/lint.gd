extends SceneTree
## Loads every GDScript in the project and reports parse/compile errors.
## godot --headless --path . -s res://tools/lint.gd

var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for root in ["res://scripts", "res://tools", "res://tests"]:
		_scan(root)
	print("lint: ", failures, " script(s) failed")
	quit(1 if failures > 0 else 0)

func _scan(dir_path: String) -> void:
	for d in DirAccess.get_directories_at(dir_path):
		_scan(dir_path + "/" + d)
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".gd"):
			var path: String = dir_path + "/" + f
			var s: Script = load(path)
			if s == null or not s.can_instantiate():
				print("  LINT FAIL ", path)
				failures += 1
