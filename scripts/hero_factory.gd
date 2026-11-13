class_name HeroFactory
extends RefCounted
## Creates Hero dictionaries from a recruitment portal. Pure data, no side effects:
## the caller (Roster) registers the ID. All randomness goes through the given rng.

const ID_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

static func create(portal_id: String, rng: RandomNumberGenerator, reserved: Dictionary, day: int = 1) -> Dictionary:
	if not Database.has_id("recruitment", portal_id):
		push_error("Unknown recruitment portal: " + portal_id)
		return {}
	var rules: Dictionary = Database.hero_rules
	var star: int = int(_pick_key(rules["star_weights"][portal_id], rng))
	var role: String = _pick_key(rules["role_weights"], rng)
	var element: String = _pick_key(rules["element_weights"], rng)

	var races: Array = Database.all_entries("races")
	var race: Dictionary = races[rng.randi_range(0, races.size() - 1)]
	var gender: String = "male" if rng.randf() < 0.5 else "female"
	var pool: Array = race["names"][gender]
	var full_name: String = pool[rng.randi_range(0, pool.size() - 1)]

	var noble_id = null
	if rng.randf() < float(rules["noble_chance"]):
		var houses: Array = Database.all_entries("nobles")
		var house: Dictionary = houses[rng.randi_range(0, houses.size() - 1)]
		noble_id = house["id"]
		full_name += " " + String(house["surname"])

	var growth_roll: Dictionary = {}
	var gr: Array = rules["growth_roll_range"]
	for k in HeroStats.CORE_STATS:
		growth_roll[k] = snappedf(rng.randf_range(float(gr[0]), float(gr[1])), 0.001)
	var pr: Array = rules["potential_range"]
	var town_skills: Array = Database.all_entries("town_skills")

	var hero: Dictionary = {
		"id": _new_id(rng, reserved),
		"name": full_name,
		"race": race["id"],
		"age": rng.randi_range(int(race["age_min"]), int(race["age_max"])),
		"gender": gender,
		"noble": noble_id,
		"role": role,
		"element": element,
		"star": star,
		"level": 1,
		"exp": 0,
		"potential": snappedf(rng.randf_range(float(pr[0]), float(pr[1])), 0.001),
		"growth_roll": growth_roll,
		"skills": [],
		"ultimate": null,
		"traits": [],
		"town_skill": town_skills[rng.randi_range(0, town_skills.size() - 1)]["id"],
		"equipment": {"weapon": null, "armor": null, "accessory": null},
		"training_bonus": {},
		"status": "active",
		"recruited_day": day,
		"recruit_source": portal_id,
	}
	fill_slots(hero, rng)
	hero["sp_max"] = int(rules["sp_base"]) + int(rules["sp_per_star"]) * star
	hero["sp"] = hero["sp_max"]
	hero["hp"] = int(HeroStats.compute(hero)["max_hp"])
	return hero

## Fills skill/trait/ultimate slots up to what the hero's Star allows.
## Called at recruitment and again after each Star promotion.
static func fill_slots(hero: Dictionary, rng: RandomNumberGenerator) -> void:
	var rules: Dictionary = Database.hero_rules
	var star: int = int(hero["star"])

	var need_skills: int = int(rules["skill_slots"][str(star)]) - hero["skills"].size()
	if need_skills > 0:
		var picked: Array = _pick_many(_skill_candidates(hero), need_skills, rng)
		hero["skills"].append_array(picked)

	var need_traits: int = int(rules["trait_slots"][str(star)]) - hero["traits"].size()
	if need_traits > 0:
		hero["traits"].append_array(_pick_many(_trait_candidates(hero), need_traits, rng))

	if hero["ultimate"] == null and star >= int(rules["ultimate_min_star"]):
		var options: Array = []
		for u in Database.all_entries("ultimate_skills"):
			if u["role"] == hero["role"] and (u["element"] == hero["element"] or u["element"] == "Normal"):
				options.append(u["id"])
		if not options.is_empty():
			hero["ultimate"] = options[rng.randi_range(0, options.size() - 1)]

# ---- candidate lists: [ [ids], [weights] ] ----------------------------------

static func _skill_candidates(hero: Dictionary) -> Array:
	var rules: Dictionary = Database.hero_rules
	var role_w: Dictionary = rules["role_category_weights"][hero["role"]]
	var ids: Array = []
	var weights: Array = []
	for s in Database.all_entries("basic_skills"):
		var el: String = s["element"]
		if s["id"] in hero["skills"]:
			continue
		if el == "Combination":
			if int(hero["star"]) < int(rules["combination_min_star"]):
				continue
			if not (hero["element"] in rules["combination_elements"][s["id"]]):
				continue
		elif el != "Normal" and el != hero["element"]:
			continue
		var wt: float = float(role_w.get(s["category"], 0.5))
		if el == hero["element"]:
			wt *= 2.0
		ids.append(s["id"])
		weights.append(wt)
	return [ids, weights]

static func _trait_candidates(hero: Dictionary) -> Array:
	var ids: Array = []
	var weights: Array = []
	for t in Database.all_entries("traits"):
		if t["id"] in hero["traits"]:
			continue
		if t["element"] != "Normal" and t["element"] != hero["element"]:
			continue
		ids.append(t["id"])
		weights.append(2.0 if t["element"] == hero["element"] else 1.0)
	return [ids, weights]

# ---- random helpers ---------------------------------------------------------

static func _pick_key(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for k in weights:
		total += float(weights[k])
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k in weights:
		acc += float(weights[k])
		if roll < acc:
			return String(k)
	return String(weights.keys().back())

## Weighted pick without replacement. candidates = [ids, weights].
static func _pick_many(candidates: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var ids: Array = candidates[0].duplicate()
	var weights: Array = candidates[1].duplicate()
	var out: Array = []
	for _n in range(mini(count, ids.size())):
		var total: float = 0.0
		for x in weights:
			total += float(x)
		var roll: float = rng.randf() * total
		var acc: float = 0.0
		var idx: int = weights.size() - 1
		for j in weights.size():
			acc += float(weights[j])
			if roll < acc:
				idx = j
				break
		out.append(ids[idx])
		ids.remove_at(idx)
		weights.remove_at(idx)
	return out

static func _new_id(rng: RandomNumberGenerator, reserved: Dictionary) -> String:
	while true:
		var id: String = "HR-"
		for _i in 6:
			id += ID_CHARS[rng.randi_range(0, ID_CHARS.length() - 1)]
		if not reserved.has(id):
			return id
	return ""
