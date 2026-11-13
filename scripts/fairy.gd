extends Node
## Autoload `Fairy` (GDD Bab 14): Mood, Personality, Trust, Knowledge, Memories, Mistakes.
## Rule-based (no external AI). Every piece of advice is computed from the CURRENT game state:
## risk analysis runs real battle simulations of the real Party, so numbers match what the engine does.
## Fairy never changes game state on her own; she only advises (apply_suggestion is called by the player's action).

var fairy_name: String = "Lumi"
var personality: String = "Cheerful"
var mood_score: int = 0                   # -100..100
var trust: int = 50                       # 0..100
var knowledge: Dictionary = {"enemies_seen": {}}
var memories: Array = []
var mistakes: Array = []
var predictions: Dictionary = {}          # "P1:12" -> last risk analysis (to be judged after the battle)
var last_suggestion: Dictionary = {}      # party_id -> slots she suggested
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	Roster.hero_recruited.connect(_on_recruited)
	Athanatos.hero_fallen.connect(_on_fallen)

## New game: pick a personality and forget everything.
func reset() -> void:
	var rules: Dictionary = Database.fairy_rules
	var keys: Array = rules["personalities"].keys()
	personality = keys[rng.randi_range(0, keys.size() - 1)]
	fairy_name = rules["names"][rng.randi_range(0, rules["names"].size() - 1)]
	mood_score = 0
	trust = int(rules["trust"]["start"])
	knowledge = {"enemies_seen": {}}
	memories = []
	mistakes = []
	predictions = {}
	last_suggestion = {}

# ============================== MOOD / TEXT ==================================

func mood_label() -> String:
	var t: Dictionary = Database.fairy_rules["mood"]["thresholds"]
	if mood_score >= int(t["excited"]): return "excited"
	if mood_score >= int(t["happy"]): return "happy"
	if mood_score <= int(t["sad"]): return "sad"
	if mood_score <= int(t["worried"]): return "worried"
	return "neutral"

func adjust_mood(delta: int) -> void:
	mood_score = clampi(mood_score + delta, -100, 100)

func adjust_trust(delta: float) -> void:
	var gain: float = float(Database.fairy_rules["personalities"][personality]["trust_gain"]) if delta > 0.0 else 1.0
	trust = clampi(trust + roundi(delta * gain), 0, 100)

func _t(key: String, data: Dictionary = {}) -> String:
	return String(Database.fairy_rules["templates"][key]).format(data)

## Wraps a message in her personality + current mood. kind "risk"/"suggest" also gets trust-based flavour.
func _say(body: String, kind: String = "plain") -> String:
	var p: Dictionary = Database.fairy_rules["personalities"][personality]
	var openers: Array = p["openers"][mood_label()]
	var out: String = String(openers[rng.randi_range(0, openers.size() - 1)]) + " "
	if kind != "plain" and trust < int(Database.fairy_rules["trust"]["low"]):
		out += "(I am not sure you will listen, but...) "
	out += body
	if kind != "plain":
		var closers: Array = p["closers"]
		out += " " + String(closers[rng.randi_range(0, closers.size() - 1)])
	return out

func _signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)

func _names(list: Array) -> Dictionary:
	return {"names": ", ".join(list), "verb": "is" if list.size() == 1 else "are"}

# ============================== MEMORIES =====================================

func remember(type: String, text: String, data: Dictionary = {}) -> void:
	memories.append({"day": Master.in_game_day, "type": type, "text": text, "data": data})
	while memories.size() > int(Database.fairy_rules["memory_limit"]):
		memories.pop_front()

func recent_memories(n: int = 5) -> Array:
	return memories.slice(maxi(0, memories.size() - n))

func _on_recruited(hero: Dictionary) -> void:
	adjust_mood(int(Database.fairy_rules["mood"]["events"]["recruit"]))
	remember("recruit", _t("memory_recruit", {"name": hero["name"], "star": hero["star"], "role": hero["role"]}))

func _on_fallen(mem: Dictionary) -> void:
	adjust_mood(int(Database.fairy_rules["mood"]["events"]["hero_fell"]))
	remember("death", _t("memory_fell", {"name": mem["name"], "place": mem["location"], "killer": mem["cause"]["killer"]}))

