extends UIScreen

var hero_id: String = ""

func _init() -> void:
	screen_title = "Hero"

func build() -> void:
	hero_id = String(params["hero_id"])
	var h: Dictionary = Roster.get_hero(hero_id)
	if h.is_empty():
		add_child(UIKit.label("This Hero is no longer in the roster.", 26, UIKit.C_DIM))
		return
	var sc := UIKit.scroll()
	add_child(sc)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(root)
	var st: Dictionary = HeroStats.compute(h)

	var c := UIKit.card(root)
	c.add_child(UIKit.label(h["name"], 40, UIKit.element_color(h["element"])))
	var house: String = ""
	if h["noble"] != null:
		house = " · " + Database.get_entry("nobles", h["noble"])["name"]
	c.add_child(UIKit.label("%s · %s · %d★ Lv%d" % [h["role"], h["element"], int(h["star"]), int(h["level"])], 26, UIKit.C_TEXT))
	c.add_child(UIKit.label("%s %s, age %d%s" % [h["race"], h["gender"], int(h["age"]), house], 22, UIKit.C_DIM))
	c.add_child(UIKit.label("ID %s · %s" % [h["id"], UIKit.hero_status(hero_id)], 22, UIKit.C_DIM))
	var cap: int = Database.level_cap_for_star(int(h["star"]))
	var need: int = Database.exp_to_next(int(h["level"]))
	c.add_child(UIKit.label("Level %d / %d" % [int(h["level"]), cap], 24))
	c.add_child(UIKit.bar(int(h["exp"]) if int(h["level"]) < cap else 1, need if int(h["level"]) < cap else 1, UIKit.C_ACCENT, 16))
	c.add_child(UIKit.label("HP %d / %d" % [int(h["hp"]), int(st["max_hp"])], 24))
	c.add_child(UIKit.bar(int(h["hp"]), int(st["max_hp"]), UIKit.C_GOOD))
	c.add_child(UIKit.label("SP %d / %d" % [int(h["sp"]), int(h["sp_max"])], 24))
	c.add_child(UIKit.bar(int(h["sp"]), int(h["sp_max"]), UIKit.C_ACCENT))

	var s := UIKit.card(root)
	s.add_child(UIKit.label("Stats", 28, UIKit.C_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	s.add_child(grid)
	for k in ["max_hp", "phys_atk", "magic_atk", "phys_def", "magic_def", "speed", "crit", "evasion", "accuracy"]:
		var extra: String = ""
		var tb: int = int(h["training_bonus"].get(k, 0))
		if tb > 0:
			extra = "  (+%d trained)" % tb
		grid.add_child(UIKit.label("%s  %s%s" % [UIKit.stat_name(k), str(st[k]), extra], 24))

	var kc := UIKit.card(root)
	kc.add_child(UIKit.label("Skills", 28, UIKit.C_ACCENT))
	for sid in h["skills"]:
		var sk: Dictionary = Database.get_entry("basic_skills", sid)
		kc.add_child(UIKit.label("%s\n%s" % [sk["name"], UIKit.skill_text(sk)], 22, UIKit.C_TEXT))
	if h["ultimate"] != null:
		var u: Dictionary = Database.get_entry("ultimate_skills", h["ultimate"])
		kc.add_child(UIKit.label("ULTIMATE: %s\n%s" % [u["name"], UIKit.ultimate_text(u)], 22, UIKit.C_WARN))
	else:
		kc.add_child(UIKit.label("Ultimate unlocks at 4★", 22, UIKit.C_DIM))
	kc.add_child(UIKit.label("Traits", 28, UIKit.C_ACCENT))
	for tid in h["traits"]:
		var t: Dictionary = Database.get_entry("traits", tid)
		kc.add_child(UIKit.label("%s — %s" % [t["name"], t["description"]], 22, UIKit.C_TEXT))
	var ts: Dictionary = Database.get_entry("town_skills", h["town_skill"])
	kc.add_child(UIKit.label("Town Skill: %s (%s, as %s)" % [ts["name"], ts["facility"], ts["works_as"]], 22, UIKit.C_TEXT))

	var e := UIKit.card(root)
	e.add_child(UIKit.label("Equipment", 28, UIKit.C_ACCENT))
	for slot in ["weapon", "armor", "accessory"]:
		var cur = h["equipment"].get(slot)
		e.add_child(UIKit.left_button("%s: %s" % [slot.capitalize(), UIKit.item_name(cur) if cur != null else "— empty —"], _pick_equipment.bind(slot), 76))

	var p := UIKit.card(root)
	p.add_child(UIKit.label("Star Promotion", 28, UIKit.C_ACCENT))
	if int(h["star"]) >= 5:
		p.add_child(UIKit.label("Maximum Star reached.", 22, UIKit.C_DIM))
	else:
		var info: Dictionary = Database.get_entry("star_progression", "STAR-%d" % int(h["star"]))
		var promo: Dictionary = info["promotion"]
		var mats: Array = []
		for m in promo["materials"]:
			mats.append("%s ×%d (have %d)" % [UIKit.item_name(m["item"]), int(m["qty"]), Inventory.count(m["item"])])
		p.add_child(UIKit.label("Needs Level %d. Cost: %d Gold, %s.\nPromotion keeps the Level and opens more skill/trait slots." % [int(info["level_cap"]), int(promo["gold"]), ", ".join(mats)], 22, UIKit.C_TEXT))
		var b := UIKit.button("Promote to %d★" % (int(h["star"]) + 1), _promote, 80)
		b.disabled = Roster.promotion_cost(hero_id).is_empty()
		p.add_child(b)

func _pick_equipment(slot: String) -> void:
	var h: Dictionary = Roster.get_hero(hero_id)
	var items: Array = []
	if h["equipment"].get(slot) != null:
		items.append({"text": "Unequip " + UIKit.item_name(h["equipment"][slot]), "value": "__unequip"})
	for id in Inventory.items:
		if Database.has_id("equipment", id) and Database.get_entry("equipment", id)["slot"] == slot:
			var eq: Dictionary = Database.get_entry("equipment", id)
			var stats: Array = []
			for k in eq["stats"]:
				stats.append("%s +%s" % [UIKit.stat_name(k), str(eq["stats"][k])])
			items.append({"text": "%s ×%d\n%s" % [eq["name"], Inventory.count(id), ", ".join(stats)], "value": id})
	app.picker("Choose %s" % slot, items, _on_equip.bind(slot))

func _on_equip(value, slot: String) -> void:
	if String(value) == "__unequip":
		Roster.unequip(hero_id, slot)
	else:
		Roster.equip(hero_id, String(value))
	rebuild()

func _promote() -> void:
	var r: Dictionary = Roster.promote_paid(hero_id)
	if r["ok"]:
		app.toast("Promoted!", UIKit.C_GOOD)
	else:
		app.toast("Cannot promote: you need more Gold or materials.", UIKit.C_WARN)
	rebuild()
