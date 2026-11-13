extends UIScreen

func _init() -> void:
	screen_title = "Athanatos"

func build() -> void:
	if not Athanatos.is_unlocked():
		add_child(UIKit.label("Athanatos is locked.", 30, UIKit.C_DIM))
		return
	var c := UIKit.card(self, Color("2a2030"))
	c.add_child(UIKit.label("Memorial Cemetery", 32, UIKit.C_ACCENT))
	c.add_child(UIKit.label("Victory builds legends, but loss leaves history. Heroes who fell do not return — their names remain.", 22, UIKit.C_DIM))
	var st: Dictionary = Athanatos.stats()
	var s: String = "%d Heroes laid to rest" % int(st["total"])
	if st["deadliest_floor"] != null:
		s += " · deadliest floor: %d" % int(st["deadliest_floor"])
	if st["deadliest_enemy"] != null:
		s += " · deadliest enemy: %s" % st["deadliest_enemy"]
	c.add_child(UIKit.label(s, 22, UIKit.C_TEXT))
	var sc := UIKit.scroll()
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if Athanatos.count() == 0:
		list.add_child(UIKit.label("The cemetery is empty. May it stay that way.", 26, UIKit.C_DIM))
	for m in Athanatos.list():
		list.add_child(UIKit.left_button("%s\nLv%d %s %s · Day %d\n%s" % [m["name"], int(m["level"]), m["role"], m["element"], int(m["day"]), m["location"]],
			_open.bind(m["hero_id"]), 120))

func _open(hero_id: String) -> void:
	var m: Dictionary = Athanatos.get_record(hero_id)
	if m.is_empty():
		return
	app.dialog("", Athanatos.tombstone_text(m), [["Edit inscription", _edit.bind(hero_id)], ["Close"]], 520)

func _edit(hero_id: String) -> void:
	var m: Dictionary = Athanatos.get_record(hero_id)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(UIKit.label("Only the inscription can be changed. Everything else is permanent.", 22, UIKit.C_DIM))
	var edit := LineEdit.new()
	edit.text = m["custom_inscription"] if m["custom_inscription"] != "" else m["inscription"]
	edit.max_length = int(Database.athanatos_rules["custom_inscription_max"])
	edit.custom_minimum_size = Vector2(0, 84)
	body.add_child(edit)
	app._open_popup("Inscription — %s" % m["name"], body, [["Save", _save.bind(hero_id, edit)], ["Cancel"]], 220)

func _save(hero_id: String, edit: LineEdit) -> void:
	Athanatos.set_inscription(hero_id, edit.text)
	app.toast("Inscription saved.", UIKit.C_GOOD)
