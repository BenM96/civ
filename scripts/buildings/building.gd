class_name Building
extends RefCounted
## A building inside a player's central hub (see Player.buildings). Buildings
## don't stand on map tiles - they live in the hub and do their work there,
## e.g. a Greenhouse grows biomass every turn, a Barracks opens the hub's
## Barracks room (see Room.required_building) and a Surgical Ward lets the
## Med Bay treat one more unit at a time.
##
## The player orders new ones from the Buildings panel (a "build_building"
## order, see Player.order_building()); they're paid for straight away and
## finished at the end of the turn.
##
## To add a building type: make a script extending Building that sets its id,
## name, description and whatever else it needs in _init(), and add it to
## create_all() below.

## What every building costs for now.
const STANDARD_COST := {
	ResourceDeposit.Type.SEDIMENT: 5,
	ResourceDeposit.Type.TITANIUM: 2,
}

## Saved in save files - never change one once it's in use.
var id := ""
var display_name := "Building"
var description := ""
## Resources this building adds to the hub's stockpile every turn:
## ResourceDeposit.Type -> int.
var output: Dictionary = {}
## What building one costs: ResourceDeposit.Type -> int.
var cost: Dictionary = STANDARD_COST
## How many a hub may have (finished and under construction).
var max_count := 1
## A building the hub must have first (its id), or "" for none - e.g. a
## Surgical Ward needs a Med Bay.
var requires := ""


## One of every building type, in the order the Buildings panel lists them.
static func create_all() -> Array[Building]:
	return [
		Greenhouse.new(),
		BarracksBuilding.new(),
		GarageBuilding.new(),
		HangarBuilding.new(),
		MedBayBuilding.new(),
		SurgicalWard.new(),
		RegenLab.new(),
		RepairBay.new(),
		MachineShop.new(),
		FlightCrewQuarters.new(),
	]


## A new building from its id (as saved), or null if there's no such type.
static func create(building_id: String) -> Building:
	for building in create_all():
		if building.id == building_id:
			return building
	push_warning("Unknown building type '%s'." % building_id)
	return null


## The display name for a building id, e.g. "Med Bay".
static func get_name_for(building_id: String) -> String:
	var building := create(building_id)
	return building.display_name if building else building_id


## "Production" step of each turn (see Player.produce()). By default, adds
## `output` to the stockpile. Override for buildings that do more.
func produce(player: Player) -> void:
	for type in output:
		player.add_resource(type, output[type])


## What it makes, e.g. "+3 Biomass per turn", or "" if nothing.
func get_output_text() -> String:
	if output.is_empty():
		return ""
	var parts: PackedStringArray = []
	for type in output:
		parts.append("%s %s" % [ResourceDeposit.format_change(output[type]), ResourceDeposit.get_type_name(type)])
	return "%s per turn" % ", ".join(parts)
