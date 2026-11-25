extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Lets Builders build command points on control points. Holding every control point, each linked to the hub by belts, wins the game.


func _init() -> void:
	super("command_doctrine", "Command Doctrine")
	unlocks_buildable = CommandPointBuildable.ID
