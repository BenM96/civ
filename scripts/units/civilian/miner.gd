class_name Miner
extends Unit
## Harvests resource deposits by hand, bringing one load home a trip (see
## HarvestMission). A colony may only ever have one (Player.MINER_LIMIT) and
## starts with it. A new one costs no resources - only its biomass upkeep -
## so a colony can never be left with no way to gather anything. Fights back
## weakly if caught: 1 damage a shot against civilians and infantry
## (see Combat). Waits in the Break Room, and starves last (see
## Player.starve()).

const NAME := "Miner"


func _init() -> void:
	unit_name = NAME
	short_name = "M"
	cost = {}
	train_turns = 2
	upkeep = 1
	max_movement = 3
	unit_type = UnitType.CIVILIAN
	#                    civilian, infantry, armour, air
	damage = damage_vs(1, 1, 0, 0)
	body_color = Color(0.85, 0.93, 1.0)
	allowed_missions = ["harvest"]
