class_name Miner
extends Worker
## Harvests resource deposits by hand, bringing one load home a trip (see
## HarvestMission). A colony may only ever have one (Player.MINER_LIMIT) and
## starts with it. A new one costs no resources - only its biomass upkeep -
## so a colony can never be left with no way to gather anything.

const NAME := "Miner"


func _init() -> void:
	super()
	unit_name = NAME
	short_name = "M"
	cost = {}
	allowed_missions = ["harvest"]
