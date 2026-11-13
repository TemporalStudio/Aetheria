extends UIScreen
## Vertical battle view: enemies on top, party at the bottom, Speed Action Queue in the middle.

var eng: BattleEngine
var floor_num: int = 1
var finished: bool = false
var running: bool = false
var pending: Dictionary = {}
var pending_kind: String = ""
var nodes: Dictionary = {}          # uid -> {"btn","hp","ug"}
var queue_label: Label
var round_label: Label
var hint_label: Label
var log_label: Label
var log_scroll: ScrollContainer
var sp_bar: ProgressBar
var sp_label: Label
var action_box: VBoxContainer
var cancel_btn: Button
var auto_btn: Button
var speed_btn: Button
var btn_skill: Button
var btn_ult: Button
var btn_med: Button
var log_lines: Array = []

func _init() -> void:
	show_header = false
	show_back = false

func on_back_request() -> bool:
	return finished

func build() -> void:
	eng = params["engine"]
	floor_num = int(params["floor"])
	add_theme_constant_override("separation", 8)
	round_label = UIKit.label("", 26, UIKit.C_ACCENT)
	add_child(round_label)

	var eg := GridContainer.new()
	eg.columns = 3
	add_child(eg)
	for u in eng.units:
		if u["side"] == "enemy":
			nodes[u["uid"]] = _make_card(u, eg, 96)

	queue_label = UIKit.label("", 20, UIKit.C_WARN)
	add_child(queue_label)
	log_scroll = UIKit.scroll()
	log_scroll.size_flags_vertical = Control.SIZE_FILL
	log_scroll.custom_minimum_size = Vector2(0, 170)
	log_label = UIKit.label("", 20, UIKit.C_TEXT)
	log_scroll.add_child(log_label)
	add_child(log_scroll)

	var pg := GridContainer.new()
	pg.columns = 3
	add_child(pg)
	for u in eng.units:
		if u["side"] == "party":
			nodes[u["uid"]] = _make_card(u, pg, 128)

	var sp_row := HBoxContainer.new()
	sp_label = UIKit.label("", 22, UIKit.C_ACCENT)
	sp_row.add_child(sp_label)
	sp_bar = UIKit.bar(0, eng.team_sp_max, UIKit.C_ACCENT, 16)
	sp_row.add_child(sp_bar)
	add_child(sp_row)
	hint_label = UIKit.label("", 22, UIKit.C_WARN)
	add_child(hint_label)

	action_box = VBoxContainer.new()
	add_child(action_box)
	var grid := GridContainer.new()
	grid.columns = 3
	action_box.add_child(grid)
	grid.add_child(UIKit.button("Attack", _on_attack, 76))
	btn_skill = UIKit.button("Skill", _on_skill, 76)
	grid.add_child(btn_skill)
	btn_ult = UIKit.button("Ultimate", _on_ultimate, 76)
	grid.add_child(btn_ult)
	btn_med = UIKit.button("Medical", _on_medical, 76)
	grid.add_child(btn_med)
	grid.add_child(UIKit.button("Guard", _on_guard, 76))
	cancel_btn = UIKit.button("Cancel", _cancel_target, 76)
	cancel_btn.visible = false
	grid.add_child(cancel_btn)
	action_box.visible = false

	var row := HBoxContainer.new()
	auto_btn = UIKit.button("AUTO: OFF", _toggle_auto, 70)
	speed_btn = UIKit.button("Speed: %dx" % GameSettings.battle_speed, _toggle_speed, 70)
	row.add_child(auto_btn)
	row.add_child(speed_btn)
	add_child(row)

	_log("Battle begins on Floor %d. Permanent death is active." % floor_num)
	_refresh()
	_loop()

# ---------------------------------------------------------------- cards
func _make_card(u: Dictionary, parent: Control, h: int) -> Dictionary:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	var b := UIKit.left_button("", _on_unit_pressed.bind(int(u["uid"])), h)
	b.add_theme_font_size_override("font_size", 19)
	v.add_child(b)
	var hp := UIKit.bar(u["hp"], u["max_hp"], UIKit.C_BAD if u["side"] == "enemy" else UIKit.C_GOOD, 14)
	v.add_child(hp)
	var ug: ProgressBar = null
	if u["side"] == "party":
		ug = UIKit.bar(0, 100, UIKit.C_WARN, 8)
		v.add_child(ug)
	parent.add_child(v)
	return {"btn": b, "hp": hp, "ug": ug}

