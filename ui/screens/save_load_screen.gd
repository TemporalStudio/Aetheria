extends UIScreen

func _init() -> void:
	screen_title = "Load / Save"
	show_header = false

func build() -> void:
	var sc := UIKit.scroll()
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var in_game: bool = Master.master_name != ""
	for slot in range(0, SaveSystem.SLOT_COUNT + 1):
		var info: Dictionary = SaveSystem.slot_info(slot)
		var c := UIKit.card(list)
		c.add_child(UIKit.label("Autosave" if slot == 0 else "Slot %d" % slot, 30, UIKit.C_ACCENT))
		if info.get("exists", false):
			c.add_child(UIKit.label("%s · Rank %s · Day %d\n%d Heroes · %d memorials · %s" % [info["master_name"], info["rank"], int(info["day"]),
				int(info["heroes"]), int(info["memorials"]), String(info["saved_at"]).replace("T", " ")], 24, UIKit.C_TEXT))
		else:
			c.add_child(UIKit.label("Empty", 24, UIKit.C_DIM))
		var row := HBoxContainer.new()
		c.add_child(row)
		if slot > 0:
			var save_b := UIKit.button("Save", _save.bind(slot, info.get("exists", false)), 72)
			save_b.disabled = not in_game
			row.add_child(save_b)
		var load_b := UIKit.button("Load", _load.bind(slot), 72)
		load_b.disabled = not info.get("exists", false)
		row.add_child(load_b)
		var del_b := UIKit.button("Delete", _delete.bind(slot), 72)
		del_b.disabled = not info.get("exists", false)
		row.add_child(del_b)

func _save(slot: int, exists: bool) -> void:
	if exists:
		app.confirm("Overwrite?", "Slot %d already has a save. Overwrite it?" % slot, _do_save.bind(slot), "Overwrite")
	else:
		_do_save(slot)

func _do_save(slot: int) -> void:
	if SaveSystem.save_slot(slot):
		app.toast("Saved to slot %d." % slot, UIKit.C_GOOD)
	else:
		app.toast("Save failed.", UIKit.C_BAD)
	rebuild()

func _load(slot: int) -> void:
	var warn: Dictionary = SaveSystem.rollback_warning(slot) if Master.master_name != "" else {}
	if warn.get("warn", false):
		app.confirm("Warning: fallen Heroes", "This save has %d memorial(s) but your current game has %d.\nLoading it will ERASE %d death record(s): those Heroes will be alive again in this save, and everything after it is lost.\nContinue?" % [
			int(warn["memorials_in_slot"]), int(warn["memorials_now"]), int(warn["loses_memorials"])], _do_load.bind(slot), "Load anyway")
	else:
		_do_load(slot)

func _do_load(slot: int) -> void:
	if SaveSystem.load_slot(slot):
		app.go_root("hub")
		app.toast("Loaded.", UIKit.C_GOOD)
	else:
		app.toast("Could not load this slot.", UIKit.C_BAD)

func _delete(slot: int) -> void:
	app.confirm("Delete save?", "Delete this save permanently?", _do_delete.bind(slot), "Delete")

func _do_delete(slot: int) -> void:
	SaveSystem.delete_slot(slot)
	rebuild()
