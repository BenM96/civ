class_name ResourceDeposit
extends RefCounted
## A finite pile of a resource sitting on a tile. Units will later be sent on
## missions to harvest it; for now deposits are generated and shown on the map.
##
## To add a new resource: add it to Type and give it an entry in DATA.

enum Type { BIOMASS, TITANIUM, SEDIMENT }

## spawn_chance: chance per eligible tile; terrains: where it can appear.
## Deposits are placed in the order listed here, one per tile at most.
const DATA := {
	Type.TITANIUM: {
		"name": "Titanium",
		"color": Color(0.62, 0.78, 1.0),
		"min_amount": 20,
		"max_amount": 60,
		"spawn_chance": 0.14,
		"terrains": [Terrain.Type.HIGHLANDS],
	},
	Type.SEDIMENT: {
		"name": "Sediment",
		"color": Color(0.97, 0.93, 0.8),
		"min_amount": 60,
		"max_amount": 160,
		"spawn_chance": 0.08,
		"terrains": [Terrain.Type.DUST_PLAINS, Terrain.Type.DUNES],
	},
	Type.BIOMASS: {
		"name": "Biomass",
		"color": Color(0.45, 0.95, 0.4),
		"min_amount": 40,
		"max_amount": 120,
		"spawn_chance": 0.07,
		"terrains": [Terrain.Type.REGOLITH, Terrain.Type.DUST_PLAINS, Terrain.Type.DUNES, Terrain.Type.HIGHLANDS],
	},
}


## Whether this resource type can spawn on `terrain`.
static func can_spawn_on(type: Type, terrain: Terrain.Type) -> bool:
	return terrain in DATA[type]["terrains"]


## Formats a cost dictionary (Type -> int) as e.g. "2 Biomass, 1 Titanium".
static func format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for type in cost:
		parts.append("%d %s" % [cost[type], get_type_name(type)])
	return ", ".join(parts)


static func get_type_name(type: Type) -> String:
	return DATA[type]["name"]


static func get_type_color(type: Type) -> Color:
	return DATA[type]["color"]

var type: Type
var coord: Vector2i
var amount := 0


func _init(p_type: Type, p_coord: Vector2i, p_amount: int) -> void:
	type = p_type
	coord = p_coord
	amount = p_amount


## Creates a deposit with a random amount in the type's configured range.
static func create_random(p_type: Type, p_coord: Vector2i, rng: RandomNumberGenerator) -> ResourceDeposit:
	var data: Dictionary = DATA[p_type]
	return ResourceDeposit.new(p_type, p_coord, rng.randi_range(data["min_amount"], data["max_amount"]))


func get_display_name() -> String:
	return DATA[type]["name"]


func get_color() -> Color:
	return DATA[type]["color"]


func is_depleted() -> bool:
	return amount <= 0


## Removes up to `requested` from the deposit and returns how much was taken.
func extract(requested: int) -> int:
	var taken := mini(requested, amount)
	amount -= taken
	return taken


func get_info_text() -> String:
	return "%s deposit: %d" % [get_display_name(), amount]
