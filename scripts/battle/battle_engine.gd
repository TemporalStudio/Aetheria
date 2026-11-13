class_name BattleEngine
extends RefCounted
## Turn-based battle simulation (pure logic, no UI). One instance = one battle.
##
## Flow for a UI:   tick() -> if it returns {"type":"awaiting_input"}, call submit(action) -> repeat.
## Flow for AUTO:   engine.auto = true; engine.run_auto()
## Actions: {"type":"attack","target_uid":n} | {"type":"skill","skill_id":id,"target_uid":n}
##          {"type":"ultimate","target_uid":n} | {"type":"medical","item_id":id,"target_uid":n} | {"type":"guard"}
## All randomness goes through `rng`, so the same seed + same setup = same battle.

var rules: Dictionary
var rng: RandomNumberGenerator
var units: Array = []
var team_sp: int = 0
var team_sp_max: int = 5
var round_num: int = 0
var queue: Array = []              # uids that still act this round
var auto: bool = false
var lethal: bool = true            # false = practice: a KO'd Hero is not recorded as fallen
var outcome: String = ""           # "" | victory | defeat | timeout
var fallen: Array = []             # death records for the Athanatos system
var ko_list: Array = []
var events_log: Array = []
var party_label: String = "P1"
var medical_slots: Array = []
var context: Dictionary = {}       # e.g. {"mode":"tower","floor":12}; copied into death records
var forced_guard: bool = false     # Town "Panicked": Heroes can only Guard
var _turn_started: bool = false
var _party_hero_ids: Array = []
var _item_counts: Dictionary = {}
var _items_used: Dictionary = {}

func _init(p_rng: RandomNumberGenerator, p_lethal: bool = true) -> void:
	rng = p_rng
	lethal = p_lethal
	rules = Database.battle_rules
	team_sp_max = int(Database.rules["team_sp_max"])
	team_sp = mini(int(rules["team_sp_start"]), team_sp_max)

# ============================== SETUP ========================================

func add_party(p_label: String, slots: Array) -> void:
	party_label = p_label
	var mental: Dictionary = Database.get_entry("mental_states", Master.town_state()).get("combat", {})
	forced_guard = mental.get("forced_action", "") == "guard"
	for slot in slots.size():
		var hid = slots[slot]
		if hid == null:
			continue
		var hero: Dictionary = Roster.get_hero(hid)
		if hero.is_empty() or int(hero["hp"]) <= 0:
			continue
		_party_hero_ids.append(hid)
		units.append(_make_hero_unit(hero, slot, mental))

func set_medical(item_ids: Array) -> void:
	medical_slots = []
	for id in item_ids:
		if id != null:
			medical_slots.append(id)
			_item_counts[id] = Inventory.count(id)
			_items_used[id] = 0

func add_enemies(entries: Array, floor_num: int) -> void:
	var n: int = 0
	for entry in entries:
		for _i in int(entry["qty"]):
			n += 1
			units.append(_make_enemy_unit(entry["enemy"], floor_num, n))

func _blank_unit(side: String, label: String, p_name: String) -> Dictionary:
	return {"uid": units.size(), "side": side, "label": label, "name": p_name, "hero_id": "", "enemy_id": "",
		"etype": "hero", "element": "Normal", "role": "", "front": true, "max_hp": 1, "hp": 1, "sp": 0,
		"sp_max": 0, "ug": 0, "stats": {}, "stats0": {}, "skills": [], "ultimate": null, "mods": [],
		"shield": 0, "shield_turns": 0, "alive": true, "taunt_turns": 0, "turns_taken": 0, "phase": 0,
		"phases": [], "cd": {}, "trait_mods": {}}

func _make_hero_unit(hero: Dictionary, slot: int, mental: Dictionary) -> Dictionary:
	var st: Dictionary = HeroStats.compute(hero)
	var stats: Dictionary = {}
	for k in ["phys_atk", "magic_atk", "phys_def", "magic_def", "speed", "crit", "evasion", "accuracy"]:
		stats[k] = float(st[k])
	stats["crit"] += float(mental.get("crit_add", 0))
	stats["speed"] *= float(mental.get("speed_mult", 1.0))
	var am: float = float(mental.get("atk_mult", 1.0))
	stats["phys_atk"] *= am
	stats["magic_atk"] *= am
	var label: String = "%s_H%d(%s)" % [party_label, slot + 1, "F" if slot < 3 else "B"]
	var u: Dictionary = _blank_unit("party", label, hero["name"])
	u["hero_id"] = hero["id"]
	u["element"] = hero["element"]
	u["role"] = hero["role"]
	u["front"] = slot < 3
	u["max_hp"] = int(st["max_hp"])
	u["hp"] = int(hero["hp"])
	u["sp"] = int(hero["sp"])
	u["sp_max"] = int(hero["sp_max"])
	u["stats"] = stats.duplicate()
	u["stats0"] = stats.duplicate()
	u["skills"] = hero["skills"].duplicate()
	u["ultimate"] = hero["ultimate"]
	u["trait_mods"] = HeroStats.modifiers(hero)
	return u

