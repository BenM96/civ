extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Unlocks the Regen Lab (Med Bay upgrade): units in the Med Bay heal 1 HP a turn faster.


func _init() -> void:
	super("regeneration", "Regeneration", "med_bay")
	unlocks_building = RegenLab.ID
