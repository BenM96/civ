extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks the Fighter (counters air units). Locked in T4 with the other anti-air units, the tier after the Hangar (T3).


func _init() -> void:
	super("fighter", "Fighter", "hangar")
	unlocks_unit = "Fighter"
