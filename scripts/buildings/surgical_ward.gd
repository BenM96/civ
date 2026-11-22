class_name SurgicalWard
extends Building
## Med Bay upgrade: one more unit heals there at a time (see Room.get_heal_slots()).

const ID := "surgical_ward"


func _init() -> void:
	id = ID
	display_name = "Surgical Ward"
	description = "Med Bay upgrade: one more unit heals at a time."
	requires = MedBayBuilding.ID
	max_count = 2
