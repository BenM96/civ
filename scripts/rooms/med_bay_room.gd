class_name MedBayRoom
extends Room
## Heals the units in it by HEAL_PER_TURN HP a turn. Units that come home
## hurt are brought here, and move on to Mission Briefing once fully healed.

const ID := "med_bay"
## HP each unit in the Med Bay gets back every turn.
const HEAL_PER_TURN := 1


func _init() -> void:
	id = ID
	display_name = "Med Bay"
	description = "Injured units heal %d HP a turn here, then move on to Mission Briefing.\nUnits that come home hurt are brought here." % HEAL_PER_TURN


func get_refusal(unit: Unit) -> String:
	if not unit.is_injured():
		return "%s isn't injured" % unit.display_name
	return ""


func has_work(player: Player) -> bool:
	return not player.get_units_in_room(id).is_empty()


func get_activity_text(unit: Unit) -> String:
	return "Healing - HP %d/%d (+%d a turn)" % [unit.health, unit.max_health, HEAL_PER_TURN]


func process_turn(player: Player) -> void:
	for unit in player.get_units_in_room(id):
		if unit.state != Unit.State.IN_HUB:
			continue
		unit.heal(HEAL_PER_TURN)
		if not unit.is_injured():
			unit.set_room(MissionBriefingRoom.ID)
			player.unit_event.emit("%s has healed and is back in Mission Briefing" % unit.display_name)
