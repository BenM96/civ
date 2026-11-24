class_name AirUnit
extends Unit
## Base for air units (Chopper, Fighter, Fighter Bomber, Bomber). Air units
## don't walk: they fly straight to their target before any ground unit
## moves (see Movement), fight there, and fly home in the air return phase
## at the end of the same turn. Missions: Sortie and Intercept (the Bomber:
## Carpet Bomb instead). Back home they refit in the Hangar for REFIT_TURNS
## (one less per Flight Crew Quarters), which also repairs them fully.
##
## In battle they fire before any ground unit and always shoot enemy
## aircraft first (see Combat, get_target_preference()).
##
## Drawn as a top-down outline of the aircraft (see `silhouette` and
## Unit.draw_aircraft()), above the ground units on its tile, pointing the
## way it's flying. Each air unit sets its name, numbers, damage and
## silhouette in its own file.

## Turns spent refitting in the Hangar after every flight.
const REFIT_TURNS := 10


func _init() -> void:
	unit_type = UnitType.AIR
	flies = true
	refit_turns = REFIT_TURNS
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 2, ResourceDeposit.Type.ELECTRUM: 2}
	upkeep = 1
	max_movement = 3
	allowed_missions = ["sortie", "intercept"]


## Enemy aircraft always first, then the usual order for the rest.
func get_target_preference() -> Array:
	var groups := [[UnitType.AIR]]
	for group: Array in super():
		var rest := group.filter(func(t: UnitType) -> bool: return t != UnitType.AIR)
		if not rest.is_empty():
			groups.append(rest)
	return groups
