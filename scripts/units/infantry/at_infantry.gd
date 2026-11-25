class_name AtInfantry
extends Infantry
## Anti-tank infantry: strong against armour. Otherwise the same as Infantry.


func _init() -> void:
	super()
	unit_name = "AT Infantry"
	short_name = "AT"
	add_specialist_cost()
	train_turns = 3
	#                    civilian, infantry, armour, air
	damage = damage_vs(6, 3, 6, 2)
	body_color = Color(0.8, 0.55, 0.3)
