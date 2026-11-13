extends Node
## Autoload `Athanatos`: permanent Hero death + Memorial Cemetery (GDD Bab 15).
## A fallen Hero is removed from the active roster for good. His ID stays reserved forever
## (Roster.reserved_ids), and one memorial record is written to Roster.memorials (saved by SaveSystem).

signal hero_fallen(memorial: Dictionary)

const BOSS_TYPES := ["mind_boss", "floor_boss", "raid_boss", "rift_boss"]
const TYPE_LABEL := {"pawn": "Pawn", "mind_boss": "Mind Boss", "floor_boss": "Floor Boss", "raid_boss": "Raid Boss",
	"rift_boss": "Rift Star Boss", "dungeon": "Dungeon monster", "status": "status effect"}

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func is_unlocked() -> bool:
	return bool(Database.athanatos_rules["unlocked"])

# ============================== BURIAL =======================================

## Turns BattleEngine "fallen" records into memorials and removes the Heroes from the roster.
## Safe to call twice with the same records (a Hero already buried is ignored).
func process_fallen(records: Array) -> Array:
	var names: Dictionary = {}
	for h in Roster.heroes.values():
		names[h["id"]] = h["name"]
	for m in Roster.memorials:
		names[m["hero_id"]] = m["name"]
	for r in records:
		names[r["hero_id"]] = r["hero_name"]
	var out: Array = []
	for r in records:
		var mem: Dictionary = _bury(r, names)
		if not mem.is_empty():
			out.append(mem)
	return out

func _bury(r: Dictionary, names: Dictionary) -> Dictionary:
	var hid: String = r["hero_id"]
	var hero: Dictionary = Roster.get_hero(hid)
	if hero.is_empty() or has_memorial(hid):
		return {}
	var ctx: Dictionary = r.get("context", {})
	var killer_type: String = String(r.get("killer_type", "status"))
	var killer: String = String(r.get("killer", "Unknown"))
	var skill_id: String = String(r.get("skill", ""))
	var place: String = _location(ctx)
	var cause_text: String
	if killer_type == "status":
		cause_text = "Succumbed to %s" % _skill_name(skill_id).to_lower()
	else:
		cause_text = "Fell to %s (%s) with %s" % [killer, TYPE_LABEL.get(killer_type, killer_type), _skill_name(skill_id)]
	var companions: Array = []
	for id in r.get("teammates", []):
		companions.append({"hero_id": id, "name": names.get(id, "Unknown")})
	var mem: Dictionary = {
		"id": "MEM-" + hid, "seq": Roster.memorials.size() + 1,
		"hero_id": hid, "name": hero["name"], "race": hero["race"], "gender": hero["gender"], "age": hero["age"],
		"noble": hero["noble"], "role": hero["role"], "element": hero["element"], "star": hero["star"], "level": hero["level"],
		"day": Master.in_game_day, "location": place, "context": ctx.duplicate(true),
		"cause": {"killer": killer, "killer_enemy_id": r.get("killer_enemy_id", ""), "killer_type": killer_type,
			"skill_id": skill_id, "skill_name": _skill_name(skill_id), "text": cause_text},
		"battle": {"round": int(r.get("round", 0)), "party": r.get("party", ""), "floor": int(ctx.get("floor", 0)), "boss": _boss_name(ctx)},
		"companions": companions,
		"inscription": _epitaph(hero["name"], killer, place, killer_type),
		"custom_inscription": "",
		"snapshot": {"skills": hero["skills"].duplicate(), "ultimate": hero["ultimate"], "traits": hero["traits"].duplicate(),
			"town_skill": hero["town_skill"], "potential": hero["potential"], "final_stats": HeroStats.compute(hero),
			"equipment": hero["equipment"].duplicate(), "recruited_day": hero["recruited_day"], "recruit_source": hero["recruit_source"]},
	}
	if bool(Database.athanatos_rules["equipment_returns_to_inventory"]):
		for slot in hero["equipment"]:
			if hero["equipment"][slot] != null:
				Inventory.add(hero["equipment"][slot], 1)
	Parties.remove_hero(hid)
	Town.remove_hero(hid)
	Roster.archive_hero(hid, mem)
	var mourn: Dictionary = Database.athanatos_rules["mourning"]
	if bool(mourn["enabled"]):
		Master.adjust_town(int(mourn["happiness_delta"]), int(mourn["fear_delta"]))
	hero_fallen.emit(mem)
	return mem

func _location(ctx: Dictionary) -> String:
	if ctx.get("mode", "") == "tower":
		return "Tower of Rebirth, Floor %d" % int(ctx.get("floor", 0))
	var m: String = String(ctx.get("mode", ""))
	return "Unknown location" if m == "" else m.capitalize()

func _boss_name(ctx: Dictionary) -> String:
	if ctx.get("mode", "") == "tower" and ctx.get("floor_type", "") in BOSS_TYPES:
		var f: Dictionary = Database.get_floor(int(ctx["floor"]))
		if not f.is_empty():
			return String(Database.get_entry("enemies", f["enemies"][0]["enemy"]).get("name", ""))
	return ""

