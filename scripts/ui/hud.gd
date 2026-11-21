class_name Hud
extends CanvasLayer
## On-screen UI. Built in code to keep scenes simple.
##
## Layout:
##   - Top bar: turn, resources, hint/help, auto-end toggle, End Turn.
##   - Bottom bar: section buttons (Units, Field, Training, Buildings). Clicking one opens that
##     section in a panel just above the bar; clicking it again closes it.
##   - Event log (top right) and hovered-tile info (bottom right).

signal end_turn_requested
## kind is a mission id understood by the game, e.g. "move" or "harvest".
signal mission_requested(unit: Unit, kind: String)
signal cancel_mission_requested(unit: Unit)
## Asks the game to centre the camera on a unit.
signal focus_requested(unit: Unit)
## Wait (true) keeps a unit home without it needing orders; false wakes it.
signal wait_requested(unit: Unit, value: bool)
## Emitted when the section panel closes.
signal hub_panel_closed
signal train_requested(blueprint: UnitBlueprint)
signal cancel_training_requested(index: int)
signal auto_end_toggled(enabled: bool)
## TESTING ONLY - remove before release. The "+50 all" button was pressed.
signal debug_resources_requested
## The player closed the winner popup with Keep Playing.
signal popup_closed

enum Section { NONE, UNITS, FIELD, TRAINING, BUILDINGS }

const END_TURN_TEXT := "End Turn (Enter)"
const MAX_LOG_LINES := 8
const BOTTOM_BAR_HEIGHT := 78.0
const PANEL_WIDTH := 380.0

const SECTION_TITLES := {Section.UNITS: "Units", Section.FIELD: "In the Field", Section.TRAINING: "Training",
	Section.BUILDINGS: "Buildings"}

const ICON_UNITS := """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<circle cx="22" cy="10" r="4.5" fill="#9fb4d6"/><path d="M14 27c1-6 4-9 8-9s7 3 8 9z" fill="#9fb4d6"/>
<circle cx="11" cy="11" r="5.5" fill="#eef4ff"/><path d="M1 29c0-7 4-11 10-11s10 4 10 11z" fill="#eef4ff"/>
</svg>"""

const ICON_TRAINING := """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<circle cx="11" cy="11" r="5.5" fill="#eef4ff"/><path d="M1 29c0-7 4-11 10-11s10 4 10 11z" fill="#eef4ff"/>
<rect x="23" y="3" width="4" height="14" rx="1" fill="#7dff7a"/><rect x="18" y="8" width="14" height="4" rx="1" fill="#7dff7a"/>
</svg>"""

## A greenhouse: a glass dome with a sprout inside.
const ICON_BUILDINGS := """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<rect x="2" y="25" width="28" height="4" rx="1" fill="#9fb4d6"/>
<path d="M4 25a12 12 0 0 1 24 0z" fill="#bfe6ff" fill-opacity="0.45" stroke="#eef4ff" stroke-width="2"/>
<path d="M16 25v-9" stroke="#7dff7a" stroke-width="2.5"/>
<path d="M16 19c-4 0-6-2-6-5 4 0 6 2 6 5zm0-2c0-3 2-5 6-5 0 3-2 5-6 5z" fill="#7dff7a"/>
</svg>"""

## A map pin over a route line: units out in the field.
const ICON_FIELD := """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<path d="M3 28c5-6 9 0 14-5s8-3 12-6" stroke="#9fb4d6" stroke-width="2.5" fill="none" stroke-dasharray="3 3"/>
<path d="M16 2c-5 0-8 3.5-8 8 0 6 8 13 8 13s8-7 8-13c0-4.5-3-8-8-8z" fill="#ffb44a"/>
<circle cx="16" cy="10" r="3.2" fill="#2a1a14"/>
</svg>"""

var _turn_label: Label
## ResourceDeposit.Type -> Label
var _inventory_labels: Dictionary = {}
var _hint_label: Label
var _help_label: Label
var _end_turn_button: Button
var _log_label: Label
var _log_lines: PackedStringArray = []
var _tile_panel: PanelContainer
var _tile_label: Label

var _section_panel: PanelContainer
var _section_title: Label
var _section_list: VBoxContainer
## Section -> Button
var _section_buttons: Dictionary = {}
var _section := Section.NONE

