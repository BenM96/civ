class_name CommandPointBuildable
extends Buildable
## A command post built on a control point (see HexMap.control_points). A
## colony with a command point on every control point on the map, each one
## linked to its hub by conveyor belts, wins (see TurnManager).
##
## Built like an extractor: on top of one of our conveyor belts, which it
## replaces (and still carries resources like one). Ordering one also lays
## the foundations and belts from the hub to it (line_of = "conveyor",
## requires "conveyor"). Other colonies' Infantry can capture or demolish it.

const ID := "command_point"
## Every stored resource it costs (Biomass isn't stored).
const COST_EACH := 20


func _init() -> void:
	id = ID
	display_name = "Command Point"
	cost = {
		ResourceDeposit.Type.TITANIUM: COST_EACH,
		ResourceDeposit.Type.SEDIMENT: COST_EACH,
		ResourceDeposit.Type.GOLD: COST_EACH,
		ResourceDeposit.Type.ELECTRUM: COST_EACH,
	}
	build_turns = 1
	structure_type = Structure.Type.COMMAND_POINT
	carries_resources = true
	requires = ["conveyor"]
	line_of = "conveyor"
	site_name = "a control point"


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var reason := get_site_reason(map, h)
	if reason != "":
		return reason
	if map.get_tile(h).structure != Structure.Type.CONVEYOR:
		return "needs a conveyor belt first"
	return ""


## Why a command point could never go at `h`, ignoring whether it has its
## foundation and belt yet.
func get_site_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.control_point:
		return "must be built on a control point"
	if not tile.is_passable():
		return "can't build on impassable ground"
	if tile.structure != Structure.Type.NONE and tile.structure != Structure.Type.CONVEYOR:
		return "already has a %s" % Structure.get_display_name(tile.structure)
	return ""


func is_built_at(map: HexMap, h: Vector2i, faction: int) -> bool:
	var tile := map.get_tile(h)
	return tile.structure == Structure.Type.COMMAND_POINT and tile.structure_owner == faction


func apply(map: HexMap, h: Vector2i, owner_faction: int) -> void:
	map.set_structure(h, Structure.Type.COMMAND_POINT, owner_faction)
