class_name BarracksRoom
extends QuartersRoom
## Where off-duty infantry wait, and are held while training.

const ID := "barracks"


func _init() -> void:
	super(ID, "Barracks", Unit.UnitType.INFANTRY)
