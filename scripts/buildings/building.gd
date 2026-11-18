class_name Building
extends Node2D
## Base class for anything built on a tile.

@export var building_name := "Building"
@export var max_health := 50

var hex: Vector2i
var map: HexMap
var health := 0


func _ready() -> void:
	health = max_health


## Puts the building on the map. The building must already be in the tree.
func place(p_map: HexMap, p_hex: Vector2i) -> void:
	map = p_map
	hex = p_hex
	global_position = map.hex_to_world(hex)
	queue_redraw()


## Called once per turn during turn resolution. Override in subclasses.
func process_turn() -> void:
	pass


func get_info_text() -> String:
	return building_name
