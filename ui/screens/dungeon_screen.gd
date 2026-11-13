extends UIScreen

var party_id: String = "P1"
var floor_num: int = 1
var initialized: bool = false

func _init() -> void:
	screen_title = "Dungeon Command Center"

func build() -> void:
	if params.has("party_id"):
		party_id = String(params["party_id"])
	if not initialized:
		initialized = true
		floor_num = int(params.get("floor", Master.current_floor))
		if int(params.get("last_entered", 0)) == floor_num and Master.highest_floor >= floor_num:
			floor_num = _max_floor()   # just cleared it: move on to the next floor
	floor_num = clampi(floor_num, 1, _max_floor())
	var sc := UIKit.scroll()
	add_child(sc)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(root)

	var t := UIKit.card(root)
	t.add_child(UIKit.label("Tower of Rebirth", 32, UIKit.C_ACCENT))
	t.add_child(UIKit.label("Highest floor %d / 100 · Rank %s" % [Master.highest_floor, Master.rank().get("rank", "F")], 22, UIKit.C_DIM))
	var nav := HBoxContainer.new()
	var prev := UIKit.button("◀", _step.bind(-1), 76)
	prev.disabled = floor_num <= 1
	nav.add_child(prev)
	nav.add_child(UIKit.label("Floor %d" % floor_num, 34, UIKit.C_TEXT, true))
	var nxt := UIKit.button("▶", _step.bind(1), 76)
	nxt.disabled = floor_num >= _max_floor()
	nav.add_child(nxt)
	t.add_child(nav)

	var f: Dictionary = Database.get_floor(floor_num)
	var kind: String = {"pawn": "Pawns", "mind_boss": "Mind Boss", "floor_boss": "Floor Boss"}.get(f["type"], f["type"])
	if f["final"]:
		kind = "FINAL CHALLENGE"
	var names: Array = []
	for x in f["enemies"]:
		var info: Dictionary = Fairy.bestiary_entry(x["enemy"])
		names.append("%s ×%d" % [info["name"], int(x["qty"])])
	t.add_child(UIKit.label("%s · %s region · difficulty ×%s" % [kind, f["region_element"], str(f["scale"])], 24, UIKit.element_color(f["region_element"])))
	t.add_child(UIKit.label("Enemies: " + ", ".join(names) + ("\n(??? = Fairy has not met them yet)" if "???" in ", ".join(names) else ""), 22, UIKit.C_TEXT))
	var rw: Dictionary = f["rewards"]
	t.add_child(UIKit.label("Rewards: %d Gold, %d EXP per surviving Hero%s" % [int(rw["gold"]), int(rw["exp"]),
		(", %d Gems (first clear)" % int(rw["first_clear_gems"])) if int(rw["first_clear_gems"]) > 0 and floor_num > Master.highest_floor else ""], 22, UIKit.C_DIM))

	var p := UIKit.card(root)
	p.add_child(UIKit.button("Party: %s — tap to change" % party_id, _choose_party, 76))
	p.add_child(UIKit.label(Parties.describe(party_id).replace(" | ", "\n"), 20, UIKit.C_DIM))
	p.add_child(UIKit.button("Ask Fairy: risk analysis", _ask_fairy, 84))
	p.add_child(UIKit.button("Enter Tower", _enter, 100))

	for name in ["Raid Boss", "Rift Star", "Explore Dungeon"]:
		var c := UIKit.card(root)
		c.add_child(UIKit.label("%s — Coming soon" % name, 26, UIKit.C_DIM))

func _max_floor() -> int:
	return mini(int(Database.tower_rules["floors"]), Master.highest_floor + 1)

func _step(d: int) -> void:
	floor_num = clampi(floor_num + d, 1, _max_floor())
	params["floor"] = floor_num
	rebuild()

func _choose_party() -> void:
	var items: Array = []
	for pid in Parties.parties:
		var n: int = Parties.hero_ids(pid).size()
		items.append({"text": "%s — %d/5 Heroes%s" % [pid, n, " (busy)" if Town.party_busy(pid) != "" else ""], "value": pid, "disabled": n == 0})
	app.picker("Choose Party", items, _on_party)

func _on_party(v) -> void:
	party_id = String(v)
	params["party_id"] = party_id
	rebuild()

func _ask_fairy() -> void:
	app.toast("%s is running the numbers…" % Fairy.fairy_name)
	await get_tree().process_frame
	await get_tree().process_frame
	var r: Dictionary = Fairy.analyze_risk(party_id, floor_num)
	if not r["ok"]:
		app.dialog("Fairy", r.get("text", "I cannot analyse this: %s." % r["reason"]))
		return
	var head: String = "Risk: %s\nWin %d%% · someone falls %d%% (from %d simulated battles)\n\n" % [r["label"], roundi(r["win_rate"] * 100.0), roundi(r["p_death"] * 100.0), int(r["runs"])]
	app.dialog("Fairy's analysis", head + r["text"])

func _enter() -> void:
	var why: String = ""
	if Town.party_busy(party_id) != "":
		why = "This Party is busy in a facility."
	elif not Parties.battle_ready(party_id)["ok"]:
		why = "This Party has no healthy Hero. Rest first, or choose another Party."
	if why != "":
		app.toast(why, UIKit.C_WARN)
		return
	var w: Dictionary = Athanatos.lethal_warning(party_id)
	var key: String = "%s:%d" % [party_id, floor_num]
	var extra: String = ""
	if Fairy.predictions.has(key):
		extra = "\n\nFairy's last estimate for this Party: %s risk." % Fairy.predictions[key]["label"]
	app.confirm("Permanent death!", w["text"] + extra, _start, "Enter Floor %d" % floor_num, "Turn back")

func _start() -> void:
	var eng: BattleEngine = BattleRunner.create_tower_battle(party_id, floor_num, Roster.rng, true)
	if eng == null:
		app.toast("Cannot enter this floor.", UIKit.C_BAD)
		return
	params["floor"] = floor_num
	params["last_entered"] = floor_num
	app.go("battle", {"engine": eng, "floor": floor_num})
