class_name HangarBuilding
extends Building
## Opens the hub's Hangar (see HangarRoom): needed to train air units, which
## refit there after every flight.

const ID := "hangar"


func _init() -> void:
	id = ID
	display_name = "Hangar"
	description = "Opens the Hangar room, where aircraft wait, refit (and are repaired) after every flight, and stand by on Intercept duty.\nNeeded to train air units."
