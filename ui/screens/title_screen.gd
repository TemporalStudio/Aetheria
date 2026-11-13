extends UIScreen

func _init() -> void:
	show_header = false
	show_back = false

func build() -> void:
	add_child(UIKit.spacer(120))
	add_child(UIKit.label("AETHERIA", 84, UIKit.C_ACCENT, true))
	add_child(UIKit.label("The World After the End", 34, UIKit.C_DIM, true))
	add_child(UIKit.spacer(80))
	add_child(UIKit.button("New Game", func(): app.go("new_game"), 100))
	var latest: int = _latest_slot()
	var cont := UIKit.button("Continue", _continue.bind(latest), 100)
	cont.disabled = latest < 0
	add_child(cont)
	add_child(UIKit.button("Load / Save", func(): app.go("save_load"), 100))
	add_child(UIKit.button("Settings", func(): app.go("settings"), 100))
	add_child(UIKit.button("Exit", func(): get_tree().quit(), 100))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(fill)
	add_child(UIKit.label("Fantasy Hero Collection · Tactical RPG · Town Management", 22, UIKit.C_DIM, true))

func _latest_slot() -> int:
	var best: int = -1
	var best_t: String = ""
	for i in range(0, SaveSystem.SLOT_COUNT + 1):
		var info: Dictionary = SaveSystem.slot_info(i)
		if info.get("exists", false) and String(info["saved_at"]) > best_t:
			best_t = String(info["saved_at"])
			best = i
	return best

func _continue(slot: int) -> void:
	if SaveSystem.load_slot(slot):
		app.go_root("hub")
	else:
		app.toast("Could not load the save.", UIKit.C_BAD)
