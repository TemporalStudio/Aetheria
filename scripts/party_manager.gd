extends Node
## Autoload `Parties`: up to 20 Parties, 5 slots each (0-2 Front, 3-4 Back) + Medical slots.
## A Hero can be in only ONE Party. Medical slots hold item IDs; stock comes from Inventory.

const PARTY_COUNT := 20
const SLOTS := 5
const FRONT_SLOTS := 3

var parties: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	parties = {}
	for i in range(1, PARTY_COUNT + 1):
		var pid: String = "P%d" % i
		var med: Array = []
		for _j in int(Database.battle_rules["medical_slots_per_party"]):
			med.append(null)
		parties[pid] = {"id": pid, "name": "Party %d" % i, "slots": [null, null, null, null, null], "medical": med}

func get_party(party_id: String) -> Dictionary:
	return parties.get(party_id, {})

func hero_party(hero_id: String) -> String:
	for pid in parties:
		if hero_id in parties[pid]["slots"]:
			return pid
	return ""

## Not in a Party and not busy elsewhere (facility assignment is added in the Town step).
func is_available(hero_id: String) -> bool:
	var hero: Dictionary = Roster.get_hero(hero_id)
	return not hero.is_empty() and hero["status"] == "active" and hero_party(hero_id) == "" and hero.get("assignment") == null

## Puts a Hero in a slot. If he is in another Party/slot he is moved; a replaced Hero becomes unassigned.
func set_slot(party_id: String, slot: int, hero_id: String) -> bool:
	var p: Dictionary = get_party(party_id)
	if p.is_empty() or slot < 0 or slot >= SLOTS:
		return false
	var hero: Dictionary = Roster.get_hero(hero_id)
	if hero.is_empty() or hero["status"] != "active" or hero.get("assignment") != null:
		return false
	remove_hero(hero_id)
	p["slots"][slot] = hero_id
	return true

func clear_slot(party_id: String, slot: int) -> void:
	var p: Dictionary = get_party(party_id)
	if not p.is_empty() and slot >= 0 and slot < SLOTS:
		p["slots"][slot] = null

## Removes a Hero from whichever Party holds him (also used when a Hero dies).
func remove_hero(hero_id: String) -> void:
	for pid in parties:
		var slots: Array = parties[pid]["slots"]
		for i in slots.size():
			if slots[i] == hero_id:
				slots[i] = null

func set_medical(party_id: String, index: int, item_id) -> bool:
	var p: Dictionary = get_party(party_id)
	if p.is_empty() or index < 0 or index >= p["medical"].size():
		return false
	if item_id != null and not Database.has_id("medical", item_id):
		return false
	p["medical"][index] = item_id
	return true

func hero_ids(party_id: String) -> Array:
	var out: Array = []
	for id in get_party(party_id).get("slots", []):
		if id != null:
			out.append(id)
	return out

func battle_ready(party_id: String) -> Dictionary:
	if get_party(party_id).is_empty():
		return {"ok": false, "reason": "unknown_party"}
	for id in hero_ids(party_id):
		if int(Roster.get_hero(id).get("hp", 0)) > 0:
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "no_healthy_hero"}

## Fills empty slots from available Heroes: Defenders/Attackers prefer Front, Healers/Supporters prefer Back.
func auto_fill(party_id: String) -> void:
	var p: Dictionary = get_party(party_id)
	if p.is_empty():
		return
	var pool: Array = []
	for h in Roster.heroes.values():
		if is_available(h["id"]) and int(h["hp"]) > 0:
			pool.append(h)
	pool.sort_custom(func(a, b): return int(a["star"]) * 1000 + int(a["level"]) > int(b["star"]) * 1000 + int(b["level"]))
	for slot in SLOTS:
		if p["slots"][slot] != null or pool.is_empty():
			continue
		var want_front: bool = slot < FRONT_SLOTS
		var idx: int = 0
		for i in pool.size():
			if (pool[i]["role"] in ["Defender", "Attacker"]) == want_front:
				idx = i
				break
		p["slots"][slot] = pool[idx]["id"]
		pool.remove_at(idx)

func describe(party_id: String) -> String:
	var parts: Array = []
	var slots: Array = get_party(party_id).get("slots", [])
	for i in slots.size():
		var tag: String = "F" if i < FRONT_SLOTS else "B"
		if slots[i] == null:
			parts.append("[%s] -" % tag)
		else:
			var h: Dictionary = Roster.get_hero(slots[i])
			parts.append("[%s] %s (%s %s %d★ Lv%d)" % [tag, h["name"], h["role"], h["element"], h["star"], h["level"]])
	return " | ".join(parts)

func to_save() -> Dictionary:
	return {"parties": parties.duplicate(true)}

func from_save(d: Dictionary) -> void:
	reset()
	var saved: Dictionary = d.get("parties", {})
	for pid in saved:
		if parties.has(pid):
			parties[pid] = saved[pid]
