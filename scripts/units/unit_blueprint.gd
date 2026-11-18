class_name UnitBlueprint
extends RefCounted
## Describes a unit a hub can train: what it costs and how long it takes.

var unit_name: String
## ResourceDeposit.Type -> int
var cost: Dictionary
var train_turns: int
var _unit_script: GDScript


func _init(p_unit_name: String, p_unit_script: GDScript, p_cost: Dictionary, p_train_turns: int) -> void:
	unit_name = p_unit_name
	_unit_script = p_unit_script
	cost = p_cost
	train_turns = p_train_turns


func create_unit() -> Unit:
	return _unit_script.new()


func get_cost_text() -> String:
	return ResourceDeposit.format_cost(cost)
