extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## +1 initiative.


func _init() -> void:
	super("initiative_2", "Initiative II", "initiative_1")
	initiative_bonus = 1
