class_name StingerInfantry
extends Infantry
## Infantry with shoulder-fired missiles: strong against air units.
## Otherwise the same as Infantry.


func _init() -> void:
	super()
	unit_name = "Stinger Infantry"
	short_name = "ST"
	cost.merge(SPECIALIST_COST)
	train_turns = 3
	#                    infantry, civilian, armour, air
	damage = damage_vs(4, 5, 6, 4)
	body_color = Color(0.85, 0.4, 0.55)
