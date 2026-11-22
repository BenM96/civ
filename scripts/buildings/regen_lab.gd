class_name RegenLab
extends Building
## Med Bay upgrade: units there heal 1 HP a turn faster (see Room.get_heal_rate()).

const ID := "regen_lab"


func _init() -> void:
	id = ID
	display_name = "Regen Lab"
	description = "Med Bay upgrade: each unit being healed gets back 1 more HP a turn."
	requires = MedBayBuilding.ID
	max_count = 2