# ============================== KNOWLEDGE ====================================

## Only enemies she has actually fought are revealed.
func bestiary_entry(enemy_id: String) -> Dictionary:
	var e: Dictionary = Database.get_entry("enemies", enemy_id)
	if e.is_empty() or not knowledge["enemies_seen"].has(enemy_id):
		return {"known": false, "name": "???"}
	var skill_names: Array = []
	for sid in e["skills"]:
		skill_names.append(Database.get_entry("basic_skills", sid)["name"])
	return {"known": true, "name": e["name"], "type": e["type"], "element": e["element"], "base_stats": e["base_stats"], "skills": skill_names}

func _familiarity(floor_data: Dictionary) -> float:
	var ids: Dictionary = {}
	for x in floor_data["enemies"]:
		ids[x["enemy"]] = true
	var seen: int = 0
	for id in ids:
		if knowledge["enemies_seen"].has(id):
			seen += 1
	return float(seen) / float(ids.size())

# ============================== PARTY SUGGESTION =============================

## Builds the best Party from Heroes that are available right now. Does not change anything.
func suggest_party(party_id: String, floor_num: int = 0) -> Dictionary:
	var region: String = ""
	if floor_num > 0 and not Database.get_floor(floor_num).is_empty():
		region = Database.get_floor(floor_num)["region_element"]
	var adv: Dictionary = Database.battle_rules["element"]["advantage"]
	var cands: Array = []
	for h in Roster.heroes.values():
		var id: String = h["id"]
		if int(h["hp"]) <= 0 or not (Parties.is_available(id) or Parties.hero_party(id) == party_id):
			continue
		var st: Dictionary = HeroStats.compute(h)
		var ratio: float = float(h["hp"]) / float(st["max_hp"])
		var rating: float = float(st["max_hp"]) / 8.0 + maxf(float(st["phys_atk"]), float(st["magic_atk"])) * 1.2 \
			+ (float(st["phys_def"]) + float(st["magic_def"])) * 0.5 + float(st["speed"])
		rating *= 0.5 + 0.5 * ratio
		if region != "":
			if region in adv.get(h["element"], []):
				rating *= 1.15
			elif h["element"] in adv.get(region, []):
				rating *= 0.85
		cands.append({"hero": h, "rating": rating, "ratio": ratio})
	if cands.is_empty():
		return {"ok": false, "text": _say(_t("suggest_none"), "suggest")}
	cands.sort_custom(func(a, b): return a["rating"] > b["rating"])

	var quota: Dictionary = {"Defender": 1, "Healer": 1, "Attacker": 2, "Support": 1}
	var chosen: Array = []
	var used: Dictionary = {}
	for role in ["Defender", "Healer", "Attacker", "Support"]:
		var need: int = quota[role]
		for c in cands:
			if need == 0:
				break
			if c["hero"]["role"] == role and not used.has(c["hero"]["id"]):
				chosen.append(c)
				used[c["hero"]["id"]] = true
				need -= 1
	for c in cands:
		if chosen.size() >= 5:
			break
		if not used.has(c["hero"]["id"]):
			chosen.append(c)
			used[c["hero"]["id"]] = true
	var front_priority: Dictionary = {"Defender": 0, "Attacker": 1, "Support": 2, "Healer": 3}
	chosen.sort_custom(func(a, b): return front_priority[a["hero"]["role"]] < front_priority[b["hero"]["role"]])

	var slots: Array = [null, null, null, null, null]
	var rows: Array = []
	var hurt: Array = []
	var has_healer: bool = false
	for i in chosen.size():
		var h: Dictionary = chosen[i]["hero"]
		slots[i] = h["id"]
		rows.append("%s %s (%s, %s, %d★ Lv%d)" % ["Front" if i < 3 else "Back", h["name"], h["role"], h["element"], h["star"], h["level"]])
		if h["role"] == "Healer":
			has_healer = true
		if chosen[i]["ratio"] < float(Database.fairy_rules["risk"]["low_hp_threshold"]):
			hurt.append(h["name"])
	var warnings: Array = []
	if not has_healer:
		warnings.append(_t("suggest_warn_no_healer"))
	if chosen.size() < 5:
		warnings.append(_t("suggest_warn_small", {"n": chosen.size()}))
	if not hurt.is_empty():
		warnings.append(_t("suggest_warn_hurt", _names(hurt)))
	last_suggestion[party_id] = slots.duplicate()
	var text: String = _say(_t("suggest_intro") + "\n" + "\n".join(rows) + ("\n" + "\n".join(warnings) if not warnings.is_empty() else ""), "suggest")
	return {"ok": true, "slots": slots, "rows": rows, "warnings": warnings, "text": text}

