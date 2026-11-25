extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Anti-Aircraft Gun (anti-air). Specialist rule: the tier after the unit type it counters arrives (air: Hangar, T3).


func _init() -> void:
	super("aa_gun", "Anti-Aircraft Gun", "garage")
	unlocks_unit = "Anti-Aircraft Gun"
