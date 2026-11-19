class_name UnitBlueprint
extends RefCounted
## A unit a hub can train. All the numbers (name, cost, training time,
## upkeep) are read from the unit's own script, so each unit's data lives in
## one place: its file in scripts/units/.

var unit_name: String
## The price of the first one: ResourceDeposit.Type -> int. The real price
## goes up with how many a colony has built - see cost_for().
var base_cost: Dictionary
## How many of this unit a colony can have built before the price starts
## doubling.
var cost_doubling_after: int
var train_turns: int
## Biomass the unit will eat per turn once trained.
var upkeep: int
var _unit_script: GDScript


func _init(p_unit_script: GDScript) -> void:
	_unit_script = p_unit_script
	# Build a throwaway copy just to read the values its _init() sets.
	var template: Unit = p_unit_script.new()
	unit_name = template.unit_name
	base_cost = template.cost
	cost_doubling_after = template.cost_doubling_after
	train_turns = template.train_turns
	upkeep = template.upkeep
	template.free()


## The price of one more, for a colony that has built `built` of this unit so
## far (including any lost since, and any in training): base_cost, doubled
## for every one beyond cost_doubling_after. E.g. with cost_doubling_after = 1:
## built 0 or 1 -> x1, 2 -> x2, 3 -> x4, 4 -> x8.
func cost_for(built: int) -> Dictionary:
	var multiplier := 1 << maxi(built - cost_doubling_after, 0)
	var cost := {}
	for type in base_cost:
		cost[type] = base_cost[type] * multiplier
	return cost


func create_unit() -> Unit:
	return _unit_script.new()
