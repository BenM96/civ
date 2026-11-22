class_name AirUnit
extends Unit
## Base for air units (Chopper, Fighter, Bomber). Air units don't walk: their
## one mission is a sortie (see SortieMission) - after everyone else has
## moved they jump straight to any tile, fight there, and fly home at the
## start of the next turn. Then they spend REFIT_TURNS refitting in the
## Hangar (which also repairs them) before they can be sent out again.
## Triangle icon. Each air unit sets its name, numbers and damage in its own
## file.

## Turns spent refitting in the Hangar after every sortie.
const REFIT_TURNS := 10


func _init() -> void:
	unit_type = UnitType.AIR
	flies = true
	refit_turns = REFIT_TURNS
	cost = {ResourceDeposit.Type.GOLD: 3, ResourceDeposit.Type.TITANIUM: 2}
	upkeep = 1
	max_movement = 3
	allowed_missions = ["sortie"]
