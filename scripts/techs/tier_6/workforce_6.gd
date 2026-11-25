extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## +1 Builder limit (Workforce IV). Its id keeps the tier it was first in (saves use it).


func _init() -> void:
	super("workforce_6", "Workforce IV")
	builder_limit_bonus = 1
