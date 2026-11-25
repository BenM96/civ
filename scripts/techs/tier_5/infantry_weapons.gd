extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Every infantry unit does +1 damage to everything.


func _init() -> void:
	super("infantry_weapons", "Infantry Weapons", "barracks")
	type_damage_attacker = Unit.UnitType.INFANTRY
	for target in Unit.UnitType.values():
		type_damage_bonus[target] = 1
