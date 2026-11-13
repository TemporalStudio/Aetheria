extends Node
## Autoload: multi-slot saves in user://saves/ (JSON). Writes via temp file + .bak backup.
## Athanatos: the roster section includes `reserved_ids` and `memorials`, so death records are always saved.

const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 1
const SLOT_COUNT := 5

func slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot

func collect() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"master": Master.to_save(),
		"inventory": Inventory.to_save(),
		"roster": Roster.to_save(),
		"parties": Parties.to_save(),
		"town": Town.to_save(),
		"fairy": Fairy.to_save(),
	}

func apply(d: Dictionary) -> void:
	Master.from_save(d["master"])
	Inventory.from_save(d.get("inventory", {}))
	Roster.from_save(d["roster"])
	Parties.from_save(d.get("parties", {}))
	Town.from_save(d.get("town", {}))
	Fairy.from_save(d.get("fairy", {}))
	for problem in Athanatos.verify_integrity():
		push_warning("Save integrity: " + problem)

func save_slot(slot: int) -> bool:
	if slot < 0 or slot > SLOT_COUNT:   # slot 0 = autosave
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path: String = slot_path(slot)
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write " + tmp)
		return false
	f.store_string(JSON.stringify(collect(), "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK

## Loads a slot; falls back to its .bak if the main file is missing/corrupt.
func load_slot(slot: int) -> bool:
	var path: String = slot_path(slot)
	var data: Dictionary = _read(path)
	if data.is_empty():
		data = _read(path + ".bak")
	if data.is_empty():
		push_error("No valid save in slot %d" % slot)
		return false
	if int(data["version"]) > SAVE_VERSION:
		push_error("Save is from a newer game version")
		return false
	apply(data)
	return true

func slot_info(slot: int) -> Dictionary:
	var d: Dictionary = _read(slot_path(slot))
	if d.is_empty():
		return {"slot": slot, "exists": false}
	var m: Dictionary = d["master"]
	var rk: Dictionary = Database.rank_for_floor(maxi(1, int(m["highest_floor"])))
	return {"slot": slot, "exists": true, "master_name": m["master_name"], "rank": rk.get("rank", "F"),
		"day": int(m["in_game_day"]), "heroes": d["roster"]["heroes"].size(), "memorials": d["roster"].get("memorials", []).size(), "saved_at": d["saved_at"]}

## Call BEFORE loading a slot. If it holds fewer memorials than the current game, loading would
## erase those deaths (GDD Bab 15.3: the game follows the loaded save), so the UI must warn the player.
func rollback_warning(slot: int) -> Dictionary:
	var d: Dictionary = _read(slot_path(slot))
	if d.is_empty():
		return {}
	var in_slot: int = d["roster"].get("memorials", []).size()
	var now: int = Roster.memorials.size()
	return {"slot": slot, "memorials_in_slot": in_slot, "memorials_now": now,
		"loses_memorials": maxi(0, now - in_slot), "warn": now > in_slot}

func delete_slot(slot: int) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(slot_path(slot) + suffix):
			DirAccess.remove_absolute(slot_path(slot) + suffix)

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = Database.normalize(parsed)
	if not (d.has("version") and d.has("master") and d.has("roster")):
		return {}
	return d
