extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Hangar: needed to train air units, which refit there after every flight. Barracks is T1, Garage T2, Hangar T3.


func _init() -> void:
	super("hangar", "Hangar")
	unlocks_building = HangarBuilding.ID
