class_name TankDestroyer
extends ArmourUnit
## Armour built to kill armour. Fires twice a round (see ArmourUnit).


func _init() -> void:
	super()
	unit_name = "Tank Destroyer"
	short_name = "TD"
	add_specialist_cost()
	train_turns = 5
	#                    civilian, infantry, armour, air
	damage = damage_vs(6, 3, 6, 2)
	body_color = Color(0.5, 0.55, 0.4)
