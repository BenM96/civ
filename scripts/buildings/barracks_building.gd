class_name BarracksBuilding
extends Building
## Opens the hub's Barracks (see BarracksRoom): needed to train infantry.

const ID := "barracks"


func _init() -> void:
	id = ID
	display_name = "Barracks"
	description = "Opens the Barracks room, where off-duty infantry wait.\nNeeded to train infantry."
