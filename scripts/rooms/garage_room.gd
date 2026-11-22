class_name GarageRoom
extends QuartersRoom
## Where off-duty armour waits, and is held while training. Opened by the
## Garage building. Also repairs damaged armour, one vehicle at a time by
## default (see Room's healing queue); Repair Bays and Machine Shops repair
## more at once and faster.

const ID := "garage"


func _init() -> void:
	super(ID, "Garage", Unit.UnitType.ARMOUR, GarageBuilding.ID)
	heals = [Unit.UnitType.ARMOUR]
	heal_slots_building = RepairBay.ID
	heal_rate_building = MachineShop.ID
	description += "\nDamaged armour is repaired here, then sent to Mission Briefing. Only the vehicle at the top of the list is repaired (1 HP a turn); drag one up or down the list to change who's next.\nRepair Bays repair more at once; Machine Shops repair faster."
