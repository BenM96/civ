class_name ResourceDeposit
extends RefCounted
## A finite pile of a resource sitting on a tile, harvested by Workers or
## mined by an Extractor.
##
## Each resource's data (name, colour, where it spawns, what Workers and
## Extractors get from it, its icon) lives in its own file in
## scripts/resources/ - see ResourceType. To add a new resource: add it to
## Type, write its file, and list it in _type_scripts().

enum Type { BIOMASS, TITANIUM, SEDIMENT, GOLD, ELECTRUM }

## Every resource's script. Deposits are placed in this order, one per tile
## at most - Gold first, as it's rare and small, so commoner resources don't
## crowd it out.
static func _type_scripts() -> Array:
	return [GoldResource, TitaniumResource, SedimentResource, BiomassResource, ElectrumResource]

## Type -> ResourceType, made on first use.
static var _infos: Dictionary = {}


## Everything about a resource type (see ResourceType).
static func get_info(type: Type) -> ResourceType:
	if _infos.is_empty():
		for script in _type_scripts():
			var info: ResourceType = script.new()
			_infos[info.type] = info
	return _infos[type]


## Every resource type's info, in placement order (see _type_scripts()).
static func all_infos() -> Array[ResourceType]:
	get_info(Type.BIOMASS)  # Make sure they exist.
	var result: Array[ResourceType] = []
	result.assign(_infos.values())
	return result


## Whether this resource type can spawn on `terrain`.
static func can_spawn_on(type: Type, terrain: Terrain.Type) -> bool:
	return get_info(type).can_spawn_on(terrain)


## Formats a cost dictionary (Type -> amount) as e.g. "2 Biomass, 1 Titanium"
## (amounts may be fractions, like income: "0.4 Titanium").
static func format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for type in cost:
		parts.append("%s %s" % [format_amount(cost[type]), get_type_name(type)])
	return ", ".join(parts)


## An amount as short text: 3 -> "3", 0.2 -> "0.2", 0.6000001 -> "0.6".
static func format_amount(amount: float) -> String:
	var rounded := snappedf(amount, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(roundi(rounded))
	return String.num(rounded, 2)


## A change per turn with its sign: "+3", "-0.8", "0".
static func format_change(amount: float) -> String:
	var text := format_amount(amount)
	return "+" + text if amount > 0 and text != "0" else text


static func get_type_name(type: Type) -> String:
	return get_info(type).display_name


static func get_type_color(type: Type) -> Color:
	return get_info(type).color

var type: Type
var coord: Vector2i
var amount := 0


func _init(p_type: Type, p_coord: Vector2i, p_amount: int) -> void:
	type = p_type
	coord = p_coord
	amount = p_amount


## Creates a deposit with a random amount in the type's configured range.
static func create_random(p_type: Type, p_coord: Vector2i, rng: RandomNumberGenerator) -> ResourceDeposit:
	var info := get_info(p_type)
	return ResourceDeposit.new(p_type, p_coord, rng.randi_range(info.min_amount, info.max_amount))


func get_info_for_type() -> ResourceType:
	return get_info(type)


func get_display_name() -> String:
	return get_info(type).display_name


func get_color() -> Color:
	return get_info(type).color


func is_depleted() -> bool:
	return amount <= 0


## Removes up to `requested` from the deposit and returns how much was taken.
func extract(requested: int) -> int:
	var taken := mini(requested, amount)
	amount -= taken
	return taken


func get_info_text() -> String:
	return "%s deposit: %d" % [get_display_name(), amount]
