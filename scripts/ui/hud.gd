class_name Hud
extends CanvasLayer
## On-screen UI. Built in code to keep scenes simple.
##
## Layout:
##   - Top bar: turn, resources, hint/help, auto-end toggle, End Turn.
##   - Bottom bar: a button per section (Central Hub, Mission Briefing, Field,
##     Training, Buildings).
##     Clicking one opens that section in a panel just above the bar;
##     clicking it again closes it.
##   - Event log (top right) and hovered-tile info (bottom right).
##
## This file is the frame: the bars, the section panel, popups, the log and
## the tile info. What each section shows lives in its own HudPanel script
## (central_hub_panel.gd, mission_briefing_panel.gd, field_panel.gd,
## training_panel.gd, buildings_panel.gd),
## and the shared look in UiStyle. Battle replays are BattleView.
##
## The HUD never changes the game itself: buttons emit the signals below,
## which the game turns into orders.

signal end_turn_requested
## kind is a mission id understood by the game, e.g. "move" or "harvest".
signal mission_requested(unit: Unit, kind: String)
signal cancel_mission_requested(unit: Unit)
## Asks the game to centre the camera on a unit.
signal focus_requested(unit: Unit)
## Asks to move a unit in the hub to another of its rooms (see Room).
signal room_move_requested(unit: Unit, room_id: String)
## Asks to move a unit to `index` in its room's healing queue (see Room).
signal heal_order_requested(unit: Unit, index: int)
## Emitted when the section panel closes.
signal hub_panel_closed
signal train_requested(blueprint: UnitBlueprint)
signal cancel_training_requested(index: int)
## Asks to build a hub building (see Building), by id.
signal build_building_requested(building_id: String)
## Asks to call off a building under construction (Player.building_queue).
signal cancel_building_requested(index: int)
signal auto_end_toggled(enabled: bool)
## TESTING ONLY - remove before release. The "+50 all" button was pressed.
signal debug_resources_requested
## The player closed the winner popup with Keep Playing.
signal popup_closed

## The bottom-bar sections, in the order their buttons appear.
enum Section { NONE, HUB, BRIEFING, FIELD, TRAINING, BUILDINGS }

const END_TURN_TEXT := "End Turn (Enter)"
const MAX_LOG_LINES := 8
const BOTTOM_BAR_HEIGHT := 78.0
const PANEL_WIDTH := 380.0
## Biomass below zero, and the starvation popup.
const STARVING_COLOR := Color(1.0, 0.4, 0.35)
## A wilted sprout in a cracked pot, for the starvation popup.
const WILTED_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<path d="M18 40h28l-4 18H22z" fill="#8a4a32" stroke="#c9785a" stroke-width="2"/>
<path d="M30 42l3 6-3 4 2 5" fill="none" stroke="#2a1410" stroke-width="2"/>
<path d="M32 40c0-10 2-16 8-20" fill="none" stroke="#9a8a4a" stroke-width="3" stroke-linecap="round"/>
<path d="M40 20c6 2 8 8 7 14-5-2-8-7-7-14z" fill="#8a7a3a"/>
<path d="M33 30c-6-1-10 2-12 7 6 1 10-2 12-7z" fill="#7a6a32"/>
<circle cx="47" cy="38" r="1.6" fill="#8a7a3a"/>
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

## Section -> HudPanel
var _panels: Dictionary = {}
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
## Popups waiting for the open one to close (e.g. a starvation notice and a
## winner on the same turn), shown in turn: Callables that show them.
var _waiting_popups: Array[Callable] = []


func _ready() -> void:
	_make_panels()
	_build()


## One HudPanel per section. To add a section, add it to Section and here.
func _make_panels() -> void:
	_panels[Section.HUB] = CentralHubPanel.new(self)
	_panels[Section.BRIEFING] = MissionBriefingPanel.new(self)
	_panels[Section.FIELD] = FieldPanel.new(self)
	_panels[Section.TRAINING] = TrainingPanel.new(self)
	_panels[Section.BUILDINGS] = BuildingsPanel.new(self)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _game_over or _popup != null:
		return
	for section in _panels:
		if key.keycode == _panels[section].shortcut:
			toggle_section(section)
			get_viewport().set_input_as_handled()
			return


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


