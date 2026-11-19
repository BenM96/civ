class_name Worker
extends Unit
## Civilian unit. Harvests resource deposits and builds structures (roads,
## bridges, extractors, conveyor belts).


func _init() -> void:
	unit_name = "Worker"
	cost = {ResourceDeposit.Type.BIOMASS: 3}
	train_turns = 2
	upkeep = 1
	max_movement = 3
	max_health = 8
	body_color = Color(0.85, 0.93, 1.0)
	allowed_missions = ["move", "harvest", "build"]
