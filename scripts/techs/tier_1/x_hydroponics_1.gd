extends Tech
## LOCKED: do not move to another tier or change without asking first.
## +1 Greenhouse limit. Greenhouses grow food for the colony's units.


func _init() -> void:
	super("hydroponics_1", "Hydroponics I")
	building_limit_bonus = {Greenhouse.ID: 1}
