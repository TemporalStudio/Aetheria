class_name UIKit
extends RefCounted
## Shared look & helpers for every screen. All UI is built from code (no .tscn editing needed).

const C_BG := Color("12141c")
const C_PANEL := Color("1d2130")
const C_PANEL2 := Color("2a3047")
const C_ACCENT := Color("7aa2ff")
const C_TEXT := Color("e8eaf2")
const C_DIM := Color("9aa0b5")
const C_GOOD := Color("6fd08c")
const C_WARN := Color("f0c060")
const C_BAD := Color("ee6a6a")
const ELEMENT_COLORS := {"Normal": Color("b8bcc8"), "Fire": Color("ff7a59"), "Water": Color("5aa9ff"), "Wind": Color("7ee0b0"),
	"Earth": Color("c9a26a"), "Light": Color("ffe27a"), "Dark": Color("a77bff")}
const STAT_NAMES := {"max_hp": "HP", "phys_atk": "P.ATK", "magic_atk": "M.ATK", "phys_def": "P.DEF", "magic_def": "M.DEF",
	"speed": "SPD", "crit": "CRIT", "evasion": "EVA", "accuracy": "ACC", "burn": "Burn"}
const TARGET_NAMES := {"single_enemy": "1 enemy", "all_enemies": "all enemies", "self": "self", "single_ally": "1 ally", "all_allies": "all allies"}

