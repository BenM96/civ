class_name CentralHubPanel
extends HudPanel
## The hub's rooms (see Room), each showing the units in it as cards with
## what they're doing there. Drag a card onto another room to move the unit
## there (a "move_room" order, via hud.room_move_requested). While dragging,
## rooms the unit can go to light up green and the rest get a red cross; the
## card under the mouse says what dropping it would do, or why it can't.
##
## Rooms the hub hasn't built yet are shown locked (padlock) and take nobody.
## In rooms that heal (Med Bay, Garage) the units waiting to heal are listed
## first, in healing order; drag one onto another of them to change the order
## (a "heal_order" order, via hud.heal_order_requested). Units in training
## show as greyed-out cards in the room that holds them, and can't be moved.
## In rooms that heal, a green box at the top holds the units being healed
## now, one place per unit the room can heal at a time.
## The big red RTB button at the top recalls every unit (Orders.recall_all()).

const COLUMNS := 4
const ROOM_WIDTH := 215.0
## Space between unit cards in a room.
const CARD_GAP := 4
## A unit card's height (measured from a real one; see _make_healing_box()).
static var _card_height := 48.0
const GAP := 8

const CARD_COLOR := Color(0.2, 0.15, 0.14, 0.95)
const ROOM_COLOR := Color(0.14, 0.1, 0.1, 0.95)
const ROOM_BORDER := Color(1, 1, 1, 0.12)
## Mission Briefing stands out: it's where units get their orders.
const BRIEFING_BORDER := Color(0.4, 0.85, 1.0, 0.7)
const LOCKED_COLOR := Color(0.09, 0.07, 0.07, 0.95)
## While dragging: rooms the unit may go to, and the hint text colours.
const CAN_DROP_COLOR := Color(0.35, 0.95, 0.45)
const CANT_DROP_COLOR := Color(1.0, 0.4, 0.35)

const PADLOCK_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="14" height="16">
<path d="M3.5 7V5a3.5 3.5 0 0 1 7 0v2" fill="none" stroke="#c9c2bd" stroke-width="2"/>
<rect x="1" y="7" width="12" height="9" rx="1.5" fill="#c9c2bd"/>
<rect x="6" y="10" width="2" height="3.5" rx="1" fill="#2a1a14"/>
</svg>"""
const CROSS_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">
<path d="M10 10L38 38M38 10L10 38" stroke="#ff5a4a" stroke-width="7" stroke-linecap="round" stroke-opacity="0.85"/>
</svg>"""

## Room id -> its box, for lighting up drop targets while dragging.
var _room_boxes: Dictionary = {}
## The second line of the card being dragged: what dropping it here would do.
var _drag_hint: Label = null


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
	add(_make_health_row())
	add_note("Drag units between rooms. Hover over a room to see what it's for.")
	_room_boxes.clear()
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	for room in player.rooms:
		var box := _make_room(room) if player.is_room_open(room) else _make_locked_room(room)
		_room_boxes[room.id] = box
		grid.add_child(box)
	add(grid)


## The hub's health (enemy Infantry demolishing it take 1 off; at 0 the
## colony is lost) and the Repair button.
func _make_health_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "Hub health %d/%d" % [player.hub_health, Player.HUB_MAX_HEALTH]
	var share := float(player.hub_health) / Player.HUB_MAX_HEALTH
	var fill_color := Color(0.35, 0.85, 0.35)
	if share <= 0.3:
		fill_color = Color(1.0, 0.35, 0.3)
		label.add_theme_color_override("font_color", fill_color)
	elif share <= 0.6:
		fill_color = Color(1.0, 0.75, 0.25)
		label.add_theme_color_override("font_color", fill_color)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.add_theme_stylebox_override("background", UiStyle.box_style(Color(0.08, 0.08, 0.08), Color(0.4, 0.4, 0.4), 1, 3))
	bar.add_theme_stylebox_override("fill", UiStyle.box_style(fill_color, fill_color, 0, 3))
	bar.max_value = Player.HUB_MAX_HEALTH
	bar.value = player.hub_health
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var button := UiStyle.make_button("Repair (%s)" % ResourceDeposit.format_cost(Player.HUB_REPAIR_COST),
		func() -> void: hud.repair_hub_requested.emit())
	var refusal := player.get_hub_repair_refusal()
	button.disabled = refusal != ""
	button.tooltip_text = "Restore 1 health for %s, once a turn.\nEnemy Infantry next to the hub demolish 1 health every %d turns; at 0 your colony is lost." % [
		ResourceDeposit.format_cost(Player.HUB_REPAIR_COST), DemolitionBuildable.new().build_turns]
	if refusal != "":
		button.tooltip_text += "\nCan't right now: %s." % refusal
	row.add_child(button)
	return row


