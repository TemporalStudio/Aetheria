extends Node
## Autoload: orchestrates a fresh game using data/starting_package.json.

func new_game(master_name: String) -> void:
	var sp: Dictionary = Database.starting_package
	Roster.reset()
	Parties.reset()
	Town.reset()
	Fairy.reset()
	Inventory.reset()
	Master.new_identity(master_name, sp, Roster.rng)
	for id in sp["items"]:
		Inventory.add(id, int(sp["items"][id]))
	for r in sp["free_recruits"]:
		for _i in int(r["count"]):
			Roster.recruit(r["portal"], Master.in_game_day)
