extends Tech
## LOCKED: do not move to another tier or change without asking first.
## +1 Builder limit. Its id keeps the tier it was first in (saves use it).


func _init() -> void:
	super("workforce_1", "Workforce I")
	builder_limit_bonus = 1