## Regroup and RTB sit in the title row, so they're there however far the
## rooms scroll.
func fill_header(header: HBoxContainer) -> void:
	header.add_child(_make_regroup_button())
	header.add_child(_make_rtb_button())


## Regroup (Player.start_regroup()): military units coming home stand by
## until the whole army is home and healed, then all go to Mission Briefing.
## While one is under way it shows how many are home.
func _make_regroup_button() -> Button:
	var button := UiStyle.make_button("Regroup", func() -> void: hud.regroup_requested.emit())
	button.custom_minimum_size = Vector2(100, 36)
	button.add_theme_font_size_override("font_size", 18)
	button.tooltip_text = "Regroup the army: every military unit that comes home (or is waiting in Mission Briefing) stands by in the QRF room - defending like the QRF, healing when hurt - until all of them are home and at full health. Then they all come to Mission Briefing together.
Units out on missions finish them first."
	if player.regroup_active:
		var progress := player.get_regroup_progress()
		button.text = "Regrouping %d/%d" % progress
		button.disabled = true
		button.tooltip_text = "Regroup under way: %d of %d military units are home and healed." % progress
	else:
		var refusal := player.start_regroup_refusal()
		if refusal != "":
			button.disabled = true
			button.tooltip_text += "
Can't right now: %s." % refusal
	return button


## The big red RTB (return to base) button: every unit drops its mission
## and comes home (Player.recall_all()).
func _make_rtb_button() -> Button:
	var button := UiStyle.make_button("RTB", func() -> void: hud.recall_all_requested.emit())
	button.custom_minimum_size = Vector2(100, 36)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["normal", "hover", "pressed"]:
		var style := (button.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
		style.bg_color = {"normal": Color(0.72, 0.1, 0.08), "hover": Color(0.88, 0.16, 0.12), "pressed": Color(0.5, 0.06, 0.05)}[state]
		style.border_color = Color(1.0, 0.55, 0.45)
		button.add_theme_stylebox_override(state, style)
	button.tooltip_text = "Return to base: every unit drops what it's doing and comes home.
Units waiting to set out (and the QRF) are stood down at once and get back what they were given; units out on the map turn for home with anything they carry.
Repeating orders and the Builders' shared job stop too. Units off duty stay where they are."
	return button


## A room's box: its name and its unit cards. Takes drops of unit cards.
func _make_room(room: Room) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(ROOM_WIDTH, 110)
	box.add_theme_stylebox_override("panel", _room_style(room))
	box.tooltip_text = room.description
	box.set_drag_forwarding(Callable(), _can_drop.bind(room, null), _drop.bind(room, null))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Drops land on the box.
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)

	# Units waiting to heal first, in healing order; then everyone else.
	var units := room.get_healing_queue(player)
	for unit in player.get_units_in_room(room.id):
		if not unit in units:
			units.append(unit)
	var training: Array[int] = []
	for i in player.training_queue.size():
		if room.holds_training(player.training_queue[i].blueprint):
			training.append(i)
	var heading := UiStyle.heading(room.display_name + ("  (%d)" % units.size() if not units.is_empty() else ""))
	column.add_child(heading)
	var healing_now: Array[Unit] = []
	if not room.heals.is_empty():
		var slots := room.get_heal_slots(player)
		column.add_child(_small_text("Heals %d at a time, +%d HP a turn" % [slots, room.get_heal_rate(player)]))
		var queue := room.get_healing_queue(player)
		for i in mini(slots, queue.size()):
			healing_now.append(queue[i])
		column.add_child(_make_healing_box(slots, healing_now, room))
	for unit in units:
		if not unit in healing_now:
			column.add_child(_make_unit_card(unit, room))
	for i in training:
		column.add_child(_make_training_card(i, room))
	if units.is_empty() and training.is_empty():
		column.add_child(UiStyle.note("Empty"))
	return box


