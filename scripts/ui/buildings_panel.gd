class_name BuildingsPanel
extends HudPanel
## The hub's buildings (see Building): every type the hub can build, with
## its price, how many it has of the most it may have, and a Build button
## (via hud.build_building_requested); the ones under construction (finished
## at the end of the turn) with Cancel buttons; and the ones it has built.


func _init(p_hud: Hud) -> void:
	super(p_hud)
	panel_width = 880.0
	title = "Buildings"
	button_text = "Buildings"
	tooltip = "Buildings in your hub (B)"
	shortcut = KEY_B
	## A greenhouse: a glass dome with a sprout inside.
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<rect x="2" y="25" width="28" height="4" rx="1" fill="#9fb4d6"/>
<path d="M4 25a12 12 0 0 1 24 0z" fill="#bfe6ff" fill-opacity="0.45" stroke="#eef4ff" stroke-width="2"/>
<path d="M16 25v-9" stroke="#7dff7a" stroke-width="2.5"/>
<path d="M16 19c-4 0-6-2-6-5 4 0 6 2 6 5zm0-2c0-3 2-5 6-5 0 3-2 5-6 5z" fill="#7dff7a"/>
</svg>"""


func get_button_text() -> String:
	var building := player.building_queue.size() if player else 0
	return "Buildings  (%d building)" % building if building > 0 else button_text


func fill() -> void:
	add_heading("Available to build")
	add_note("Paid for now, ready at the end of the turn. Hover for details.")
	var grid := _grid()
	for type in player.building_types:
		if player.count_planned_buildings(type.id) < player.get_building_limit(type.id):
			grid.add_child(_make_build_row(type))
	if grid.get_child_count() > 0:
		add(grid)
	else:
		grid.free()
		add_note("Everything has been built.")

	if not player.building_queue.is_empty():
		add_separator()
		add_heading("Under construction (%d)" % player.building_queue.size())
		for i in player.building_queue.size():
			var type := player.get_building_type(player.building_queue[i])
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = "%s - ready at the end of the turn" % type.display_name
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var index := i
			var cancel := UiStyle.make_button("Cancel", func() -> void: hud.cancel_building_requested.emit(index))
			cancel.tooltip_text = "Call it off and get back %s." % ResourceDeposit.format_cost(type.cost)
			row.add_child(cancel)
			add(row)

	add_separator()
	add_heading("Built (%d)" % player.buildings.size())
	if player.buildings.is_empty():
		add_note("No buildings yet.")
		return
	var built := _grid()
	for type in player.building_types:
		var count := player.count_buildings(type.id)
		if count == 0:
			continue
		var label := Label.new()
		label.text = "%s  %d/%d" % [type.display_name, count, player.get_building_limit(type.id)]
		var output := type.get_output_text()
		if output != "":
			label.text += "  (%s%s)" % [output, " each" if count > 1 else ""]
		label.tooltip_text = type.description
		label.mouse_filter = Control.MOUSE_FILTER_PASS  # So the tooltip shows.
		label.custom_minimum_size.x = _column_width()
		built.add_child(label)
	add(built)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _column_width() -> float:
	return (panel_width - 16 - 16) / 2.0


## "Surgical Ward  0/2" and what it does, with a "Build - 5 Sediment,
## 2 Titanium" button (disabled, saying why, if it can't be built now).
func _make_build_row(type: Building) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.x = _column_width()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.tooltip_text = type.description
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = "%s  %d/%d" % [type.display_name, player.count_planned_buildings(type.id), player.get_building_limit(type.id)]
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	text.add_child(name_label)
	var about := Label.new()
	about.text = type.description.get_slice("\n", 0)
	about.add_theme_font_size_override("font_size", 12)
	about.modulate = Color(1, 1, 1, 0.65)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.mouse_filter = Control.MOUSE_FILTER_PASS
	text.add_child(about)

	var reason := player.get_building_refusal(type.id)
	var button := UiStyle.make_button("Build\n%s" % ResourceDeposit.format_cost(type.cost),
		func() -> void: hud.build_building_requested.emit(type.id))
	button.custom_minimum_size.x = 160
	button.add_theme_font_size_override("font_size", 13)
	button.disabled = reason != ""
	button.tooltip_text = ("Can't build yet: %s.\n\n" % reason if reason != "" else "") + type.description
	row.add_child(button)
	if reason.begins_with("needs"):
		name_label.text += "  (%s)" % reason
		name_label.modulate = Color(1, 1, 1, 0.55)
	return row
