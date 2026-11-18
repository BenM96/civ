class_name ExtractorBuildable
extends Buildable
## Mining rig placed on a resource deposit. Once linked to the hub by
## conveyor belts it delivers 1 of that resource every turn.


func _init() -> void:
	id = "extractor"
	display_name = "Extractor"
	cost = {ResourceDeposit.Type.TITANIUM: 2, ResourceDeposit.Type.SEDIMENT: 1}
	build_turns = 2


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.is_passable():
		return "can't build on impassable ground"
	if tile.structure != Structure.Type.NONE:
		return "already has a %s" % Structure.get_display_name(tile.structure)
	if not tile.has_deposit():
		return "must be built on a resource deposit"
	return ""


func apply(map: HexMap, h: Vector2i, owner_faction: int) -> void:
	map.set_structure(h, Structure.Type.EXTRACTOR, owner_faction)
