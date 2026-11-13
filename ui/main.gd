extends Control
## Root of the UI: frame (header + content), screen navigation, popups and toasts.

const SCREENS := {
	"title": preload("res://ui/screens/title_screen.gd"),
	"new_game": preload("res://ui/screens/new_game_screen.gd"),
	"save_load": preload("res://ui/screens/save_load_screen.gd"),
	"settings": preload("res://ui/screens/settings_screen.gd"),
	"hub": preload("res://ui/screens/hub_screen.gd"),
	"hero_roster": preload("res://ui/screens/hero_roster_screen.gd"),
	"hero_detail": preload("res://ui/screens/hero_detail_screen.gd"),
	"recruitment": preload("res://ui/screens/recruitment_screen.gd"),
	"party": preload("res://ui/screens/party_screen.gd"),
	"inventory": preload("res://ui/screens/inventory_screen.gd"),
	"town": preload("res://ui/screens/town_screen.gd"),
	"facility": preload("res://ui/screens/facility_screen.gd"),
	"town_reports": preload("res://ui/screens/town_reports_screen.gd"),
	"dungeon": preload("res://ui/screens/dungeon_screen.gd"),
	"battle": preload("res://ui/screens/battle_screen.gd"),
	"fairy": preload("res://ui/screens/fairy_screen.gd"),
	"athanatos": preload("res://ui/screens/athanatos_screen.gd"),
	"database": preload("res://ui/screens/database_screen.gd"),
}

var stack: Array = []
var current: UIScreen = null
var content: Control
var popups: Control
var header: PanelContainer
var header_l1: Label
var header_l2: Label

func _ready() -> void:
	theme = UIKit.make_theme()
	_build_frame()
	go("title")

func _build_frame() -> void:
	var bg := ColorRect.new()
	bg.color = UIKit.C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset: Vector2 = _safe_insets()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16 + int(inset.x))
	margin.add_theme_constant_override("margin_bottom", 16 + int(inset.y))
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	header = PanelContainer.new()
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	header.add_child(hv)
	header_l1 = UIKit.label("", 24, UIKit.C_TEXT)
	header_l2 = UIKit.label("", 22, UIKit.C_DIM)
	hv.add_child(header_l1)
	hv.add_child(header_l2)
	v.add_child(header)
	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	popups = Control.new()
	popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popups)

## Top/bottom inset (in UI pixels) for notches and gesture bars.
func _safe_insets() -> Vector2:
	var win: Vector2i = DisplayServer.window_get_size()
	if win.y <= 0:
		return Vector2.ZERO
	var sa: Rect2i = DisplayServer.get_display_safe_area()
	var scale: float = 1280.0 / float(win.y)
	var top: float = float(sa.position.y) * scale
	var bottom: float = maxf(0.0, float(win.y - (sa.position.y + sa.size.y))) * scale
	return Vector2(clampf(top, 0.0, 120.0), clampf(bottom, 0.0, 80.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()

# ---------------------------------------------------------------- navigation
func go(screen_name: String, p: Dictionary = {}, replace: bool = false) -> void:
	if replace and not stack.is_empty():
		stack.pop_back()
	stack.append({"name": screen_name, "params": p})
	_show(screen_name, p)

func go_root(screen_name: String, p: Dictionary = {}) -> void:
	stack.clear()
	go(screen_name, p)

func back() -> void:
	if current != null and not current.on_back_request():
		return
	if stack.size() <= 1:
		return
	stack.pop_back()
	var top: Dictionary = stack[stack.size() - 1]
	_show(top["name"], top["params"])

func _show(screen_name: String, p: Dictionary) -> void:
	if current != null:
		content.remove_child(current)
		current.queue_free()
	var s: UIScreen = SCREENS[screen_name].new()
	s.app = self
	s.params = p
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(s)
	current = s
	header.visible = s.show_header and Master.master_name != ""
	s.setup()
	refresh_header()

func refresh_header() -> void:
	if Master.master_name == "":
		return
	var rk: Dictionary = Master.rank()
	header_l1.text = "%s · Rank %s %s · Day %d" % [Master.master_name, rk.get("rank", "F"), rk.get("title", ""), Master.in_game_day]
	var w: Dictionary = Master.wallet
	header_l2.text = "Gold %d · Gems %d · Tickets %d · Special %d" % [int(w["gold"]), int(w["gems"]), int(w["tickets"]), int(w["special_tickets"])]

# ---------------------------------------------------------------- popups
func _open_popup(title: String, body: Control, buttons: Array, body_h: int) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	if title != "":
		v.add_child(UIKit.label(title, 32, UIKit.C_ACCENT))
	var sc := UIKit.scroll()
	sc.size_flags_vertical = Control.SIZE_FILL
	sc.custom_minimum_size = Vector2(0, body_h)
	sc.add_child(body)
	v.add_child(sc)
	for b in buttons:
		var btn := UIKit.button(b[0], Callable(), 76)
		var cb: Callable = b[1] if b.size() > 1 else Callable()
		btn.pressed.connect(_on_popup_button.bind(overlay, cb))
		v.add_child(btn)
	popups.add_child(overlay)
	return overlay

func _on_popup_button(overlay: Control, cb: Callable) -> void:
	overlay.queue_free()
	if cb.is_valid():
		cb.call()

## Message box. buttons = [["Label", Callable], ...] (default: one OK button).
func dialog(title: String, text: String, buttons: Array = [], body_h: int = 0) -> void:
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(UIKit.label(text, 26, UIKit.C_TEXT))
	var h: int = body_h
	if h == 0:
		h = clampi(60 + (text.length() / 34 + text.count("\n") + 1) * 34, 120, 760)
	_open_popup(title, body, buttons if not buttons.is_empty() else [["OK"]], h)

func confirm(title: String, text: String, on_yes: Callable, yes_text: String = "Yes", no_text: String = "Cancel") -> void:
	dialog(title, text, [[yes_text, on_yes], [no_text]])

## List picker. items = [{"text": String, "value": Variant, "disabled": bool}]. Calls on_pick(value).
func picker(title: String, items: Array, on_pick: Callable, cancel_text: String = "Cancel") -> void:
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var overlay_holder: Array = []
	for it in items:
		var b := UIKit.left_button(String(it["text"]), Callable(), 84)
		b.disabled = bool(it.get("disabled", false))
		b.pressed.connect(_on_pick.bind(overlay_holder, on_pick, it["value"]))
		body.add_child(b)
	if items.is_empty():
		body.add_child(UIKit.label("Nothing to choose from.", 26, UIKit.C_DIM))
	var h: int = clampi(items.size() * 96 + 20, 120, 760)
	overlay_holder.append(_open_popup(title, body, [[cancel_text]], h))

func _on_pick(holder: Array, on_pick: Callable, value) -> void:
	if not holder.is_empty():
		holder[0].queue_free()
	on_pick.call(value)

func toast(text: String, color: Color = UIKit.C_TEXT) -> void:
	var p := PanelContainer.new()
	var l := UIKit.label(text, 26, color, true)
	p.add_child(l)
	p.custom_minimum_size = Vector2(560, 0)
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.position = Vector2(80, 1080)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popups.add_child(p)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
