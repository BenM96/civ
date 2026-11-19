class_name ConveyorBuildable
extends Buildable
## One tile of conveyor belt. A continuous line of belts from an extractor to
## the hub carries the extractor's output home every turn.


func _init() -> void:
	id = "conveyor"
	display_name = "Conveyor Belt"
	cost = {ResourceDeposit.Type.TITANIUM: 1}
	build_turns = 1
	structure_type = Structure.Type.CONVEYOR
	carries_resources = true


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.is_passable():
		return "can't build on impassable ground"
	if tile.structure != Structure.Type.NONE:
		return "already has a %s" % Structure.get_display_name(tile.structure)
	if tile.has_deposit():
		return "deposits need an Extractor, not a belt"
	return ""


func apply(map: HexMap, h: Vector2i, owner_faction: int) -> void:
	map.set_structure(h, Structure.Type.CONVEYOR, owner_faction)
