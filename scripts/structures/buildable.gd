class_name Buildable
extends RefCounted
## Something a Builder can construct on a tile (roads, later farms, mines...).
##
## To add a new structure: extend this class, set id / display_name / cost /
## build_turns in _init(), override get_invalid_reason() and apply(), then add
## it to CentralHub.buildables.

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


## Why this can't be built at `h`, or "" if it can.
func get_invalid_reason(_map: HexMap, _h: Vector2i) -> String:
	return ""


func can_build_at(map: HexMap, h: Vector2i) -> bool:
	return get_invalid_reason(map, h) == ""


## Changes the world once construction finishes.
func apply(_map: HexMap, _h: Vector2i) -> void:
	pass


func get_cost_text() -> String:
	return ResourceDeposit.format_cost(cost)


## Why `u` can't do this job at all, or "" if it can. Builders build;
## override for jobs done by other units (e.g. Infantry demolition).
func get_unit_reason(u: Unit) -> String:
	return "" if u.can_build else "%s can't build" % u.unit_name


## Whether the unit must work from a neighbouring tile rather than stand on
## `h` (e.g. the tile is, or will become, impassable).
func works_from_adjacent(_map: HexMap, _h: Vector2i) -> bool:
	return build_from_adjacent
