class_name BattleRunner
extends RefCounted
## Glue between Parties, Tower data and the BattleEngine, plus reward payout.

## Builds a Tower battle for a Party. Returns null if not allowed (check Parties.battle_ready / floor access).
static func create_tower_battle(party_id: String, floor_num: int, rng: RandomNumberGenerator, lethal: bool = true) -> BattleEngine:
	if floor_num < 1 or floor_num > int(Database.tower_rules["floors"]) or floor_num > Master.highest_floor + 1:
		return null
	if not Parties.battle_ready(party_id)["ok"] or Town.party_busy(party_id) != "":
		return null   # unhealthy, or the Party is busy in a facility
	var f: Dictionary = Database.get_floor(floor_num)
	var e := BattleEngine.new(rng, lethal)
	e.context = {"mode": "tower", "floor": floor_num, "floor_type": f["type"]}
	e.add_party(party_id, Parties.get_party(party_id)["slots"])
	e.set_medical(Parties.get_party(party_id)["medical"])
	e.add_enemies(f["enemies"], floor_num)
	return e

## Runs a full AUTO battle on a throw-away basis: nothing is written to Roster/Inventory/Master.
static func simulate_tower(party_id: String, floor_num: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var e: BattleEngine = create_tower_battle(party_id, floor_num, rng, true)
	if e == null:
		return {"outcome": "invalid"}
	return e.run_auto()

## Call once after a battle ended. Saves HP/SP, pays rewards on victory.
## Fallen Heroes are buried by Athanatos (result["memorials"]). Show Athanatos.lethal_warning() BEFORE the fight.
static func finish_tower(e: BattleEngine, floor_num: int) -> Dictionary:
	e.commit()
	var res: Dictionary = e.get_result()
	res["memorials"] = Athanatos.process_fallen(res["fallen"])   # permanent death
	Fairy.on_battle_finished(e, res)
	res["rewards"] = {}
	if res["outcome"] != "victory":
		return res
	var rw: Dictionary = Database.get_floor(floor_num)["rewards"]
	var got: Dictionary = {"gold": int(rw["gold"]), "exp": int(rw["exp"]), "gems": 0, "drops": []}
	Master.add_currency("gold", got["gold"])
	if floor_num > Master.highest_floor and int(rw["first_clear_gems"]) > 0:
		got["gems"] = int(rw["first_clear_gems"])
		Master.add_currency("gems", got["gems"])
	for hero_id in res["survivors"]:
		Roster.add_exp(hero_id, got["exp"])
	for d in rw["drops"]:
		if e.rng.randf() < float(d["chance"]):
			Inventory.add(d["item"], int(d["qty"]))
			got["drops"].append("%s x%d" % [d["item"], int(d["qty"])])
	Master.record_floor_clear(floor_num)
	res["rewards"] = got
	return res
