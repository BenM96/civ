class_name Infantry
extends Unit
## Military unit. Can guard a tile, capture other colonies' extractors and
## conveyors, and demolish man-made structures (roads, bridges, extractors,
## conveyors), leaving rubble behind. Can't harvest or build.
## Fights: trades one-for-one with enemy infantry and kills enemy workers
## on its tile (see Combat).


func _init() -> void:
	unit_name = "Infantry"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 1}
	cost_doubling_after = 0
	train_turns = 3
	upkeep = 1
	max_movement = 3
	max_health = 15
	body_color = Color(0.9, 0.35, 0.3)
	allowed_missions = ["move", "guard", "capture", "demolish"]
	can_fight = true