func _make_enemy_unit(enemy_id: String, floor_num: int, n: int) -> Dictionary:
	var e: Dictionary = Database.get_entry("enemies", enemy_id)
	var s: Dictionary = Database.get_scaled_stats(enemy_id, floor_num)
	var d: Dictionary = rules["enemy_defaults"]
	var u: Dictionary = _blank_unit("enemy", "E%d" % n, e["name"])
	u["enemy_id"] = enemy_id
	u["etype"] = e["type"]
	u["element"] = e["element"]
	u["front"] = n <= 3
	u["max_hp"] = int(s["hp"])
	u["hp"] = int(s["hp"])
	# Enemies have a single ATK/DEF (GDD); the skill's damage_type decides which side of the formula is used.
	var st: Dictionary = {"phys_atk": float(s["atk"]), "magic_atk": float(s["atk"]),
		"phys_def": float(s["def"]), "magic_def": float(s["def"]), "speed": float(s["spd"]),
		"crit": float(d["crit"]), "evasion": float(d["evasion"]), "accuracy": float(d["accuracy"])}
	u["stats"] = st.duplicate()
	u["stats0"] = st.duplicate()
	u["skills"] = e["skills"].duplicate()
	u["ultimate"] = e["ultimate"]
	if e["phases"] != null:
		u["phases"] = e["phases"].duplicate(true)
		u["skills"] = u["phases"][0]["skills"].duplicate()
	return u

# ============================== QUERIES ======================================

func eff(u: Dictionary, stat: String) -> float:
	var base: float = float(u["stats"][stat])
	var total: float = 0.0
	for m in u["mods"]:
		if m["stat"] == stat:
			total += float(m["value"])
	if stat == "crit" or stat == "evasion" or stat == "accuracy":
		return base + total * 100.0
	return base * maxf(0.1, 1.0 + total)

func _alive_side(side: String) -> Array:
	var out: Array = []
	for u in units:
		if u["alive"] and u["side"] == side:
			out.append(u)
	return out

func _foes_of(u: Dictionary) -> Array:
	return _alive_side("enemy" if u["side"] == "party" else "party")

func _friends_of(u: Dictionary) -> Array:
	return _alive_side(u["side"])

func _lbl(uid: int) -> String:
	return String(units[uid]["label"]) if uid >= 0 else "Status"

## Order of the Speed Action Queue (remaining actors this round, or a preview of the next round).
func preview_order() -> Array:
	var labels: Array = []
	if queue.is_empty():
		var alive: Array = []
		for u in units:
			if u["alive"]:
				alive.append(u)
		alive.sort_custom(_speed_order)
		for u in alive:
			labels.append(u["label"])
	else:
		for uid in queue:
			if units[uid]["alive"]:
				labels.append(units[uid]["label"])
	return labels

func queue_text() -> String:
	return " → ".join(preview_order())

func _speed_order(a: Dictionary, b: Dictionary) -> bool:
	var sa: float = eff(a, "speed")
	var sb: float = eff(b, "speed")
	if sa != sb:
		return sa > sb
	if a["side"] != b["side"]:
		return a["side"] == "party"
	return int(a["uid"]) < int(b["uid"])

func _element_mult(attack_elements: Array, target_element: String) -> float:
	var adv: Dictionary = rules["element"]["advantage"]
	var best: float = 0.0
	for el in attack_elements:
		var m: float = 1.0
		if target_element in adv.get(el, []):
			m = float(rules["element"]["strong_mult"])
		elif el in adv.get(target_element, []):
			m = float(rules["element"]["weak_mult"])
		best = maxf(best, m)
	return best

func _skill_elements(skill: Dictionary) -> Array:
	if skill["element"] == "Combination":
		return Database.hero_rules["combination_elements"][skill["id"]]
	return [skill["element"]]

func _skill_cost(u: Dictionary, skill: Dictionary) -> int:
	return maxi(0, roundi(float(skill["sp_cost"]) * (1.0 + float(u["trait_mods"].get("sp_cost", 0.0)))))

# ============================== TURN LOOP ====================================

func _begin_round() -> void:
	round_num += 1
	var alive: Array = []
	for u in units:
		if u["alive"]:
			alive.append(u)
	alive.sort_custom(_speed_order)
	queue = []
	for u in alive:
		queue.append(u["uid"])

