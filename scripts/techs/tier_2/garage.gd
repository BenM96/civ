extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Garage: needed to train armour, and where damaged armour is repaired. Barracks is T1, Garage T2, Hangar T3.


func _init() -> void:
	super("garage", "Garage")
	unlocks_building = GarageBuilding.ID