func _refresh() -> void:
	var actor_uid: int = -1
	if not eng.queue.is_empty() and eng.outcome == "":
		actor_uid = int(eng.queue[0])
	for u in eng.units:
		var n: Dictionary = nodes[u["uid"]]
		var btn: Button = n["btn"]
		var extra: String = ""
		if int(u["shield"]) > 0:
			extra += " +%d sh" % int(u["shield"])
		if u["side"] == "enemy":
			if u["phases"].size() > 0:
				extra += " · Ph%d" % (int(u["phase"]) + 1)
			btn.text = "%s %s\nHP %d/%d%s" % [u["label"], u["name"], int(u["hp"]), int(u["max_hp"]), extra]
		else:
			btn.text = "%s\n%s\nHP %d/%d%s\nSP %d" % [u["label"], u["name"], int(u["hp"]), int(u["max_hp"]), extra, int(u["sp"])]
			n["ug"].value = int(u["ug"])
		n["hp"].max_value = maxf(1.0, float(u["max_hp"]))
		n["hp"].value = int(u["hp"])
		btn.modulate = Color(1, 1, 1, 1.0 if u["alive"] else 0.35)
		if int(u["uid"]) == actor_uid:
			btn.add_theme_stylebox_override("normal", UIKit.box(UIKit.C_ACCENT.darkened(0.35), 14, UIKit.C_ACCENT, 3, 12))
		else:
			btn.remove_theme_stylebox_override("normal")
	round_label.text = "Floor %d · Round %d" % [floor_num, eng.round_num]
	queue_label.text = "Queue: " + eng.queue_text()
	sp_label.text = "Team SP %d/%d" % [eng.team_sp, eng.team_sp_max]
	sp_bar.value = eng.team_sp
	auto_btn.text = "AUTO: ON" if eng.auto else "AUTO: OFF"

func _log(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > 60:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)
	await get_tree().process_frame
	if is_instance_valid(log_scroll):
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

# ---------------------------------------------------------------- loop
func _loop() -> void:
	if running:
		return
	running = true
	while is_inside_tree() and not finished:
		var ev: Array = eng.tick()
		var waiting: bool = false
		var slow: bool = false
		for e in ev:
			if e["type"] == "awaiting_input":
				waiting = true
			else:
				_log(eng.format_event(e))
				if e["type"] in ["damage", "heal", "miss", "use", "ultimate", "guard", "medical", "phase"]:
					slow = true
		_refresh()
		if eng.outcome != "":
			running = false
			_on_end()
			return
		if waiting:
			_open_actions()
			break
		action_box.visible = false
		await get_tree().create_timer((0.55 / float(GameSettings.battle_speed)) if slow else 0.02).timeout
	running = false

func _open_actions() -> void:
	var actor: Dictionary = eng.units[eng.queue[0]]
	action_box.visible = true
	hint_label.text = "%s's turn (%s)" % [actor["name"], actor["role"]]
	btn_skill.disabled = actor["skills"].is_empty()
	btn_ult.disabled = actor["ultimate"] == null or int(actor["ug"]) < int(eng.rules["ug_max"])
	btn_ult.text = "Ultimate" if actor["ultimate"] == null else "Ultimate %d%%" % mini(100, int(actor["ug"]))
	btn_med.disabled = eng.medical_slots.is_empty() or eng.team_sp < int(eng.rules["medical_team_sp"])
	cancel_btn.visible = false

func _actor() -> Dictionary:
	return eng.units[eng.queue[0]]

# ---------------------------------------------------------------- actions
func _submit(action: Dictionary) -> void:
	pending = {}
	pending_kind = ""
	var ev: Array = eng.submit(action)
	for e in ev:
		if e["type"] == "invalid":
			app.toast("Cannot do that (%s)." % e["reason"], UIKit.C_WARN)
			_open_actions()
			return
	for e in ev:
		_log(eng.format_event(e))
	action_box.visible = false
	hint_label.text = ""
	_refresh()
	if eng.outcome != "":
		_on_end()
	else:
		_loop()

func _alive(side: String) -> Array:
	var out: Array = []
	for u in eng.units:
		if u["side"] == side and u["alive"]:
			out.append(u)
	return out

func _begin_target(action: Dictionary, kind: String) -> void:
	var side: String = "enemy" if kind == "enemy" else "party"
	var options: Array = _alive(side)
	if kind == "enemy" and options.size() == 1:
		action["target_uid"] = options[0]["uid"]
		_submit(action)
		return
	pending = action
	pending_kind = kind
	hint_label.text = "Tap %s to target" % ("an enemy" if kind == "enemy" else "an ally")
	cancel_btn.visible = true

func _cancel_target() -> void:
	pending = {}
	pending_kind = ""
	_open_actions()

