class_name UnitBlueprint
extends RefCounted
## A unit a hub can train. All the numbers (name, cost, training time,
## upkeep) are read from the unit's own script, so each unit's data lives in
## one place: its file in scripts/units/.

var unit_name: String
## The price of the first one: ResourceDeposit.Type -> int. The real price
## goes up with how many a colony has built - see cost_for().
var base_cost: Dictionary
## How the price rises, and after how many built (see Unit.cost_growth).
var cost_growth: Unit.CostGrowth
var cost_rises_after: int
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
	cost_growth = template.cost_growth
	cost_rises_after = template.cost_rises_after
	train_turns = template.train_turns
	upkeep = template.upkeep
	template.free()


## The price of one more, for a colony that has built `built` of this unit so
## far (including any lost since, and any in training): base_cost, raised
## once for every one beyond cost_rises_after. E.g. with cost_rises_after = 1
## and base 1 Gold: built 0 or 1 -> 1, then DOUBLE: 2, 4, 8...; ADD_ONE: 2, 3, 4...
func cost_for(built: int) -> Dictionary:
	var rises := maxi(built - cost_rises_after, 0)
	var cost := {}
	for type in base_cost:
		match cost_growth:
			Unit.CostGrowth.ADD_ONE:
				cost[type] = base_cost[type] + rises
			_:
				cost[type] = base_cost[type] * (1 << rises)
	return cost


## How the price rises, for tooltips.
func get_cost_growth_text() -> String:
	if cost_growth == Unit.CostGrowth.ADD_ONE:
		return "Each %s you build adds 1 of each resource to the price of the next, even if it's later lost." % unit_name
	return "Each %s you build doubles the price of the next, even if it's later lost." % unit_name


func create_unit() -> Unit:
	return _unit_script.new()