## Applies a suggestion (call this only when the player taps "Use suggestion").
func apply_suggestion(party_id: String, suggestion: Dictionary) -> bool:
	if not suggestion.get("ok", false):
		return false
	for i in 5:
		Parties.clear_slot(party_id, i)
	for i in 5:
		if suggestion["slots"][i] != null:
			Parties.set_slot(party_id, i, suggestion["slots"][i])
	return true

# ============================== RISK ANALYSIS ================================

## Runs real simulated battles (AUTO behaviour) with the Party as it is right now. Nothing is changed in the game.
func analyze_risk(party_id: String, floor_num: int) -> Dictionary:
	var rules: Dictionary = Database.fairy_rules
	var ready: Dictionary = Parties.battle_ready(party_id)
	if not ready["ok"]:
		return {"ok": false, "reason": ready["reason"], "text": _say(_t("suggest_none"), "risk")}
	var f: Dictionary = Database.get_floor(floor_num)
	if f.is_empty() or floor_num > Master.highest_floor + 1 or Town.party_busy(party_id) != "":
		return {"ok": false, "reason": "cannot_enter"}
	var runs: int = int(rules["risk"]["runs"])
	var seed0: int = hash([Master.in_game_day, floor_num, party_id])
	var wins: int = 0
	var any_death: int = 0
	var wipes: int = 0
	var fallen_total: int = 0
	var per_hero: Dictionary = {}
	for i in runs:
		var r: Dictionary = BattleRunner.simulate_tower(party_id, floor_num, seed0 + i)
		if r["outcome"] == "invalid":
			return {"ok": false, "reason": "cannot_enter"}
		if r["outcome"] == "victory":
			wins += 1
		var n: int = r["fallen"].size()
		fallen_total += n
		if n > 0:
			any_death += 1
		if r["survivors"].is_empty():
			wipes += 1
		for rec in r["fallen"]:
			per_hero[rec["hero_id"]] = int(per_hero.get(rec["hero_id"], 0)) + 1
	var p_win: float = float(wins) / runs
	var p_death: float = float(any_death) / runs
	var fam: float = _familiarity(f)
	var p_eff: float = p_death + float(rules["personalities"][personality]["risk_offset"]) + float(rules["risk"]["unknown_margin"]) * (1.0 - fam)
	var label: String = "Deadly"
	for lv in rules["risk"]["levels"]:
		if p_eff < float(lv[1]):
			label = lv[0]
			break

	var hero_risk: Array = []
	var warnings: Array = []
	var low_hp: Array = []
	var weak: Array = []
	var has_healer: bool = false
	var region: String = f["region_element"]
	var adv: Dictionary = Database.battle_rules["element"]["advantage"]
	for id in Parties.hero_ids(party_id):
		var h: Dictionary = Roster.get_hero(id)
		hero_risk.append({"id": id, "name": h["name"], "p_death": float(per_hero.get(id, 0)) / runs})
		if h["role"] == "Healer" and int(h["hp"]) > 0:
			has_healer = true
		if float(h["hp"]) / float(HeroStats.compute(h)["max_hp"]) < float(rules["risk"]["low_hp_threshold"]):
			low_hp.append(h["name"])
		if h["element"] in adv.get(region, []):
			weak.append(h["name"])
	hero_risk.sort_custom(func(a, b): return a["p_death"] > b["p_death"])
	if not has_healer:
		warnings.append(_t("warn_no_healer"))
	if not low_hp.is_empty():
		warnings.append(_t("warn_low_hp", _names(low_hp)))
	var med_empty: bool = true
	for m in Parties.get_party(party_id)["medical"]:
		if m != null:
			med_empty = false
	if med_empty:
		warnings.append(_t("warn_no_medical"))
	if not weak.is_empty():
		var wd: Dictionary = _names(weak)
		wd["element"] = region
		warnings.append(_t("warn_element_weak", wd))
	if fam < 1.0:
		warnings.append(_t("warn_unknown"))
	var past: Array = []
	for m in Roster.memorials:
		if int(m["battle"]["floor"]) == floor_num:
			past.append(m["name"])
	if not past.is_empty():
		warnings.append(_t("warn_past_deaths", {"n": past.size(), "names": ", ".join(past)}))

	var body: String = ""
	if not mistakes.is_empty() and Master.in_game_day - int(mistakes[-1]["day"]) <= int(rules["recent_mistake_days"]):
		body += _t("mistake_admit", {"what": mistakes[-1]["what"]}) + " "
	body += _t("risk_" + label, {"floor": floor_num, "win": roundi(p_win * 100.0), "death": roundi(p_death * 100.0)})
	if not hero_risk.is_empty() and float(hero_risk[0]["p_death"]) >= float(rules["risk"]["top_risk_hero_min"]):
		body += " " + _t("risk_weak_hero", {"name": hero_risk[0]["name"], "pct": roundi(float(hero_risk[0]["p_death"]) * 100.0)})
	if not warnings.is_empty():
		body += "\n" + "\n".join(warnings)

	var slots: Array = Parties.get_party(party_id)["slots"]
	predictions["%s:%d" % [party_id, floor_num]] = {"floor": floor_num, "party": party_id, "p_death": p_death, "label": label,
		"day": Master.in_game_day, "followed": last_suggestion.get(party_id, []) == slots}
	return {"ok": true, "floor": floor_num, "party": party_id, "runs": runs, "win_rate": p_win, "p_death": p_death, "p_wipe": float(wipes) / runs,
		"avg_fallen": float(fallen_total) / runs, "label": label, "familiarity": fam, "hero_risk": hero_risk, "warnings": warnings,
		"text": _say(body, "risk")}

