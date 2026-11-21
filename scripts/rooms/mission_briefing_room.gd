class_name MissionBriefingRoom
extends Room
## Where idle units go to get their orders. Only units in here can be given
## a mission (see Unit.needs_orders()). Units coming home go here unless
## they're hurt (see MedBayRoom), and so do newly trained units.

const ID := "mission_briefing"


func _init() -> void:
	id = ID
	display_name = "Mission Briefing"
	description = "Idle units wait here for orders. Only units in Mission Briefing can be given a mission.\nDrag a unit here to make it ready for orders (this calls off any mission it hasn't left on yet)."


func get_activity_text(_unit: Unit) -> String:
	return "Ready for orders"
