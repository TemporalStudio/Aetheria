extends Node
## Autoload: stackable item storage (materials, equipment, medical) keyed by item ID.

signal changed

var items: Dictionary = {}   # item id -> qty

func reset() -> void:
	items = {}
	changed.emit()

func count(id: String) -> int:
	return int(items.get(id, 0))

func add(id: String, qty: int = 1) -> bool:
	if qty <= 0 or not Database.item_exists(id):
		push_error("Inventory.add rejected: %s x%d" % [id, qty])
		return false
	items[id] = count(id) + qty
	changed.emit()
	return true

func remove(id: String, qty: int = 1) -> bool:
	if qty <= 0 or count(id) < qty:
		return false
	items[id] = count(id) - qty
	if items[id] == 0:
		items.erase(id)
	changed.emit()
	return true

## inputs = [{"item": "MAT-001", "qty": 3}, ...] (recipe format)
func has_items(inputs: Array) -> bool:
	for i in inputs:
		if count(i["item"]) < int(i["qty"]):
			return false
	return true

## Crafts a recipe. Result: {"ok": bool, "reason": String, "success": bool, "output": String}.
## ok=false means the attempt never started (nothing consumed).
## On a failed roll the materials are consumed and nothing is produced (draft rule).
## `bonus` is added to base_success (facility/Town Skill bonuses, later step).
func craft(recipe_id: String, facility_level: int, rng: RandomNumberGenerator, bonus: float = 0.0) -> Dictionary:
	var r: Dictionary = Database.get_entry("recipes", recipe_id)
	if r.is_empty():
		return {"ok": false, "reason": "unknown_recipe"}
	if facility_level < int(r["facility_level_min"]):
		return {"ok": false, "reason": "facility_level"}
	if not has_items(r["inputs"]):
		return {"ok": false, "reason": "missing_materials"}
	for i in r["inputs"]:
		remove(i["item"], int(i["qty"]))
	var success: bool = rng.randf() < float(r["base_success"]) + bonus
	if success:
		add(r["output"], int(r["output_qty"]))
	return {"ok": true, "reason": "", "success": success, "output": r["output"]}

func to_save() -> Dictionary:
	return {"items": items.duplicate()}

func from_save(d: Dictionary) -> void:
	items = d.get("items", {})
	changed.emit()