func _skill_name(id: String) -> String:
	if id == "BASIC":
		return "Basic Attack"
	if id == "burn":
		return "Burning"
	if Database.has_id("basic_skills", id):
		return Database.get_entry("basic_skills", id)["name"]
	if Database.has_id("ultimate_skills", id):
		return Database.get_entry("ultimate_skills", id)["name"]
	return id

func _epitaph(p_name: String, killer: String, place: String, killer_type: String) -> String:
	var cat: String = "boss" if killer_type in BOSS_TYPES else ("status" if killer_type == "status" else "enemy")
	var pool: Array = Database.epitaphs[cat]
	var t: String = pool[rng.randi_range(0, pool.size() - 1)]
	return t.format({"name": p_name, "killer": killer, "place": place})

# ============================== CEMETERY VIEW ================================

func has_memorial(hero_id: String) -> bool:
	for m in Roster.memorials:
		if m["hero_id"] == hero_id:
			return true
	return false

func get_record(hero_id: String) -> Dictionary:
	for m in Roster.memorials:
		if m["hero_id"] == hero_id:
			return m
	return {}

## sort_by: "recent" (default) | "level" | "star"
func list(sort_by: String = "recent") -> Array:
	var out: Array = Roster.memorials.duplicate()
	match sort_by:
		"level":
			out.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
		"star":
			out.sort_custom(func(a, b): return int(a["star"]) > int(b["star"]))
		_:
			out.sort_custom(func(a, b): return int(a["seq"]) > int(b["seq"]))
	return out

func count() -> int:
	return Roster.memorials.size()

## Only the inscription may be personalised; every other field of a record is permanent.
func set_inscription(hero_id: String, text: String) -> bool:
	var m: Dictionary = get_record(hero_id)
	if m.is_empty():
		return false
	m["custom_inscription"] = text.strip_edges().left(int(Database.athanatos_rules["custom_inscription_max"]))
	return true

func tombstone_text(m: Dictionary) -> String:
	var lines: Array = []
	lines.append("IN MEMORIAM")
	lines.append("%s  (%s)" % [m["name"], m["hero_id"]])
	lines.append("%s · %s · %s · %d★ · Lv %d" % [m["race"], m["role"], m["element"], m["star"], m["level"]])
	lines.append("Fell on Day %d — %s" % [m["day"], m["location"]])
	if m["battle"]["boss"] != "":
		lines.append("Boss: %s" % m["battle"]["boss"])
	lines.append("Cause: %s" % m["cause"]["text"])
	var names: Array = []
	for c in m["companions"]:
		names.append(c["name"])
	if not names.is_empty():
		lines.append("Fought beside: %s" % ", ".join(names))
	var ins: String = m["custom_inscription"] if m["custom_inscription"] != "" else m["inscription"]
	lines.append("“%s”" % ins)
	return "\n".join(lines)

func stats() -> Dictionary:
	var by_type: Dictionary = {}
	var by_floor: Dictionary = {}
	var by_killer: Dictionary = {}
	for m in Roster.memorials:
		var t: String = m["cause"]["killer_type"]
		by_type[t] = int(by_type.get(t, 0)) + 1
		var fl: int = int(m["battle"]["floor"])
		if fl > 0:
			by_floor[fl] = int(by_floor.get(fl, 0)) + 1
		var k: String = m["cause"]["killer"]
		by_killer[k] = int(by_killer.get(k, 0)) + 1
	return {"total": count(), "by_killer_type": by_type, "deadliest_floor": _top_key(by_floor), "deadliest_enemy": _top_key(by_killer)}

func _top_key(d: Dictionary):
	var best = null
	var best_n: int = 0
	for k in d:
		if int(d[k]) > best_n:
			best_n = int(d[k])
			best = k
	return best

## Text the UI must show (and the player must confirm) before a battle where Heroes can die for good.
func lethal_warning(party_id: String) -> Dictionary:
	var at_risk: Array = []
	for id in Parties.hero_ids(party_id):
		var h: Dictionary = Roster.get_hero(id)
		if int(h["hp"]) > 0:
			at_risk.append({"id": id, "name": h["name"], "star": h["star"], "level": h["level"]})
	var names: Array = []
	for a in at_risk:
		names.append("%s (%d★ Lv%d)" % [a["name"], a["star"], a["level"]])
	return {"lethal": true, "heroes": at_risk,
		"text": "Permanent death is active. A Hero whose HP reaches 0 is lost forever and buried in Athanatos. At risk: %s." % ", ".join(names)}

## Returns a list of problems (empty = all good). Used after loading a save.
func verify_integrity() -> Array:
	var problems: Array = []
	var seen: Dictionary = {}
	for m in Roster.memorials:
		var id: String = m["hero_id"]
		if seen.has(id):
			problems.append("Duplicate memorial for %s" % id)
		seen[id] = true
		if Roster.heroes.has(id):
			problems.append("Fallen Hero %s is still in the active roster" % id)
		if not Roster.reserved_ids.has(id):
			problems.append("Fallen Hero ID %s is not reserved" % id)
	return problems
