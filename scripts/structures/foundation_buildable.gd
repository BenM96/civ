class_name FoundationBuildable
extends Buildable
## Lays a Foundation: prepared ground that is cheap to move across (like a
## road) and that conveyor belts and extractors must be built on. It costs
## Sediment, more the further it is from the colony's hub (see
## SEDIMENT_BY_DISTANCE).

## [furthest distance from the hub, Sediment] bands, nearest first; anything
## beyond the last band costs FAR_SEDIMENT.
const SEDIMENT_BY_DISTANCE := [[5, 1], [10, 5], [20, 20]]
const FAR_SEDIMENT := 50


func _init() -> void:
	id = "foundation"
	display_name = "Foundation"
	cost = {ResourceDeposit.Type.SEDIMENT: 1}
	build_turns = 1
	line_of = "foundation"


## Sediment for a foundation `distance` tiles from its hub.
static func sediment_at(distance: int) -> int:
	for band: Array in SEDIMENT_BY_DISTANCE:
		if distance <= band[0]:
			return band[1]
	return FAR_SEDIMENT


func get_cost_at(player: Player, h: Vector2i) -> Dictionary:
	return {ResourceDeposit.Type.SEDIMENT: sediment_at(Hex.distance(h, player.hex))}


func get_cost_text() -> String:
	return "1-50 Sediment, more the further from the hub"


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
