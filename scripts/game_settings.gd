extends Node
## Autoload `GameSettings`: small player preferences saved to user://settings.json.

const PATH := "user://settings.json"

var battle_speed: int = 1     # 1 = normal, 2 = fast
var autosave: bool = true     # autosave to slot 0 on Skip Day

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(d) == TYPE_DICTIONARY:
		battle_speed = clampi(int(d.get("battle_speed", 1)), 1, 2)
		autosave = bool(d.get("autosave", true))

func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"battle_speed": battle_speed, "autosave": autosave}))
		f.close()