## Advances the battle by at most one actor. Returns the events produced.
func tick() -> Array:
	var ev: Array = []
	if outcome != "":
		return ev
	if queue.is_empty():
		if round_num >= int(rules["max_rounds"]):
			_finish("timeout", ev)
			return ev
		_begin_round()
		ev.append({"type": "round", "round": round_num})
	var u: Dictionary = units[queue[0]]
	if not u["alive"]:
		queue.pop_front()
		return ev
	if not _turn_started:
		_turn_started = true
		_start_turn(u, ev)
		if not u["alive"]:
			_end_turn(u, ev)
			events_log.append_array(ev)
			return ev
	if u["side"] == "party" and not auto and not forced_guard:
		ev.append({"type": "awaiting_input", "uid": u["uid"]})
		return ev
	_execute(u, _ai_action(u), ev)
	_end_turn(u, ev)
	events_log.append_array(ev)
	return ev

## Executes the player's action for the current party actor.
func submit(action: Dictionary) -> Array:
	var ev: Array = []
	if outcome != "" or queue.is_empty():
		return ev
	var u: Dictionary = units[queue[0]]
	if u["side"] != "party":
		return ev
	var check: Dictionary = _validate(u, action)
	if not check["ok"]:
		return [{"type": "invalid", "reason": check["reason"]}]
	if not _turn_started:
		_turn_started = true
		_start_turn(u, ev)
	if u["alive"]:
		_execute(u, action, ev)
	_end_turn(u, ev)
	events_log.append_array(ev)
	return ev

func run_auto(max_ticks: int = 20000) -> Dictionary:
	auto = true
	var n: int = 0
	while outcome == "" and n < max_ticks:
		tick()
		n += 1
	if outcome == "":
		var ev: Array = []
		_finish("timeout", ev)
	return get_result()

func _start_turn(u: Dictionary, ev: Array) -> void:
	for m in u["mods"].duplicate():
		if m["stat"] == "burn" and u["alive"]:
			var dmg: int = maxi(1, roundi(float(u["max_hp"]) * float(m["value"])))
			_apply_damage(-1, u, dmg, "burn", ev, {"status": "burn"})

func _end_turn(u: Dictionary, ev: Array) -> void:
	var kept: Array = []
	for m in u["mods"]:
		m["turns"] = int(m["turns"]) - 1
		if int(m["turns"]) > 0:
			kept.append(m)
	u["mods"] = kept
	if int(u["shield_turns"]) > 0:
		u["shield_turns"] = int(u["shield_turns"]) - 1
		if int(u["shield_turns"]) == 0:
			u["shield"] = 0
	if int(u["taunt_turns"]) > 0:
		u["taunt_turns"] = int(u["taunt_turns"]) - 1
	u["turns_taken"] = int(u["turns_taken"]) + 1
	if not queue.is_empty() and queue[0] == u["uid"]:
		queue.pop_front()
	_turn_started = false
	_check_outcome(ev)

func _check_outcome(ev: Array) -> void:
	if _alive_side("enemy").is_empty():
		_finish("victory", ev)
	elif _alive_side("party").is_empty():
		_finish("defeat", ev)

func _finish(result: String, ev: Array) -> void:
	outcome = result
	queue = []
	ev.append({"type": "end", "outcome": result})

# ============================== VALIDATION ===================================

func _validate(u: Dictionary, action: Dictionary) -> Dictionary:
	var t: String = String(action.get("type", ""))
	match t:
		"guard":
			return {"ok": true}
		"attack":
			return {"ok": not _foes_of(u).is_empty(), "reason": "no_target"}
		"skill":
			var sid: String = String(action.get("skill_id", ""))
			if not sid in u["skills"]:
				return {"ok": false, "reason": "unknown_skill"}
			var sk: Dictionary = Database.get_entry("basic_skills", sid)
			if int(u["sp"]) < _skill_cost(u, sk):
				return {"ok": false, "reason": "not_enough_sp"}
			return {"ok": true}
		"ultimate":
			if u["ultimate"] == null:
				return {"ok": false, "reason": "no_ultimate"}
			if int(u["ug"]) < int(rules["ug_max"]):
				return {"ok": false, "reason": "ug_not_full"}
			return {"ok": true}
		"medical":
			var item: String = String(action.get("item_id", ""))
			if not item in medical_slots or int(_item_counts.get(item, 0)) < 1:
				return {"ok": false, "reason": "no_medical"}
			if team_sp < int(rules["medical_team_sp"]):
				return {"ok": false, "reason": "not_enough_team_sp"}
			var tgt_uid: int = int(action.get("target_uid", -1))
			if tgt_uid < 0 or tgt_uid >= units.size() or not units[tgt_uid]["alive"] or units[tgt_uid]["side"] != "party":
				return {"ok": false, "reason": "bad_target"}
			return {"ok": true}
	return {"ok": false, "reason": "unknown_action"}

# ============================== EXECUTION ====================================

