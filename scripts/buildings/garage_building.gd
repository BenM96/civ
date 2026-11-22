class_name GarageBuilding
extends Building
## Opens the hub's Garage (see GarageRoom): needed to train armour, and
## where damaged armour is repaired.

const ID := "garage"


func _init() -> void:
	id = ID
	display_name = "Garage"
	description = "Opens the Garage room, where off-duty armour waits and damaged armour is repaired (one vehicle at a time, 1 HP a turn).\nNeeded to train armour."