## Called by BattleRunner.finish_tower: learns enemies, updates mood/memory, and judges her own prediction.
func on_battle_finished(e: BattleEngine, res: Dictionary) -> void:
	var rules: Dictionary = Database.fairy_rules
	var floor_num: int = int(e.context.get("floor", 0))
	var pid: String = e.party_label
	for u in e.units:
		if u["side"] == "enemy":
			knowledge["enemies_seen"][u["enemy_id"]] = true
	var won: bool = res["outcome"] == "victory"
	adjust_mood(int(rules["mood"]["events"]["victory"] if won else rules["mood"]["events"]["defeat"]))
	remember("battle", _t("memory_win" if won else "memory_loss", {"floor": floor_num, "party": pid}))
	var key: String = "%s:%d" % [pid, floor_num]
	if not predictions.has(key):
		return
	var pred: Dictionary = predictions[key]
	predictions.erase(key)
	if Master.in_game_day - int(pred["day"]) > 1:
		return
	var died: bool = res["fallen"].size() > 0 or res["ko"].size() > 0
	var what: String = ""
	if pred["label"] == "Low" and died:
		what = "I called it safe, but a Hero fell"
	elif float(pred["p_death"]) >= float(rules["risk"]["mistake_if_pdeath_at_least_but_safe"]) and not died and won:
		what = "I feared the worst, but everyone survived"
	if what != "":
		mistakes.append({"day": Master.in_game_day, "floor": floor_num, "party": pid, "what": what, "predicted": pred["label"], "p_death": pred["p_death"]})
		while mistakes.size() > int(rules["mistake_limit"]):
			mistakes.pop_front()
		adjust_trust(float(rules["trust"]["mistake"]))
		adjust_mood(int(rules["mood"]["events"]["mistake"]))
		remember("mistake", _t("memory_mistake", {"floor": floor_num, "what": what}))
	else:
		adjust_trust(float(rules["trust"]["correct"]))
		if pred["followed"] and won and not died:
			adjust_trust(float(rules["trust"]["followed_win"]))