func _execute(u: Dictionary, action: Dictionary, ev: Array) -> void:
	if u["side"] == "party" and forced_guard:
		action = {"type": "guard"}
	match String(action["type"]):
		"attack":
			_do_basic_attack(u, int(action.get("target_uid", -1)), ev)
		"skill":
			var sk: Dictionary = Database.get_entry("basic_skills", action["skill_id"])
			if u["side"] == "party":
				u["sp"] = int(u["sp"]) - _skill_cost(u, sk)
			if sk["category"] != "attack":
				u["cd"][sk["id"]] = round_num + int(rules["ai"]["support_cooldown"])
			_use_skill(u, sk, int(action.get("target_uid", -1)), ev)
			_gain_ug(u, 1.0)
		"ultimate":
			var ult: Dictionary = Database.get_entry("ultimate_skills", u["ultimate"])
			u["ug"] = 0
			ev.append({"type": "ultimate", "source": u["uid"], "name": ult["name"]})
			_use_ultimate(u, ult, int(action.get("target_uid", -1)), ev)
		"medical":
			_use_medical(u, String(action["item_id"]), int(action["target_uid"]), ev)
		_:
			_do_guard(u, ev)

func _do_guard(u: Dictionary, ev: Array) -> void:
	var b: float = float(rules["guard_def_bonus"])
	_add_mod(u, "phys_def", b, 2)
	_add_mod(u, "magic_def", b, 2)
	if u["side"] == "party":
		u["sp"] = mini(int(u["sp_max"]), int(u["sp"]) + int(rules["hero_sp_per_basic_attack"]))
	ev.append({"type": "guard", "source": u["uid"]})

func _do_basic_attack(u: Dictionary, target_uid: int, ev: Array) -> void:
	var tgt: Dictionary = _pick_valid_target(u, target_uid)
	if tgt.is_empty():
		return
	var dtype: String = "physical"
	if u["side"] == "party":
		dtype = rules["basic_attack_type"][u["role"]]
	ev.append({"type": "use", "source": u["uid"], "name": "Attack", "skill": "BASIC"})
	_attack_hit(u, tgt, {"skill": "BASIC", "power": 100.0, "dtype": dtype, "elements": ["Normal"], "bcrit": 0.0, "bacc": 0.0}, ev)
	if u["side"] == "party":
		u["sp"] = mini(int(u["sp_max"]), int(u["sp"]) + int(rules["hero_sp_per_basic_attack"]))
		team_sp = mini(team_sp_max, team_sp + int(rules["team_sp_per_basic_attack"]))
		_gain_ug(u, 1.0)

func _gain_ug(u: Dictionary, factor: float) -> void:
	if u["side"] != "party" or u["ultimate"] == null:
		return
	var gain: int = ceili(float(rules["ug_per_action"]) * factor * (1.0 + float(u["trait_mods"].get("ug_gain", 0.0))))
	u["ug"] = mini(int(rules["ug_max"]), int(u["ug"]) + gain)

func _pick_valid_target(u: Dictionary, target_uid: int) -> Dictionary:
	var foes: Array = _foes_of(u)
	if foes.is_empty():
		return {}
	for f in foes:
		if int(f["taunt_turns"]) > 0:
			return f
	if target_uid >= 0 and target_uid < units.size():
		var t: Dictionary = units[target_uid]
		if t["alive"] and t["side"] != u["side"]:
			return t
	return foes[0]

func _resolve_targets(src: Dictionary, target_type: String, target_uid: int) -> Array:
	match target_type:
		"single_enemy":
			var t: Dictionary = _pick_valid_target(src, target_uid)
			return [] if t.is_empty() else [t]
		"all_enemies":
			return _foes_of(src)
		"self":
			return [src]
		"single_ally":
			if target_uid >= 0 and target_uid < units.size():
				var a: Dictionary = units[target_uid]
				if a["alive"] and a["side"] == src["side"]:
					return [a]
			return [_lowest_ratio(_friends_of(src))]
		"all_allies":
			return _friends_of(src)
	return []

func _use_skill(src: Dictionary, skill: Dictionary, target_uid: int, ev: Array) -> void:
	var effect = skill.get("effect")
	var power: float = float(skill["power"])
	var hostile: bool = skill["target"] in ["single_enemy", "all_enemies"]
	ev.append({"type": "use", "source": src["uid"], "name": skill["name"], "skill": skill["id"]})
	if effect != null and effect["type"] == "taunt":
		src["taunt_turns"] = int(effect["turns"])
		return
	var bcrit: float = 0.0
	var bacc: float = 0.0
	if effect != null and effect["type"] == "buff" and int(effect["turns"]) == 0:
		if effect["stat"] == "crit":
			bcrit = float(effect["value"]) * 100.0
		elif effect["stat"] == "accuracy":
			bacc = float(effect["value"]) * 100.0
	for t in _resolve_targets(src, skill["target"], target_uid):
		if hostile:
			if power > 0.0 and skill["damage_type"] != "none":
				var r: Dictionary = _attack_hit(src, t, {"skill": skill["id"], "power": power, "dtype": skill["damage_type"],
					"elements": _skill_elements(skill), "bcrit": bcrit, "bacc": bacc}, ev)
				if r["hit"]:
					_apply_effect(src, t, effect, int(r["dealt"]), ev)
			else:
				_apply_effect(src, t, effect, 0, ev)
		else:
			if skill["category"] == "heal" and power > 0.0:
				var amt: int = roundi(eff(src, "magic_atk") * power / 100.0 * (1.0 + float(src["trait_mods"].get("heal_power", 0.0))))
				ev.append(_heal_unit(src["uid"], t, amt))
			_apply_effect(src, t, effect, 0, ev)