var _player: Player
var _game_over := false
## The popup covering the screen, or null.
var _popup: Control = null
## Unit id -> the mission kind picked in its dropdown this session. Takes
## priority over the unit's last mission (once sent, they're the same).
var _chosen_mission: Dictionary = {}


func _ready() -> void:
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _game_over or _popup != null:
		return
	if key.keycode == KEY_U:
		toggle_section(Section.UNITS)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F:
		toggle_section(Section.FIELD)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_T:
		toggle_section(Section.TRAINING)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_B:
		toggle_section(Section.BUILDINGS)
		get_viewport().set_input_as_handled()


# --- Public API ------------------------------------------------------------

## Connects the HUD to the player whose units, training and buildings it shows.
func set_player(player: Player) -> void:
	if _player == player:
		return
	if _player:
		for s in [_player.units_changed, _player.inventory_changed, _player.training_changed, _player.buildings_changed]:
			if s.is_connected(refresh):
				s.disconnect(refresh)
	_player = player
	_player.units_changed.connect(refresh)
	_player.inventory_changed.connect(refresh)
	_player.training_changed.connect(refresh)
	_player.buildings_changed.connect(refresh)
	refresh()


## Opens the Units section for `hub` (used when the hub is clicked on the map).
func show_hub(player: Player) -> void:
	set_player(player)
	open_section(Section.UNITS)


func hide_hub() -> void:
	close_section()


func is_hub_open() -> bool:
	return _section != Section.NONE


func open_section(section: Section) -> void:
	if section == Section.NONE:
		close_section()
		return
	_section = section
	_section_panel.visible = true
	refresh()


func close_section() -> void:
	if _section == Section.NONE:
		return
	_section = Section.NONE
	_section_panel.visible = false
	_update_section_buttons()
	hub_panel_closed.emit()


func toggle_section(section: Section) -> void:
	if _section == section:
		close_section()
	else:
		open_section(section)


func set_turn(turn: int) -> void:
	_turn_label.text = "Turn %d" % turn
	refresh()


## Shows every resource type, including ones the hub has none of yet, plus
## the net change per turn, e.g. "Titanium: 5 (+1)" or "Biomass: 40 (-2)".
func set_inventory(inventory: Dictionary, income: Dictionary = {}) -> void:
	for type in _inventory_labels:
		var label: Label = _inventory_labels[type]
		label.text = "%s: %d" % [ResourceDeposit.get_type_name(type), inventory.get(type, 0)]
		if not is_zero_approx(income.get(type, 0.0)):
			label.text += " (%s)" % ResourceDeposit.format_change(income[type])


## Covers the screen with a final message and a Play Again button.
func show_game_over(title: String, message: String, color: Color) -> void:
	_game_over = true
	_end_turn_button.disabled = true
	_show_popup(title, message, color, false)


## Announces the winner. Unlike game over, the player can close it with
## Keep Playing and carry on; `popup_closed` is emitted when they do.
func show_winner(title: String, message: String, color: Color) -> void:
	_show_popup(title, message, color, true)


## True while a popup (winner or game over) is covering the screen.
func is_popup_open() -> bool:
	return _popup != null


## A message box in the middle of the screen that blocks clicks to the map.
## Always has Play Again; `can_continue` adds Keep Playing, which closes it.
func _show_popup(title: String, message: String, color: Color, can_continue: bool) -> void:
	close_section()
	if _popup:
		_popup.queue_free()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks to the map.
	add_child(shade)
	_popup = shade
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box_style(Color(0.1, 0.07, 0.07, 0.97), color, 3, 10))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", color)
	box.add_child(title_label)
	var body := Label.new()
	body.text = message
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 420
	box.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	if can_continue:
		buttons.add_child(_make_button("Keep Playing", func() -> void:
			_popup.queue_free()
			_popup = null
			popup_closed.emit()))
	buttons.add_child(_make_button("Play Again", func() -> void: get_tree().reload_current_scene()))


func set_tile_info(text: String) -> void:
	_tile_label.text = text
	_tile_panel.visible = text != ""


func set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = text != ""
	_help_label.visible = text == ""


func log_event(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)


## Re-reads the hub: bottom-bar counts always, panel contents if open.
func refresh() -> void:
	_update_section_buttons()
	if _player == null or _section == Section.NONE:
		return
	_section_title.text = SECTION_TITLES[_section]
	for child in _section_list.get_children():
		child.queue_free()
	match _section:
		Section.UNITS:
			_fill_units()
		Section.FIELD:
			_fill_field()
		Section.TRAINING:
			_fill_training()
		Section.BUILDINGS:
			_fill_buildings()


