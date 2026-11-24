class_name StingerInfantry
extends Infantry
## Infantry with shoulder-fired missiles: strong against air units.
## Otherwise the same as Infantry.


func _init() -> void:
	super()
	unit_name = "Stinger Infantry"
	short_name = "ST"
	add_specialist_cost()
	train_turns = 3
	#                    infantry, civilian, armour, air
	damage = damage_vs(4, 5, 6, 10)
	body_color = Color(0.85, 0.4, 0.55)
