extends Node
## Autoload singleton: loads every JSON in res://data/ and indexes entries by ID.
## Usage: Database.get_entry("basic_skills", "BS-FIR-011")

const DATA_DIR := "res://data/"
const TABLES_WITH_ID := ["basic_skills", "ultimate_skills", "traits", "recruitment", "mental_states", "facilities",
	"materials", "equipment", "medical", "recipes", "star_progression",
	"enemies", "tower_floors", "raid_bosses", "rift_gates",
	"roles", "races", "nobles", "town_skills", "dilemmas"]

var tables: Dictionary = {}   # table_name -> { id: entry }
var master_ranks: Array = []
var rules: Dictionary = {}
var exp_curve: Dictionary = {}
var tower_rules: Dictionary = {}
var hero_rules: Dictionary = {}
var starting_package: Dictionary = {}
var battle_rules: Dictionary = {}
var athanatos_rules: Dictionary = {}
var epitaphs: Dictionary = {}
var town_rules: Dictionary = {}
var fairy_rules: Dictionary = {}

func _ready() -> void:
	for t in TABLES_WITH_ID:
		tables[t] = _index_by_id(t)
	master_ranks = _load_json("master_ranks")
	rules = _load_json("game_rules")
	exp_curve = _load_json("exp_curve")
	tower_rules = _load_json("tower_rules")
	hero_rules = _load_json("hero_rules")
	starting_package = _load_json("starting_package")
	battle_rules = _load_json("battle_rules")
	athanatos_rules = _load_json("athanatos_rules")
	epitaphs = _load_json("epitaphs")
	town_rules = _load_json("town_rules")
	fairy_rules = _load_json("fairy_rules")
	_validate_recipes()
	_validate_enemies()
	print("[Database] loaded: ", _summary())

## JSON has no ints: Godot parses every number as float. Converts whole-number floats back to int.
static func normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = normalize(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(normalize(x))
			return a
		TYPE_FLOAT:
			if v == floorf(v) and absf(v) < 1.0e15:
				return int(v)
			return v
	return v

func get_entry(table: String, id: String) -> Dictionary:
	return tables.get(table, {}).get(id, {})

func all_entries(table: String) -> Array:
	return tables.get(table, {}).values()

func has_id(table: String, id: String) -> bool:
	return tables.get(table, {}).has(id)

## Master Rank from Highest Tower Floor (GDD Bab 3).
func rank_for_floor(floor_num: int) -> Dictionary:
	for r in master_ranks:
		if floor_num >= int(r["floor_min"]) and floor_num <= int(r["floor_max"]):
			return r
	return {}

## EXP needed to go from `level` to level+1 (draft formula).
func exp_to_next(level: int) -> int:
	return roundi(float(exp_curve["base"]) * pow(level, float(exp_curve["exponent"])))

func level_cap_for_star(star: int) -> int:
	return int(get_entry("star_progression", "STAR-%d" % star).get("level_cap", 1))

## Any ID (material/equipment/medical) -> true if it exists in some item table.
func item_exists(id: String) -> bool:
	return has_id("materials", id) or has_id("equipment", id) or has_id("medical", id)

## Tower scaling multiplier for a floor (draft formula in tower_rules.json).
func tower_scale(floor_num: int) -> float:
	return 1.0 + float(tower_rules["scaling"]["per_floor"]) * (floor_num - 1)

## Final stats of an enemy. Only "tower" scaling enemies change with floor.
func get_scaled_stats(enemy_id: String, floor_num: int = 1) -> Dictionary:
	var e := get_entry("enemies", enemy_id)
	if e.is_empty():
		return {}
	var out: Dictionary = e["base_stats"].duplicate()
	if e["scaling"] == "tower":
		var growth := tower_scale(floor_num) - 1.0
		for k in out:
			var weight := float(tower_rules["stat_weight"].get(k, 1.0))
			out[k] = roundi(float(out[k]) * (1.0 + growth * weight))
	return out

func get_floor(floor_num: int) -> Dictionary:
	return get_entry("tower_floors", "FLR-%03d" % floor_num)

func _validate_enemies() -> void:
	for e in all_entries("enemies"):
		var skill_ids: Array = e["skills"].duplicate()
		for ph in (e["phases"] if e["phases"] != null else []):
			skill_ids.append_array(ph["skills"])
		for sid in skill_ids:
			if not has_id("basic_skills", sid):
				push_error("Enemy %s: unknown skill %s" % [e["id"], sid])
		if e["ultimate"] != null and not has_id("ultimate_skills", e["ultimate"]):
			push_error("Enemy %s: unknown ultimate %s" % [e["id"], e["ultimate"]])
	for f in all_entries("tower_floors"):
		for x in f["enemies"]:
			if not has_id("enemies", x["enemy"]):
				push_error("Floor %s: unknown enemy %s" % [f["id"], x["enemy"]])

func _validate_recipes() -> void:
	for r in all_entries("recipes"):
		if not item_exists(r["output"]):
			push_error("Recipe %s: unknown output %s" % [r["id"], r["output"]])
		for i in r["inputs"]:
			if not item_exists(i["item"]):
				push_error("Recipe %s: unknown input %s" % [r["id"], i["item"]])

func _index_by_id(table: String) -> Dictionary:
	var out := {}
	for entry in _load_json(table):
		var id: String = entry["id"]
		if out.has(id):
			push_error("Duplicate ID '%s' in %s" % [id, table])
			continue
		out[id] = entry
	return out

func _load_json(table: String):
	var path := DATA_DIR + table + ".json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open " + path)
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("Invalid JSON in " + path)
		return []
	return normalize(parsed)

func _summary() -> String:
	var parts := []
	for t in tables:
		parts.append("%s=%d" % [t, tables[t].size()])
	return ", ".join(parts)
