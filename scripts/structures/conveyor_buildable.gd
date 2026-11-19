class_name ConveyorBuildable
extends Buildable
## One tile of conveyor belt. A continuous line of belts from an extractor to
## the hub carries the extractor's output home every turn. Must be built on a
## foundation (or a bridge). Extractors are built on top of a belt.


func _init() -> void:
	id = "conveyor"
	display_name = "Conveyor Belt"
	cost = {ResourceDeposit.Type.TITANIUM: 1}
	build_turns = 1
	structure_type = Structure.Type.CONVEYOR
	carries_resources = true
	requires = ["foundation"]
	line_of = "conveyor"


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var reason := get_site_reason(map, h)
	if reason != "":
		return reason
	if not Terrain.is_foundation(map.get_tile(h).terrain):
		return "needs a foundation first"
	return ""


## Why a belt could never go at `h`, ignoring whether it has a foundation
## yet - so planners (like the AI) can find routes before laying them.
func get_site_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.is_passable():
		return "can't build on impassable ground"
	if tile.structure != Structure.Type.NONE:
		return "already has a %s" % Structure.get_display_name(tile.structure)
	return ""  # Deposits too: a belt there is the base for an Extractor.


## A belt line counts as done where we already have a belt or an extractor
## (both carry resources).
func is_built_at(map: HexMap, h: Vector2i, faction: int) -> bool:
	var tile := map.get_tile(h)
	return Structure.carries_resources(tile.structure) and tile.structure_owner == faction


func apply(map: HexMap, h: Vector2i, owner_faction: int) -> void:
	map.set_structure(h, Structure.Type.CONVEYOR, owner_faction)
