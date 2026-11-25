extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Tank: another armour unit, in T3 alongside the anti-armour units.


func _init() -> void:
	super("tank", "Tank", "garage")
	unlocks_unit = "Tank"
