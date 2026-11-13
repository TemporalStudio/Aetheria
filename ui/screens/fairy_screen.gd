extends UIScreen

var tab: int = 0

func _init() -> void:
	screen_title = "Fairy"

func build() -> void:
	var c := UIKit.card(self, Color("232a40"))
	c.add_child(UIKit.label("%s · %s" % [Fairy.fairy_name, Fairy.personality], 32, UIKit.C_ACCENT))
	c.add_child(UIKit.label("Mood: %s" % Fairy.mood_label().capitalize(), 24, UIKit.C_TEXT))
	var tr := HBoxContainer.new()
	tr.add_child(UIKit.label("Trust %d" % Fairy.trust, 22, UIKit.C_DIM))
	tr.add_child(UIKit.bar(Fairy.trust, 100, UIKit.C_ACCENT))
	c.add_child(tr)
	add_child(UIKit.tab_row(["Advice", "Memories", "Mistakes", "Bestiary"], tab, _set_tab))
	var sc := UIKit.scroll()
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	match tab:
		0:
			_advice(list)
		1:
			_memories(list)
		2:
			_mistakes(list)
		_:
			_bestiary(list)

func _set_tab(i: int) -> void:
	tab = i
	rebuild()

func _advice(list: VBoxContainer) -> void:
	var b: Dictionary = Fairy.town_briefing()
	var c := UIKit.card(list)
	c.add_child(UIKit.label("Town briefing", 26, UIKit.C_ACCENT))
	c.add_child(UIKit.label(b["text"], 24, UIKit.C_TEXT))
	var p := UIKit.card(list)
	p.add_child(UIKit.label("Party advice", 26, UIKit.C_ACCENT))
	p.add_child(UIKit.label("She builds the best Party from available Heroes and can estimate the risk of a Tower floor with real simulated battles.", 22, UIKit.C_DIM))
	p.add_child(UIKit.button("Suggest a Party", _pick_party, 80))
	p.add_child(UIKit.button("Risk analysis (go to Dungeon)", app.go.bind("dungeon"), 80))

func _pick_party() -> void:
	var items: Array = []
	for pid in Parties.parties:
		items.append({"text": "%s — %d/5 Heroes" % [pid, Parties.hero_ids(pid).size()], "value": pid})
	app.picker("Suggest for which Party?", items, _suggest)

func _suggest(pid) -> void:
	var s: Dictionary = Fairy.suggest_party(String(pid), Master.current_floor)
	if not s["ok"]:
		app.dialog("Fairy", s["text"])
		return
	app.dialog("Fairy's suggestion for %s" % pid, s["text"], [["Use this Party", _apply.bind(String(pid), s)], ["Not now"]])

func _apply(pid: String, s: Dictionary) -> void:
	Fairy.apply_suggestion(pid, s)
	app.toast("Party updated.", UIKit.C_GOOD)

func _memories(list: VBoxContainer) -> void:
	if Fairy.memories.is_empty():
		list.add_child(UIKit.label("Nothing to remember yet.", 24, UIKit.C_DIM))
	for i in range(Fairy.memories.size() - 1, -1, -1):
		var m: Dictionary = Fairy.memories[i]
		var c := UIKit.card(list)
		c.add_child(UIKit.label("Day %d · %s" % [int(m["day"]), String(m["type"]).capitalize()], 20, UIKit.C_DIM))
		c.add_child(UIKit.label(m["text"], 22, UIKit.C_TEXT))
		if i < Fairy.memories.size() - 40:
			break

func _mistakes(list: VBoxContainer) -> void:
	if Fairy.mistakes.is_empty():
		list.add_child(UIKit.label("She has not been wrong yet.", 24, UIKit.C_DIM))
	for i in range(Fairy.mistakes.size() - 1, -1, -1):
		var m: Dictionary = Fairy.mistakes[i]
		var c := UIKit.card(list)
		c.add_child(UIKit.label("Day %d · Floor %d · predicted %s" % [int(m["day"]), int(m["floor"]), m["predicted"]], 20, UIKit.C_DIM))
		c.add_child(UIKit.label(m["what"], 22, UIKit.C_TEXT))

func _bestiary(list: VBoxContainer) -> void:
	var seen: int = Fairy.knowledge["enemies_seen"].size()
	list.add_child(UIKit.label("Enemies met: %d / %d" % [seen, Database.all_entries("enemies").size()], 22, UIKit.C_DIM))
	for e in Database.all_entries("enemies"):
		var info: Dictionary = Fairy.bestiary_entry(e["id"])
		if info["known"]:
			list.add_child(UIKit.left_button("%s\n%s · %s" % [info["name"], String(info["type"]).capitalize(), info["element"]], _show_enemy.bind(e["id"]), 84))
		else:
			var b := UIKit.left_button("???", Callable(), 64)
			b.disabled = true
			list.add_child(b)

func _show_enemy(id: String) -> void:
	var info: Dictionary = Fairy.bestiary_entry(id)
	var s: Dictionary = info["base_stats"]
	app.dialog(info["name"], "%s · %s\nHP %d · ATK %d · DEF %d · SPD %d (base, before floor scaling)\nSkills: %s" % [
		String(info["type"]).capitalize(), info["element"], int(s["hp"]), int(s["atk"]), int(s["def"]), int(s["spd"]), ", ".join(info["skills"])])
