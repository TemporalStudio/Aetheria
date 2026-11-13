extends UIScreen

func _init() -> void:
	screen_title = "Recruitment Portal"

func build() -> void:
	var sc := UIKit.scroll()
	add_child(sc)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(root)
	for portal in Database.all_entries("recruitment"):
		var c := UIKit.card(root)
		c.add_child(UIKit.label(portal["name"], 30, UIKit.C_ACCENT))
		var odds: Dictionary = Database.hero_rules["star_weights"][portal["id"]]
		var total: float = 0.0
		for k in odds:
			total += float(odds[k])
		var parts: Array = []
		for k in odds:
			parts.append("%s★ %d%%" % [k, roundi(float(odds[k]) / total * 100.0)])
		var guar: String = "Guaranteed " if portal["guaranteed"] else "Random "
		c.add_child(UIKit.label("%sHero: %s" % [guar, " · ".join(parts)], 22, UIKit.C_DIM))
		c.add_child(UIKit.label("Cost: %s" % UIKit.cost_text(portal["cost"]), 24, UIKit.C_TEXT))
		var b := UIKit.button("Recruit", _recruit.bind(portal["id"]), 80)
		b.disabled = not Master.can_afford(portal["cost"])
		c.add_child(b)
	var log_card := UIKit.card(root)
	log_card.add_child(UIKit.label("Recruitment Log", 28, UIKit.C_ACCENT))
	if Roster.recruit_log.is_empty():
		log_card.add_child(UIKit.label("Nobody recruited yet.", 22, UIKit.C_DIM))
	var shown: int = 0
	for i in range(Roster.recruit_log.size() - 1, -1, -1):
		var r: Dictionary = Roster.recruit_log[i]
		log_card.add_child(UIKit.label("Day %d · %s · %d★ %s %s" % [int(r["day"]), r["name"], int(r["star"]), r["role"], r["element"]], 22, UIKit.C_TEXT))
		shown += 1
		if shown >= 15:
			break

func _recruit(portal_id: String) -> void:
	var h: Dictionary = Roster.recruit_paid(portal_id)
	if h.is_empty():
		app.toast("Not enough resources.", UIKit.C_WARN)
		return
	app.dialog("New Hero!", UIKit.hero_summary(h))
	rebuild()