func _on_unit_pressed(uid: int) -> void:
	if pending.is_empty():
		return
	var u: Dictionary = eng.units[uid]
	var ok: bool = u["alive"] and ((pending_kind == "enemy" and u["side"] == "enemy") or (pending_kind == "ally" and u["side"] == "party"))
	if not ok:
		app.toast("Not a valid target.", UIKit.C_WARN)
		return
	var action: Dictionary = pending.duplicate()
	action["target_uid"] = uid
	_submit(action)

func _on_attack() -> void:
	_begin_target({"type": "attack"}, "enemy")

func _on_guard() -> void:
	_submit({"type": "guard"})

func _on_skill() -> void:
	var actor: Dictionary = _actor()
	var items: Array = []
	for sid in actor["skills"]:
		var sk: Dictionary = Database.get_entry("basic_skills", sid)
		items.append({"text": "%s\n%s" % [sk["name"], UIKit.skill_text(sk)], "value": sid, "disabled": int(actor["sp"]) < eng._skill_cost(actor, sk)})
	app.picker("Skill (SP %d)" % int(actor["sp"]), items, _on_skill_picked)

func _on_skill_picked(sid) -> void:
	var sk: Dictionary = Database.get_entry("basic_skills", sid)
	var action: Dictionary = {"type": "skill", "skill_id": sid}
	match String(sk["target"]):
		"single_enemy":
			_begin_target(action, "enemy")
		"single_ally":
			_begin_target(action, "ally")
		_:
			action["target_uid"] = -1
			_submit(action)

func _on_ultimate() -> void:
	var actor: Dictionary = _actor()
	var ult: Dictionary = Database.get_entry("ultimate_skills", actor["ultimate"])
	var action: Dictionary = {"type": "ultimate"}
	if ult["target"] == "single_enemy":
		_begin_target(action, "enemy")
	else:
		action["target_uid"] = -1
		_submit(action)

func _on_medical() -> void:
	var items: Array = []
	for id in eng.medical_slots:
		var med: Dictionary = Database.get_entry("medical", id)
		var left: int = int(eng._item_counts.get(id, 0))
		items.append({"text": "%s ×%d\n%s" % [med["name"], left, med["type"]], "value": id, "disabled": left < 1})
	app.picker("Medical (costs 1 Team SP)", items, _on_medical_picked)

func _on_medical_picked(id) -> void:
	_begin_target({"type": "medical", "item_id": id}, "ally")

func _toggle_auto() -> void:
	eng.auto = not eng.auto
	auto_btn.text = "AUTO: ON" if eng.auto else "AUTO: OFF"
	if eng.auto and not running and not finished:
		action_box.visible = false
		pending = {}
		_loop()

func _toggle_speed() -> void:
	GameSettings.battle_speed = 1 if GameSettings.battle_speed == 2 else 2
	GameSettings.save_settings()
	speed_btn.text = "Speed: %dx" % GameSettings.battle_speed

# ---------------------------------------------------------------- end
func _on_end() -> void:
	finished = true
	action_box.visible = false
	var res: Dictionary = BattleRunner.finish_tower(eng, floor_num)
	app.refresh_header()
	var lines: Array = []
	match String(res["outcome"]):
		"victory":
			lines.append("VICTORY — Floor %d cleared in %d rounds." % [floor_num, int(res["rounds"])])
		"defeat":
			lines.append("DEFEAT — your Party was wiped out.")
		_:
			lines.append("The battle dragged on too long and your Party withdrew.")
	var rw: Dictionary = res["rewards"]
	if not rw.is_empty():
		var parts: Array = ["%d Gold" % int(rw["gold"]), "%d EXP each" % int(rw["exp"])]
		if int(rw["gems"]) > 0:
			parts.append("%d Gems" % int(rw["gems"]))
		lines.append("Rewards: " + ", ".join(parts))
		if not rw["drops"].is_empty():
			var drops: Array = []
			for d in rw["drops"]:
				var bits: PackedStringArray = String(d).split(" x")
				drops.append("%s ×%s" % [UIKit.item_name(bits[0]), bits[1]])
			lines.append("Drops: " + ", ".join(drops))
	if not res["memorials"].is_empty():
		lines.append("\nFALLEN — buried in Athanatos:")
		for m in res["memorials"]:
			lines.append("• %s (Lv%d %s): %s\n  “%s”" % [m["name"], int(m["level"]), m["role"], m["cause"]["text"], m["inscription"]])
	var survivors: int = res["survivors"].size()
	lines.append("\nSurvivors: %d" % survivors)
	_log("— " + String(res["outcome"]).to_upper() + " —")
	app.dialog("Battle result", "\n".join(lines), [["Return", _leave]], 600)

func _leave() -> void:
	app.back()
