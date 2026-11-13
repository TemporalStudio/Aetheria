class_name SkipDay
extends RefCounted
## One in-game day (GDD Bab 12): Dormitory recovery, Training Ground growth, Town Skills,
## Happiness/Fear change, a possible Moral Dilemma, report, day+1, autosave.

static func run(rng: RandomNumberGenerator, autosave: bool = true) -> Dictionary:
	if Town.pending_dilemma != "":
		return {"ok": false, "reason": "dilemma_pending"}
	var rules: Dictionary = Database.town_rules
	var state: String = Master.town_state()
	var mental: Dictionary = Town.mental_modifiers()
	var eff_mult: float = float(mental.get("efficiency", 1.0))
	var speed_mult: float = float(mental.get("work_speed", 1.0))
	var report: Dictionary = {"day": Master.in_game_day, "town_state": state, "facilities": [], "recovery": [], "growth": [],
		"happiness_change": 0, "fear_change": 0, "dilemma_id": "", "fairy_note": ""}

	for fid in Town.FAC_IDS:
		var st: Dictionary = Town.status(fid)
		var staff_names: Array = []
		for sid in st["staff"]:
			staff_names.append(_name(sid))
		report["facilities"].append({"id": fid, "name": st["name"], "rank": st["rank"], "operational": st["operational"],
			"leader": _name(st["leader"]), "staff": staff_names, "parties": st["parties"]})

	var injured_start: bool = false
	for h in Roster.heroes.values():
		if float(h["hp"]) / float(HeroStats.compute(h)["max_hp"]) < float(rules["daily"]["injured_threshold"]):
			injured_start = true

	# --- Dormitory ---
	var resting: Dictionary = {}
	if Town.is_operational("FAC-DORM"):
		var dorm: Dictionary = Town.facilities["FAC-DORM"]
		var b: Dictionary = Town.facility_bonuses("FAC-DORM")
		var boost: float = float(rules["dorm"]["level_mult"][int(dorm["level"]) - 1]) * (1.0 + float(b.get("recovery_bonus", 0.0))) * eff_mult
		for pid in dorm["parties"]:
			for hid in Parties.hero_ids(pid):
				_recover(Roster.get_hero(hid), float(rules["dorm"]["hp_pct"]) * boost, float(rules["dorm"]["sp_pct"]) * boost, "dormitory", report)
				resting[hid] = true
	# Everyone else rests a little (passive recovery)
	for h in Roster.heroes.values():
		if not resting.has(h["id"]):
			_recover(h, float(rules["passive_recovery"]["hp_pct"]), float(rules["passive_recovery"]["sp_pct"]), "rest", report)

	# --- Training Ground ---
	if Town.is_operational("FAC-TRAIN"):
		var train: Dictionary = Town.facilities["FAC-TRAIN"]
		var tb: Dictionary = Town.facility_bonuses("FAC-TRAIN")
		var t: Dictionary = rules["training"]
		var lvl_mult: float = float(t["level_mult"][int(train["level"]) - 1])
		var chance: float = clampf((float(t["chance"]) + float(tb.get("growth_chance", 0.0))) * speed_mult * (1.0 + float(tb.get("work_speed", 0.0))), 0.0, 1.0)
		for pid in train["parties"]:
			for hid in Parties.hero_ids(pid):
				if rng.randf() < chance:
					_train(Roster.get_hero(hid), t, lvl_mult * eff_mult * (1.0 + float(tb.get("facility_efficiency", 0.0))), rng, report)

	# --- Happiness / Fear ---
	var d: Dictionary = rules["daily"]
	var dh: int = int(d["happiness_base"])
	var df: int = 0
	if Master.town_fear > int(d["fear_baseline"]):
		df += int(d["fear_calm"])
	if Town.is_operational("FAC-DORM"):
		dh += int(d["happiness_dorm_bonus"])
	for fid in Town.FAC_IDS:
		if Town.is_operational(fid):
			var fb: Dictionary = Town.facility_bonuses(fid)
			dh += roundi(float(fb.get("happiness_per_day", 0.0)))
			df += roundi(float(fb.get("fear_per_day", 0.0)))
	if injured_start:
		df += int(d["injured_fear"])
	var h0: int = Master.town_happiness
	var f0: int = Master.town_fear
	Master.adjust_town(dh, df)
	report["happiness_change"] = Master.town_happiness - h0
	report["fear_change"] = Master.town_fear - f0

	# --- Moral Dilemma ---
	if rng.randf() < float(rules["dilemma_chance"]):
		Town.pending_dilemma = Town.pick_dilemma(rng)
		report["dilemma_id"] = Town.pending_dilemma

	report["fairy_note"] = Fairy.skip_day_note(report)
	Master.in_game_day += 1
	Town.add_report(report)
	if autosave:
		SaveSystem.save_slot(0)
	var dilemma: Dictionary = {}
	if Town.pending_dilemma != "":
		dilemma = Database.get_entry("dilemmas", Town.pending_dilemma)
	return {"ok": true, "report": report, "dilemma": dilemma}

