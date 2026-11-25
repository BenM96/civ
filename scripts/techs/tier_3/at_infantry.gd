extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks AT Infantry (anti-armour). Specialist rule: the tier after the unit type it counters arrives (armour: Garage, T2).


func _init() -> void:
	super("at_infantry", "AT Infantry", "barracks")
	unlocks_unit = "AT Infantry"
