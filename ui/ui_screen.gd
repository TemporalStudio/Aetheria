class_name UIScreen
extends VBoxContainer
## Base class for every screen. Override build(); call rebuild() after the state changes.

var app                       # Main (untyped on purpose)
var params: Dictionary = {}
var screen_title: String = ""
var show_header: bool = true
var show_back: bool = true

func setup() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_all()

func _build_all() -> void:
	if show_back or screen_title != "":
		var row := HBoxContainer.new()
		if show_back:
			var b := UIKit.button("◀", Callable(app, "back"), 70)
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			b.custom_minimum_size = Vector2(90, 70)
			row.add_child(b)
		row.add_child(UIKit.label(screen_title, 34, UIKit.C_ACCENT))
		add_child(row)
	build()

func rebuild() -> void:
	UIKit.clear(self)
	_build_all()
	app.refresh_header()

func build() -> void:
	pass

## Return false to block the Back button (e.g. during a battle).
func on_back_request() -> bool:
	return true
