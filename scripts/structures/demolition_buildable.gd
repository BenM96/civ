class_name DemolitionBuildable
extends Buildable
## Not something you build, but it works exactly like a build job: travel
## to a tile, work a turn, change the tile. Clears every man-made thing on
## the tile (roads, extractors, conveyors) and leaves Rubble - except a
## bridge, which collapses back into the Chasm. Bridges are demolished from
## the bank so the unit isn't standing on it when it falls.
## Used by DemolishMission; Infantry do this, not Builders.


func _init() -> void:
	id = "demolish"
	display_name = "Demolition"
	cost = {}
	build_turns = 1


## Whether anything on `tile` was made by people.
static func is_man_made(tile: HexTile) -> bool:
	return tile.structure != Structure.Type.NONE \
		or tile.terrain == Terrain.Type.ROAD or tile.terrain == Terrain.Type.BRIDGE


## A short description of what demolishing `tile` would destroy.
static func describe(tile: HexTile) -> String:
	var parts: PackedStringArray = []
	if tile.structure != Structure.Type.NONE:
		parts.append(Structure.get_display_name(tile.structure))
	if tile.terrain == Terrain.Type.ROAD or tile.terrain == Terrain.Type.BRIDGE:
		parts.append(Terrain.get_display_name(tile.terrain))
	return " and ".join(parts)


func get_unit_reason(u: Unit) -> String:
	return "" if u.can_demolish else "%s can't demolish" % u.unit_name


func get_invalid_reason(map: HexMap, h: Vector2i) -> String:
	var tile := map.get_tile(h)
	if tile == null or not is_man_made(tile):
		return "nothing man-made to demolish"
	return ""


func works_from_adjacent(map: HexMap, h: Vector2i) -> bool:
	var tile := map.get_tile(h)
	return tile != null and tile.terrain == Terrain.Type.BRIDGE


func apply(map: HexMap, h: Vector2i, _owner_faction: int) -> void:
	var was_bridge := map.get_tile(h).terrain == Terrain.Type.BRIDGE
	# Structure first so the supply network sees the final state last.
	map.set_structure(h, Structure.Type.NONE)
	map.set_terrain(h, Terrain.Type.CHASM if was_bridge else Terrain.Type.RUBBLE)
