class_name UnitBlueprint
extends RefCounted
## A unit a hub can train. All the numbers (name, cost, training time,
## upkeep) are read from the unit's own script, so each unit's data lives in
## one place: its file in scripts/units/.

var unit_name: String
## ResourceDeposit.Type -> int
var cost: Dictionary
var train_turns: int
## Biomass the unit will eat per turn once trained.
var upkeep: int
var _unit_script: GDScript


func _init(p_unit_script: GDScript) -> void:
	_unit_script = p_unit_script
	# Build a throwaway copy just to read the values its _init() sets.
	var template: Unit = p_unit_script.new()
	unit_name = template.unit_name
	cost = template.cost
	train_turns = template.train_turns
	upkeep = template.upkeep
	template.free()


func create_unit() -> Unit:
	return _unit_script.new()


func get_cost_text() -> String:
	return ResourceDeposit.format_cost(cost)
