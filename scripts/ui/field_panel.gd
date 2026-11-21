class_name FieldPanel
extends HudPanel
## Every unit that is out of the hub or leaving it, grouped by what it's
## doing, with Cancel (if it can still be called off) or Show.


func _init(p_hud: Hud) -> void:
	super(p_hud)
	title = "In the Field"
	button_text = "Field"
	tooltip = "Units in the field (F)"
	shortcut = KEY_F
	## A map pin over a route line: units out in the field.
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<path d="M3 28c5-6 9 0 14-5s8-3 12-6" stroke="#9fb4d6" stroke-width="2.5" fill="none" stroke-dasharray="3 3"/>
<path d="M16 2c-5 0-8 3.5-8 8 0 6 8 13 8 13s8-7 8-13c0-4.5-3-8-8-8z" fill="#ffb44a"/>
<circle cx="16" cy="10" r="3.2" fill="#2a1a14"/>
</svg>"""


func get_button_text() -> String:
	var out := player.get_field_units().size() if player else 0
	return "Field  (%d)" % out if out > 0 else button_text


func fill() -> void:
	var field := player.get_field_units()
	if field.is_empty():
		add_note("Nobody is out. Give orders from the Mission Briefing panel.")
		return
	var groups := [
		[Unit.State.DEPLOYING, "Departing at end of turn"],
		[Unit.State.ON_MISSION, "On a mission"],
		[Unit.State.RETURNING, "Returning to the hub"],
	]
	var first := true
	for group in groups:
		var members: Array[Unit] = []
		for unit in field:
			if unit.state == group[0]:
				members.append(unit)
		if members.is_empty():
			continue
		if not first:
			add_separator()
		first = false
		add_heading("%s (%d)" % [group[1], members.size()])
		for unit in members:
			add(_make_row(unit))


func _make_row(unit: Unit) -> HBoxContainer:
	var row := HBoxContainer.new()
	var status := Label.new()
	status.text = "%s\n  %s" % [unit.display_name, unit.get_status_text()]
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 240
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	var u := unit
	if unit.can_cancel_mission():
		var cancel := UiStyle.make_button("Cancel", func() -> void: hud.cancel_mission_requested.emit(u))
		if unit.state == Unit.State.DEPLOYING:
			cancel.tooltip_text = "Withdraw the order (refunds any cost)"
		else:
			cancel.tooltip_text = "Call off the mission; the unit stays at the hub, ready for new orders. Anything already built stays."
		cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cancel)
	else:
		var show := UiStyle.make_button("Show", func() -> void: hud.focus_requested.emit(u))
		show.tooltip_text = "Centre the camera on this unit"
		show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(show)
	return row
