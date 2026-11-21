class_name CentralHubPanel
extends HudPanel
## The hub's rooms (see Room), each showing the units in it as cards with
## what they're doing there. Drag a card onto another room to move the unit
## there (a "move_room" order, via hud.room_move_requested); a room that
## won't take that unit refuses the drop, and says why. Units in training
## show as greyed-out cards in the room that holds them, and can't be moved.

const COLUMNS := 4
const ROOM_WIDTH := 215.0
const GAP := 8

const CARD_COLOR := Color(0.2, 0.15, 0.14, 0.95)
const ROOM_COLOR := Color(0.14, 0.1, 0.1, 0.95)
const ROOM_BORDER := Color(1, 1, 1, 0.12)
## Mission Briefing stands out: it's where units get their orders.
const BRIEFING_BORDER := Color(0.4, 0.85, 1.0, 0.7)


func _init(p_hud: Hud) -> void:
	super(p_hud)
	title = "Central Hub"
	button_text = "Central Hub"
	tooltip = "The rooms of your central hub: drag units between them (H)"
	shortcut = KEY_H
	panel_width = COLUMNS * ROOM_WIDTH + (COLUMNS - 1) * GAP + 16
	## A habitat dome with rooms (windows) and a door.
	icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
<rect x="1" y="26" width="30" height="4" rx="1" fill="#9fb4d6"/>
<path d="M3 26a13 13 0 0 1 26 0z" fill="#bfe6ff" fill-opacity="0.35" stroke="#eef4ff" stroke-width="2"/>
<rect x="8" y="17" width="5" height="4" fill="#ffb44a"/><rect x="19" y="17" width="5" height="4" fill="#ffb44a"/>
<rect x="13.5" y="9" width="5" height="4" fill="#ffb44a"/><rect x="14" y="20" width="4" height="6" fill="#2a1a14"/>
</svg>"""


func get_button_text() -> String:
	var home := player.get_garrison().size() if player else 0
	return "%s  (%d)" % [button_text, home] if home > 0 else button_text


func fill() -> void:
	add_note("Drag units between rooms. Hover over a room to see what it's for.")
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	for room in player.rooms:
		grid.add_child(_make_room(room))
	add(grid)


## A room's box: its name and its unit cards. Takes drops of unit cards.
func _make_room(room: Room) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(ROOM_WIDTH, 110)
	var border := BRIEFING_BORDER if room.id == MissionBriefingRoom.ID else ROOM_BORDER
	box.add_theme_stylebox_override("panel", UiStyle.box_style(ROOM_COLOR, border, 1, 6))
	box.tooltip_text = room.description
	box.set_drag_forwarding(Callable(), _can_drop.bind(room), _drop.bind(room))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Drops land on the box.
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)

	var units := player.get_units_in_room(room.id)
	var training: Array[int] = []
	for i in player.training_queue.size():
		if room.holds_training(player.training_queue[i].blueprint):
			training.append(i)
	var heading := UiStyle.heading(room.display_name + ("  (%d)" % units.size() if not units.is_empty() else ""))
	column.add_child(heading)
	for unit in units:
		column.add_child(_make_unit_card(unit, room))
	for i in training:
		column.add_child(_make_training_card(i, room))
	if units.is_empty() and training.is_empty():
		column.add_child(UiStyle.note("Empty"))
	return box


## A draggable card for a unit: name, HP and what it's doing.
func _make_unit_card(unit: Unit, room: Room) -> PanelContainer:
	var card := _card(unit.body_color)
	card.tooltip_text = "%s (%s)\n%s\nDrag to another room to move it." % [
		unit.display_name, Unit.get_type_name(unit.unit_type), unit.get_status_text()]
	card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	card.set_drag_forwarding(_drag_unit.bind(unit, card), _can_drop.bind(room), _drop.bind(room))
	var lines: VBoxContainer = card.get_child(0)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(top)
	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var hp := Label.new()
	hp.text = "HP %d/%d" % [unit.health, unit.max_health]
	hp.add_theme_font_size_override("font_size", 12)
	if unit.is_injured():
		hp.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	else:
		hp.modulate = Color(1, 1, 1, 0.6)
	top.add_child(hp)
	lines.add_child(_small_text(_activity_text(unit)))
	return card


## A greyed-out card for a unit in training (can't be dragged).
func _make_training_card(index: int, room: Room) -> PanelContainer:
	var order := player.training_queue[index]
	var card := _card(Color(0.5, 0.5, 0.5))
	card.modulate = Color(1, 1, 1, 0.55)
	card.tooltip_text = "Being trained. It joins Mission Briefing when it's ready."
	card.set_drag_forwarding(Callable(), _can_drop.bind(room), _drop.bind(room))
	var lines: VBoxContainer = card.get_child(0)
	var name_label := Label.new()
	name_label.text = "%s (in training)" % order.blueprint.unit_name
	lines.add_child(name_label)
	var status := "Training - %d turn(s) left" % order.turns_left if index == 0 \
		else "Queued - training starts after the one ahead"
	lines.add_child(_small_text(status))
	return card


## An empty card with a stripe of `stripe` colour down its left side; add
## lines to its VBoxContainer (child 0).
func _card(stripe: Color) -> PanelContainer:
	var card := PanelContainer.new()
	var style := UiStyle.box_style(CARD_COLOR, stripe, 0, 4)
	style.border_width_left = 4
	style.set_content_margin_all(4)
	style.content_margin_left = 8
	card.add_theme_stylebox_override("panel", style)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 0)
	card.add_child(lines)
	return card


func _small_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 1, 0.7)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## What a unit is doing in its room. Units with a mission (Airlock, QRF)
## describe their mission instead.
func _activity_text(unit: Unit) -> String:
	if unit.mission:
		return unit.mission.get_deploying_text() if unit.state == Unit.State.DEPLOYING \
			else unit.mission.get_progress_text()
	return player.get_room(unit.room_id).get_activity_text(unit)


# --- Drag and drop -----------------------------------------------------------

func _drag_unit(_at: Vector2, unit: Unit, card: Control) -> Variant:
	var preview := _card(unit.body_color)
	var label := Label.new()
	label.text = unit.display_name
	preview.get_child(0).add_child(label)
	preview.modulate = Color(1, 1, 1, 0.85)
	card.set_drag_preview(preview)
	return {"hub_unit": unit.id}


func _dragged_unit(data: Variant) -> Unit:
	if data is Dictionary and data.has("hub_unit") and player:
		return player.get_unit(int(data["hub_unit"]))
	return null


func _can_drop(_at: Vector2, data: Variant, room: Room) -> bool:
	var unit := _dragged_unit(data)
	if unit == null:
		return false
	if unit.room_id == room.id:
		hud.show_drop_hint("")
		return false
	var reason := player.get_room_move_refusal(unit, room.id)
	if reason != "":
		hud.show_drop_hint("Can't move %s to the %s: %s." % [unit.display_name, room.display_name, reason])
		return false
	var note := " (calls off its mission)" if unit.mission else ""
	hud.show_drop_hint("Drop to move %s to the %s%s." % [unit.display_name, room.display_name, note])
	return true


func _drop(_at: Vector2, data: Variant, room: Room) -> void:
	var unit := _dragged_unit(data)
	if unit:
		hud.room_move_requested.emit(unit, room.id)