func _use_ultimate(src: Dictionary, ult: Dictionary, target_uid: int, ev: Array) -> void:
	var power: float = float(ult["power"])
	if power > 0.0:
		var sk: Dictionary = {"id": ult["id"], "name": ult["name"], "element": ult["element"], "category": "attack",
			"target": ult["target"], "power": power, "damage_type": rules["ultimate_damage_type"][ult["role"]],
			"effect": null, "sp_cost": 0}
		_use_skill(src, sk, target_uid, ev)
		return
	# Support-type Ultimates have no numbers in the database: effect comes from the Role (battle_rules.ultimate_fallback).
	var fb: Dictionary = rules["ultimate_fallback"][ult["role"]]
	var turns: int = int(fb.get("turns", 3))
	for t in _resolve_targets(src, ult["target"], target_uid):
		match String(ult["role"]):
			"Healer":
				ev.append(_heal_unit(src["uid"], t, roundi(float(t["max_hp"]) * float(fb["heal_percent"]))))
				_cleanse(t)
			"Support":
				if t["side"] == src["side"]:
					_mod_event(src, t, "phys_atk", float(fb["buff"]), turns, ev)
					_mod_event(src, t, "magic_atk", float(fb["buff"]), turns, ev)
				else:
					_mod_event(src, t, "speed", float(fb["debuff_speed"]), turns, ev)
					_mod_event(src, t, "phys_atk", float(fb["debuff_atk"]), turns, ev)
					_mod_event(src, t, "magic_atk", float(fb["debuff_atk"]), turns, ev)
			"Defender":
				_shield_unit(src, t, float(fb["shield_percent"]), turns, ev)
				_mod_event(src, t, "phys_def", float(fb["def_buff"]), turns, ev)
				_mod_event(src, t, "magic_def", float(fb["def_buff"]), turns, ev)

func _use_medical(u: Dictionary, item_id: String, target_uid: int, ev: Array) -> void:
	var med: Dictionary = Database.get_entry("medical", item_id)
	var tgt: Dictionary = units[target_uid]
	team_sp -= int(rules["medical_team_sp"])
	_item_counts[item_id] = int(_item_counts[item_id]) - 1
	_items_used[item_id] = int(_items_used[item_id]) + 1
	ev.append({"type": "medical", "source": u["uid"], "target": tgt["uid"], "name": med["name"]})
	var p: float = 1.0 + float(u["trait_mods"].get("medical_power", 0.0))
	var e: Dictionary = med["effect"]
	match String(med["type"]):
		"heal_hp":
			ev.append(_heal_unit(u["uid"], tgt, roundi(float(e["hp_flat"]) * p)))
		"restore_sp":
			tgt["sp"] = mini(int(tgt["sp_max"]), int(tgt["sp"]) + roundi(float(e["sp_flat"]) * p))
		"heal_hp_sp":
			ev.append(_heal_unit(u["uid"], tgt, roundi(float(tgt["max_hp"]) * float(e["hp_percent"]) * p)))
			tgt["sp"] = mini(int(tgt["sp_max"]), int(tgt["sp"]) + roundi(float(e["sp_flat"]) * p))
		"cleanse":
			_cleanse(tgt)
		"shield":
			_shield_unit(u, tgt, float(e["shield_hp_percent"]), int(e["turns"]), ev)
		"gain_ug":
			tgt["ug"] = mini(int(rules["ug_max"]), int(tgt["ug"]) + int(e["ug_flat"]))

# ============================== COMBAT MATH ==================================

