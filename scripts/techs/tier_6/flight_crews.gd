extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Unlocks Flight Crew Quarters (Hangar upgrade): aircraft refit 1 turn faster after every flight, per one built.


func _init() -> void:
	super("flight_crews", "Flight Crews", "hangar")
	unlocks_building = FlightCrewQuarters.ID
