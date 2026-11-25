extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Every air unit does +1 damage to everything.


func _init() -> void:
	super("air_weapons", "Air Weapons", "hangar")
	type_damage_attacker = Unit.UnitType.AIR
	for target in Unit.UnitType.values():
		type_damage_bonus[target] = 1
