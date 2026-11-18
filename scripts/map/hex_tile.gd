class_name HexTile
extends RefCounted
## Data for a single map tile: terrain plus anything sitting on it.

var coord: Vector2i
var terrain: Terrain.Type
## Resource on this tile, or null.
var deposit: ResourceDeposit
## Extractor, conveyor... built on this tile.
var structure: Structure.Type = Structure.Type.NONE


func _init(p_coord: Vector2i, p_terrain: Terrain.Type) -> void:
	coord = p_coord
	terrain = p_terrain


func get_move_cost() -> int:
	return Terrain.get_move_cost(terrain)


func is_passable() -> bool:
	return Terrain.is_passable(terrain)


func has_deposit() -> bool:
	return deposit != null and not deposit.is_depleted()


func get_display_name() -> String:
	return Terrain.get_display_name(terrain)
