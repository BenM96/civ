extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Unlocks Assault Infantry.


func _init() -> void:
	super("assault_infantry", "Assault Infantry", "barracks")
	unlocks_unit = "Assault Infantry"
