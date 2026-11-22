class_name BarracksRoom
extends QuartersRoom
## Where off-duty infantry wait, and are held while training. Opened by the
## Barracks building.

const ID := "barracks"


func _init() -> void:
	super(ID, "Barracks", Unit.UnitType.INFANTRY, BarracksBuilding.ID)
