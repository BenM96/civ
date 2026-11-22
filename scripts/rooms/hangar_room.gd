class_name HangarRoom
extends QuartersRoom
## Where off-duty air units wait, and are held while training. Opened by the
## Hangar building. Aircraft back from a sortie refit here (see QuartersRoom
## and Player.get_refit_turns()), which also repairs them.

const ID := "hangar"


func _init() -> void:
	super(ID, "Hangar", Unit.UnitType.AIR, HangarBuilding.ID)
	description += "\nAircraft back from a sortie refit here for %d turns (which repairs them), then move on to Mission Briefing. Each Flight Crew Quarters cuts a turn off." % AirUnit.REFIT_TURNS
