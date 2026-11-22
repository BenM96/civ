class_name HangarBuilding
extends Building
## Opens the hub's Hangar (see HangarRoom): needed to train air units, which
## refit there after every sortie.

const ID := "hangar"


func _init() -> void:
	id = ID
	display_name = "Hangar"
	description = "Opens the Hangar room, where aircraft wait and refit after every sortie.\nNeeded to train air units."