## Kept for older callers.
func refresh_hub_panel() -> void:
	refresh()


# --- Section contents ------------------------------------------------------

## Every mission `unit` may be given, as [kind, label, tooltip, affordable],
## in the order the dropdown lists them. Driven by the unit's
## allowed_missions, so a new unit type needs no HUD changes.
func _mission_choices(unit: Unit) -> Array:
	var choices := []
	if unit.can_take("move"):
		choices.append(["move", "Move", "Walk to a tile, then come home.", true])
	if unit.can_take("guard"):
		choices.append(["guard", "Guard (%d turns)" % GuardMission.GUARD_TURNS,
			"Hold a tile for %d turns, stopping enemy infantry and killing enemy workers there, then come home." % GuardMission.GUARD_TURNS, true])
	if unit.can_take("escort"):
		for other in _player.units:
			var m := EscortMission.new(other.id)
			if m.get_invalid_reason(unit) == "":
				var plans := "" if other.mission == null else " (%s)" % other.mission.get_description()
				choices.append(["escort:%d" % other.id, "Escort %s%s" % [other.display_name, plans],
					"Follow %s wherever it goes and fight beside it, then come home with it. Sets off as soon as %s does - no target to pick." % [
						other.display_name, other.display_name], true])
	if unit.can_take("capture"):
		choices.append(["capture", "Capture",
			"Take over another colony's extractor or conveyor belt. Takes 1 turn on the spot.", true])
	if unit.can_take("harvest"):
		choices.append(["harvest", "Harvest", "Bring back 1 resource from a deposit.", true])
	if unit.can_take("build"):
		for b in _player.buildables:
			# Line jobs pay as they go, so they're always offered; the order
			# itself says if you can't afford to start.
			if b.line_of == b.id:
				var extra := "" if b.requires.is_empty() else " (and %ss where missing)" % " / ".join(
					b.requires.map(func(r: String) -> String: return _player.get_buildable(r).display_name))
				choices.append(["build:" + b.id, "Build %ss (%s each)" % [b.display_name, b.get_cost_text()],
					"Pick a tile: builds a %s%s on every tile from the hub to there, paying as it goes. Stops and comes home if you run out." % [
						b.display_name, extra], true])
			elif b.line_of != "":
				var line_name := _player.get_buildable(b.line_of).display_name
				choices.append(["build:" + b.id, "Build %s (%s, + %ss to hub)" % [b.display_name, b.get_cost_text(), line_name],
					"Pick a deposit: lays foundations and %ss from the hub to it where missing, then builds the %s. Pays as it goes." % [
						line_name, b.display_name], true])
			else:
				choices.append(["build:" + b.id, "Build %s (%s)" % [b.display_name, b.get_cost_text()],
					"Costs %s." % b.get_cost_text(), _player.can_afford(b.cost)])
	if unit.can_take("demolish"):
		choices.append(["demolish", "Demolish",
			"Tear down foundations, bridges, extractors or conveyors on a tile, leaving rubble.", true])
	return choices


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
	_style_button(picker)
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


