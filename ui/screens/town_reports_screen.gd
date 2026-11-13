extends UIScreen

func _init() -> void:
	screen_title = "Skip Day Reports"

func build() -> void:
	var sc := UIKit.scroll()
	add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if Town.reports.is_empty():
		list.add_child(UIKit.label("No reports yet. Use Skip Day in the Town Square.", 26, UIKit.C_DIM))
	for i in range(Town.reports.size() - 1, -1, -1):
		var r: Dictionary = Town.reports[i]
		list.add_child(UIKit.left_button("Day %d · %s\nHappiness %+d · Fear %+d · %d recovered, %d growth" % [
			int(r["day"]), String(r["town_state"]).capitalize(), int(r["happiness_change"]), int(r["fear_change"]), r["recovery"].size(), r["growth"].size()],
			_open.bind(i), 100))

func _open(i: int) -> void:
	var r: Dictionary = Town.reports[i]
	var lines: Array = [SkipDay.summary_text(r)]
	for f in r["facilities"]:
		var staff: String = ", ".join(f["staff"]) if not f["staff"].is_empty() else "—"
		lines.append("%s [%s]: Leader %s · Staff %s" % [f["name"], f["rank"], f["leader"], staff])
	for x in r["recovery"]:
		lines.append("%s recovered %d HP, %d SP (%s)" % [x["name"], int(x["hp"]), int(x["sp"]), x["source"]])
	if r.get("dilemma_choice", "") != "":
		lines.append("Decision: %s — %s" % [r["dilemma_choice"], r["dilemma_result"]])
	if r["fairy_note"] != "":
		lines.append("\n" + r["fairy_note"])
	app.dialog("Day %d" % int(r["day"]), "\n".join(lines), [["Close"]], 640)
