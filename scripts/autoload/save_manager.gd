extends Node
## Local career saves in user://saves. Three slots. Writes are atomic: data is
## written to a temp file, verified by re-parsing, the previous save is kept
## as a .bak, then the temp file replaces the main file. Loading falls back to
## the backup when the main file is missing or corrupt.

signal saved(slot: int, ok: bool, message: String)

const DIR := "user://saves"
const SLOTS := 3
const GAME_ID := "gridiron_dynasty"

var last_error: String = ""

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

func slot_path(slot: int) -> String:
	return "%s/career_%d.json" % [DIR, slot]

func backup_path(slot: int) -> String:
	return "%s/career_%d.bak.json" % [DIR, slot]

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(backup_path(slot))

func any_save() -> bool:
	for i in SLOTS:
		if has_save(i):
			return true
	return false

## Most recently written slot, or -1.
func latest_slot() -> int:
	var best := -1
	var best_t := -1
	for i in SLOTS:
		var info := slot_info(i)
		if info.is_empty():
			continue
		var tm := int(info.get("saved_at", 0))
		if tm > best_t:
			best_t = tm
			best = i
	return best

## Lightweight metadata for the slot picker (reads only the header fields).
func slot_info(slot: int) -> Dictionary:
	for path in [slot_path(slot), backup_path(slot)]:
		if not FileAccess.file_exists(path):
			continue
		var d := _read_json(path)
		if d.is_empty():
			continue
		var m: Dictionary = d.get("meta", {})
		m["saved_at"] = d.get("saved_at", 0)
		m["from_backup"] = path == backup_path(slot)
		return m
	return {}

func save_league(league: League, slot: int) -> bool:
	var ut := league.user_team()
	var meta := {
		"coach": league.coach_name, "team": ut.full_name(), "abbr": ut.abbr,
		"year": league.year, "week": league.week, "phase": int(league.phase),
		"record": ut.record_string(), "titles": league.history.get("champions", []).filter(func(c): return c.get("team", "") == ut.id).size(),
		"primary": ut.primary.to_html(false), "secondary": ut.secondary.to_html(false), "logo": ut.logo,
	}
	var doc := {
		"game": GAME_ID, "schema": League.SCHEMA_VERSION, "version": ProjectSettings.get_setting("application/config/version", "1.0.0"),
		"saved_at": int(Time.get_unix_time_from_system()), "meta": meta, "league": league.to_dict(),
	}
	var text := JSON.stringify(doc)
	var tmp := slot_path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail(slot, "Could not open save file for writing (%s)" % error_string(FileAccess.get_open_error()))
	f.store_string(text)
	f.close()
	# Verify what was written before replacing the old save.
	var check := _read_json(tmp)
	if check.is_empty() or check.get("game", "") != GAME_ID:
		DirAccess.remove_absolute(tmp)
		return _fail(slot, "Save verification failed; previous save kept")
	if FileAccess.file_exists(slot_path(slot)):
		if FileAccess.file_exists(backup_path(slot)):
			DirAccess.remove_absolute(backup_path(slot))
		DirAccess.rename_absolute(slot_path(slot), backup_path(slot))
	var err := DirAccess.rename_absolute(tmp, slot_path(slot))
	if err != OK:
		return _fail(slot, "Could not finalize save (%s)" % error_string(err))
	last_error = ""
	saved.emit(slot, true, "Career saved")
	return true

func _fail(slot: int, msg: String) -> bool:
	last_error = msg
	push_warning(msg)
	saved.emit(slot, false, msg)
	return false

## Returns a League or null (last_error explains why).
func load_league(slot: int) -> League:
	last_error = ""
	for path in [slot_path(slot), backup_path(slot)]:
		if not FileAccess.file_exists(path):
			continue
		var d := _read_json(path)
		var lg := _validate_and_build(d)
		if lg != null:
			if path == backup_path(slot):
				last_error = "Main save was damaged; restored from backup."
			return lg
	if last_error == "":
		last_error = "No valid save found in slot %d" % (slot + 1)
	return null

func _validate_and_build(d: Dictionary) -> League:
	if d.is_empty():
		last_error = "Save file is unreadable"
		return null
	if d.get("game", "") != GAME_ID:
		last_error = "Not a Gridiron Dynasty save"
		return null
	var schema := int(d.get("schema", 0))
	if schema > League.SCHEMA_VERSION:
		last_error = "Save was made by a newer version of the game"
		return null
	var ld: Dictionary = d.get("league", {})
	ld = migrate(ld, schema)
	var lg := League.from_dict(ld)
	if lg == null:
		last_error = "Save data is incomplete"
	return lg

## Upgrades older save data to the current schema.
func migrate(ld: Dictionary, from_schema: int) -> Dictionary:
	# Schema 1 is the first release; future migrations go here.
	return ld

func delete_slot(slot: int) -> void:
	for path in [slot_path(slot), backup_path(slot), slot_path(slot) + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

# ---------------------------------------------------------------- global records

const RECORDS_PATH := "user://records.json"

func load_records() -> Dictionary:
	var d := _read_json(RECORDS_PATH)
	if d.is_empty():
		d = {"careers": [], "best": {}}
	return d

func save_records(d: Dictionary) -> void:
	var f := FileAccess.open(RECORDS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "\t"))
