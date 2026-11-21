class_name UnitBlueprint
extends RefCounted
## A unit a hub can train. All the numbers (name, cost, training time,
## upkeep) are read from the unit's own script, so each unit's data lives in
## one place: its file in scripts/units/<type>/ (e.g. armour/tank.gd).

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
	cost_growth = template.cost_growth
	cost_rises_after = template.cost_rises_after
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
##  Missions: move, guard, escort, qrf"
func get_info_text() -> String:
	var lines: PackedStringArray = ["%s - %d HP." % [Unit.get_type_name(unit_type), _max_health]]
	if _shots_per_turn > 1:
		lines[0] += " Fires %d shots a turn." % _shots_per_turn
	if _refit_turns > 0:
		lines[0] += " Refits for %d turns after each sortie." % _refit_turns
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
