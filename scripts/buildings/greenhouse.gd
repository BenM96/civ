class_name Greenhouse
extends Building
## Grows food for the colony's units. Every hub starts with one and can
## build more, up to MAX.

const ID := "greenhouse"
## Biomass grown every turn.
const BIOMASS_OUTPUT := 3
## Most a hub can have, counting the one it starts with.
const MAX := 3


func _init() -> void:
	id = ID
	display_name = "Greenhouse"
	description = "Grows biomass to feed the colony's units."
	output = {ResourceDeposit.Type.BIOMASS: BIOMASS_OUTPUT}
	max_count = MAX
