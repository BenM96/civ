class_name ArmourUnit
extends Unit
## Base for armour units (APC, Tank, ...). Armour fires twice each time its
## turn comes round in a battle (see Combat), but can't capture or demolish
## structures. Square icon; waits in the Garage. Each armour unit sets its
## name, numbers and damage in its own file.


func _init() -> void:
	unit_type = UnitType.ARMOUR
	shots_per_turn = 2
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 3, ResourceDeposit.Type.SEDIMENT: 2}
	upkeep = 1
	max_movement = 3
	allowed_missions = ["move", "escort", "qrf"]
