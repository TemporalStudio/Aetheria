extends UIScreen

var name_edit: LineEdit

func _init() -> void:
	screen_title = "New Game"
	show_header = false

func build() -> void:
	add_child(UIKit.spacer(20))
	var c := UIKit.card(self)
	c.add_child(UIKit.label("AETHERIA ORIGIN RECORD", 30, UIKit.C_ACCENT))
	c.add_child(UIKit.label("THE RECORD IS INCOMPLETE", 26, UIKit.C_WARN))
	c.add_child(UIKit.label("You are the Master: you do not fight, you decide. Recruit Heroes, form Parties, run the Town and choose how much risk every expedition is worth.", 24, UIKit.C_DIM))
	var w := UIKit.card(self, Color("3a2230"))
	w.add_child(UIKit.label("Permanent death is active", 28, UIKit.C_BAD))
	w.add_child(UIKit.label("A Hero whose HP reaches 0 in battle is lost forever. He or she is buried in Athanatos and the ID can never be used again.", 24, UIKit.C_TEXT))
	add_child(UIKit.label("Master name", 26, UIKit.C_DIM))
	name_edit = LineEdit.new()
	name_edit.text = "Master"
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(0, 84)
	add_child(name_edit)
	add_child(UIKit.button("Begin", _start, 100))

func _start() -> void:
	var n: String = name_edit.text.strip_edges()
	if n == "":
		app.toast("Please enter a name.", UIKit.C_WARN)
		return
	GameState.new_game(n)
	app.go_root("hub")
	app.dialog("Your Fairy", "%s, a %s Fairy, will guide you.\nShe advises, but every decision is yours." % [Fairy.fairy_name, Fairy.personality])
