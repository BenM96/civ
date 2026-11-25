extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Med Bay: a hub room where injured infantry and civilians heal.


func _init() -> void:
	super("med_bay", "Med Bay")
	unlocks_building = MedBayBuilding.ID
