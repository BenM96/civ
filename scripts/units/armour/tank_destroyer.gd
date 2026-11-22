class_name TankDestroyer
extends ArmourUnit
## Armour built to kill armour. Fires twice a round (see ArmourUnit).


func _init() -> void:
	super()
	unit_name = "Tank Destroyer"
	short_name = "TD"
	cost.merge(SPECIALIST_COST)
	train_turns = 5
	#                    infantry, civilian, armour, air
	damage = damage_vs(2, 4, 8, 1)
	body_color = Color(0.5, 0.55, 0.4)
