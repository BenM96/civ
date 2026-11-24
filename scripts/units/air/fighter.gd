class_name Fighter
extends AirUnit
## Fighter jet: strong against other aircraft. Flies sorties, then refits
## (see AirUnit).


func _init() -> void:
	super()
	unit_name = "Fighter"
	short_name = "F"
	add_specialist_cost()
	train_turns = 5
	#                    infantry, civilian, armour, air
	damage = damage_vs(2, 3, 2, 8)
	body_color = Color(0.7, 0.85, 1.0)
