class_name Greenhouse
extends Building
## Grows food for the colony's units. Every hub starts with one.

const ID := "greenhouse"
## Biomass grown every turn.
const BIOMASS_OUTPUT := 3


func _init() -> void:
	id = ID
	display_name = "Greenhouse"
	description = "Grows biomass to feed the colony's units."
	output = {ResourceDeposit.Type.BIOMASS: BIOMASS_OUTPUT}
