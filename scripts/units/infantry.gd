class_name Infantry
extends Unit
## Military unit. Can guard a tile, escort another unit from its hub,
## capture other colonies' extractors and conveyors, and demolish man-made
## structures (foundations, bridges, extractors, conveyors), leaving rubble
## behind. Can't harvest or build. The colony's fighter: 7 damage a shot
## against infantry armour, which Workers wear too (see Combat).


func _init() -> void:
	unit_name = "Infantry"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 1}
	cost_growth = CostGrowth.ADD_ONE  # 1 Gold + 1 Titanium, then 2 + 2, 3 + 3...
	cost_rises_after = 0
	train_turns = 3
	upkeep = 1
	max_movement = 3
	armor_type = ArmorType.INFANTRY
	damage = {ArmorType.INFANTRY: 7}
	body_color = Color(0.9, 0.35, 0.3)
	allowed_missions = ["move", "guard", "escort", "capture", "demolish"]
