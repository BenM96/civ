extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## +1 Builder limit (Workforce III). Its id keeps the tier it was first in (saves use it).


func _init() -> void:
	super("workforce_5", "Workforce III")
	builder_limit_bonus = 1