# ============================== TOWN & REPORTS ===============================

## Warnings about the Town (Fear, Happiness, idle facilities, injuries, pending decisions).
func town_briefing() -> Dictionary:
	var rules: Dictionary = Database.fairy_rules["town"]
	var lines: Array = []
	var level: String = "ok"
	var state: String = Master.town_state()
	if state == "panicked":
		lines.append(_t("town_panic"))
		level = "danger"
	elif Master.town_fear >= int(rules["fear_warn"]):
		lines.append(_t("town_fear", {"fear": Master.town_fear}))
		level = "warn"
	if state == "burnout":
		lines.append(_t("town_burnout"))
		level = "danger"
	elif Master.town_happiness <= int(rules["happiness_warn"]):
		lines.append(_t("town_happiness", {"happiness": Master.town_happiness}))
		if level == "ok":
			level = "warn"
	var injured: int = 0
	for h in Roster.heroes.values():
		if float(h["hp"]) / float(HeroStats.compute(h)["max_hp"]) < float(rules["injured_threshold"]):
			injured += 1
	if injured > 0:
		lines.append(_t("town_injured", {"n": injured}))
		if level == "ok":
			level = "warn"
	for fid in Town.FAC_IDS:
		var st: Dictionary = Town.status(fid)
		if not st["operational"] and (st["leader"] != null or not st["staff"].is_empty() or not st["parties"].is_empty()) and state != "panicked":
			lines.append(_t("town_idle", {"name": st["name"]}))
	if Town.pending_dilemma != "":
		lines.append(_t("town_dilemma"))
	if lines.is_empty():
		lines.append(_t("town_ok"))
	return {"level": level, "lines": lines, "text": _say("\n".join(lines))}

## Short note stored in the Skip Day report (report["fairy_note"]).
func skip_day_note(report: Dictionary) -> String:
	var ev: Dictionary = Database.fairy_rules["mood"]["events"]
	var d: int = -int(Database.fairy_rules["mood"]["decay_per_day"]) if mood_score > 0 else int(Database.fairy_rules["mood"]["decay_per_day"])
	mood_score = 0 if absi(mood_score) <= absi(d) else mood_score + d
	var state: String = Master.town_state()
	if state == "panicked":
		adjust_mood(int(ev["town_panic"]))
	elif state == "inspired":
		adjust_mood(int(ev["town_inspired"]))
	var trained: int = 0
	for g in report["growth"]:
		if not g["capped"]:
			trained += 1
	var line: String = _t("skip_summary", {"day": report["day"], "rested": report["recovery"].size(), "trained": trained,
		"dh": _signed(int(report["happiness_change"])), "df": _signed(int(report["fear_change"]))})
	var brief: Dictionary = town_briefing()
	if brief["level"] != "ok":
		line += " " + brief["lines"][0]
	if report["dilemma_id"] != "":
		line += " " + _t("town_dilemma")
	remember("day", line)
	return _say(line)

## Narration for exploration/events (used by the Explore Dungeon system later).
func narrate(event: String, data: Dictionary = {}) -> String:
	var key: String = "narrate_" + event
	if not Database.fairy_rules["templates"].has(key):
		return ""
	return _say(_t(key, data))

# ============================== SAVE =========================================

func to_save() -> Dictionary:
	return {"name": fairy_name, "personality": personality, "mood": mood_score, "trust": trust, "knowledge": knowledge.duplicate(true),
		"memories": memories.duplicate(true), "mistakes": mistakes.duplicate(true), "last_suggestion": last_suggestion.duplicate(true)}

func from_save(d: Dictionary) -> void:
	if d.is_empty():
		reset()
		return
	fairy_name = d.get("name", "Lumi")
	personality = d.get("personality", "Cheerful")
	mood_score = int(d.get("mood", 0))
	trust = int(d.get("trust", 50))
	knowledge = d.get("knowledge", {"enemies_seen": {}})
	memories = d.get("memories", [])
	mistakes = d.get("mistakes", [])
	last_suggestion = d.get("last_suggestion", {})
	predictions = {}
