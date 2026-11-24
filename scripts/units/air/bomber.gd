class_name Bomber
extends AirUnit
## Heavy bomber: its only mission is Carpet Bomb (see CarpetBombMission),
## flattening everything man-made on a tile or knocking 1 off an enemy hub's
## health. Its guns can't hurt ground units and barely trouble aircraft.
## Refits after every flight (see AirUnit).


func _init() -> void:
	super()
	unit_name = "Bomber"
	short_name = "B"
	silhouette = "lancaster"
	add_specialist_cost()
	train_turns = 5
	allowed_missions = ["carpet_bomb"]
	#                    infantry, civilian, armour, air
	damage = damage_vs(0, 0, 0, 2)
	body_color = Color(0.5, 0.65, 0.85)
