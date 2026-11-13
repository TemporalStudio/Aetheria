extends UIScreen

var party_id: String = "P1"

func _init() -> void:
	screen_title = "Party"

func build() -> void:
	if params.has("party_id"):
		party_id = String(params["party_id"])
	add_child(UIKit.button("%s — tap to change Party" % party_id, _choose_party, 80))
	var busy: String = Town.party_busy(party_id)
	if busy != "":
		add_child(UIKit.label("This Party is busy in %s and cannot fight." % Database.get_entry("facilities", busy)["name"], 22, UIKit.C_WARN))
	var sc := UIKit.scroll()
	add_child(sc)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(root)
	var p: Dictionary = Parties.get_party(party_id)
	var c := UIKit.card(root)
	c.add_child(UIKit.label("Formation", 28, UIKit.C_ACCENT))
	for i in Parties.SLOTS:
		var pos: String = "Front" if i < Parties.FRONT_SLOTS else "Back"
		var hid = p["slots"][i]
		var text: String = "%s %d: — empty —" % [pos, i + 1]
		if hid != null:
			var h: Dictionary = Roster.get_hero(hid)
			text = "%s %d: %s\nHP %d/%d · SP %d/%d" % [pos, i + 1, UIKit.hero_line(h), int(h["hp"]), int(HeroStats.compute(h)["max_hp"]), int(h["sp"]), int(h["sp_max"])]
		c.add_child(UIKit.left_button(text, _pick_hero.bind(i), 100))
	var m := UIKit.card(root)
	m.add_child(UIKit.label("Medical Slots", 28, UIKit.C_ACCENT))
	for i in p["medical"].size():
		var mid = p["medical"][i]
		var t: String = "Slot %d: — empty —" % (i + 1)
		if mid != null:
			t = "Slot %d: %s ×%d" % [i + 1, UIKit.item_name(mid), Inventory.count(mid)]
		m.add_child(UIKit.left_button(t, _pick_medical.bind(i), 76))
	var a := UIKit.card(root)
	a.add_child(UIKit.button("Ask Fairy to suggest a Party", _suggest, 80))
	a.add_child(UIKit.button("Auto-fill empty slots", _autofill, 80))
	a.add_child(UIKit.button("Clear Party", _clear, 80))

func _choose_party() -> void:
	var items: Array = []
	for pid in Parties.parties:
		var n: int = Parties.hero_ids(pid).size()
		items.append({"text": "%s — %d/5 Heroes%s" % [pid, n, " (busy)" if Town.party_busy(pid) != "" else ""], "value": pid})
	app.picker("Choose Party", items, _on_party_chosen)

func _on_party_chosen(v) -> void:
	party_id = String(v)
	rebuild()

func _pick_hero(slot: int) -> void:
	var items: Array = []
	if Parties.get_party(party_id)["slots"][slot] != null:
		items.append({"text": "Remove from this slot", "value": "__clear"})
	for h in Roster.heroes.values():
		if Parties.is_available(h["id"]) or Parties.hero_party(h["id"]) == party_id:
			var low: bool = int(h["hp"]) <= 0
			items.append({"text": "%s\nHP %d/%d" % [UIKit.hero_line(h), int(h["hp"]), int(HeroStats.compute(h)["max_hp"])], "value": h["id"], "disabled": low})
	app.picker("Hero for slot %d" % (slot + 1), items, _on_hero.bind(slot))

func _on_hero(value, slot: int) -> void:
	if String(value) == "__clear":
		Parties.clear_slot(party_id, slot)
	elif not Parties.set_slot(party_id, slot, String(value)):
		app.toast("That Hero cannot join.", UIKit.C_WARN)
	rebuild()

func _pick_medical(index: int) -> void:
	var items: Array = [{"text": "Empty this slot", "value": "__clear"}]
	for id in Inventory.items:
		if Database.has_id("medical", id):
			var med: Dictionary = Database.get_entry("medical", id)
			items.append({"text": "%s ×%d\n%s" % [med["name"], Inventory.count(id), med["type"]], "value": id})
	app.picker("Medical slot %d" % (index + 1), items, _on_medical.bind(index))

func _on_medical(value, index: int) -> void:
	Parties.set_medical(party_id, index, null if String(value) == "__clear" else String(value))
	rebuild()

func _suggest() -> void:
	var s: Dictionary = Fairy.suggest_party(party_id)
	if not s["ok"]:
		app.dialog("Fairy", s["text"])
		return
	app.dialog("Fairy's suggestion", s["text"], [["Use this Party", _apply.bind(s)], ["Not now"]])

func _apply(s: Dictionary) -> void:
	Fairy.apply_suggestion(party_id, s)
	rebuild()

func _autofill() -> void:
	Parties.auto_fill(party_id)
	rebuild()

func _clear() -> void:
	for i in Parties.SLOTS:
		Parties.clear_slot(party_id, i)
	rebuild()