# ---------------------------------------------------------------- theme
static func box(color: Color, radius: int = 14, border: Color = Color(0, 0, 0, 0), border_w: int = 0, margin: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	return s

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_color("font_color", "Label", C_TEXT)
	t.set_stylebox("normal", "Button", box(C_PANEL2, 14, Color(1, 1, 1, 0.06), 2, 16))
	t.set_stylebox("hover", "Button", box(C_PANEL2.lightened(0.08), 14, C_ACCENT, 2, 16))
	t.set_stylebox("pressed", "Button", box(C_ACCENT.darkened(0.45), 14, C_ACCENT, 2, 16))
	t.set_stylebox("disabled", "Button", box(C_PANEL.darkened(0.2), 14, Color(1, 1, 1, 0.03), 2, 16))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", C_TEXT)
	t.set_color("font_disabled_color", "Button", C_DIM)
	t.set_font_size("font_size", "Button", 26)
	t.set_stylebox("panel", "PanelContainer", box(C_PANEL, 18, Color(1, 1, 1, 0.05), 2, 16))
	t.set_stylebox("background", "ProgressBar", box(C_BG, 8, Color(1, 1, 1, 0.06), 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(C_GOOD, 8, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("normal", "LineEdit", box(C_BG, 12, C_ACCENT.darkened(0.3), 2, 14))
	t.set_stylebox("focus", "LineEdit", box(C_BG, 12, C_ACCENT, 2, 14))
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 12)
	t.set_constant("v_separation", "GridContainer", 12)
	return t

# ---------------------------------------------------------------- widgets
static func label(text: String, size: int = 0, color: Color = C_TEXT, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func button(text: String, cb: Callable = Callable(), h: int = 84) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func left_button(text: String, cb: Callable = Callable(), h: int = 96) -> Button:
	var b := button(text, cb, h)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b

## A framed card. Returns the inner VBox; the card itself is added to `parent`.
static func card(parent: Node, color: Color = C_PANEL) -> VBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color != C_PANEL:
		p.add_theme_stylebox_override("panel", box(color, 18, Color(1, 1, 1, 0.05), 2, 16))
	var v := VBoxContainer.new()
	p.add_child(v)
	parent.add_child(p)
	return v

static func bar(value: float, max_value: float, color: Color = C_GOOD, h: int = 18) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = maxf(1.0, max_value)
	b.value = clampf(value, 0.0, b.max_value)
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("fill", box(color, 8, Color(0, 0, 0, 0), 0, 0))
	return b

static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

static func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

## Row of toggle-style tab buttons. on_select receives the tab index.
static func tab_row(names: Array, selected: int, on_select: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	for i in names.size():
		var b := button(names[i], on_select.bind(i), 64)
		if i == selected:
			b.add_theme_stylebox_override("normal", box(C_ACCENT.darkened(0.4), 14, C_ACCENT, 2, 12))
		row.add_child(b)
	return row

# ---------------------------------------------------------------- text helpers
static func stars(n: int) -> String:
	return "%d★" % n

static func stat_name(k: String) -> String:
	return STAT_NAMES.get(k, k)

static func element_color(el: String) -> Color:
	return ELEMENT_COLORS.get(el, C_TEXT)

static func item_name(id: String) -> String:
	for t in ["materials", "equipment", "medical"]:
		if Database.has_id(t, id):
			return Database.get_entry(t, id)["name"]
	return id

static func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	var names := {"gold": "Gold", "gems": "Gems", "tickets": "Ticket", "special_tickets": "Special Ticket"}
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), names.get(k, k)])
	return ", ".join(parts)

static func inputs_text(inputs: Array) -> String:
	var parts: Array = []
	for i in inputs:
		parts.append("%s %d/%d" % [item_name(i["item"]), Inventory.count(i["item"]), int(i["qty"])])
	return ", ".join(parts)

static func effect_text(e) -> String:
	if e == null:
		return ""
	match String(e["type"]):
		"buff", "debuff":
			if e["stat"] == "burn":
				return "Burn %d%%/turn (%dt)" % [roundi(float(e["value"]) * 100.0), int(e["turns"])]
			var when: String = "(%dt)" % int(e["turns"]) if int(e["turns"]) > 0 else "(this hit)"
			return "%s %+d%% %s" % [stat_name(e["stat"]), roundi(float(e["value"]) * 100.0), when]
		"shield":
			return "Shield %d%% HP (%dt)" % [roundi(float(e["value"]) * 100.0), int(e["turns"])]
		"lifesteal":
			return "Lifesteal %d%%" % roundi(float(e["value"]) * 100.0)
		"cleanse":
			return "Cleanse"
		"taunt":
			return "Taunt (%dt)" % int(e["turns"])
	return ""

static func skill_text(sk: Dictionary) -> String:
	var s: String = "%s · SP %d · %s" % [String(sk["category"]).capitalize(), int(sk["sp_cost"]), TARGET_NAMES.get(sk["target"], sk["target"])]
	if float(sk["power"]) > 0.0:
		s += " · Power %d %s" % [int(sk["power"]), sk["damage_type"]]
	var e = sk.get("effect")
	if e != null:
		s += " · " + effect_text(e)
	return s

static func ultimate_text(u: Dictionary) -> String:
	var s: String = "%s · %s" % [u["role"], TARGET_NAMES.get(u["target"], u["target"])]
	if float(u["power"]) > 0.0:
		s += " · Power %d" % int(u["power"])
	return s

static func hero_line(h: Dictionary) -> String:
	return "%s · %s · %s · %d★ Lv%d" % [h["name"], h["role"], h["element"], int(h["star"]), int(h["level"])]

static func hero_status(hero_id: String) -> String:
	var h: Dictionary = Roster.get_hero(hero_id)
	var pid: String = Parties.hero_party(hero_id)
	if pid != "":
		var busy: String = Town.party_busy(pid)
		return "Party %s%s" % [pid, " (at %s)" % Database.get_entry("facilities", busy)["name"] if busy != "" else ""]
	if h.get("assignment") != null:
		return "%s (%s)" % [Database.get_entry("facilities", h["assignment"]["facility"])["name"], h["assignment"]["role"]]
	return "Available"

static func skill_names(ids: Array) -> String:
	var n: Array = []
	for id in ids:
		n.append(Database.get_entry("basic_skills", id)["name"])
	return ", ".join(n)

static func hero_summary(h: Dictionary) -> String:
	var lines: Array = []
	var house: String = ""
	if h["noble"] != null:
		house = " · " + Database.get_entry("nobles", h["noble"])["name"]
	lines.append("%s (%s)" % [h["name"], h["id"]])
	lines.append("%s %s, age %d%s" % [h["race"], h["gender"], int(h["age"]), house])
	lines.append("%s · %s · %d★ Lv%d" % [h["role"], h["element"], int(h["star"]), int(h["level"])])
	lines.append("Skills: " + skill_names(h["skills"]))
	if h["ultimate"] != null:
		lines.append("Ultimate: " + Database.get_entry("ultimate_skills", h["ultimate"])["name"])
	var tn: Array = []
	for t in h["traits"]:
		tn.append(Database.get_entry("traits", t)["name"])
	lines.append("Traits: " + ", ".join(tn))
	lines.append("Town Skill: " + Database.get_entry("town_skills", h["town_skill"])["name"])
	return "\n".join(lines)