## Units at home that are ready for orders. Units told to wait are listed
## separately underneath (just a Wake button) so they can be brought back.
func _fill_units() -> void:
	var ready := _player.get_units_needing_orders()
	_add_heading("Ready for orders (%d)" % ready.size())
	if ready.is_empty():
		_add_note("Nobody is waiting for orders.")
	for unit in ready:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = unit.display_name
		name_label.custom_minimum_size.x = 84
		row.add_child(name_label)
		var u := unit
		var picker := _make_mission_picker(unit)
		row.add_child(picker)
		var target := _make_button("Select Target", func() -> void:
			if picker.selected >= 0:
				mission_requested.emit(u, picker.get_item_metadata(picker.selected)))
		target.disabled = picker.selected < 0
		# Escorts need no tile: the button gives the order straight away.
		var label_for := func(i: int) -> void:
			var escort := i >= 0 and str(picker.get_item_metadata(i)).begins_with("escort:")
			target.text = "Give Order" if escort else "Select Target"
			target.tooltip_text = "Sends the order now (no tile to pick)." if escort \
				else "Then click a tile on the map to send this unit there."
		label_for.call(picker.selected)
		picker.item_selected.connect(label_for)
		row.add_child(target)
		var wait := _make_button("Wait", func() -> void: wait_requested.emit(u, true))
		wait.tooltip_text = "Stay at the hub. Waiting units don't need orders, so idle turns can be skipped."
		row.add_child(wait)
		_section_list.add_child(row)

	var waiting: Array[Unit] = []
	for unit in _player.get_garrison():
		if unit.waiting:
			waiting.append(unit)
	if waiting.is_empty():
		return
	_section_list.add_child(HSeparator.new())
	_add_heading("Waiting at the hub (%d)" % waiting.size())
	for unit in waiting:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = unit.display_name
		name_label.modulate = Color(1, 1, 1, 0.55)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var u := unit
		var wake := _make_button("Wake", func() -> void: wait_requested.emit(u, false))
		wake.tooltip_text = "Make this unit ready for orders again"
		row.add_child(wake)
		_section_list.add_child(row)


## Every unit that is out of the hub or leaving it, grouped by what it's doing.
func _fill_field() -> void:
	var field := _player.get_field_units()
	if field.is_empty():
		_add_note("Nobody is out. Give orders from the Units panel.")
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
			_section_list.add_child(HSeparator.new())
		first = false
		_add_heading("%s (%d)" % [group[1], members.size()])
		for unit in members:
			var row := HBoxContainer.new()
			var status := Label.new()
			status.text = "%s\n  %s" % [unit.display_name, unit.get_status_text()]
			status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status.custom_minimum_size.x = 240
			status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(status)
			var u := unit
			if unit.can_cancel_mission():
				var cancel := _make_button("Cancel", func() -> void: cancel_mission_requested.emit(u))
				if unit.state == Unit.State.DEPLOYING:
					cancel.tooltip_text = "Withdraw the order (refunds any cost)"
				else:
					cancel.tooltip_text = "Call off the mission; the unit stays at the hub, ready for new orders. Anything already built stays."
				cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(cancel)
			else:
				var show := _make_button("Show", func() -> void: focus_requested.emit(u))
				show.tooltip_text = "Centre the camera on this unit"
				show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(show)
			_section_list.add_child(row)


