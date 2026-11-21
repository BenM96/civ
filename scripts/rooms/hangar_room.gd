class_name HangarRoom
extends QuartersRoom
## Where off-duty air units wait, and are held while training. Aircraft
## back from a sortie refit here for AirUnit.REFIT_TURNS turns (see
## QuartersRoom), which also repairs them.

const ID := "hangar"


func _init() -> void:
	super(ID, "Hangar", Unit.UnitType.AIR)
	description += "\nAircraft back from a sortie refit here for %d turns (which repairs them), then move on to Mission Briefing." % AirUnit.REFIT_TURNS
