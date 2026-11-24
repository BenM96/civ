class_name Room
extends RefCounted
## A room inside a colony's central hub (see Player.rooms). Every unit in the
## hub is in exactly one room (Unit.room_id). Each kind of room has its own
## file, holding what happens to the units in it.
##
## Units change rooms in two ways:
##   - The player drags them (a "move_room" order, see Orders and
##     Player.move_unit_to_room()). The room's get_refusal() says who may be
##     dragged in.
##   - Automatically (see Player): units that come home go to Mission
##     Briefing, or the room that heals them if they're hurt; units given a
##     mission go to the room the mission names
##     (Mission.get_departure_room_id() - the Airlock, or the QRF room);
##     called-off units go back to Mission Briefing; and rooms can send units
##     on themselves in process_turn() (healed units go to Mission Briefing).
##
## Some rooms need a building before they open (required_building, e.g. the
## Barracks building opens the Barracks); until then they're locked and take
## nobody. Rooms that heal (the Med Bay and the Garage - see `heals`) treat
## their injured units in a queue the player can reorder: only the first
## get_heal_slots() heal each turn, the rest wait.
##
## To add a room: make a script extending Room that sets its id, name and
## description in _init() and overrides what it needs, then add it to
## create_all() below.

## Saved in save files (Unit.room_id) - never change one once it's in use.
var id := ""
var display_name := "Room"
## What the room is for, for tooltips.
var description := ""
## The building (its id) the hub needs before this room opens, or "" if it's
## open from the start. See Player.is_room_open().
var required_building := ""

## Unit types this room heals; empty if it doesn't heal anyone.
var heals: Array[Unit.UnitType] = []
## HP a unit being healed gets back each turn, before upgrades.
var heal_rate := 1
## Upgrade buildings (ids): each one built lets one more unit heal at a time
## (heal_slots_building) or adds 1 HP a turn (heal_rate_building).
var heal_slots_building := ""
var heal_rate_building := ""
## Unit ids in the order they'll be healed. Kept in step with who's actually
## here by get_healing_queue(); reordered by the player (see
## Player.move_in_healing_queue()). Saved.
var healing_order: Array[int] = []


## One of every room, in the order the Central Hub panel shows them.
static func create_all() -> Array[Room]:
	return [
		MissionBriefingRoom.new(),
		AirlockRoom.new(),
		MedBayRoom.new(),
		QrfRoom.new(),
		BreakRoom.new(),
		BarracksRoom.new(),
		HangarRoom.new(),
		GarageRoom.new(),
	]


# --- Virtuals --------------------------------------------------------------

## Why the player can't drag `unit` into this room, or "" if they can.
## (Player.get_room_move_refusal() checks the general rules first, including
## whether the room is open.)
func get_refusal(_unit: Unit) -> String:
	return ""


## Why the player can't drag `unit` out of this room yet, or "" if they can.
func get_leave_refusal(_unit: Unit) -> String:
	return ""


## Whether letting a turn pass changes something here (e.g. units healing),
## so idle turns are worth skipping (see TurnManager).
func has_work(player: Player) -> bool:
	return not get_healing_queue(player).is_empty()


## What `unit` is doing in this room, for unit cards and status text. Only
## asked about units at home - units with a mission describe themselves.
func get_activity_text(unit: Unit) -> String:
	var healing := get_healing_text(unit)
	return healing if healing != "" else "In the %s" % display_name


## Whether units of `blueprint`'s type are held here while they train.
func holds_training(_blueprint: UnitBlueprint) -> bool:
	return false


## "Hub" step of each turn (see Player.run_hub()): whatever the room
## does to the units in it. Rooms that heal, heal; override for more.
func process_turn(player: Player) -> void:
	_heal_units(player)


# --- Healing -----------------------------------------------------------------

## Whether this room heals units like `unit` (when they're hurt).
func heals_unit(unit: Unit) -> bool:
	return unit.unit_type in heals


## How many units heal at once.
func get_heal_slots(player: Player) -> int:
	return 1 + (player.count_buildings(heal_slots_building) if heal_slots_building != "" else 0)


## HP each unit being healed gets back a turn.
func get_heal_rate(player: Player) -> int:
	return heal_rate + (player.count_buildings(heal_rate_building) if heal_rate_building != "" else 0)


## The injured units here waiting to heal, in healing order: the first
## get_heal_slots() of them are being healed, the rest wait their turn.
## Units that have arrived since last time join the end of the queue.
func get_healing_queue(player: Player) -> Array[Unit]:
	if heals.is_empty():
		return []
	var waiting: Array[Unit] = []
	for unit in player.get_units_in_room(id):
		if unit.state == Unit.State.IN_HUB and heals_unit(unit) and unit.is_injured() and unit.refit_turns_left <= 0:
			waiting.append(unit)
	var order: Array[int] = []
	for unit_id in healing_order:
		if waiting.any(func(u: Unit) -> bool: return u.id == unit_id):
			order.append(unit_id)
	for unit in waiting:
		if not unit.id in order:
			order.append(unit.id)
	healing_order = order
	var queue: Array[Unit] = []
	for unit_id in order:
		queue.append(player.get_unit(unit_id))
	return queue


## Moves `unit` to `index` in the healing queue (0 = healed first). Returns
## "" if it moved, otherwise why not.
func move_in_healing_queue(player: Player, unit: Unit, index: int) -> String:
	if not unit in get_healing_queue(player):
		return "%s isn't waiting to heal in the %s" % [unit.display_name, display_name]
	healing_order.erase(unit.id)
	healing_order.insert(clampi(index, 0, healing_order.size()), unit.id)
	return ""


## What a unit in the healing queue is doing, e.g. "Healing - HP 4/10 (+1 a
## turn)" or "Waiting to heal (2nd in line)"; "" if it isn't in the queue.
func get_healing_text(unit: Unit) -> String:
	var player := unit.player
	if player == null:
		return ""
	var position := get_healing_queue(player).find(unit)
	if position < 0:
		return ""
	var slots := get_heal_slots(player)
	if position < slots:
		return "Healing - HP %d/%d (+%d a turn)" % [unit.health, unit.max_health, get_heal_rate(player)]
	return "Waiting to heal - %s in line" % _ordinal(position - slots + 1)


## The first get_heal_slots() units in the queue heal; fully healed ones go
## to Mission Briefing.
func _heal_units(player: Player) -> void:
	var queue := get_healing_queue(player)
	var rate := get_heal_rate(player)
	for i in mini(get_heal_slots(player), queue.size()):
		var unit := queue[i]
		unit.heal(rate)
		if not unit.is_injured():
			unit.set_room(MissionBriefingRoom.ID)
			player.unit_event.emit("%s has healed and is back in Mission Briefing" % unit.display_name)


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
