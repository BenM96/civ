extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks Stinger Infantry (anti-air). Specialist rule: the tier after the unit type it counters arrives (air: Hangar, T3).


func _init() -> void:
	super("stinger_infantry", "Stinger Infantry", "barracks")
	unlocks_unit = "Stinger Infantry"
