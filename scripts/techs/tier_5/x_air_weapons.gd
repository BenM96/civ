extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Every air unit does +1 damage to everything.


func _init() -> void:
	super("air_weapons", "Air Weapons", "hangar")
	type_damage_attacker = Unit.UnitType.AIR
	for target in Unit.UnitType.values():
		type_damage_bonus[target] = 1
