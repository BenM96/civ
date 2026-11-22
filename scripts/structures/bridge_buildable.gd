class_name BridgeBuildable
extends Buildable
## Spans a chasm tile, making it passable. Builders can't stand in a chasm,
## so they build from a neighbouring tile - a finished bridge tile then
## lets them reach the next one, so wide chasms are crossed tile by tile.


func _init() -> void:
	id = "bridge"
	display_name = "Bridge"
	cost = {ResourceDeposit.Type.TITANIUM: 2, ResourceDeposit.Type.SEDIMENT: 2}
	build_turns = 1
	build_from_adjacent = true


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null:
		return "off the map"
	if tile.terrain == Terrain.Type.BRIDGE:
		return "already bridged"
	if tile.terrain != Terrain.Type.CHASM:
		return "bridges can only span chasms"
	return ""


func apply(map: HexMap, h: Vector2i, _owner_faction: int) -> void:
	map.set_terrain(h, Terrain.Type.BRIDGE)
