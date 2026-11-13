extends UIScreen

func _init() -> void:
	screen_title = "Town Square"

func build() -> void:
	var sc := UIKit.scroll()
	add_child(sc)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(root)
	var brief: Dictionary = Fairy.town_briefing()
	var c := UIKit.card(root)
	c.add_child(UIKit.label("Day %d · Town is %s" % [Master.in_game_day, Master.town_state().capitalize()], 28, UIKit.C_ACCENT))
	var hb := HBoxContainer.new()
	hb.add_child(UIKit.label("Happiness %d" % Master.town_happiness, 22, UIKit.C_GOOD))
	hb.add_child(UIKit.bar(Master.town_happiness, 100, UIKit.C_GOOD))
	c.add_child(hb)
	var fb := HBoxContainer.new()
	fb.add_child(UIKit.label("Fear %d" % Master.town_fear, 22, UIKit.C_BAD))
	fb.add_child(UIKit.bar(Master.town_fear, 100, UIKit.C_BAD))
	c.add_child(fb)
	var col: Color = UIKit.C_TEXT
	if brief["level"] == "warn":
		col = UIKit.C_WARN
	elif brief["level"] == "danger":
		col = UIKit.C_BAD
	c.add_child(UIKit.label("%s: %s" % [Fairy.fairy_name, "\n".join(brief["lines"])], 22, col))
	if Town.pending_dilemma != "":
		root.add_child(UIKit.button("A decision awaits you!", _show_dilemma, 90))
	for fid in Town.FAC_IDS:
		var st: Dictionary = Town.status(fid)
		var fc := UIKit.card(root)
		var leader_name: String = "—"
		if st["leader"] != null:
			leader_name = Roster.get_hero(st["leader"]).get("name", "?")
		var line: String = "%s  [%s]  %s\nLeader: %s · Staff: %d/2" % [st["name"], st["rank"], "WORKING" if st["operational"] else "idle", leader_name, st["staff"].size()]
		if fid in Town.PARTY_FACILITIES:
			line += " · Parties: %d/%d" % [st["parties"].size(), st["party_capacity"]]
		fc.add_child(UIKit.left_button(line, app.go.bind("facility", {"facility": fid}), 130))
	root.add_child(UIKit.button("Skip Day", _skip_day, 100))
	root.add_child(UIKit.button("Skip Day Reports (%d)" % Town.reports.size(), app.go.bind("town_reports"), 80))

func _skip_day() -> void:
	var res: Dictionary = SkipDay.run(Roster.rng, GameSettings.autosave)
	if not res["ok"]:
		app.toast("Resolve the pending decision first.", UIKit.C_WARN)
		_show_dilemma()
		return
	var rep: Dictionary = res["report"]
	var text: String = SkipDay.summary_text(rep) + "\n\n" + rep["fairy_note"]
	app.refresh_header()
	if Town.pending_dilemma != "":
		app.dialog("Day %d complete" % int(rep["day"]), text, [["Decide now", _show_dilemma], ["Later", rebuild]])
	else:
		app.dialog("Day %d complete" % int(rep["day"]), text, [["OK", rebuild]])

func _show_dilemma() -> void:
	if Town.pending_dilemma == "":
		return
	var d: Dictionary = Database.get_entry("dilemmas", Town.pending_dilemma)
	var buttons: Array = []
	for i in d["choices"].size():
		var c: Dictionary = d["choices"][i]
		buttons.append([c["label"] + _fx_hint(c["effects"]), _resolve.bind(i)])
	app.dialog(d["title"], d["text"], buttons)

func _fx_hint(fx: Dictionary) -> String:
	var parts: Array = []
	if fx.has("gold"):
		parts.append("%+d Gold" % int(fx["gold"]))
	if fx.has("happiness"):
		parts.append("Happiness %+d" % int(fx["happiness"]))
	if fx.has("fear"):
		parts.append("Fear %+d" % int(fx["fear"]))
	if fx.has("hp_pct_all"):
		parts.append("Heroes HP %+d%%" % roundi(float(fx["hp_pct_all"]) * 100.0))
	return "\n(" + ", ".join(parts) + ")" if not parts.is_empty() else ""

func _resolve(choice: int) -> void:
	var r: Dictionary = Town.resolve_dilemma(choice)
	if r["ok"]:
		app.dialog(r["label"], r["text"], [["OK", rebuild]])
	app.refresh_header()
