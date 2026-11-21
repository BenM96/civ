class_name GuardUnit
extends Unit
## Civilian security guard. Can move, guard a tile and join the QRF, but is
## weaker than Infantry. Round icon; waits in the Break Room.


func _init() -> void:
	unit_name = "Guard"
	short_name = "G"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 1}
	cost_growth = CostGrowth.ADD_ONE
	cost_rises_after = 0
	train_turns = 2
	upkeep = 1
	max_movement = 3
	unit_type = UnitType.CIVILIAN
	#                    infantry, civilian, armour, air
	damage = damage_vs(3, 4, 0, 0)
	body_color = Color(0.95, 0.85, 0.45)
	allowed_missions = ["move", "guard", "qrf"]
