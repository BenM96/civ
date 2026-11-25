extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Civilians do +2 damage to civilians and +1 to infantry.


func _init() -> void:
	super("civil_defence", "Civil Defence")
	type_damage_attacker = Unit.UnitType.CIVILIAN
	type_damage_bonus = {Unit.UnitType.CIVILIAN: 2, Unit.UnitType.INFANTRY: 1}
