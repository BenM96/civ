class_name Buildable
extends RefCounted
## Something a Worker can construct on a tile (foundations, later farms, mines...).
##
## Each structure keeps ALL its data in its own file: name, cost, build time,
## where it can go, what it does when finished, and any gameplay numbers.
##
## To add a new structure: extend this class, set its data in _init(),
## override get_invalid_reason() and apply(), then add it to
## Player.buildables. If it stands on tiles as a Structure (rather than
## changing the terrain, like foundations), also add a value to Structure.Type and
## list it in Structure._create_all().

## Short unique id used by the UI, e.g. "foundation".
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
## terrain instead (foundations, bridges).
var structure_type := Structure.Type.NONE
## Whether resources travel through this structure as part of a hub's
## supply network.
var carries_resources := false
## Ids of buildables that must be on the same tile first, e.g. a conveyor
## needs a "foundation". Workers build them automatically.
var requires: Array[String] = []
## If set, ordering this is a line job (see LineBuildMission): the worker
## builds this buildable (with its requirements) on every tile from the hub
## to the target, e.g. "conveyor" for an extractor so it's connected, or the
## buildable's own id for foundations and belts. "" = a single-tile build.
var line_of := ""
## What to pick on the map when ordering it, for the Mission Briefing tooltip.
var site_name := "a tile"


## Why this can't be built at `h`, or "" if it can.
func get_invalid_reason(_map: HexMap, _h: Vector2i) -> String:
	return ""


## Like get_invalid_reason(), but ignoring missing `requires` - i.e. could it
## go here once they're built? Used to plan lines ahead.
func get_site_reason(map: HexMap, h: Vector2i) -> String:
	return get_invalid_reason(map, h)


## Whether this is already in place at `h` for `faction` (so a line job can
## skip it).
func is_built_at(_map: HexMap, _h: Vector2i, _faction: int) -> bool:
	return false


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
