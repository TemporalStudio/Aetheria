extends UIScreen

var fid: String = ""

func _init() -> void:
	screen_title = "Facility"

func build() -> void:
	fid = String(params["facility"])
	var st: Dictionary = Town.status(fid)
	var sc := UIKit.scroll()
	add_child(sc)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(root)
	var c := UIKit.card(root)
	c.add_child(UIKit.label("%s — Rank %s (Lv %d)" % [st["name"], st["rank"], int(st["level"])], 32, UIKit.C_ACCENT))
	c.add_child(UIKit.label(Database.get_entry("facilities", fid)["function"], 22, UIKit.C_DIM))
	var state: String = "WORKING" if st["operational"] else "IDLE — needs a Leader and at least 1 Staff"
	if Master.town_state() == "panicked":
		state = "STOPPED — the Town is Panicked"
	c.add_child(UIKit.label(state, 24, UIKit.C_GOOD if st["operational"] else UIKit.C_WARN))
	var bonuses: Dictionary = Town.facility_bonuses(fid)
	if not bonuses.is_empty():
		var bt: Array = []
		for k in bonuses:
			bt.append("%s %s" % [k, str(snappedf(float(bonuses[k]), 0.01))])
		c.add_child(UIKit.label("Staff bonuses: " + ", ".join(bt), 22, UIKit.C_TEXT))

	var w := UIKit.card(root)
	w.add_child(UIKit.label("Leader & Staff", 28, UIKit.C_ACCENT))
	w.add_child(UIKit.left_button("Leader: %s" % (Roster.get_hero(st["leader"]).get("name", "?") if st["leader"] != null else "— empty —"), _pick_worker.bind("leader"), 76))
	for i in 2:
		var label: String = "Staff %d: —" % (i + 1)
		if i < st["staff"].size():
			label = "Staff %d: %s" % [i + 1, Roster.get_hero(st["staff"][i]).get("name", "?")]
		w.add_child(UIKit.left_button(label, _pick_worker.bind("staff"), 76))
	w.add_child(UIKit.label("Heroes working here cannot be in a Party.", 20, UIKit.C_DIM))

	if fid in Town.PARTY_FACILITIES:
		var p := UIKit.card(root)
		p.add_child(UIKit.label("Parties (%d/%d)" % [st["parties"].size(), st["party_capacity"]], 28, UIKit.C_ACCENT))
		for pid in st["parties"]:
			p.add_child(UIKit.left_button("%s · %d Heroes — tap to remove" % [pid, Parties.hero_ids(pid).size()], _remove_party.bind(pid), 76))
		p.add_child(UIKit.button("Assign a Party", _pick_party, 76))

	var up := UIKit.card(root)
	var cost: Dictionary = Town.upgrade_cost(fid)
	if cost.is_empty():
		up.add_child(UIKit.label("Maximum rank reached.", 24, UIKit.C_DIM))
	else:
		up.add_child(UIKit.label("Upgrade to rank %s: %s" % [Town.rank_letter(int(st["level"]) + 1), UIKit.cost_text(cost)], 24, UIKit.C_TEXT))
		var ub := UIKit.button("Upgrade", _upgrade, 80)
		ub.disabled = not Master.can_afford(cost)
		up.add_child(ub)

	if fid in ["FAC-SMITH", "FAC-MAGIC"]:
		var station: String = "blacksmith" if fid == "FAC-SMITH" else "magic_tower"
		var cr := UIKit.card(root)
		cr.add_child(UIKit.label("Crafting", 28, UIKit.C_ACCENT))
		for r in Database.all_entries("recipes"):
			if r["station"] != station:
				continue
			var out_name: String = UIKit.item_name(r["output"])
			var locked: bool = int(r["facility_level_min"]) > int(st["level"])
			var chance: int = roundi(float(r["base_success"]) * 100.0)
			var b := UIKit.left_button("%s%s\n%s · success %d%%%s" % [out_name, "  (needs rank %s)" % Town.rank_letter(int(r["facility_level_min"])) if locked else "", UIKit.inputs_text(r["inputs"]), chance, ""], _craft.bind(r["id"]), 100)
			b.disabled = locked or not Inventory.has_items(r["inputs"])
			cr.add_child(b)

func _pick_worker(role: String) -> void:
	var items: Array = []
	var st: Dictionary = Town.status(fid)
	items.append({"text": "Remove from post…", "value": "__none"})
	for h in Roster.heroes.values():
		var here: bool = h.get("assignment") != null and h["assignment"]["facility"] == fid
		if Parties.hero_party(h["id"]) != "" or (h.get("assignment") != null and not here):
			continue
		var ts: Dictionary = Database.get_entry("town_skills", h["town_skill"])
		items.append({"text": "%s\nTown Skill: %s (%s)" % [UIKit.hero_line(h), ts["name"], ts["facility"]], "value": h["id"]})
	app.picker("Choose %s" % role, items, _on_worker.bind(role))

func _on_worker(value, role: String) -> void:
	if String(value) == "__none":
		_pick_remove()
		return
	var r: Dictionary = Town.assign_worker(fid, String(value), role)
	if not r["ok"]:
		app.toast("Cannot assign: %s" % r["reason"], UIKit.C_WARN)
	rebuild()

func _pick_remove() -> void:
	var st: Dictionary = Town.status(fid)
	var items: Array = []
	if st["leader"] != null:
		items.append({"text": "Leader: " + Roster.get_hero(st["leader"]).get("name", "?"), "value": st["leader"]})
	for s in st["staff"]:
		items.append({"text": "Staff: " + Roster.get_hero(s).get("name", "?"), "value": s})
	app.picker("Remove who?", items, _on_remove)

func _on_remove(value) -> void:
	Town.unassign_worker(String(value))
	rebuild()

func _pick_party() -> void:
	var items: Array = []
	for pid in Parties.parties:
		if Parties.hero_ids(pid).is_empty():
			continue
		var busy: String = Town.party_busy(pid)
		items.append({"text": "%s · %d Heroes%s" % [pid, Parties.hero_ids(pid).size(), " (busy)" if busy != "" else ""], "value": pid, "disabled": busy != ""})
	app.picker("Assign which Party?", items, _on_party)

func _on_party(value) -> void:
	var r: Dictionary = Town.assign_party(fid, String(value))
	if not r["ok"]:
		app.toast("Cannot assign: %s" % r["reason"], UIKit.C_WARN)
	rebuild()

func _remove_party(pid: String) -> void:
	Town.unassign_party(pid)
	rebuild()

func _upgrade() -> void:
	var r: Dictionary = Town.upgrade(fid)
	app.toast("Upgraded!" if r["ok"] else "Cannot upgrade.", UIKit.C_GOOD if r["ok"] else UIKit.C_WARN)
	rebuild()

func _craft(recipe_id: String) -> void:
	var r: Dictionary = Town.craft(recipe_id, Roster.rng)
	if not r["ok"]:
		var why: String = {"not_operational": "The facility is not working.", "missing_materials": "Missing materials.", "facility_level": "Facility rank too low."}.get(r["reason"], r["reason"])
		app.toast(why, UIKit.C_WARN)
	elif r["success"]:
		app.toast("Crafted %s!" % UIKit.item_name(r["output"]), UIKit.C_GOOD)
	else:
		app.toast("The attempt failed. Materials were lost.", UIKit.C_BAD)
	rebuild()
