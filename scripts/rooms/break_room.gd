class_name BreakRoom
extends QuartersRoom
## Where off-duty civilian units (Miner, Builders, Guards) wait, and are
## held while training.

const ID := "break_room"


func _init() -> void:
	super(ID, "Break Room", Unit.UnitType.CIVILIAN)
