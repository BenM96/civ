extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Unlocks the Fighter Bomber.


func _init() -> void:
	super("fighter_bomber", "Fighter Bomber", "hangar")
	unlocks_unit = "Fighter Bomber"
