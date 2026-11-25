class_name UnitBlueprint
extends RefCounted
## A unit a hub can train. All the numbers (name, cost, training time,
## upkeep) are read from the unit's own script, so each unit's data lives in
## one place: its file in scripts/units/<type>/ (e.g. armour/tank.gd).

var unit_name: String
## The price of one: ResourceDeposit.Type -> int (see Player.get_training_cost()).
var base_cost: Dictionary
var train_turns: int
## Biomass the unit will eat per turn once trained.
var upkeep: int
## What kind of unit it trains (decides which hub room holds it while in
## training - see Room.holds_training()).
var unit_type: Unit.UnitType
## What a trained one is like, for tooltips (see get_info_text()).
var _damage: Dictionary
var _shots_per_turn: int
var _allowed_missions: Array[String]
var _refit_turns: int
var _max_health: int
var _target_preference: Array
var _unit_script: GDScript


func _init(p_unit_script: GDScript) -> void:
	_unit_script = p_unit_script
	# Build a throwaway copy just to read the values its _init() sets.
	var template: Unit = p_unit_script.new()
	unit_name = template.unit_name
	base_cost = template.cost
	train_turns = template.train_turns
	upkeep = template.upkeep
	unit_type = template.unit_type
	_damage = template.damage
	_shots_per_turn = template.shots_per_turn
	_allowed_missions = template.allowed_missions
	_refit_turns = template.refit_turns
	_max_health = template.max_health
	_target_preference = template.get_target_preference()
	template.free()


## What the unit is and does, for tooltips, e.g.
## "Armour - 10 HP. Fires 2 shots a turn.
##  Damage: Infantry 8, Civilian 8, Armour 4, Air 2
##  Missions: move, escort, qrf"
func get_info_text() -> String:
	var lines: PackedStringArray = ["%s - %d HP." % [Unit.get_type_name(unit_type), _max_health]]
	if _shots_per_turn > 1:
		lines[0] += " Fires %d shots a turn." % _shots_per_turn
	if _refit_turns > 0:
		lines[0] += " Refits (and is repaired) for %d turns after each flight." % _refit_turns
	var hits: PackedStringArray = []
	for type in [Unit.UnitType.INFANTRY, Unit.UnitType.CIVILIAN, Unit.UnitType.ARMOUR, Unit.UnitType.AIR]:
		hits.append("%s %d" % [Unit.get_type_name(type), _damage.get(type, 0)])
	lines.append("Damage: " + ", ".join(hits))
	var order: PackedStringArray = []
	for group: Array in _target_preference:
		order.append(" / ".join(group.map(func(t: Unit.UnitType) -> String: return Unit.get_type_name(t))))
	lines.append("Shoots first: " + ", then ".join(order))
	lines.append("Missions: " + ", ".join(_allowed_missions))
	return "\n".join(lines)


func create_unit() -> Unit:
	return _unit_script.new()


## Damage one shot does to a unit of `type` (before any Weapons tech).
func get_damage(type: Unit.UnitType) -> int:
	return _damage.get(type, 0)
