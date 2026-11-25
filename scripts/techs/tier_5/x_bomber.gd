extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Bomber: flattens structures or knocks 1 off an enemy hub's health.


func _init() -> void:
	super("bomber", "Bomber", "hangar")
	unlocks_unit = "Bomber"
