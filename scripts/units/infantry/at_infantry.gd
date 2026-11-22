class_name AtInfantry
extends Infantry
## Anti-tank infantry: strong against armour. Otherwise the same as Infantry.


func _init() -> void:
	super()
	unit_name = "AT Infantry"
	short_name = "AT"
	cost.merge(SPECIALIST_COST)
	train_turns = 3
	#                    infantry, civilian, armour, air
	damage = damage_vs(5, 7, 10, 3)
	body_color = Color(0.8, 0.55, 0.3)
