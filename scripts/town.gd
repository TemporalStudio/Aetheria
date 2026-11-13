extends Node
## Autoload `Town`: facilities, staff, party assignments, crafting access, Skip Day reports, Moral Dilemmas.
## Each facility needs 1 Leader + 1..2 Staff to work (GDD Bab 10). Levels: F (Lv1), D (Lv2), B (Lv3/MAX).
## Dormitory / Training Ground take whole PARTIES; Blacksmith / Magic Tower craft on demand.

const FAC_IDS := ["FAC-DORM", "FAC-TRAIN", "FAC-SMITH", "FAC-MAGIC"]
const PARTY_FACILITIES := ["FAC-DORM", "FAC-TRAIN"]
const STATION_FACILITY := {"blacksmith": "FAC-SMITH", "magic_tower": "FAC-MAGIC"}
const MAX_LEVEL := 3

var facilities: Dictionary = {}
var reports: Array = []            # newest last, max game_rules.skip_day_report_limit
var pending_dilemma: String = ""
var recent_dilemmas: Array = []

func _ready() -> void:
	reset()

func reset() -> void:
	facilities = {}
	for id in FAC_IDS:
		facilities[id] = {"level": 1, "leader": null, "staff": [], "parties": []}
	reports = []
	pending_dilemma = ""
	recent_dilemmas = []

# ============================== STATUS =======================================

func rank_letter(level: int) -> String:
	return String(Database.town_rules["level_names"][level - 1])

func capacity(fac_id: String) -> int:
	if not fac_id in PARTY_FACILITIES:
		return 0
	return int(Database.town_rules["party_capacity"][int(facilities[fac_id]["level"]) - 1])

## Needs a Leader and at least 1 Staff, and the Town must not be Panicked.
func is_operational(fac_id: String) -> bool:
	var f: Dictionary = facilities[fac_id]
	return f["leader"] != null and f["staff"].size() >= int(Database.rules["facility"]["min_staff"]) and Master.town_state() != "panicked"

func status(fac_id: String) -> Dictionary:
	var f: Dictionary = facilities[fac_id]
	return {"id": fac_id, "name": Database.get_entry("facilities", fac_id)["name"], "level": f["level"], "rank": rank_letter(int(f["level"])),
		"operational": is_operational(fac_id), "leader": f["leader"], "staff": f["staff"].duplicate(),
		"parties": f["parties"].duplicate(), "party_capacity": capacity(fac_id)}

func mental_modifiers() -> Dictionary:
	return Database.get_entry("mental_states", Master.town_state()).get("facility", {})

## Sum of Town Skill + Trait bonuses from this facility's Leader and Staff.
func facility_bonuses(fac_id: String) -> Dictionary:
	var out: Dictionary = {}
	var f: Dictionary = facilities[fac_id]
	var fname: String = Database.get_entry("facilities", fac_id)["name"]
	var crafting: bool = fac_id in ["FAC-SMITH", "FAC-MAGIC"]
	var workers: Array = []
	if f["leader"] != null:
		workers.append([f["leader"], "leader"])
	for s in f["staff"]:
		workers.append([s, "staff"])
	for w in workers:
		var hero: Dictionary = Roster.get_hero(w[0])
		if hero.is_empty():
			continue
		var ts: Dictionary = Database.get_entry("town_skills", hero["town_skill"])
		if not ts.is_empty() and (ts["facility"] == "any" or ts["facility"] == fname) and (ts["works_as"] == "both" or ts["works_as"] == w[1]):
			var k: String = ts["effect"]["stat"]
			out[k] = float(out.get(k, 0.0)) + float(ts["effect"]["value"])
		var mods: Dictionary = HeroStats.modifiers(hero)
		if mods.has("facility_efficiency"):
			out["facility_efficiency"] = float(out.get("facility_efficiency", 0.0)) + float(mods["facility_efficiency"])
		if crafting and mods.has("craft_success"):
			out["craft_success"] = float(out.get("craft_success", 0.0)) + float(mods["craft_success"])
	return out

# ============================== STAFF & PARTIES ==============================

func assign_worker(fac_id: String, hero_id: String, role: String) -> Dictionary:
	if not facilities.has(fac_id) or not role in ["leader", "staff"]:
		return {"ok": false, "reason": "bad_request"}
	var hero: Dictionary = Roster.get_hero(hero_id)
	if hero.is_empty() or hero["status"] != "active":
		return {"ok": false, "reason": "no_hero"}
	if Parties.hero_party(hero_id) != "":
		return {"ok": false, "reason": "in_party"}
	var f: Dictionary = facilities[fac_id]
	if role == "staff" and f["staff"].size() >= int(Database.rules["facility"]["max_staff"]) and not hero_id in f["staff"]:
		return {"ok": false, "reason": "staff_full"}
	unassign_worker(hero_id)
	if role == "leader":
		if f["leader"] != null:
			_free(f["leader"])
		f["leader"] = hero_id
	else:
		f["staff"].append(hero_id)
	hero["assignment"] = {"facility": fac_id, "role": role}
	return {"ok": true}

