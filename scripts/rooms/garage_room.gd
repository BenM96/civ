class_name GarageRoom
extends QuartersRoom
## Where off-duty armour units wait, and are held while training.

const ID := "garage"


func _init() -> void:
	super(ID, "Garage", Unit.UnitType.ARMOUR)
