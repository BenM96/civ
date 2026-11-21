class_name MissionBriefingPanel
extends HudPanel
## The units in the hub's Mission Briefing room (see MissionBriefingRoom) -
## the only ones that can be given orders. Each gets a mission dropdown, a
## Select Target button and Wait (off duty in its Break Room, Barracks,
## Hangar or Garage). Units in other rooms are in the Central Hub panel.

## Unit id -> the mission kind picked in its dropdown this session. Takes
## priority over the unit's last mission (once sent, they're the same).
var _chosen_mission: Dictionary = {}


func _init(p_hud: Hud) -> void:
	super(p_hud)
	title = "Mission Briefing"
	button_text = "Mission Briefing"
	tooltip = "Mission Briefing: give orders to the units waiting for them (M)"
	shortcut = KEY_M
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<circle cx="22" cy="10" r="4.5" fill="#9fb4d6"/><path d="M14 27c1-6 4-9 8-9s7 3 8 9z" fill="#9fb4d6"/>
<circle cx="11" cy="11" r="5.5" fill="#eef4ff"/><path d="M1 29c0-7 4-11 10-11s10 4 10 11z" fill="#eef4ff"/>
</svg>"""


func get_button_text() -> String:
	var idle := player.get_units_needing_orders().size() if player else 0
	return "%s  (%d ready)" % [button_text, idle] if idle > 0 else button_text


func fill() -> void:
	var ready := player.get_units_needing_orders()
	add_heading("Ready for orders (%d)" % ready.size())
	if ready.is_empty():
		add_note("Nobody is waiting for orders.")
	for unit in ready:
		add(_make_ready_row(unit))
	var elsewhere := player.get_garrison().size() - ready.size()
	if elsewhere > 0:
		add_separator()
		add_note("%d more unit(s) in other rooms of the hub.\nOpen Central Hub (H) and drag them here to give them orders." % elsewhere)


## Name, mission dropdown, Select Target (or Give Order) and Wait.
func _make_ready_row(unit: Unit) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.custom_minimum_size.x = 84
	row.add_child(name_label)
	var u := unit
	var picker := _make_mission_picker(unit)
	row.add_child(picker)
	var target := UiStyle.make_button("Select Target", func() -> void:
		if picker.selected >= 0:
			hud.mission_requested.emit(u, picker.get_item_metadata(picker.selected)))
	target.disabled = picker.selected < 0
	# Escorts and QRF need no tile: the button gives the order straight away.
	var label_for := func(i: int) -> void:
		var no_tile := i >= 0 and not Orders.needs_target(str(picker.get_item_metadata(i)))
		target.text = "Give Order" if no_tile else "Select Target"
		target.tooltip_text = "Sends the order now (no tile to pick)." if no_tile \
			else "Then click a tile on the map to send this unit there."
	label_for.call(picker.selected)
	picker.item_selected.connect(label_for)
	row.add_child(target)
	var quarters := player.get_quarters_for(unit)
	if quarters:
		var wait := UiStyle.make_button("Wait", func() -> void: hud.room_move_requested.emit(u, quarters.id))
		wait.tooltip_text = "Go off duty in the %s. Units there don't need orders, so idle turns can be skipped." % quarters.display_name
		row.add_child(wait)
	return row


## A dropdown of `unit`'s missions. Opens on the mission the unit did last
## (Unit.last_mission_kind), and remembers a new pick per unit so it
## survives the panel being rebuilt.
func _make_mission_picker(unit: Unit) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE  # Keep Enter for End Turn.
	# Same width on every row (not sized to the longest entry), so rows line up.
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.custom_minimum_size.x = 150
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(picker)
	# What you've picked for it just now, else the mission it did last time.
	var remembered: String = _chosen_mission.get(unit.id, unit.last_mission_kind)
	for choice in _mission_choices(unit):
		var i := picker.item_count
		picker.add_item(choice[1])
		picker.set_item_metadata(i, choice[0])
		picker.set_item_tooltip(i, choice[2] if choice[3] else "Can't afford: %s" % choice[2].to_lower())
		picker.set_item_disabled(i, not choice[3])
	# Select the remembered mission if it's still possible, else the first one that is.
	picker.selected = -1
	for i in picker.item_count:
		if not picker.is_item_disabled(i) and (picker.selected < 0 or picker.get_item_metadata(i) == remembered):
			picker.selected = i
	var id := unit.id
	picker.item_selected.connect(func(i: int) -> void:
		_chosen_mission[id] = picker.get_item_metadata(i))
	return picker


## Every mission `unit` may be given, as [kind, label, tooltip, affordable],
## in the order the dropdown lists them. Driven by the unit's
## allowed_missions, so a new unit type needs no HUD changes.
func _mission_choices(unit: Unit) -> Array:
	var choices := []
	if unit.can_take("move"):
		choices.append(["move", "Move", "Walk to a tile, then come home.", true])
	if unit.can_take("guard"):
		choices.append(["guard", "Guard (%d turns)" % GuardMission.GUARD_TURNS,
			"Hold a tile for %d turns, fighting any enemy that comes onto it, then come home." % GuardMission.GUARD_TURNS, true])
	if unit.can_take("escort"):
		for other in player.units:
			var m := EscortMission.new(other.id)
			if m.get_invalid_reason(unit) == "":
				var plans := "" if other.mission == null else " (%s)" % other.mission.get_description()
				choices.append(["escort:%d" % other.id, "Escort %s%s" % [other.display_name, plans],
					"Follow %s wherever it goes and fight beside it, then come home with it. Sets off as soon as %s does - no target to pick." % [
						other.display_name, other.display_name], true])
	if unit.can_take("sortie"):
		choices.append(["sortie", "Sortie",
			"Pick any tile but a hub. Once everyone else has moved, flies straight there and fights whoever is near; flies home next turn, then refits in the Hangar for %d turns." % unit.refit_turns, true])
	if unit.can_take("qrf"):
		choices.append(["qrf", "QRF (quick reaction force)",
			"Stand by in the QRF room. After everyone else has moved each turn, head for the nearest enemy on one of our extractors or belts; come back when they've gone. Stays on duty until you drag it out of the QRF room.", true])
	if unit.can_take("capture"):
		choices.append(["capture", "Capture",
			"Take over another colony's extractor or conveyor belt. Takes 1 turn on the spot.", true])
	if unit.can_take("harvest"):
		choices.append(["harvest", "Harvest", "Bring back 1 resource from a deposit.", true])
	if unit.can_take("build"):
		for b in player.buildables:
			# Line jobs pay as they go, so they're always offered; the order
			# itself says if you can't afford to start.
			if b.line_of == b.id:
				var extra := "" if b.requires.is_empty() else " (and %ss where missing)" % " / ".join(
					b.requires.map(func(r: String) -> String: return player.get_buildable(r).display_name))
				choices.append(["build:" + b.id, "Build %ss (%s each)" % [b.display_name, b.get_cost_text()],
					"Pick a tile: builds a %s%s on every tile from the hub to there, paying as it goes. Stops and comes home if you run out." % [
						b.display_name, extra], true])
			elif b.line_of != "":
				var line_name := player.get_buildable(b.line_of).display_name
				choices.append(["build:" + b.id, "Build %s (%s, + %ss to hub)" % [b.display_name, b.get_cost_text(), line_name],
					"Pick a deposit: lays foundations and %ss from the hub to it where missing, then builds the %s. Pays as it goes." % [
						line_name, b.display_name], true])
			else:
				choices.append(["build:" + b.id, "Build %s (%s)" % [b.display_name, b.get_cost_text()],
					"Costs %s." % b.get_cost_text(), player.can_afford(b.cost)])
	if unit.can_take("demolish"):
		choices.append(["demolish", "Demolish",
			"Tear down foundations, bridges, extractors or conveyors on a tile, leaving rubble.", true])
	return choices
