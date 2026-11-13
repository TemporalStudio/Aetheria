extends UIScreen

var tab: int = 0
const TABS := ["Skills", "Ultimates", "Traits", "Equip", "Medical", "Materials", "Bestiary"]

func _init() -> void:
	screen_title = "Data Base"

func build() -> void:
	var rows := VBoxContainer.new()
	var r1 := HBoxContainer.new()
	var r2 := HBoxContainer.new()
	for i in TABS.size():
		var b := UIKit.button(TABS[i], _set_tab.bind(i), 56)
		b.add_theme_font_size_override("font_size", 22)
		if i == tab:
			b.add_theme_stylebox_override("normal", UIKit.box(UIKit.C_ACCENT.darkened(0.4), 14, UIKit.C_ACCENT, 2, 10))
		(r1 if i < 4 else r2).add_child(b)
	rows.add_child(r1)
	rows.add_child(r2)
	add_child(rows)
	var sc := UIKit.scroll()
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	match tab:
		0:
			for s in Database.all_entries("basic_skills"):
				_row(list, "%s  [%s] %s" % [s["name"], s["element"], s["id"]], UIKit.skill_text(s), UIKit.element_color(s["element"]))
		1:
			for u in Database.all_entries("ultimate_skills"):
				_row(list, "%s  [%s] %s" % [u["name"], u["element"], u["id"]], UIKit.ultimate_text(u) + " · needs 4★", UIKit.element_color(u["element"]))
		2:
			for t in Database.all_entries("traits"):
				_row(list, "%s  [%s]" % [t["name"], t["element"]], t["description"], UIKit.element_color(t["element"]))
		3:
			for e in Database.all_entries("equipment"):
				var parts: Array = []
				for k in e["stats"]:
					parts.append("%s +%s" % [UIKit.stat_name(k), str(e["stats"][k])])
				_row(list, e["name"], "%s · tier %d · %s" % [e["slot"], int(e["tier"]), ", ".join(parts)], UIKit.C_TEXT)
		4:
			for m in Database.all_entries("medical"):
				_row(list, m["name"], "%s · cannot revive" % m["type"], UIKit.C_TEXT)
		5:
			for m in Database.all_entries("materials"):
				_row(list, m["name"], "%s · %s" % [m["category"], m["source"]], UIKit.C_TEXT)
		_:
			list.add_child(UIKit.label("Only enemies the Fairy has met are shown.", 22, UIKit.C_DIM))
			for e in Database.all_entries("enemies"):
				var info: Dictionary = Fairy.bestiary_entry(e["id"])
				if info["known"]:
					var s: Dictionary = info["base_stats"]
					_row(list, info["name"], "%s · %s · HP %d ATK %d DEF %d SPD %d" % [String(info["type"]).capitalize(), info["element"], int(s["hp"]), int(s["atk"]), int(s["def"]), int(s["spd"])], UIKit.element_color(info["element"]))
				else:
					_row(list, "???", "Not yet encountered", UIKit.C_DIM)

func _row(list: VBoxContainer, title: String, sub: String, color: Color) -> void:
	var c := UIKit.card(list)
	c.add_child(UIKit.label(title, 24, color))
	c.add_child(UIKit.label(sub, 20, UIKit.C_DIM))

func _set_tab(i: int) -> void:
	tab = i
	rebuild()