## The green box at the top of a healing room: one place per unit it can
## heal at a time (Room.get_heal_slots()), holding the units being healed
## now - empty places show as empty space. Everyone below it is waiting.
func _make_healing_box(slots: int, healing: Array[Unit], room: Room) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Drops land on the room.
	var style := UiStyle.box_style(Color(0.2, 0.75, 0.3, 0.12), Color(0.35, 1.0, 0.45, 0.9), 2, 6)
	style.set_content_margin_all(4)
	box.add_theme_stylebox_override("panel", style)
	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", CARD_GAP)
	box.add_child(inner)
	for unit in healing:
		inner.add_child(_make_unit_card(unit, room))
	# Room for `slots` cards, full or not (sized to a real card once one is laid out).
	inner.custom_minimum_size.y = slots * _card_height + (slots - 1) * CARD_GAP
	if not healing.is_empty():
		var first: Control = inner.get_child(0)
		first.resized.connect(func() -> void:
			var h := first.get_combined_minimum_size().y  # Not size: that can be stretched.
			if h > 0:
				_card_height = h
				inner.custom_minimum_size.y = slots * _card_height + (slots - 1) * CARD_GAP
				hud.refit_section())
	return box


## A room the hub hasn't built yet: dimmed, with a padlock and what to build.
func _make_locked_room(room: Room) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(ROOM_WIDTH, 110)
	box.add_theme_stylebox_override("panel", UiStyle.box_style(LOCKED_COLOR, ROOM_BORDER, 1, 6))
	var lock_text := player.get_room_lock_text(room)
	box.tooltip_text = "Locked: %s (Buildings panel, B).\n\n%s" % [lock_text, room.description]
	box.set_drag_forwarding(Callable(), _can_drop.bind(room, null), _drop.bind(room, null))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lock := TextureRect.new()
	lock.texture = UiStyle.svg_texture(PADLOCK_SVG)
	lock.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(lock)
	var heading := UiStyle.heading(room.display_name)
	heading.modulate = Color(1, 1, 1, 0.5)
	top.add_child(heading)
	column.add_child(top)
	var note := _small_text("Locked - %s." % lock_text)
	note.custom_minimum_size.x = ROOM_WIDTH - 20
	column.add_child(note)
	return box


func _room_style(room: Room) -> StyleBoxFlat:
	var border := BRIEFING_BORDER if room.id == MissionBriefingRoom.ID else ROOM_BORDER
	return UiStyle.box_style(ROOM_COLOR, border, 1, 6)


## A draggable card for a unit: name, HP and what it's doing.
func _make_unit_card(unit: Unit, room: Room) -> PanelContainer:
	var card := _card(unit.body_color)
	var tip := "%s (%s)\n%s\nDrag to another room to move it." % [
		unit.display_name, Unit.get_type_name(unit.unit_type), unit.get_status_text()]
	if unit in room.get_healing_queue(player):
		tip += "\nDrag onto another injured unit here to move it to that place in the healing queue."
	card.tooltip_text = tip
	card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	card.set_drag_forwarding(_drag_unit.bind(unit, card), _can_drop.bind(room, unit), _drop.bind(room, unit))
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
	card.set_drag_forwarding(Callable(), _can_drop.bind(room, null), _drop.bind(room, null))
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
	var lines: VBoxContainer = preview.get_child(0)
	var label := Label.new()
	label.text = unit.display_name
	lines.add_child(label)
	_drag_hint = Label.new()
	_drag_hint.add_theme_font_size_override("font_size", 13)
	_drag_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drag_hint.custom_minimum_size.x = 260
	_drag_hint.text = "Drop on a room"
	_drag_hint.modulate = Color(1, 1, 1, 0.7)
	lines.add_child(_drag_hint)
	preview.modulate = Color(1, 1, 1, 0.92)
	card.set_drag_preview(preview)
	_show_drop_targets(unit)
	return {"hub_unit": unit.id}


