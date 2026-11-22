class_name RepairBay
extends Building
## Garage upgrade: one more vehicle is repaired there at a time (see Room.get_heal_slots()).

const ID := "repair_bay"


func _init() -> void:
	id = ID
	display_name = "Repair Bay"
	description = "Garage upgrade: one more vehicle is repaired at a time."
	requires = GarageBuilding.ID
	max_count = 2
