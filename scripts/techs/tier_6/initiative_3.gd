extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## +1 initiative.


func _init() -> void:
	super("initiative_3", "Initiative III", "initiative_2")
	initiative_bonus = 1
