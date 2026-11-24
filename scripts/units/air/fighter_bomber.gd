class_name FighterBomber
extends AirUnit
## Fighter bomber: like the Chopper, but its bombs smash armour. Flies
## sorties and intercepts, then refits (see AirUnit).


func _init() -> void:
	super()
	unit_name = "Fighter Bomber"
	short_name = "FB"
	silhouette = "eurofighter"
	add_specialist_cost()
	train_turns = 5
	#                    infantry, civilian, armour, air
	damage = damage_vs(6, 6, 10, 6)
	body_color = Color(0.6, 0.75, 0.8)
