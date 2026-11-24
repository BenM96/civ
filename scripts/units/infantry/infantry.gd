class_name Infantry
extends Unit
## Military unit. Can guard a tile, escort another unit from its hub,
## capture other colonies' extractors and conveyors, demolish man-made
## structures (foundations, bridges, extractors, conveyors), leaving rubble
## behind, and stand by as a quick reaction force (QRF). Can't harvest or
## build. The colony's basic fighter (see Combat). Pentagon icon; waits in
## the Barracks. Assault, AT and Stinger Infantry are variants of it.


func _init() -> void:
	unit_name = "Infantry"
	short_name = "I"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 2}
	train_turns = 3
	upkeep = 1
	max_movement = 3
	unit_type = UnitType.INFANTRY
	#                    infantry, civilian, armour, air
	damage = damage_vs(4, 6, 2, 2)
	body_color = Color(0.9, 0.35, 0.3)
	allowed_missions = ["move", "guard", "escort", "capture", "demolish", "qrf"]
