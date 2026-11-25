extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Every infantry unit does +1 damage to everything.


func _init() -> void:
	super("infantry_weapons", "Infantry Weapons", "barracks")
	type_damage_attacker = Unit.UnitType.INFANTRY
	for target in Unit.UnitType.values():
		type_damage_bonus[target] = 1
