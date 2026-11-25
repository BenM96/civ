extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Tank Destroyer (anti-armour). Specialist rule: the tier after the unit type it counters arrives (armour: Garage, T2).


func _init() -> void:
	super("tank_destroyer", "Tank Destroyer", "garage")
	unlocks_unit = "Tank Destroyer"
