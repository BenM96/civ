class_name Builder
extends Unit
## Builds structures (foundations, bridges, extractors, conveyor belts,
## command points, FOBs), paying for them from the hub's stockpile. Colonies
## start without one; how many it may have is Player.get_builder_limit(),
## raised by the Workforce techs. Fights back weakly if caught: 1 damage a
## shot against civilians and infantry (see Combat). Waits in the
## Break Room, and starves last (see Player.starve()).

const NAME := "Builder"


func _init() -> void:
	unit_name = NAME
	short_name = "B"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 1}
	train_turns = 2
	upkeep = 1
	max_movement = 3
	unit_type = UnitType.CIVILIAN
	#                    civilian, infantry, armour, air
	damage = damage_vs(1, 1, 0, 0)
	body_color = Color(0.85, 0.93, 1.0)
	allowed_missions = ["build"]