## Lights up every room `unit` could be dropped in (green) and crosses out
## the rest. (The HUD rebuilds the panel when the drag ends, clearing it.)
func _show_drop_targets(unit: Unit) -> void:
	for room_id in _room_boxes:
		var box: PanelContainer = _room_boxes[room_id]
		if room_id == unit.room_id:
			continue
		if player.get_room_move_refusal(unit, room_id) == "":
			var style: StyleBoxFlat = (box.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
			style.border_color = CAN_DROP_COLOR
			style.set_border_width_all(3)
			style.bg_color = style.bg_color.lerp(CAN_DROP_COLOR, 0.12)
			box.add_theme_stylebox_override("panel", style)
		else:
			var cross := TextureRect.new()
			cross.texture = UiStyle.svg_texture(CROSS_SVG)
			cross.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(cross)


func _dragged_unit(data: Variant) -> Unit:
	if data is Dictionary and data.has("hub_unit") and player:
		return player.get_unit(int(data["hub_unit"]))
	return null


## `onto` is the unit whose card it's over, if any (for reordering healing).
func _can_drop(_at: Vector2, data: Variant, room: Room, onto: Unit) -> bool:
	var unit := _dragged_unit(data)
	if unit == null:
		return false
	var queue_index := _healing_swap_index(unit, room, onto)
	if queue_index >= 0:
		_set_drag_hint("Move to %s in the healing queue (%s's place)" % [
			_ordinal(queue_index + 1), onto.display_name], true)
		return true
	if unit.room_id == room.id:
		_set_drag_hint("Already in the %s" % room.display_name, false)
		return false
	var reason := player.get_room_move_refusal(unit, room.id)
	if reason != "":
		_set_drag_hint("Can't go to the %s: %s" % [room.display_name, reason], false)
		return false
	var note := " (calls off its mission)" if unit.mission else ""
	if room is QrfRoom:
		_set_drag_hint("Put on QRF duty for %d turns%s" % [QrfMission.DRAG_TURNS, note], true)
		return true
	_set_drag_hint("Move to the %s%s" % [room.display_name, note], true)
	return true


func _drop(_at: Vector2, data: Variant, room: Room, onto: Unit) -> void:
	var unit := _dragged_unit(data)
	if unit == null:
		return
	var queue_index := _healing_swap_index(unit, room, onto)
	if queue_index >= 0:
		hud.heal_order_requested.emit(unit, queue_index)
	else:
		hud.room_move_requested.emit(unit, room.id, 0)


## Where `unit` goes in the healing queue if dropped on `onto`'s card - both
## waiting to heal in this room - or -1 if that isn't a reorder.
func _healing_swap_index(unit: Unit, room: Room, onto: Unit) -> int:
	if onto == null or onto == unit or unit.room_id != room.id:
		return -1
	var queue := room.get_healing_queue(player)
	if not unit in queue:
		return -1
	return queue.find(onto)


func _set_drag_hint(text: String, ok: bool) -> void:
	if not is_instance_valid(_drag_hint):
		return
	_drag_hint.text = text
	_drag_hint.modulate = Color.WHITE
	_drag_hint.add_theme_color_override("font_color", CAN_DROP_COLOR if ok else CANT_DROP_COLOR)


static func _ordinal(n: int) -> String:
	return Room._ordinal(n)
