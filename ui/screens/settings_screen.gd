extends UIScreen

func _init() -> void:
	screen_title = "Settings"

func build() -> void:
	var c := UIKit.card(self)
	c.add_child(UIKit.button("Battle speed: %s" % ("Fast (2x)" if GameSettings.battle_speed == 2 else "Normal (1x)"), _toggle_speed, 88))
	c.add_child(UIKit.button("Autosave on Skip Day: %s" % ("ON" if GameSettings.autosave else "OFF"), _toggle_autosave, 88))
	var r := UIKit.card(self, Color("3a2230"))
	r.add_child(UIKit.label("Rules that cannot be changed", 26, UIKit.C_BAD))
	r.add_child(UIKit.label("Permanent Hero death is always on. Fallen Heroes cannot be revived by items, skills or facilities.", 24, UIKit.C_TEXT))
	add_child(UIKit.label("Saves are stored on this device only. Uninstalling the game or clearing its data deletes them.", 22, UIKit.C_DIM))

func _toggle_speed() -> void:
	GameSettings.battle_speed = 1 if GameSettings.battle_speed == 2 else 2
	GameSettings.save_settings()
	rebuild()

func _toggle_autosave() -> void:
	GameSettings.autosave = not GameSettings.autosave
	GameSettings.save_settings()
	rebuild()