func _fill_training() -> void:
	_add_heading("Train a unit")
	for blueprint in _player.blueprints:
		var bp := blueprint
		var cost := _player.get_training_cost(bp)
		var button := _make_button("Train %s  (%s, %d turns)" % [
			bp.unit_name, ResourceDeposit.format_cost(cost), bp.train_turns],
			func() -> void: train_requested.emit(bp))
		button.disabled = not _player.can_afford(cost)
		button.tooltip_text = ("Not enough resources. " if button.disabled else "") \
			+ bp.get_cost_growth_text()
		_section_list.add_child(button)

	_section_list.add_child(HSeparator.new())
	_add_heading("Queue (%d)" % _player.training_queue.size())
	if _player.training_queue.is_empty():
		_add_note("Nothing in training.")
	for i in _player.training_queue.size():
		var order := _player.training_queue[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		if i == 0:
			label.text = "%s - %d turn(s) left" % [order.blueprint.unit_name, order.turns_left]
		else:
			label.text = "%s - queued" % order.blueprint.unit_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var index := i
		row.add_child(_make_button("Cancel", func() -> void: cancel_training_requested.emit(index)))
		_section_list.add_child(row)


## The buildings inside the hub. (Building new ones will come here later.)
func _fill_buildings() -> void:
	_add_heading("In your hub (%d)" % _player.buildings.size())
	if _player.buildings.is_empty():
		_add_note("No buildings yet.")
	for building in _player.buildings:
		var label := Label.new()
		var output := building.get_output_text()
		label.text = building.display_name + ("  (%s)" % output if output != "" else "")
		label.tooltip_text = building.description
		label.mouse_filter = Control.MOUSE_FILTER_PASS  # So the tooltip shows.
		_section_list.add_child(label)


func _update_section_buttons() -> void:
	if _section_buttons.is_empty():
		return
	var units_button: Button = _section_buttons[Section.UNITS]
	var training_button: Button = _section_buttons[Section.TRAINING]
	var field_button: Button = _section_buttons[Section.FIELD]
	var buildings_button: Button = _section_buttons[Section.BUILDINGS]
	if _player:
		var idle := _player.get_units_needing_orders().size()
		units_button.text = "Units  (%d ready)" % idle if idle > 0 else "Units"
		var out := _player.get_field_units().size()
		field_button.text = "Field  (%d)" % out if out > 0 else "Field"
		var queued := _player.training_queue.size()
		training_button.text = "Training  (%d)" % queued if queued > 0 else "Training"
		var built := _player.buildings.size()
		buildings_button.text = "Buildings  (%d)" % built if built > 0 else "Buildings"
	for section in _section_buttons:
		var b: Button = _section_buttons[section]
		b.set_pressed_no_signal(section == _section)


# --- Construction ----------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_top_bar(root)
	_build_bottom_bar(root)

	# Section panel: sits just above the bottom bar on the left, grows upward.
	_section_panel = PanelContainer.new()
	_pin(_section_panel, Vector2(0, 1), Vector2(12, -BOTTOM_BAR_HEIGHT - 8),
		Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	_section_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_section_panel.add_theme_stylebox_override("panel",
		_box_style(Color(0.1, 0.07, 0.07, 0.94), Color(0.4, 0.85, 1.0, 0.6), 2, 8))
	_section_panel.visible = false
	root.add_child(_section_panel)
	var box := VBoxContainer.new()
	_section_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_section_title = Label.new()
	_section_title.add_theme_font_size_override("font_size", 20)
	_section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_section_title)
	header.add_child(_make_button("X", close_section))
	_section_list = VBoxContainer.new()
	box.add_child(_section_list)

	# Event log (top right)
	var log_panel := PanelContainer.new()
	_pin(log_panel, Vector2(1, 0), Vector2(-12, 52), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	log_panel.custom_minimum_size = Vector2(300, 0)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_theme_stylebox_override("panel", _box_style(Color(0.1, 0.07, 0.07, 0.8), Color(1, 1, 1, 0.1), 1, 6))
	root.add_child(log_panel)
	var log_box := VBoxContainer.new()
	log_panel.add_child(log_box)
	var log_title := Label.new()
	log_title.text = "Events"
	log_box.add_child(log_title)
	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.modulate = Color(1, 1, 1, 0.8)
	log_box.add_child(_log_label)

	# Hovered tile info (bottom right, above the bar)
	_tile_panel = PanelContainer.new()
	_pin(_tile_panel, Vector2(1, 1), Vector2(-12, -BOTTOM_BAR_HEIGHT - 8),
		Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	_tile_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile_panel.add_theme_stylebox_override("panel", _box_style(Color(0.1, 0.07, 0.07, 0.85), Color(1, 1, 1, 0.1), 1, 6))
	root.add_child(_tile_panel)
	_tile_label = Label.new()
	_tile_panel.add_child(_tile_label)
	_tile_panel.visible = false


func _build_top_bar(root: Control) -> void:
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	var top_style := _bar_style()
	top_style.border_width_bottom = 2
	top.add_theme_stylebox_override("panel", top_style)
	root.add_child(top)
	var top_row := HBoxContainer.new()
	top.add_child(top_row)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(_turn_label)
	# One coloured label per resource, in a fixed order.
	for type in [ResourceDeposit.Type.BIOMASS, ResourceDeposit.Type.TITANIUM, ResourceDeposit.Type.SEDIMENT,
			ResourceDeposit.Type.GOLD, ResourceDeposit.Type.UNOBTAINIUM]:
		var gap := Control.new()
		gap.custom_minimum_size.x = 10
		top_row.add_child(gap)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", ResourceDeposit.get_type_color(type))
		top_row.add_child(label)
		_inventory_labels[type] = label
	# Hint (shown while choosing a target; replaces the controls help)
	_hint_label = Label.new()
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.visible = false
	top_row.add_child(_hint_label)
	_help_label = Label.new()
	_help_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_help_label.text = "WASD: pan   Wheel: zoom   U: units   F: field   T: training   B: buildings   "
	_help_label.modulate = Color(1, 1, 1, 0.6)
	_help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(_help_label)
	var auto_end := CheckBox.new()
	auto_end.text = "Skip idle turns"
	auto_end.button_pressed = true
	auto_end.focus_mode = Control.FOCUS_NONE
	auto_end.tooltip_text = "Move straight on to the next turn when every unit is already busy at the start of a turn.\nTurns where you give orders are never ended for you."
	auto_end.toggled.connect(func(on: bool) -> void: auto_end_toggled.emit(on))
	top_row.add_child(auto_end)
	# TESTING ONLY - remove before release (with Orders.debug_resources()).
	var debug_give := _make_button("+%d all (test)" % Orders.DEBUG_RESOURCE_AMOUNT,
		func() -> void: debug_resources_requested.emit())
	debug_give.tooltip_text = "Testing only: give your colony %d of every resource." % Orders.DEBUG_RESOURCE_AMOUNT
	top_row.add_child(debug_give)
	_end_turn_button = _make_button(END_TURN_TEXT, func() -> void: end_turn_requested.emit())
	_end_turn_button.custom_minimum_size.x = 140
	top_row.add_child(_end_turn_button)


func _build_bottom_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -BOTTOM_BAR_HEIGHT
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bar_style := _bar_style()
	bar_style.border_width_top = 2
	bar.add_theme_stylebox_override("panel", bar_style)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_section_buttons[Section.UNITS] = _make_section_button(row, "Units", ICON_UNITS, Section.UNITS, "Units (U)")
	_section_buttons[Section.FIELD] = _make_section_button(row, "Field", ICON_FIELD, Section.FIELD, "Units in the field (F)")
	_section_buttons[Section.TRAINING] = _make_section_button(row, "Training", ICON_TRAINING, Section.TRAINING, "Training (T)")
	_section_buttons[Section.BUILDINGS] = _make_section_button(row, "Buildings", ICON_BUILDINGS, Section.BUILDINGS, "Buildings in your hub (B)")


func _make_section_button(parent: Control, text: String, svg: String, section: Section, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.icon = _svg_texture(svg)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, BOTTOM_BAR_HEIGHT - 14)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_constant_override("h_separation", 10)
	var accent := Color(0.4, 0.85, 1.0)
	b.add_theme_stylebox_override("normal", _box_style(Color(0.2, 0.15, 0.14, 0.95), Color(1, 1, 1, 0.08)))
	b.add_theme_stylebox_override("hover", _box_style(Color(0.28, 0.21, 0.19, 0.95), Color(1, 1, 1, 0.25)))
	b.add_theme_stylebox_override("pressed", _box_style(Color(0.16, 0.26, 0.32, 0.95), accent))
	b.add_theme_stylebox_override("hover_pressed", _box_style(Color(0.19, 0.3, 0.37, 0.95), accent))
	b.add_theme_color_override("font_pressed_color", accent.lightened(0.4))
	b.add_theme_color_override("font_hover_pressed_color", accent.lightened(0.4))
	b.pressed.connect(func() -> void: toggle_section(section))
	parent.add_child(b)
	return b


func _box_style(bg: Color, border: Color, border_width := 2, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(8)
	return s


## Solid background for the top/bottom bars.
func _bar_style() -> StyleBoxFlat:
	var s := _box_style(Color(0.1, 0.07, 0.07, 0.94), Color(0.45, 0.25, 0.18, 0.8), 0, 0)
	s.set_content_margin_all(6)
	return s


func _svg_texture(svg: String) -> Texture2D:
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.25) != OK:
		return null
	return ImageTexture.create_from_image(image)


## Anchors a control to a point on the screen; it grows from there as its
## content needs more room.
func _pin(c: Control, anchor: Vector2, offset: Vector2,
		grow_h: Control.GrowDirection, grow_v: Control.GrowDirection) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y
	c.grow_horizontal = grow_h
	c.grow_vertical = grow_v


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # Keep Enter/arrows for the game.
	b.pressed.connect(on_pressed)
	_style_button(b)
	return b


## The HUD's rust-brown button look, for any kind of button.
func _style_button(b: Button) -> void:
	var normal := _box_style(Color(0.3, 0.2, 0.17), Color(0.6, 0.38, 0.28), 1, 4)
	normal.set_content_margin_all(5)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.42, 0.28, 0.22)
	hover.border_color = Color(0.95, 0.65, 0.45)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.13, 0.11)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.18, 0.14, 0.13)
	disabled.border_color = Color(0.3, 0.24, 0.22)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)


func _add_heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_section_list.add_child(l)


func _add_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.55)
	_section_list.add_child(l)
