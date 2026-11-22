class_name MedBayBuilding
extends Building
## Opens the hub's Med Bay (see MedBayRoom), where injured infantry and
## civilians heal.

const ID := "med_bay"


func _init() -> void:
	id = ID
	display_name = "Med Bay"
	description = "Opens the Med Bay room, where injured infantry and civilians heal (one unit at a time, 1 HP a turn).\nWithout one, injured infantry and civilians stay hurt."
