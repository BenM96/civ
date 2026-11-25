extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Unlocks the Surgical Ward (Med Bay upgrade): one more unit heals in the Med Bay at a time.


func _init() -> void:
	super("surgery", "Surgery", "med_bay")
	unlocks_building = SurgicalWard.ID
