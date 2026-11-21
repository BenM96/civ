class_name SaveGame
extends RefCounted
## Saving and loading the whole game as plain data (Dictionaries, Arrays,
## strings, numbers, bools) - the same format can be written to a file or
## sent over a network.
##
## Each part of the game saves itself (to_dict / load_dict on HexMap,
## Player, Unit and Mission); this file just ties them together. When you
## add new state to something, add it to that thing's to_dict / load_dict.
##
## Enums are stored by name ("BIOMASS", "ON_MISSION") rather than number so
## saves stay readable and survive new values being added.

const FILE := "user://savegame.json"
## Bump when the format changes in a way old saves can't be loaded.
const VERSION := 1


## The whole game as plain data.
static func capture(map: HexMap, players: Array[Player], turn: int, gold_goal_reached := false) -> Dictionary:
	var player_data := []
	for player in players:
		player_data.append(player.to_dict())
	return {
		"version": VERSION,
		"turn": turn,
		"gold_goal_reached": gold_goal_reached,
		"map": map.to_dict(),
		"players": player_data,
	}


static func write_file(data: Dictionary, path := FILE) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


## The saved game, or {} if there isn't a readable one.
static func read_file(path := FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
		return {}
	return parsed


# --- Helpers for the to_dict / load_dict functions --------------------------

static func hex_to_data(h: Vector2i) -> Array:
	return [h.x, h.y]


static func hex_from_data(data: Variant) -> Vector2i:
	return Vector2i(int(data[0]), int(data[1]))


## {ResourceDeposit.Type: amount} -> {"BIOMASS": amount}
static func resources_to_data(resources: Dictionary) -> Dictionary:
	var data := {}
	for type in resources:
		data[ResourceDeposit.Type.keys()[type]] = resources[type]
	return data


static func resources_from_data(data: Dictionary) -> Dictionary:
	var resources := {}
	for type_name in data:
		resources[ResourceDeposit.Type[type_name]] = int(data[type_name])
	return resources
