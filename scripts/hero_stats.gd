class_name HeroStats
extends RefCounted
## Stat calculation for a Hero dictionary (see HeroFactory for the shape).
## Final core stat = (role base + growth*(level-1)) * race * element * star * potential * growth_roll * noble * (1+trait%)
##                   + equipment + training bonus.
## Secondary stats (crit/evasion/accuracy) = role base + per-star bonus + race flat + trait*100 + equipment + training.

const CORE_STATS := ["max_hp", "phys_atk", "magic_atk", "phys_def", "magic_def", "speed"]
const SECONDARY_STATS := ["crit", "evasion", "accuracy"]

static func compute(hero: Dictionary) -> Dictionary:
	var rules: Dictionary = Database.hero_rules
	var role: Dictionary = Database.get_entry("roles", hero["role"])
	var race: Dictionary = Database.get_entry("races", hero["race"])
	var level: int = int(hero["level"])
	var star: int = int(hero["star"])
	var star_mult: float = float(rules["star_multiplier"][str(star)])
	var potential: float = float(hero.get("potential", 1.0))
	var rolls: Dictionary = hero.get("growth_roll", {})
	var noble_mult: float = float(rules["noble_stat_mult"]) if hero.get("noble") != null else 1.0
	var elem_bonus: Dictionary = rules["element_stat_bonus"].get(hero["element"], {})
	var trait_totals: Dictionary = _trait_totals(hero)
	var equip: Dictionary = _equipment_totals(hero)
	var training: Dictionary = hero.get("training_bonus", {})
	var out: Dictionary = {}

	for k in CORE_STATS:
		var v: float = float(role["base"][k]) + float(role["growth"][k]) * (level - 1)
		v *= float(race["mult"].get(k, 1.0))
		if elem_bonus.get("stat", "") == k:
			v *= float(elem_bonus["mult"])
		v *= star_mult * potential * float(rolls.get(k, 1.0)) * noble_mult
		v *= 1.0 + float(trait_totals.get(k, 0.0))
		v += float(equip.get(k, 0.0)) + float(training.get(k, 0.0))
		out[k] = roundi(v)

	for k in SECONDARY_STATS:
		var v2: float = float(role["secondary_base"][k])
		v2 += float(rules["secondary_per_star"][k]) * (star - 1)
		v2 += float(race["flat"].get(k, 0.0))
		v2 += float(trait_totals.get(k, 0.0)) * 100.0
		v2 += float(equip.get(k, 0.0)) + float(training.get(k, 0.0))
		out[k] = snappedf(v2, 0.1)
	return out

## Trait effects that are not combat stats (sp_cost, ug_gain, exp_gain, fear_resist, ...).
static func modifiers(hero: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in _trait_totals(hero):
		if not (k in CORE_STATS or k in SECONDARY_STATS):
			out[k] = _trait_totals(hero)[k]
	return out

static func _trait_totals(hero: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for tid in hero.get("traits", []):
		var t: Dictionary = Database.get_entry("traits", tid)
		if t.is_empty():
			continue
		totals[t["stat"]] = float(totals.get(t["stat"], 0.0)) + float(t["value"])
	return totals

static func _equipment_totals(hero: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	var eq: Dictionary = hero.get("equipment", {})
	for slot in eq:
		if eq[slot] == null:
			continue
		var item: Dictionary = Database.get_entry("equipment", eq[slot])
		for k in item.get("stats", {}):
			totals[k] = float(totals.get(k, 0.0)) + float(item["stats"][k])
	return totals
