class_name FoundationBuildable
extends Buildable
## Lays a Foundation: prepared ground that is cheap to move across (like a
## road) and that conveyor belts and extractors must be built on.


func _init() -> void:
	id = "foundation"
	display_name = "Foundation"
	cost = {ResourceDeposit.Type.SEDIMENT: 1}
	build_turns = 1
	line_of = "foundation"


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.is_passable():
		return "can't build on impassable ground"
	if tile.terrain == Terrain.Type.BRIDGE:
		return "a bridge already counts as a foundation"
	if tile.terrain == Terrain.Type.FOUNDATION:
		return "already has a foundation"
	return ""


func is_built_at(map: HexMap, h: Vector2i, _faction: int) -> bool:
	return Terrain.is_foundation(map.get_tile(h).terrain)


func apply(map: HexMap, h: Vector2i, _owner_faction: int) -> void:
	map.set_terrain(h, Terrain.Type.FOUNDATION)