func _attack_hit(src: Dictionary, tgt: Dictionary, c: Dictionary, ev: Array) -> Dictionary:
	var hit_chance: float = clampf((eff(src, "accuracy") + float(c["bacc"]) - eff(tgt, "evasion")) / 100.0, float(rules["min_hit_chance"]), 1.0)
	if rng.randf() > hit_chance:
		ev.append({"type": "miss", "source": src["uid"], "target": tgt["uid"]})
		return {"hit": false, "dealt": 0}
	var atk_stat: String = "phys_atk" if c["dtype"] == "physical" else "magic_atk"
	var def_stat: String = "phys_def" if c["dtype"] == "physical" else "magic_def"
	var dmg: float = eff(src, atk_stat) * float(c["power"]) / 100.0 * (100.0 / (100.0 + eff(tgt, def_stat)))
	var mult: float = _element_mult(c["elements"], tgt["element"])
	dmg *= mult
	if not tgt["front"]:
		dmg *= float(rules["back_row_damage_mult"])
	var v: float = float(rules["damage_variance"])
	dmg *= 1.0 + rng.randf_range(-v, v)
	var crit: bool = rng.randf() < (eff(src, "crit") + float(c["bcrit"])) / 100.0
	if crit:
		dmg *= float(rules["crit_multiplier"])
	var dealt: int = _apply_damage(src["uid"], tgt, maxi(1, roundi(dmg)), String(c["skill"]), ev, {"crit": crit, "mult": mult})
	return {"hit": true, "dealt": dealt}

## Applies damage (shield first). Returns HP actually lost. Handles death + boss phases.
func _apply_damage(src_uid: int, tgt: Dictionary, amount: int, skill_id: String, ev: Array, meta: Dictionary = {}) -> int:
	var absorbed: int = mini(int(tgt["shield"]), amount)
	tgt["shield"] = int(tgt["shield"]) - absorbed
	var dealt: int = amount - absorbed
	tgt["hp"] = maxi(0, int(tgt["hp"]) - dealt)
	var e: Dictionary = {"type": "damage", "source": src_uid, "target": tgt["uid"], "amount": dealt,
		"absorbed": absorbed, "skill": skill_id, "killed": false}
	e.merge(meta)
	if tgt["side"] == "party" and dealt > 0:
		tgt["ug"] = mini(int(rules["ug_max"]), int(tgt["ug"]) + ceili(float(rules["ug_per_hit_taken"]) * (1.0 + float(tgt["trait_mods"].get("ug_gain", 0.0)))))
	if int(tgt["hp"]) <= 0:
		tgt["alive"] = false
		e["killed"] = true
		_record_death(tgt, src_uid, skill_id)
	ev.append(e)
	_check_phase(tgt, ev)
	return dealt

func _record_death(tgt: Dictionary, src_uid: int, skill_id: String) -> void:
	if tgt["side"] != "party":
		return
	var killer: Dictionary = units[src_uid] if src_uid >= 0 else {}
	var mates: Array = []
	for id in _party_hero_ids:
		if id != tgt["hero_id"]:
			mates.append(id)
	var rec: Dictionary = {"hero_id": tgt["hero_id"], "hero_name": tgt["name"], "round": round_num,
		"party": party_label, "killer": killer.get("name", "Status effect"),
		"killer_enemy_id": killer.get("enemy_id", ""), "killer_type": killer.get("etype", "status"),
		"skill": skill_id, "teammates": mates, "context": context.duplicate(true)}
	if lethal:
		fallen.append(rec)
	else:
		ko_list.append(rec)

func _check_phase(u: Dictionary, ev: Array) -> void:
	if u["side"] != "enemy" or not u["alive"]:
		return
	var phases: Array = u["phases"]
	while int(u["phase"]) + 1 < phases.size():
		var nxt: Dictionary = phases[int(u["phase"]) + 1]
		if float(u["hp"]) / float(u["max_hp"]) > float(nxt["hp_threshold"]):
			break
		u["phase"] = int(u["phase"]) + 1
		u["skills"] = nxt["skills"].duplicate()
		var sm: Dictionary = nxt["stat_mult"]
		u["stats"]["phys_atk"] = float(u["stats0"]["phys_atk"]) * float(sm.get("atk", 1.0))
		u["stats"]["magic_atk"] = float(u["stats0"]["magic_atk"]) * float(sm.get("atk", 1.0))
		u["stats"]["speed"] = float(u["stats0"]["speed"]) * float(sm.get("spd", 1.0))
		var sh: int = roundi(float(u["max_hp"]) * float(nxt["shield_percent"]))
		u["shield"] = int(u["shield"]) + sh
		u["shield_turns"] = 999
		ev.append({"type": "phase", "target": u["uid"], "phase": int(nxt["phase"]), "shield": sh})

func _heal_unit(src_uid: int, tgt: Dictionary, amount: int) -> Dictionary:
	if not tgt["alive"]:
		return {"type": "heal", "source": src_uid, "target": tgt["uid"], "amount": 0}
	var before: int = int(tgt["hp"])
	tgt["hp"] = mini(int(tgt["max_hp"]), before + maxi(0, amount))
	return {"type": "heal", "source": src_uid, "target": tgt["uid"], "amount": int(tgt["hp"]) - before}

