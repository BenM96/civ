class_name TrainingPanel
extends HudPanel
## A Train button for every unit the hub can train (with its current price),
## grouped by unit type - only units whose tech we have and whose building
## the hub has built, and the training queue with Cancel buttons.

const COLUMNS := 3


func _init(p_hud: Hud) -> void:
	super(p_hud)
	panel_width = 640.0
	title = "Training"
	button_text = "Training"
	tooltip = "Training (T)"
	shortcut = KEY_T
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<circle cx="11" cy="11" r="5.5" fill="#eef4ff"/><path d="M1 29c0-7 4-11 10-11s10 4 10 11z" fill="#eef4ff"/>
<rect x="23" y="3" width="4" height="14" rx="1" fill="#7dff7a"/><rect x="18" y="8" width="14" height="4" rx="1" fill="#7dff7a"/>
</svg>"""


func get_button_text() -> String:
	var queued := player.training_queue.size() if player else 0
	return "Training  (%d)" % queued if queued > 0 else button_text


func fill() -> void:
	add_note("Hover over a unit to see what it does and how hard it hits.")
	var shown := 0
	for type in [Unit.UnitType.CIVILIAN, Unit.UnitType.INFANTRY, Unit.UnitType.ARMOUR, Unit.UnitType.AIR]:
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		for blueprint in player.blueprints:
			if blueprint.unit_type == type and player.has_unit_tech(blueprint) and player.has_training_building(blueprint):
				grid.add_child(_make_train_button(blueprint))
		if grid.get_child_count() == 0:
			grid.free()
			continue
		shown += 1
		var heading := Unit.get_type_name(type)
		if type == Unit.UnitType.CIVILIAN:
			heading += "  -  Workers %d/%d" % [player.count_workers(), player.get_worker_limit()]
		add_heading(heading)
		add(grid)
	if shown == 0:
		add_note("Nothing to train yet. Research techs and build the buildings that house units.")

	add_separator()
	add_heading("Queue (%d)" % player.training_queue.size())
	if player.training_queue.is_empty():
		add_note("Nothing in training.")
	for i in player.training_queue.size():
		var order := player.training_queue[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		if i == 0:
			label.text = "%s - %d turn(s) left" % [order.blueprint.unit_name, order.turns_left]
		else:
			label.text = "%s - queued" % order.blueprint.unit_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var index := i
		row.add_child(UiStyle.make_button("Cancel", func() -> void: hud.cancel_training_requested.emit(index)))
		add(row)


## "Tank Destroyer" over "3 Gold, 3 Titanium - 5 turns"; trains one when
## pressed. Over why not instead if it can't be trained now (e.g. the
## Worker limit).
func _make_train_button(bp: UnitBlueprint) -> Button:
	var cost := player.get_training_cost(bp)
	var needs := player.get_training_refusal(bp)
	var second_line := "%s - %d turns" % [ResourceDeposit.format_cost(cost), bp.train_turns] \
		if needs == "" else needs.left(1).to_upper() + needs.substr(1)
	var button := UiStyle.make_button("%s\n%s" % [bp.unit_name, second_line],
		func() -> void: hud.train_requested.emit(bp))
	button.custom_minimum_size.x = (panel_width - 16 - 6 * (COLUMNS - 1)) / COLUMNS
	button.add_theme_font_size_override("font_size", 13)
	button.disabled = needs != "" or not player.can_afford(cost)
	var why := ""
	if needs != "":
		why = "Can't train yet: %s.\n" % needs
	elif button.disabled:
		why = "Not enough resources.\n"
	button.tooltip_text = why + bp.get_info_text() + "\n" + bp.get_cost_growth_text()
	return button
