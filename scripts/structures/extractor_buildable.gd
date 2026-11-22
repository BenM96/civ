class_name ExtractorBuildable
extends Buildable
## Mining rig placed on a resource deposit, on top of one of our conveyor
## belts (which sits on a foundation). It replaces the belt and still carries
## resources like one. Once linked to the hub by conveyor belts it delivers
## its resource every turn - how much depends on the resource (see
## extractor_output in its file in scripts/resources/). Ordering one also
## lays the foundations and belts from the hub to it, and under it (line_of =
## "conveyor", requires "conveyor").


## What an extractor on a deposit of `type` delivers per turn.
static func output_for(type: ResourceDeposit.Type) -> float:
	return ResourceDeposit.get_info(type).extractor_output


func _init() -> void:
	id = "extractor"
	display_name = "Extractor"
	cost = {ResourceDeposit.Type.TITANIUM: 2, ResourceDeposit.Type.SEDIMENT: 2}
	build_turns = 1
	structure_type = Structure.Type.EXTRACTOR
	carries_resources = true
	requires = ["conveyor"]
	line_of = "conveyor"
	site_name = "a deposit"


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var reason := get_site_reason(map, h)
	if reason != "":
		return reason
	if map.get_tile(h).structure != Structure.Type.CONVEYOR:
		return "needs a conveyor belt first"
	return ""


## Why an extractor could never go at `h`, ignoring whether it has its
## foundation and belt yet. (Whose belt it is gets checked by the line job:
## another colony's belt can't be built over.)
func get_site_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.is_passable():
		return "can't build on impassable ground"
	if tile.structure != Structure.Type.NONE and tile.structure != Structure.Type.CONVEYOR:
		return "already has a %s" % Structure.get_display_name(tile.structure)
	if not tile.has_deposit():
		return "must be built on a resource deposit"
	return ""


func is_built_at(map: HexMap, h: Vector2i, faction: int) -> bool:
	var tile := map.get_tile(h)
	return tile.structure == Structure.Type.EXTRACTOR and tile.structure_owner == faction


func apply(map: HexMap, h: Vector2i, owner_faction: int) -> void:
	map.set_structure(h, Structure.Type.EXTRACTOR, owner_faction)
