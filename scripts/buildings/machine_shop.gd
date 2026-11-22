class_name MachineShop
extends Building
## Garage upgrade: vehicles there are repaired 1 HP a turn faster (see Room.get_heal_rate()).

const ID := "machine_shop"


func _init() -> void:
	id = ID
	display_name = "Machine Shop"
	description = "Garage upgrade: each vehicle being repaired gets back 1 more HP a turn."
	requires = GarageBuilding.ID
	max_count = 2
