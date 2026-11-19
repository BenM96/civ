class_name Worker
extends Unit
## Civilian unit. Harvests resource deposits and builds structures (foundations,
## bridges, extractors, conveyor belts).


func _init() -> void:
	unit_name = "Worker"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 1}
	cost_doubling_after = 1  # Every colony starts with one.
	train_turns = 2
	upkeep = 1
	max_movement = 3
	max_health = 8
	body_color = Color(0.85, 0.93, 1.0)
	allowed_missions = ["harvest", "build"]
