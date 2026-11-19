class_name Buildable
extends RefCounted
## Something a Worker can construct on a tile (roads, later farms, mines...).
##
## Each structure keeps ALL its data in its own file: name, cost, build time,
## where it can go, what it does when finished, and any gameplay numbers.
##
## To add a new structure: extend this class, set its data in _init(),
## override get_invalid_reason() and apply(), then add it to
## CentralHub.buildables. If it stands on tiles as a Structure (rather than
## changing the terrain, like roads), also add a value to Structure.Type and
## list it in Structure._create_all().

## Short unique id used by the UI, e.g. "road".
var id := ""
var display_name := "Structure"
## ResourceDeposit.Type -> int. Paid when the order is given.
var cost: Dictionary = {}
## Turns the builder spends working once on the tile.
var build_turns := 1
## If true the builder works from a passable neighbouring tile instead of
## standing on the target (e.g. bridges over impassable chasms).
var build_from_adjacent := false
## The Structure.Type this places on a tile, or NONE if it changes the
## terrain instead (roads, bridges).
var structure_type := Structure.Type.NONE
## Whether resources travel through this structure as part of a hub's
## supply network.
var carries_resources := false


## Why this can't be built at `h`, or "" if it can.
func get_invalid_reason(_map: HexMap, _h: Vector2i) -> String:
	return ""


func can_build_at(map: HexMap, h: Vector2i) -> bool:
	return get_invalid_reason(map, h) == ""


## Changes the world once construction finishes.
func apply(_map: HexMap, _h: Vector2i, _owner_faction: int) -> void:
	pass


func get_cost_text() -> String:
	return ResourceDeposit.format_cost(cost)


## Whether the unit must work from a neighbouring tile rather than stand on
## `h` (e.g. the tile is, or will become, impassable).
func works_from_adjacent(_map: HexMap, _h: Vector2i) -> bool:
	return build_from_adjacent
