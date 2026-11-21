class_name Worker
extends Unit
## Civilian unit. Harvests resource deposits and builds structures (foundations,
## bridges, extractors, conveyor belts). Fights back weakly if caught: 3
## damage a shot against infantry armour (see Combat).


func _init() -> void:
	unit_name = "Worker"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 1}
	cost_growth = CostGrowth.DOUBLE
	cost_rises_after = 1  # Every colony starts with one.
	train_turns = 2
	upkeep = 1
	max_movement = 3
	armor_type = ArmorType.INFANTRY
	damage = {ArmorType.INFANTRY: 3}
	body_color = Color(0.85, 0.93, 1.0)
	allowed_missions = ["harvest", "build"]
