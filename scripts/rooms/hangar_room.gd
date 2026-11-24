class_name HangarRoom
extends QuartersRoom
## Where off-duty air units wait, and are held while training. Opened by the
## Hangar building. Aircraft back from a sortie refit here first (see
## QuartersRoom and Player.get_refit_turns()) - refitting doesn't repair
## them. Then damaged ones are repaired here like armour in the Garage: one
## at a time, 1 HP a turn (see Room's healing queue); each Flight Crew
## Quarters repairs one more at once.

const ID := "hangar"


func _init() -> void:
	super(ID, "Hangar", Unit.UnitType.AIR, HangarBuilding.ID)
	heals = [Unit.UnitType.AIR]
	heal_slots_building = FlightCrewQuarters.ID
	description += "\nAircraft back from a sortie refit here for %d turns (each Flight Crew Quarters cuts a turn off). Then damaged ones are repaired here, 1 HP a turn, one at a time (one more at once per Flight Crew Quarters), and go to Mission Briefing once fully repaired." % AirUnit.REFIT_TURNS