func _add_mod(u: Dictionary, stat: String, value: float, turns: int) -> void:
	var kept: Array = []
	for m in u["mods"]:
		if m["stat"] == stat and (float(m["value"]) >= 0.0) == (value >= 0.0):
			continue
		kept.append(m)
	kept.append({"stat": stat, "value": value, "turns": turns})
	u["mods"] = kept

func _mod_event(src: Dictionary, t: Dictionary, stat: String, value: float, turns: int, ev: Array) -> void:
	if not t["alive"]:
		return
	_add_mod(t, stat, value, turns)
	ev.append({"type": "mod", "source": src["uid"], "target": t["uid"], "stat": stat, "value": value, "turns": turns})

func _shield_unit(src: Dictionary, t: Dictionary, percent: float, turns: int, ev: Array) -> void:
	if not t["alive"]:
		return
	var amt: int = roundi(float(t["max_hp"]) * percent)
	t["shield"] = int(t["shield"]) + amt
	t["shield_turns"] = maxi(int(t["shield_turns"]), turns)
	ev.append({"type": "shield", "source": src["uid"], "target": t["uid"], "amount": amt})

func _cleanse(t: Dictionary) -> void:
	var kept: Array = []
	for m in t["mods"]:
		if float(m["value"]) >= 0.0 and m["stat"] != "burn":
			kept.append(m)
	t["mods"] = kept

func _apply_effect(src: Dictionary, t: Dictionary, effect, dealt: int, ev: Array) -> void:
	if effect == null:
		return
	match String(effect["type"]):
		"buff", "debuff":
			if int(effect["turns"]) > 0:
				_mod_event(src, t, String(effect["stat"]), float(effect["value"]), int(effect["turns"]), ev)
		"shield":
			_shield_unit(src, t, float(effect["value"]), int(effect["turns"]), ev)
		"lifesteal":
			var h: int = roundi(float(dealt) * float(effect["value"]))
			if h > 0 and src["alive"]:
				ev.append(_heal_unit(src["uid"], src, h))
		"cleanse":
			_cleanse(t)

# ============================== AI ===========================================

