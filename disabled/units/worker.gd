class_name Worker
extends Unit
## Base for the colony's civilian workers: the Miner (harvests deposits) and
## the Builder (builds structures). Not trained itself. Fights back weakly
## if caught: 2 damage a shot against civilians, 1 against infantry (see
## Combat). Waits in the Break Room, and starves last (see Player.starve()).


func _init() -> void:
	train_turns = 2
	upkeep = 1
	max_movement = 3
	unit_type = UnitType.CIVILIAN
	#                    infantry, civilian, armour, air
	damage = damage_vs(1, 2, 0, 0)
	body_color = Color(0.85, 0.93, 1.0)
