extends Node
## Autoload: the active Hero roster + the permanent registry of every Hero ID ever issued.
## `reserved_ids` is NEVER shrunk (not even when a Hero dies), so an ID can't be reused (GDD Bab 15.3).

signal hero_recruited(hero: Dictionary)

var heroes: Dictionary = {}        # id -> hero dict (active only)
var reserved_ids: Dictionary = {}  # id -> true (active + dead)
var recruit_log: Array = []        # last 100 recruitments (Recruitment Log)
var memorials: Array = []          # Athanatos records (filled by the death system, later step)
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

## Creates and registers a new Hero. Payment is handled by the caller (Master/Inventory, later step).
func recruit(portal_id: String, day: int = 1) -> Dictionary:
	var hero: Dictionary = HeroFactory.create(portal_id, rng, reserved_ids, day)
	if hero.is_empty():
		return {}
	heroes[hero["id"]] = hero
	reserved_ids[hero["id"]] = true
	recruit_log.append({"day": day, "id": hero["id"], "name": hero["name"], "star": hero["star"], "role": hero["role"], "element": hero["element"], "source": portal_id})
	while recruit_log.size() > 100:
		recruit_log.pop_front()
	hero_recruited.emit(hero)
	return hero

func reset() -> void:
	heroes = {}
	reserved_ids = {}
	memorials = []
	recruit_log = []

## Pays the portal cost from Master's wallet, then recruits. Returns {} if unaffordable.
func recruit_paid(portal_id: String) -> Dictionary:
	var portal: Dictionary = Database.get_entry("recruitment", portal_id)
	if portal.is_empty() or not Master.pay(portal["cost"]):
		return {}
	return recruit(portal_id, Master.in_game_day)

## Equips an item from Inventory; the previously equipped item returns to Inventory.
func equip(hero_id: String, item_id: String) -> bool:
	var hero: Dictionary = get_hero(hero_id)
	var item: Dictionary = Database.get_entry("equipment", item_id)
	if hero.is_empty() or item.is_empty() or Inventory.count(item_id) < 1:
		return false
	var slot: String = item["slot"]
	var old = hero["equipment"][slot]
	Inventory.remove(item_id, 1)
	if old != null:
		Inventory.add(old, 1)
	hero["equipment"][slot] = item_id
	hero["hp"] = mini(int(hero["hp"]), int(HeroStats.compute(hero)["max_hp"]))
	return true

func unequip(hero_id: String, slot: String) -> bool:
	var hero: Dictionary = get_hero(hero_id)
	if hero.is_empty() or hero["equipment"].get(slot) == null:
		return false
	Inventory.add(hero["equipment"][slot], 1)
	hero["equipment"][slot] = null
	hero["hp"] = mini(int(hero["hp"]), int(HeroStats.compute(hero)["max_hp"]))
	return true

## Full heal (Dormitory/Skip Day will use this logic later).
func heal_all() -> void:
	for h in heroes.values():
		h["hp"] = int(HeroStats.compute(h)["max_hp"])
		h["sp"] = int(h["sp_max"])

## Moves a Hero from the active roster to the memorial archive. His ID stays reserved forever.
func archive_hero(id: String, memorial: Dictionary) -> void:
	heroes.erase(id)
	memorials.append(memorial)
	reserved_ids[id] = true

## Charges the promotion cost (Gold + materials) and promotes. Level must be at the cap.
func promote_paid(id: String) -> Dictionary:
	var cost: Dictionary = promotion_cost(id)
	if cost.is_empty():
		return {"ok": false, "reason": "not_ready"}
	var gold: Dictionary = {"gold": int(cost["gold"])}
	if not Master.can_afford(gold) or not Inventory.has_items(cost["materials"]):
		return {"ok": false, "reason": "cannot_afford"}
	Master.pay(gold)
	for m in cost["materials"]:
		Inventory.remove(m["item"], int(m["qty"]))
	promote_star(id)
	return {"ok": true}

func get_hero(id: String) -> Dictionary:
	return heroes.get(id, {})

func active_count() -> int:
	return heroes.size()

## Adds EXP and levels up while below the Star's level cap. Returns levels gained.
func add_exp(id: String, amount: int) -> int:
	var hero: Dictionary = get_hero(id)
	if hero.is_empty():
		return 0
	var cap: int = Database.level_cap_for_star(int(hero["star"]))
	var gained: int = 0
	hero["exp"] = int(hero["exp"]) + amount
	while int(hero["level"]) < cap and int(hero["exp"]) >= Database.exp_to_next(int(hero["level"])):
		hero["exp"] = int(hero["exp"]) - Database.exp_to_next(int(hero["level"]))
		hero["level"] = int(hero["level"]) + 1
		gained += 1
	if int(hero["level"]) >= cap:
		hero["exp"] = 0
	return gained

## Cost of promoting to the next Star ({} if not allowed). Level must be at the cap; Level is NOT reset.
func promotion_cost(id: String) -> Dictionary:
	var hero: Dictionary = get_hero(id)
	if hero.is_empty() or int(hero["star"]) >= 5:
		return {}
	var info: Dictionary = Database.get_entry("star_progression", "STAR-%d" % int(hero["star"]))
	if int(hero["level"]) < int(info["level_cap"]):
		return {}
	return info["promotion"]

## Applies the promotion (caller must already have charged the cost) and unlocks new slots.
func promote_star(id: String) -> bool:
	if promotion_cost(id).is_empty():
		return false
	var hero: Dictionary = heroes[id]
	hero["star"] = int(hero["star"]) + 1
	HeroFactory.fill_slots(hero, rng)
	hero["sp_max"] = int(Database.hero_rules["sp_base"]) + int(Database.hero_rules["sp_per_star"]) * int(hero["star"])
	return true

# ---- Save hooks (wired to the Save System in a later step) ----
func to_save() -> Dictionary:
	return {"heroes": heroes.duplicate(true), "reserved_ids": reserved_ids.keys(), "memorials": memorials.duplicate(true), "recruit_log": recruit_log.duplicate(true)}

func from_save(d: Dictionary) -> void:
	heroes = d.get("heroes", {})
	memorials = d.get("memorials", [])
	recruit_log = d.get("recruit_log", [])
	reserved_ids = {}
	for id in d.get("reserved_ids", []):
		reserved_ids[id] = true
	for id in heroes:
		reserved_ids[id] = true
	# A Hero with a memorial can never be active again, even if an old/edited save says so.
	for m in memorials:
		reserved_ids[m["hero_id"]] = true
		heroes.erase(m["hero_id"])
