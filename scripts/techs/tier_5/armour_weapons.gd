extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Every armour unit does +1 damage to everything.


func _init() -> void:
	super("armour_weapons", "Armour Weapons", "garage")
	type_damage_attacker = Unit.UnitType.ARMOUR
	for target in Unit.UnitType.values():
		type_damage_bonus[target] = 1