static func _name(hero_id) -> String:
	if hero_id == null:
		return "-"
	var h: Dictionary = Roster.get_hero(hero_id)
	return String(h.get("name", "?"))

static func _recover(hero: Dictionary, hp_pct: float, sp_pct: float, source: String, report: Dictionary) -> void:
	if hero.is_empty():
		return
	var mx: int = int(HeroStats.compute(hero)["max_hp"])
	var hp_gain: int = mini(mx - int(hero["hp"]), roundi(mx * hp_pct))
	var sp_gain: int = mini(int(hero["sp_max"]) - int(hero["sp"]), roundi(float(hero["sp_max"]) * sp_pct))
	if hp_gain <= 0 and sp_gain <= 0:
		return
	hero["hp"] = int(hero["hp"]) + maxi(0, hp_gain)
	hero["sp"] = int(hero["sp"]) + maxi(0, sp_gain)
	report["recovery"].append({"hero_id": hero["id"], "name": hero["name"], "hp": maxi(0, hp_gain), "sp": maxi(0, sp_gain), "source": source})

static func _train(hero: Dictionary, t: Dictionary, mult: float, rng: RandomNumberGenerator, report: Dictionary) -> void:
	if hero.is_empty():
		return
	var stat: String = HeroFactory._pick_key(t["weights"], rng)
	var range_: Array = t["gain"][stat]
	var amount: int = maxi(1, roundi(rng.randi_range(int(range_[0]), int(range_[1])) * mult))
	var cap: int = int(t["cap_per_star"][stat]) * int(hero["star"])
	var cur: int = int(hero["training_bonus"].get(stat, 0))
	var gain: int = mini(amount, cap - cur)
	if gain <= 0:
		report["growth"].append({"hero_id": hero["id"], "name": hero["name"], "stat": stat, "gain": 0, "capped": true})
		return
	hero["training_bonus"][stat] = cur + gain
	if stat == "max_hp":
		hero["hp"] = int(hero["hp"]) + gain
	report["growth"].append({"hero_id": hero["id"], "name": hero["name"], "stat": stat, "gain": gain, "capped": false})

## Short human-readable summary for the Skip Day screen.
static func summary_text(report: Dictionary) -> String:
	var lines: Array = []
	lines.append("Day %d — Town is %s" % [int(report["day"]), report["town_state"]])
	for f in report["facilities"]:
		lines.append("%s [%s]: %s" % [f["name"], f["rank"], "working (Leader: %s)" % f["leader"] if f["operational"] else "idle"])
	lines.append("Recovered: %d Heroes" % report["recovery"].size())
	for g in report["growth"]:
		lines.append("Training: %s %s" % [g["name"], "reached the cap on %s" % g["stat"] if g["capped"] else "+%d %s" % [int(g["gain"]), g["stat"]]])
	lines.append("Happiness %+d, Fear %+d" % [int(report["happiness_change"]), int(report["fear_change"])])
	if report["dilemma_id"] != "":
		lines.append("A dilemma awaits your decision.")
	return "\n".join(lines)
