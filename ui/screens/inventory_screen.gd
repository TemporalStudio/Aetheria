extends UIScreen

var tab: int = 0

func _init() -> void:
	screen_title = "Inventory"

func build() -> void:
	add_child(UIKit.tab_row(["Wallet", "Materials", "Equipment", "Medical"], tab, _set_tab))
	var sc := UIKit.scroll()
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if tab == 0:
		var c := UIKit.card(list)
		var w: Dictionary = Master.wallet
		c.add_child(UIKit.label("Gold: %d\nGems: %d\nTickets: %d\nSpecial Tickets: %d" % [int(w["gold"]), int(w["gems"]), int(w["tickets"]), int(w["special_tickets"])], 30, UIKit.C_TEXT))
		return
	var table: String = ["", "materials", "equipment", "medical"][tab]
	var any: bool = false
	var ids: Array = Inventory.items.keys()
	ids.sort()
	for id in ids:
		if not Database.has_id(table, id):
			continue
		any = true
		var e: Dictionary = Database.get_entry(table, id)
		var c2 := UIKit.card(list)
		c2.add_child(UIKit.label("%s  ×%d" % [e["name"], Inventory.count(id)], 26, UIKit.C_TEXT))
		if table == "equipment":
			var parts: Array = []
			for k in e["stats"]:
				parts.append("%s +%s" % [UIKit.stat_name(k), str(e["stats"][k])])
			c2.add_child(UIKit.label("%s · tier %d · %s" % [e["slot"], int(e["tier"]), ", ".join(parts)], 22, UIKit.C_DIM))
		elif table == "medical":
			c2.add_child(UIKit.label("%s · cannot revive" % e["type"], 22, UIKit.C_DIM))
		else:
			c2.add_child(UIKit.label(e["category"], 22, UIKit.C_DIM))
	if not any:
		list.add_child(UIKit.label("Nothing here yet.", 26, UIKit.C_DIM))

func _set_tab(i: int) -> void:
	tab = i
	rebuild()