## Opens the Central Hub section for `player` (used when the hub is clicked
## on the map).
func show_hub(player: Player) -> void:
	set_player(player)
	open_section(Section.HUB)


func hide_hub() -> void:
	close_section()


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
## the net change per turn, e.g. "Titanium: 5 (+1)". Resources that aren't
## stored show only their production, e.g. "Biomass: +2 a turn" (red below
## zero, when units are starving).
func set_inventory(inventory: Dictionary, income: Dictionary = {}) -> void:
	for type in _inventory_labels:
		var label: Label = _inventory_labels[type]
		var type_name := ResourceDeposit.get_type_name(type)
		if not ResourceDeposit.get_info(type).stored:
			var rate: float = income.get(type, 0.0)
			label.text = "%s: %s a turn" % [type_name, ResourceDeposit.format_change(rate)]
			label.add_theme_color_override("font_color",
				STARVING_COLOR if rate < 0 else ResourceDeposit.get_type_color(type))
			label.tooltip_text = "Biomass made each turn (Greenhouses, Biomass extractors) less what your units eat. It isn't stored.\nBelow zero, one unit starves every turn - the most injured first, Workers last." if rate >= 0 \
				else "Your units eat more biomass than the colony makes: one unit will starve at the end of every turn until this is back to zero or above.\nBuild a Greenhouse (Buildings, B) or connect a Biomass extractor."
			continue
		label.text = "%s: %d" % [type_name, inventory.get(type, 0)]
		if not is_zero_approx(income.get(type, 0.0)):
			label.text += " (%s)" % ResourceDeposit.format_change(income[type])


