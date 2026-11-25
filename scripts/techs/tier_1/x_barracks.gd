extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Barracks: needed to train infantry. Barracks is T1, Garage T2, Hangar T3.


func _init() -> void:
	super("barracks", "Barracks")
	unlocks_building = BarracksBuilding.ID
