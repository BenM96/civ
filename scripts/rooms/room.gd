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
##     Briefing, or the Med Bay if they're hurt; units given a mission go to
##     the room the mission names (Mission.get_departure_room_id() - the
##     Airlock, or the QRF room); called-off units go back to Mission
##     Briefing; and rooms can send units on themselves in process_turn()
##     (the Med Bay sends healed units to Mission Briefing).
##
## To add a room: make a script extending Room that sets its id, name and
## description in _init() and overrides what it needs, then add it to
## create_all() below.

## Saved in save files (Unit.room_id) - never change one once it's in use.
var id := ""
var display_name := "Room"
## What the room is for, for tooltips.
var description := ""


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
## (Player.get_room_move_refusal() checks the general rules first.)
func get_refusal(_unit: Unit) -> String:
	return ""


## Why the player can't drag `unit` out of this room yet, or "" if they can.
func get_leave_refusal(_unit: Unit) -> String:
	return ""


## Whether letting a turn pass changes something here (e.g. units healing),
## so idle turns are worth skipping (see TurnManager).
func has_work(_player: Player) -> bool:
	return false


## What `unit` is doing in this room, for unit cards and status text. Only
## asked about units at home - units with a mission describe themselves.
func get_activity_text(_unit: Unit) -> String:
	return "In the %s" % display_name


## Whether units of `blueprint`'s type are held here while they train.
func holds_training(_blueprint: UnitBlueprint) -> bool:
	return false


## "Production" step of each turn (see Player.produce()): whatever the room
## does to the units in it.
func process_turn(_player: Player) -> void:
	pass
