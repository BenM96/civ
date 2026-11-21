class_name AirlockRoom
extends Room
## Units with a mission wait here until they leave the hub at the end of the
## turn (and come back here if their mission brings them back to the hub
## partway through, e.g. a builder waiting for resources). Units only come
## in by being given a mission; dragging one out calls the mission off.

const ID := "airlock"


func _init() -> void:
	id = ID
	display_name = "Airlock"
	description = "Units with a mission wait here to leave the hub at the end of the turn.\nGive a unit a mission in Mission Briefing to send it here; drag it out to call the mission off."


func get_refusal(_unit: Unit) -> String:
	return "units only go to the Airlock when given a mission"
