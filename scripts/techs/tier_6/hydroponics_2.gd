extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## +1 Greenhouse limit. Greenhouses grow food for the colony's units.


func _init() -> void:
	super("hydroponics_2", "Hydroponics II", "hydroponics_1")
	building_limit_bonus = {Greenhouse.ID: 1}