## Makes sure the player notices that one of their units has starved (see
## Player.starve() for `report`): a red flash, then a popup that springs in
## explaining why it happened and how to fix it. Blocks the map until closed
## with Understood (`popup_closed` is emitted then).
func show_starvation(report: Dictionary) -> void:
	if _game_over:
		return
	if _popup:
		_waiting_popups.append(show_starvation.bind(report))
		return
	close_section()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.6, 0.05, 0.02, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks to the map.
	add_child(shade)
	_popup = shade
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box_style(Color(0.12, 0.05, 0.05, 0.98), STARVING_COLOR, 3, 10))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var icon := TextureRect.new()
	icon.texture = UiStyle.svg_texture(WILTED_SVG)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	box.add_child(icon)
	var title := Label.new()
	title.text = "A Unit Has Starved"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", STARVING_COLOR)
	box.add_child(title)
	var who := Label.new()
	who.text = "%s has starved to death." % report["unit"]
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_size_override("font_size", 20)
	box.add_child(who)
	var body := Label.new()
	body.text = _starvation_text(report)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 480
	box.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var ok := UiStyle.make_button("Understood", func() -> void:
		var out := shade.create_tween()
		out.tween_property(shade, "modulate:a", 0.0, 0.2)
		out.tween_callback(shade.queue_free)
		_close_popup())
	ok.custom_minimum_size.x = 160
	buttons.add_child(ok)

	# The animation: the screen flashes red and settles to a dark shade while
	# the popup springs in, then the icon shudders.
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.6, 0.6)
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size / 2.0)
	var flash := shade.create_tween()
	flash.tween_property(shade, "color", Color(0.75, 0.05, 0.02, 0.55), 0.12)
	flash.tween_property(shade, "color", Color(0.08, 0.0, 0.0, 0.65), 0.45)
	var pop := shade.create_tween().set_parallel()
	pop.tween_property(panel, "modulate:a", 1.0, 0.25).set_delay(0.1)
	pop.tween_property(panel, "scale", Vector2.ONE, 0.45).set_delay(0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	icon.resized.connect(func() -> void: icon.pivot_offset = icon.size / 2.0)
	var shake := shade.create_tween()
	shake.tween_interval(0.5)
	for angle in [0.18, -0.15, 0.1, -0.06, 0.0]:
		shake.tween_property(icon, "rotation", angle, 0.07)


## Why the unit starved and what to do about it.
func _starvation_text(report: Dictionary) -> String:
	var production: float = report["production"]
	var eaten: int = report["eaten"]
	var made := production + eaten
	var lines: PackedStringArray = []
	lines.append("Your colony makes %s biomass a turn, but your %d units eat %d: you're %s short." % [
		ResourceDeposit.format_amount(made), report["units"], eaten, ResourceDeposit.format_amount(-production)])
	lines.append("Every turn biomass production is below zero, another unit starves - the most injured first, Workers last.")
	var after: float = report["after"]
	if after >= 0:
		lines.append("With one less unit to feed, production is back to %s a turn, so nobody else will starve - for now." % ResourceDeposit.format_change(after))
	else:
		lines.append("Production is still %s a turn: another unit will starve at the end of next turn." % ResourceDeposit.format_change(after))
	lines.append("To grow more food, build a Greenhouse (Buildings, B) or connect a Biomass extractor to your hub with conveyor belts.")
	return "\n\n".join(lines)


## Covers the screen with a final message and a Play Again button.
func show_game_over(title: String, message: String, color: Color) -> void:
	_game_over = true
	_end_turn_button.disabled = true
	_waiting_popups.clear()
	if _popup:
		_popup.queue_free()
		_popup = null
	_show_popup(title, message, color, false)


## Announces the winner. Unlike game over, the player can close it with
## Keep Playing and carry on; `popup_closed` is emitted when they do.
func show_winner(title: String, message: String, color: Color) -> void:
	if _popup:
		_waiting_popups.append(show_winner.bind(title, message, color))
		return
	_show_popup(title, message, color, true)


## A popup that can be closed was closed: show the next one waiting, or
## let play carry on (`popup_closed`) once there are none.
func _close_popup() -> void:
	_popup = null
	if not _waiting_popups.is_empty():
		_waiting_popups.pop_front().call()
	else:
		popup_closed.emit()


## Replays a battle (see Combat) on a screen of its own and waits for it to
## finish. Returns true if the player chose to skip every remaining battle.
func play_battle(report: Dictionary, map: HexMap) -> bool:
	close_section()
	var view := BattleView.new()
	view.setup(report, map)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	if _popup:
		move_child(_popup, -1)  # Game over / winner stays on top.
	view.play()
	var skip_rest: bool = await view.finished
	view.queue_free()
	return skip_rest


## True while a popup (winner or game over) is covering the screen.
func is_popup_open() -> bool:
	return _popup != null


func set_tile_info(text: String) -> void:
	_tile_label.text = text
	_tile_panel.visible = text != ""


func set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = text != ""
	_help_label.visible = text == ""


## A drag in the Central Hub lights up rooms; redraw the panel when it ends
## to clear them (whether or not the unit was dropped anywhere).
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _section == Section.HUB:
		refresh.call_deferred()


func log_event(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)


## Re-reads the player: bottom-bar counts always, the open panel's contents
## if one is open.
func refresh() -> void:
	_update_section_buttons()
	if _player == null or _section == Section.NONE:
		return
	var panel: HudPanel = _panels[_section]
	_section_title.text = panel.title
	for child in _section_list.get_children():
		_section_list.remove_child(child)
		child.queue_free()
	_section_panel.custom_minimum_size.x = panel.panel_width
	panel.player = _player
	panel.list = _section_list
	panel.fill()
	_fit_section_panel.call_deferred()


## Sizes the section panel to its contents (so it shrinks again too), kept
## pinned just above the bottom bar on the left.
func _fit_section_panel() -> void:
	var s := _section_panel.get_combined_minimum_size()
	_section_panel.offset_left = 12
	_section_panel.offset_right = 12 + s.x
	_section_panel.offset_bottom = -BOTTOM_BAR_HEIGHT - 8
	_section_panel.offset_top = _section_panel.offset_bottom - s.y


func _update_section_buttons() -> void:
	for section in _section_buttons:
		var panel: HudPanel = _panels[section]
		panel.player = _player
		var b: Button = _section_buttons[section]
		b.text = panel.get_button_text()
		b.set_pressed_no_signal(section == _section)


## A message box in the middle of the screen that blocks clicks to the map.
## Always has Play Again; `can_continue` adds Keep Playing, which closes it.
func _show_popup(title: String, message: String, color: Color, can_continue: bool) -> void:
	close_section()
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
	panel.add_theme_stylebox_override("panel", UiStyle.box_style(Color(0.1, 0.07, 0.07, 0.97), color, 3, 10))
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
		buttons.add_child(UiStyle.make_button("Keep Playing", func() -> void:
			shade.queue_free()
			_close_popup()))
	buttons.add_child(UiStyle.make_button("Play Again", func() -> void: get_tree().reload_current_scene()))


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
		UiStyle.box_style(Color(0.1, 0.07, 0.07, 0.94), Color(0.4, 0.85, 1.0, 0.6), 2, 8))
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
	header.add_child(UiStyle.make_button("X", close_section))
	_section_list = VBoxContainer.new()
	box.add_child(_section_list)

	# Event log (top right)
	var log_panel := PanelContainer.new()
	_pin(log_panel, Vector2(1, 0), Vector2(-12, 52), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	log_panel.custom_minimum_size = Vector2(300, 0)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_theme_stylebox_override("panel", UiStyle.box_style(Color(0.1, 0.07, 0.07, 0.8), Color(1, 1, 1, 0.1), 1, 6))
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
	_tile_panel.add_theme_stylebox_override("panel", UiStyle.box_style(Color(0.1, 0.07, 0.07, 0.85), Color(1, 1, 1, 0.1), 1, 6))
	root.add_child(_tile_panel)
	_tile_label = Label.new()
	_tile_panel.add_child(_tile_label)
	_tile_panel.visible = false

	# The open section (e.g. the wide Central Hub) draws over the log and tile info.
	root.move_child(_section_panel, -1)


func _build_top_bar(root: Control) -> void:
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	var top_style := UiStyle.bar_style()
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
	_help_label.text = "WASD: pan   Wheel: zoom   %s   " % _shortcuts_text()
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
	var debug_give := UiStyle.make_button("+%d all (test)" % Orders.DEBUG_RESOURCE_AMOUNT,
		func() -> void: debug_resources_requested.emit())
	debug_give.tooltip_text = "Testing only: give your colony %d of every resource." % Orders.DEBUG_RESOURCE_AMOUNT
	top_row.add_child(debug_give)
	_end_turn_button = UiStyle.make_button(END_TURN_TEXT, func() -> void: end_turn_requested.emit())
	_end_turn_button.custom_minimum_size.x = 140
	top_row.add_child(_end_turn_button)


## e.g. "U: units   F: field   T: training   B: buildings"
func _shortcuts_text() -> String:
	var parts: PackedStringArray = []
	for section in _panels:
		var panel: HudPanel = _panels[section]
		parts.append("%s: %s" % [OS.get_keycode_string(panel.shortcut), panel.button_text.to_lower()])
	return "   ".join(parts)


func _build_bottom_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -BOTTOM_BAR_HEIGHT
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bar_style := UiStyle.bar_style()
	bar_style.border_width_top = 2
	bar.add_theme_stylebox_override("panel", bar_style)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	for section in _panels:
		_section_buttons[section] = _make_section_button(row, section)


func _make_section_button(parent: Control, section: Section) -> Button:
	var panel: HudPanel = _panels[section]
	var b := Button.new()
	b.text = panel.button_text
	b.tooltip_text = panel.tooltip
	b.icon = UiStyle.svg_texture(panel.icon_svg)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, BOTTOM_BAR_HEIGHT - 14)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_constant_override("h_separation", 10)
	var accent := Color(0.4, 0.85, 1.0)
	b.add_theme_stylebox_override("normal", UiStyle.box_style(Color(0.2, 0.15, 0.14, 0.95), Color(1, 1, 1, 0.08)))
	b.add_theme_stylebox_override("hover", UiStyle.box_style(Color(0.28, 0.21, 0.19, 0.95), Color(1, 1, 1, 0.25)))
	b.add_theme_stylebox_override("pressed", UiStyle.box_style(Color(0.16, 0.26, 0.32, 0.95), accent))
	b.add_theme_stylebox_override("hover_pressed", UiStyle.box_style(Color(0.19, 0.3, 0.37, 0.95), accent))
	b.add_theme_color_override("font_pressed_color", accent.lightened(0.4))
	b.add_theme_color_override("font_hover_pressed_color", accent.lightened(0.4))
	b.pressed.connect(func() -> void: toggle_section(section))
	parent.add_child(b)
	return b


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
