class_name Tank
extends ArmourUnit
## Main battle tank: strong against infantry. Fires twice a round (see
## ArmourUnit).


func _init() -> void:
	super()
	unit_name = "Tank"
	short_name = "T"
	add_specialist_cost()
	train_turns = 5
	#                    civilian, infantry, armour, air
	damage = damage_vs(10, 6, 3, 2)
	body_color = Color(0.6, 0.65, 0.45)
