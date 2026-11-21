class_name Building
extends RefCounted
## A building inside a player's central hub (see Player.buildings). Buildings
## don't stand on map tiles - they live in the hub and do their work there,
## e.g. a Greenhouse grows biomass every turn.
##
## To add a building type: make a script extending Building that sets its id,
## name, description and output in _init(), and add it to create() below.

## Saved in save files - never change one once it's in use.
var id := ""
var display_name := "Building"
var description := ""
## Resources this building adds to the hub's stockpile every turn:
## ResourceDeposit.Type -> int.
var output: Dictionary = {}


## A new building from its id (as saved), or null if there's no such type.
static func create(building_id: String) -> Building:
	match building_id:
		Greenhouse.ID:
			return Greenhouse.new()
	push_warning("Unknown building type '%s'." % building_id)
	return null


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
