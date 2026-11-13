extends UIScreen

func _init() -> void:
	show_back = false

func build() -> void:
	var sc := UIKit.scroll()
	add_child(sc)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(root)

	# Master status
	var rk: Dictionary = Master.rank()
	var avail: int = 0
	var in_party: int = 0
	for id in Roster.heroes:
		if Parties.is_available(id):
			avail += 1
	var used: int = 0
	for pid in Parties.parties:
		var n: int = Parties.hero_ids(pid).size()
		in_party += n
		if n > 0:
			used += 1
	var c := UIKit.card(root)
	c.add_child(UIKit.label("Master Status", 30, UIKit.C_ACCENT))
	c.add_child(UIKit.label("%s (%s)\nRank %s — %s\nTower: highest floor %d · current floor %d\nHeroes: %d total · %d available · %d in Parties\nParties in use: %d / %d" % [
		Master.master_name, Master.master_id, rk.get("rank", "F"), rk.get("title", ""), Master.highest_floor, Master.current_floor,
		Roster.active_count(), avail, in_party, used, Parties.PARTY_COUNT], 24, UIKit.C_TEXT))
	c.add_child(UIKit.label("Town: %s" % Master.town_state().capitalize(), 24, UIKit.C_DIM))
	var hb := HBoxContainer.new()
	hb.add_child(UIKit.label("Happiness %d" % Master.town_happiness, 22, UIKit.C_GOOD))
	hb.add_child(UIKit.bar(Master.town_happiness, 100, UIKit.C_GOOD))
	c.add_child(hb)
	var fb := HBoxContainer.new()
	fb.add_child(UIKit.label("Fear %d" % Master.town_fear, 22, UIKit.C_BAD))
	fb.add_child(UIKit.bar(Master.town_fear, 100, UIKit.C_BAD))
	c.add_child(fb)

	# Fairy
	var f := UIKit.card(root, Color("232a40"))
	var brief: Dictionary = Fairy.town_briefing()
	f.add_child(UIKit.label("%s (Fairy)" % Fairy.fairy_name, 26, UIKit.C_ACCENT))
	f.add_child(UIKit.label(brief["text"], 24, UIKit.C_TEXT))

	# Modules
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	var mods: Array = [["Hero Roster", "hero_roster"], ["Party", "party"], ["Recruitment", "recruitment"], ["Inventory", "inventory"],
		["Town Square", "town"], ["Dungeon", "dungeon"], ["Fairy", "fairy"], ["Athanatos", "athanatos"], ["Data Base", "database"], ["Load / Save", "save_load"]]
	for m in mods:
		var label: String = m[0]
		if m[1] == "athanatos" and Athanatos.count() > 0:
			label += " (%d)" % Athanatos.count()
		grid.add_child(UIKit.button(label, app.go.bind(m[1]), 110))
	grid.add_child(UIKit.button("Main Menu", func(): app.go_root("title"), 110))
