class_name QuartersRoom
extends Room
## Where off-duty units of one type wait, and where units of that type are
## held while they train: the Break Room, Barracks, Hangar and Garage. Units
## waiting here don't need orders; drag them to Mission Briefing when you
## want them again, or send them with Wait and a number of turns, after
## which they come back by themselves (Unit.wait_turns_left). All but the
## Break Room need their building first, and units of that type can't be
## trained until it's built.
##
## Units that refit after every trip out (Unit.refit_turns - air units)
## come straight here when they get home and refit: one turn off
## Unit.refit_turns_left each turn. They can't leave until it's done; then
## they're repaired to full HP and move on to Mission Briefing (where a unit
## on a standing duty, e.g. Intercept, takes it up again - see
## Player.repeat_orders()).

## The only kind of unit allowed in.
var unit_type := Unit.UnitType.INFANTRY


func _init(p_id: String, p_name: String, p_unit_type: Unit.UnitType, p_required_building := "") -> void:
	id = p_id
	display_name = p_name
	unit_type = p_unit_type
	required_building = p_required_building
	var kind := Unit.get_type_name(unit_type).to_lower()
	description = "Off-duty %s units wait here (they don't need orders), and new %s units are held here while they train.\nOnly %s units are allowed in." % [kind, kind, kind]


func get_refusal(unit: Unit) -> String:
	if unit.unit_type != unit_type:
		return "only %s units are allowed in the %s" % [Unit.get_type_name(unit_type).to_lower(), display_name]
	return ""


func get_leave_refusal(unit: Unit) -> String:
	if unit.refit_turns_left > 0:
		return "%s is refitting (%d turn(s) left)" % [unit.display_name, unit.refit_turns_left]
	return ""


func has_work(player: Player) -> bool:
	for unit in player.get_units_in_room(id):
		if unit.refit_turns_left > 0 or unit.wait_turns_left > 0:
			return true
	return super(player)


func get_activity_text(unit: Unit) -> String:
	if unit.refit_turns_left > 0:
		return "Refitting - %d turn(s) left" % unit.refit_turns_left
	var healing := get_healing_text(unit)
	if healing != "":
		return healing
	if unit.wait_turns_left > 0:
		return "Off duty - back in Mission Briefing in %d turn(s)" % unit.wait_turns_left
	return "Off duty"


func holds_training(blueprint: UnitBlueprint) -> bool:
	return blueprint.unit_type == unit_type


## Heals (if this room heals - the Garage); refitting units get a turn
## closer, and finished ones are repaired and go to Mission Briefing.
func process_turn(player: Player) -> void:
	super(player)
	for unit in player.get_units_in_room(id):
		if unit.refit_turns_left <= 0 or unit.state != Unit.State.IN_HUB:
			continue
		unit.refit_turns_left -= 1
		if unit.refit_turns_left > 0:
			unit.state_changed.emit(unit)  # Show the new count.
			continue
		unit.heal(unit.max_health)
		unit.set_room(MissionBriefingRoom.ID)
		player.unit_event.emit("%s has finished refitting (fully repaired) and is in Mission Briefing" % unit.display_name)
	# Timed waits (the Wait button's number) count down; then back to work.
	for unit in player.get_units_in_room(id):
		if unit.wait_turns_left <= 0 or unit.state != Unit.State.IN_HUB or unit.refit_turns_left > 0:
			continue
		unit.wait_turns_left -= 1
		if unit.wait_turns_left > 0:
			unit.state_changed.emit(unit)  # Show the new count.
			continue
		unit.set_room(MissionBriefingRoom.ID)
		player.unit_event.emit("%s is back from off duty and ready for orders" % unit.display_name)
