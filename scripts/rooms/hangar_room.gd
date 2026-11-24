class_name HangarRoom
extends QuartersRoom
## Where off-duty air units wait, and are held while training. Opened by the
## Hangar building. Aircraft back from any flight refit here for
## AirUnit.REFIT_TURNS (one less per Flight Crew Quarters - see
## Player.get_refit_turns()), which repairs them fully (see QuartersRoom).
## Interceptors on standby wait here too (see InterceptMission).

const ID := "hangar"


func _init() -> void:
	super(ID, "Hangar", Unit.UnitType.AIR, HangarBuilding.ID)
	description += "\nAircraft back from a flight refit here for %d turns (each Flight Crew Quarters cuts a turn off), which also repairs them fully. Then they go to Mission Briefing - or, if they're on Intercept duty, straight back on standby here." % AirUnit.REFIT_TURNS
	description += "\nInterceptors stand by here; drag one out to take it off intercept duty."
