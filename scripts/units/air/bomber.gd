class_name Bomber
extends AirUnit
## Bomber: strong against infantry and armour, weak against aircraft. Flies
## sorties, then refits (see AirUnit).


func _init() -> void:
	super()
	unit_name = "Bomber"
	short_name = "B"
	cost = {ResourceDeposit.Type.GOLD: 3, ResourceDeposit.Type.TITANIUM: 4}
	train_turns = 5
	#                    infantry, civilian, armour, air
	damage = damage_vs(7, 7, 7, 1)
	body_color = Color(0.5, 0.65, 0.85)
