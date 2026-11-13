extends Node
## Autoload: the player's Master identity, wallet, Tower progress and Town mood.
## No Master Level/EXP (GDD Bab 3): Rank comes only from Highest Tower Floor.

signal wallet_changed

const WALLET_KEYS := ["gold", "gems", "tickets", "special_tickets"]

var master_id: String = ""
var master_name: String = ""
var wallet: Dictionary = {}
var highest_floor: int = 0
var current_floor: int = 1
var in_game_day: int = 1
var town_happiness: int = 50
var town_fear: int = 20

func new_identity(p_name: String, start: Dictionary, rng: RandomNumberGenerator) -> void:
	master_id = "MS-"
	for _i in 6:
		master_id += HeroFactory.ID_CHARS[rng.randi_range(0, HeroFactory.ID_CHARS.length() - 1)]
	master_name = p_name
	wallet = {}
	for k in WALLET_KEYS:
		wallet[k] = int(start["wallet"].get(k, 0))
	highest_floor = 0
	current_floor = int(start["start_floor"])
	in_game_day = int(start["start_day"])
	town_happiness = int(start["town"]["happiness"])
	town_fear = int(start["town"]["fear"])
	wallet_changed.emit()

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if int(wallet.get(k, 0)) < int(cost[k]):
			return false
	return true

## Atomically pays a cost ({"gold": 1000}). Returns false and changes nothing if unaffordable.
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		wallet[k] = int(wallet[k]) - int(cost[k])
	wallet_changed.emit()
	return true

func add_currency(key: String, amount: int) -> void:
	if not key in WALLET_KEYS:
		push_error("Unknown currency: " + key)
		return
	wallet[key] = maxi(0, int(wallet.get(key, 0)) + amount)
	wallet_changed.emit()

## Rank/Title from Highest Tower Floor (floor 0 counts as F).
func rank() -> Dictionary:
	return Database.rank_for_floor(maxi(1, highest_floor))

func record_floor_clear(floor_num: int) -> void:
	highest_floor = maxi(highest_floor, floor_num)
	if floor_num >= current_floor:
		current_floor = mini(floor_num + 1, int(Database.tower_rules["floors"]))

func adjust_town(d_happiness: int, d_fear: int) -> void:
	town_happiness = clampi(town_happiness + d_happiness, 0, 100)
	town_fear = clampi(town_fear + d_fear, 0, 100)

## "panicked" / "inspired" / "burnout" / "stable" (GDD Bab 11). Panic is checked first.
func town_state() -> String:
	for id in ["panicked", "inspired", "burnout"]:
		var cond: Dictionary = Database.get_entry("mental_states", id)["condition"]
		if _matches(cond):
			return id
	return "stable"

func _matches(c: Dictionary) -> bool:
	if c.has("happiness_min") and town_happiness < int(c["happiness_min"]): return false
	if c.has("happiness_max") and town_happiness > int(c["happiness_max"]): return false
	if c.has("fear_min") and town_fear < int(c["fear_min"]): return false
	if c.has("fear_max") and town_fear > int(c["fear_max"]): return false
	return true

func to_save() -> Dictionary:
	return {"master_id": master_id, "master_name": master_name, "wallet": wallet.duplicate(),
		"highest_floor": highest_floor, "current_floor": current_floor, "in_game_day": in_game_day,
		"town_happiness": town_happiness, "town_fear": town_fear}

func from_save(d: Dictionary) -> void:
	master_id = d.get("master_id", "")
	master_name = d.get("master_name", "")
	wallet = {}
	for k in WALLET_KEYS:
		wallet[k] = int(d.get("wallet", {}).get(k, 0))
	highest_floor = int(d.get("highest_floor", 0))
	current_floor = int(d.get("current_floor", 1))
	in_game_day = int(d.get("in_game_day", 1))
	town_happiness = int(d.get("town_happiness", 50))
	town_fear = int(d.get("town_fear", 20))
	wallet_changed.emit()