func unassign_worker(hero_id: String) -> void:
	for id in FAC_IDS:
		var f: Dictionary = facilities[id]
		if f["leader"] == hero_id:
			f["leader"] = null
		f["staff"].erase(hero_id)
	_free(hero_id)

func _free(hero_id: String) -> void:
	var h: Dictionary = Roster.get_hero(hero_id)
	if not h.is_empty():
		h["assignment"] = null

## Called when a Hero is buried (Athanatos).
func remove_hero(hero_id: String) -> void:
	unassign_worker(hero_id)

func party_busy(party_id: String) -> String:
	for id in PARTY_FACILITIES:
		if party_id in facilities[id]["parties"]:
			return id
	return ""

func assign_party(fac_id: String, party_id: String) -> Dictionary:
	if not fac_id in PARTY_FACILITIES or Parties.get_party(party_id).is_empty():
		return {"ok": false, "reason": "bad_request"}
	if Parties.hero_ids(party_id).is_empty():
		return {"ok": false, "reason": "empty_party"}
	if party_busy(party_id) != "":
		return {"ok": false, "reason": "already_assigned"}
	if facilities[fac_id]["parties"].size() >= capacity(fac_id):
		return {"ok": false, "reason": "capacity"}
	facilities[fac_id]["parties"].append(party_id)
	return {"ok": true}

func unassign_party(party_id: String) -> void:
	for id in PARTY_FACILITIES:
		facilities[id]["parties"].erase(party_id)

# ============================== UPGRADE & CRAFT ==============================

func upgrade_cost(fac_id: String) -> Dictionary:
	var lvl: int = int(facilities[fac_id]["level"])
	if lvl >= MAX_LEVEL:
		return {}
	return Database.town_rules["upgrade_cost"][str(lvl + 1)]

func upgrade(fac_id: String) -> Dictionary:
	var cost: Dictionary = upgrade_cost(fac_id)
	if cost.is_empty():
		return {"ok": false, "reason": "max_level"}
	if not Master.pay(cost):
		return {"ok": false, "reason": "cannot_afford"}
	facilities[fac_id]["level"] = int(facilities[fac_id]["level"]) + 1
	return {"ok": true, "level": facilities[fac_id]["level"]}

## Crafts at the right facility: must be operational; Leader/Staff bonuses add to the success chance.
func craft(recipe_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var r: Dictionary = Database.get_entry("recipes", recipe_id)
	if r.is_empty():
		return {"ok": false, "reason": "unknown_recipe"}
	var fac_id: String = STATION_FACILITY[r["station"]]
	if not is_operational(fac_id):
		return {"ok": false, "reason": "not_operational"}
	var bonus: float = float(facility_bonuses(fac_id).get("craft_success", 0.0)) * float(mental_modifiers().get("efficiency", 1.0))
	return Inventory.craft(recipe_id, int(facilities[fac_id]["level"]), rng, bonus)

# ============================== DILEMMAS & REPORTS ===========================

func add_report(report: Dictionary) -> void:
	reports.append(report)
	var limit: int = int(Database.rules["skip_day_report_limit"])
	while reports.size() > limit:
		reports.pop_front()

func pick_dilemma(rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for d in Database.all_entries("dilemmas"):
		if not d["id"] in recent_dilemmas:
			pool.append(d["id"])
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	recent_dilemmas.append(id)
	while recent_dilemmas.size() > int(Database.town_rules["dilemma_no_repeat"]):
		recent_dilemmas.pop_front()
	return id

## Applies the chosen option of the pending Moral Dilemma.
func resolve_dilemma(choice: int) -> Dictionary:
	if pending_dilemma == "":
		return {"ok": false, "reason": "none_pending"}
	var d: Dictionary = Database.get_entry("dilemmas", pending_dilemma)
	if choice < 0 or choice >= d["choices"].size():
		return {"ok": false, "reason": "bad_choice"}
	var c: Dictionary = d["choices"][choice]
	var fx: Dictionary = c["effects"]
	Master.adjust_town(int(fx.get("happiness", 0)), int(fx.get("fear", 0)))
	if fx.has("gold"):
		Master.add_currency("gold", int(fx["gold"]))
	if fx.has("hp_pct_all"):
		for h in Roster.heroes.values():
			var mx: int = int(HeroStats.compute(h)["max_hp"])
			h["hp"] = clampi(int(h["hp"]) + roundi(mx * float(fx["hp_pct_all"])), 1, mx)
	if not reports.is_empty() and reports[-1].get("dilemma_id", "") == pending_dilemma:
		reports[-1]["dilemma_choice"] = c["label"]
		reports[-1]["dilemma_result"] = c["result"]
	pending_dilemma = ""
	return {"ok": true, "label": c["label"], "text": c["result"], "effects": fx.duplicate()}

func to_save() -> Dictionary:
	return {"facilities": facilities.duplicate(true), "reports": reports.duplicate(true),
		"pending_dilemma": pending_dilemma, "recent_dilemmas": recent_dilemmas.duplicate()}

func from_save(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for id in FAC_IDS:
		if d.get("facilities", {}).has(id):
			facilities[id] = d["facilities"][id]
	reports = d.get("reports", [])
	pending_dilemma = d.get("pending_dilemma", "")
	recent_dilemmas = d.get("recent_dilemmas", [])
