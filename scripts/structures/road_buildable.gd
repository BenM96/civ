class_name RoadBuildable
extends Buildable
## Turns a tile into Road terrain, which is cheap to move across.


func _init() -> void:
	id = "road"
	display_name = "Road"
	cost = {ResourceDeposit.Type.SEDIMENT: 1}
	build_turns = 1


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not tile.is_passable():
		return "can't build on impassable ground"
	if tile.terrain == Terrain.Type.BRIDGE:
		return "can't pave a bridge"
	if tile.terrain == Terrain.Type.ROAD:
		return "already a road"
	return ""


func apply(map: HexMap, h: Vector2i) -> void:
	map.set_terrain(h, Terrain.Type.ROAD)
