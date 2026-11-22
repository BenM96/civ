class_name Chopper
extends AirUnit
## Attack helicopter: the default air unit. Flies sorties, then refits (see
## AirUnit).


func _init() -> void:
	super()
	unit_name = "Chopper"
	short_name = "CH"
	train_turns = 4
	#                    infantry, civilian, armour, air
	damage = damage_vs(4, 4, 4, 4)
	body_color = Color(0.55, 0.8, 0.95)
