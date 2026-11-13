extends UIScreen

var role_filter: String = "All"
var sort_by: String = "star"

func _init() -> void:
	screen_title = "Hero Roster"

func build() -> void:
	var rf := HBoxContainer.new()
	for r in ["All", "Attacker", "Defender", "Healer", "Support"]:
		var b := UIKit.button(r if r == "All" else r.left(3), _set_role.bind(r), 60)
		if r == role_filter:
			b.add_theme_stylebox_override("normal", UIKit.box(UIKit.C_ACCENT.darkened(0.4), 14, UIKit.C_ACCENT, 2, 12))
		rf.add_child(b)
	add_child(rf)
	var sf := HBoxContainer.new()
	for s in [["star", "Star"], ["level", "Level"], ["name", "Name"]]:
		var b := UIKit.button("Sort: " + s[1], _set_sort.bind(s[0]), 60)
		if s[0] == sort_by:
			b.add_theme_stylebox_override("normal", UIKit.box(UIKit.C_ACCENT.darkened(0.4), 14, UIKit.C_ACCENT, 2, 12))
		sf.add_child(b)
	add_child(sf)
	var heroes: Array = []
	for h in Roster.heroes.values():
		if role_filter == "All" or h["role"] == role_filter:
			heroes.append(h)
	match sort_by:
		"level":
			heroes.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
		"name":
			heroes.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
		_:
			heroes.sort_custom(func(a, b): return int(a["star"]) * 1000 + int(a["level"]) > int(b["star"]) * 1000 + int(b["level"]))
	add_child(UIKit.label("%d Heroes" % heroes.size(), 22, UIKit.C_DIM))
	var sc := UIKit.scroll()
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if heroes.is_empty():
		list.add_child(UIKit.label("No Heroes here. Visit the Recruitment Portal.", 26, UIKit.C_DIM))
	for h in heroes:
		var row := HBoxContainer.new()
		var strip := ColorRect.new()
		strip.color = UIKit.element_color(h["element"])
		strip.custom_minimum_size = Vector2(12, 0)
		row.add_child(strip)
		var mx: int = int(HeroStats.compute(h)["max_hp"])
		row.add_child(UIKit.left_button("%s\n%s · HP %d/%d\n%s" % [UIKit.hero_line(h), h["race"], int(h["hp"]), mx, UIKit.hero_status(h["id"])],
			app.go.bind("hero_detail", {"hero_id": h["id"]}), 118))
		list.add_child(row)

func _set_role(r: String) -> void:
	role_filter = r
	rebuild()

func _set_sort(s: String) -> void:
	sort_by = s
	rebuild()
