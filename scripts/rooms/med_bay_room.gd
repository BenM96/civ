class_name MedBayRoom
extends Room
## Heals injured infantry and civilians, one at a time by default (see Room's
## healing queue). Opened by the Med Bay building; its upgrades (Surgical
## Ward, Regen Lab) heal more units at once and faster. Injured infantry and
## civilians that come home are brought here, and move on to Mission
## Briefing once fully healed.

const ID := "med_bay"


func _init() -> void:
	id = ID
	display_name = "Med Bay"
	required_building = MedBayBuilding.ID
	heals = [Unit.UnitType.INFANTRY, Unit.UnitType.CIVILIAN]
	heal_slots_building = SurgicalWard.ID
	heal_rate_building = RegenLab.ID
	description = "Heals injured infantry and civilians, then sends them to Mission Briefing. Injured ones that come home are brought here.\nOnly the unit at the top of the list heals (1 HP a turn); the rest wait their turn. Drag a unit up or down the list to change who's next.\nSurgical Wards heal more units at once; Regen Labs heal faster."


func get_refusal(unit: Unit) -> String:
	if not heals_unit(unit):
		return "the Med Bay only treats infantry and civilians"
	if not unit.is_injured():
		return "%s isn't injured" % unit.display_name
	return ""