func _lowest_ratio(list: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_r: float = 2.0
	for u in list:
		var r: float = float(u["hp"]) / float(u["max_hp"])
		if r < best_r:
			best_r = r
			best = u
	return best

func _lowest_hp(list: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_hp: int = 1 << 60
	for u in list:
		if int(u["hp"]) < best_hp:
			best_hp = int(u["hp"])
			best = u
	return best

func _ai_action(u: Dictionary) -> Dictionary:
	return _ai_hero(u) if u["side"] == "party" else _ai_enemy(u)

func _ai_hero(u: Dictionary) -> Dictionary:
	var ai: Dictionary = rules["ai"]
	var foes: Array = _foes_of(u)
	var friends: Array = _friends_of(u)
	var weakest_foe: Dictionary = _lowest_hp(foes)
	if u["ultimate"] != null and int(u["ug"]) >= int(rules["ug_max"]):
		return {"type": "ultimate", "target_uid": weakest_foe["uid"]}
	var hurt: Dictionary = _lowest_ratio(friends)
	var hurt_ratio: float = float(hurt["hp"]) / float(hurt["max_hp"])
	if hurt_ratio < float(ai["medical_hp_threshold"]) and team_sp >= int(rules["medical_team_sp"]):
		for item in medical_slots:
			var med: Dictionary = Database.get_entry("medical", item)
			if int(_item_counts.get(item, 0)) > 0 and med["type"] in ["heal_hp", "heal_hp_sp"]:
				return {"type": "medical", "item_id": item, "target_uid": hurt["uid"]}
	if hurt_ratio < float(ai["heal_hp_threshold"]):
		for sid in u["skills"]:
			var sk: Dictionary = Database.get_entry("basic_skills", sid)
			if sk["category"] == "heal" and int(u["sp"]) >= _skill_cost(u, sk) and round_num >= int(u["cd"].get(sid, 0)):
				return {"type": "skill", "skill_id": sid, "target_uid": hurt["uid"]}
	for sid in u["skills"]:
		var sk2: Dictionary = Database.get_entry("basic_skills", sid)
		var is_support: bool = sk2["category"] in ["buff", "shield"] or (sk2["category"] == "debuff" and float(sk2["power"]) == 0.0)
		if is_support and int(u["sp"]) >= _skill_cost(u, sk2) and round_num >= int(u["cd"].get(sid, 0)):
			var effect = sk2.get("effect")
			if effect != null and effect["type"] == "taunt":
				continue
			return {"type": "skill", "skill_id": sid, "target_uid": weakest_foe["uid"] if sk2["target"] == "single_enemy" else hurt["uid"]}
	if rng.randf() < float(ai["skill_chance"]):
		var best_id: String = ""
		var best_power: float = 0.0
		for sid in u["skills"]:
			var sk3: Dictionary = Database.get_entry("basic_skills", sid)
			if sk3["target"] in ["single_enemy", "all_enemies"] and float(sk3["power"]) > best_power and int(u["sp"]) >= _skill_cost(u, sk3):
				best_power = float(sk3["power"])
				best_id = sid
		if best_id != "":
			return {"type": "skill", "skill_id": best_id, "target_uid": weakest_foe["uid"]}
	return {"type": "attack", "target_uid": weakest_foe["uid"]}

func _ai_enemy(u: Dictionary) -> Dictionary:
	var ai: Dictionary = rules["ai"]
	var foes: Array = _foes_of(u)
	var friends: Array = _friends_of(u)
	if u["ultimate"] != null and u["phases"].size() > 0:
		var ph: Dictionary = u["phases"][int(u["phase"])]
		if ph.get("uses_ultimate", false) and (int(u["turns_taken"]) + 1) % int(ai["enemy_ultimate_every"]) == 0:
			return {"type": "ultimate", "target_uid": _random_foe(foes)["uid"]}
	var options: Array = ["BASIC"]
	options.append_array(u["skills"])
	var pick: String = options[rng.randi_range(0, options.size() - 1)]
	if pick == "BASIC":
		return {"type": "attack", "target_uid": _random_foe(foes)["uid"]}
	var sk: Dictionary = Database.get_entry("basic_skills", pick)
	var hurt: Dictionary = _lowest_ratio(friends)
	if sk["target"] in ["single_enemy", "all_enemies"]:
		return {"type": "skill", "skill_id": pick, "target_uid": _random_foe(foes)["uid"]}
	return {"type": "skill", "skill_id": pick, "target_uid": hurt["uid"]}

func _random_foe(foes: Array) -> Dictionary:
	var fw: float = float(rules["enemy_front_weight"])
	var total: float = 0.0
	for f in foes:
		total += fw if f["front"] else 1.0
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for f in foes:
		acc += fw if f["front"] else 1.0
		if roll < acc:
			return f
	return foes[foes.size() - 1]

# ============================== RESULT =======================================

func get_result() -> Dictionary:
	var survivors: Array = []
	for u in units:
		if u["side"] == "party" and u["alive"]:
			survivors.append(u["hero_id"])
	return {"outcome": outcome, "rounds": round_num, "fallen": fallen.duplicate(true), "ko": ko_list.duplicate(true),
		"survivors": survivors, "team_sp": team_sp}

## Writes HP/SP back to the Heroes and consumes the Medical items that were used.
func commit() -> void:
	for u in units:
		if u["side"] != "party":
			continue
		var hero: Dictionary = Roster.get_hero(u["hero_id"])
		if hero.is_empty():
			continue
		if u["alive"]:
			hero["hp"] = int(u["hp"])
		else:
			hero["hp"] = 0 if lethal else 1
		hero["sp"] = int(u["sp"])
	for item in _items_used:
		if int(_items_used[item]) > 0:
			Inventory.remove(item, int(_items_used[item]))

func format_event(e: Dictionary) -> String:
	match String(e["type"]):
		"round":
			return "— Round %d —" % int(e["round"])
		"use":
			return "%s uses %s" % [_lbl(int(e["source"])), e["name"]]
		"ultimate":
			return "%s unleashes ULTIMATE: %s!" % [_lbl(int(e["source"])), e["name"]]
		"damage":
			var s: String = "  %s takes %d damage" % [_lbl(int(e["target"])), int(e["amount"])]
			if e.get("crit", false): s += " (CRIT)"
			if float(e.get("mult", 1.0)) > 1.0: s += " (strong)"
			elif float(e.get("mult", 1.0)) < 1.0: s += " (weak)"
			if int(e["absorbed"]) > 0: s += " [shield -%d]" % int(e["absorbed"])
			if e["killed"]: s += " — DEFEATED"
			return s
		"miss":
			return "  %s misses %s" % [_lbl(int(e["source"])), _lbl(int(e["target"]))]
		"heal":
			return "  %s recovers %d HP" % [_lbl(int(e["target"])), int(e["amount"])]
		"mod":
			return "  %s %s %+d%% for %d turns" % [_lbl(int(e["target"])), e["stat"], roundi(float(e["value"]) * 100.0), int(e["turns"])]
		"shield":
			return "  %s gains a %d shield" % [_lbl(int(e["target"])), int(e["amount"])]
		"phase":
			return "  ⚠ %s enters Phase %d (+%d shield)" % [_lbl(int(e["target"])), int(e["phase"]), int(e["shield"])]
		"guard":
			return "%s guards" % _lbl(int(e["source"]))
		"medical":
			return "%s uses %s on %s" % [_lbl(int(e["source"])), e["name"], _lbl(int(e["target"]))]
		"awaiting_input":
			return "… waiting for %s" % _lbl(int(e["uid"]))
		"end":
			return "Battle ended: %s" % e["outcome"]
	return str(e)
