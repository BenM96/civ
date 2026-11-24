class_name FobBuildable
extends Buildable
## A Forward Operating Base: a fort out on the belt network. While it's
## linked to its hub by belts, QRF units can be based there instead of the
## hub (see QrfMission), standing by on the FOB and defending from it.
##
## Built like a command point: on top of one of our conveyor belts, which it
## replaces (and still carries resources like one). Ordering one also lays
## the foundations and belts from the hub to it. Each one costs double the
## last: BASE_COST times 2 for every FOB the colony has ever built
## (Player.fobs_built). Enemies can demolish or bomb it, but not capture it.

const ID := "fob"
## What the first one costs.
const BASE_COST := {ResourceDeposit.Type.SEDIMENT: 10, ResourceDeposit.Type.TITANIUM: 20}


func _init() -> void:
	id = ID
	display_name = "FOB"
	cost = BASE_COST.duplicate()
	build_turns = 1
	structure_type = Structure.Type.FOB
	carries_resources = true
	requires = ["conveyor"]
	line_of = "conveyor"
	site_name = "a tile on one of your belts"


## What `built_before` FOBs make the next one cost.
static func cost_after(built_before: int) -> Dictionary:
	var result := {}
	for type: ResourceDeposit.Type in BASE_COST:
		result[type] = BASE_COST[type] * int(pow(2, built_before))
	return result


func get_cost_at(player: Player, _h: Vector2i) -> Dictionary:
	return cost_after(player.fobs_built) if player else cost


func get_cost_text() -> String:
	return "%s, doubling with every FOB built" % ResourceDeposit.format_cost(BASE_COST)


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var reason := get_site_reason(map, h)
	if reason != "":
		return reason
	if map.get_tile(h).structure != Structure.Type.CONVEYOR:
		return "needs a conveyor belt first"
	return ""


## Why an FOB could never go at `h`, ignoring whether it has its foundation
## and belt yet.
func get_site_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.is_passable():
		return "can't build on impassable ground"
	if tile.control_point:
		return "control points are for command points"
	if tile.has_deposit():
		return "deposits are for extractors"
	if map.get_player_at(h) != null:
		return "can't build on a hub"
	if tile.structure != Structure.Type.NONE and tile.structure != Structure.Type.CONVEYOR:
		return "already has a %s" % Structure.get_display_name(tile.structure)
	return ""


func is_built_at(map: HexMap, h: Vector2i, faction: int) -> bool:
	var tile := map.get_tile(h)
	return tile.structure == Structure.Type.FOB and tile.structure_owner == faction


func apply(map: HexMap, h: Vector2i, owner_faction: int) -> void:
	map.set_structure(h, Structure.Type.FOB, owner_faction)
	var owner: Player = map.players.get(owner_faction)
	if owner:
		owner.fobs_built += 1
