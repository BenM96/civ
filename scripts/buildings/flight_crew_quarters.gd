class_name FlightCrewQuarters
extends Building
## Hangar upgrade: aircraft refit 1 turn faster after a sortie, per one
## built (see Player.get_refit_turns()).

const ID := "flight_crew_quarters"


func _init() -> void:
	id = ID
	display_name = "Flight Crew Quarters"
	description = "Hangar upgrade: aircraft refit 1 turn faster after each sortie."
	requires = HangarBuilding.ID
	max_count = 3
