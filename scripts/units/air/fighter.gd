class_name Fighter
extends AirUnit
## Fighter: built to shoot down aircraft; strafes soft targets but barely
## scratches armour. Flies sorties and intercepts, then refits (see AirUnit).


func _init() -> void:
	super()
	unit_name = "Fighter"
	short_name = "F"
	silhouette = "spitfire"
	add_specialist_cost()
	train_turns = 5
	#                    infantry, civilian, armour, air
	damage = damage_vs(6, 6, 2, 10)
	body_color = Color(0.7, 0.85, 1.0)
