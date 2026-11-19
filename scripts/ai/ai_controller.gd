class_name AiController
extends RefCounted
## Plays a rival colony. It follows the same rules as the player: it can only
## give missions to units waiting in its hub, pays the same costs, and its
## units walk out and back on their own.
##
## Each turn (called just before the turn resolves, so its orders depart at
## the same time as the player's) it:
##   1. Growth: if its biomass income is at least MIN_BIOMASS_INCOME_TO_GROW,
##      it wants another unit - Workers until it has WANTED_WORKERS, then
##      Infantry (up to MAX_UNITS in total). It trains one if it can afford
##      it; if not, construction pauses and every idle worker gathers what
##      that unit costs (step 3).
##   2. Construction (when not saving up for a unit): puts every idle worker
##      it can afford to work connecting the nearest deposit - first a road
##      to it, then a conveyor belt along the road, then an extractor on it.
##   3. Sends remaining idle workers to harvest only what step 1 or 2 is
##      short of (the most pressing needs first). If nothing is short, they
##      wait at home. Never Biomass, which it only gets from extractors.

## How many workers the rival tries to keep.
const WANTED_WORKERS := 5
const MAX_UNITS := 8
## Longest conveyor line it will lay to reach a deposit.
const MAX_BELT_LENGTH := 8
## Workers only travel this far (hex distance) to harvest.
const MAX_HARVEST_DISTANCE := 12
## Biomass income per turn (hub + extractors - unit upkeep) at which the AI
## stops building and focuses on getting more units.
const MIN_BIOMASS_INCOME_TO_GROW := 2

var hub: CentralHub
var map: HexMap
## Resources the rest of the current project is short of (Type -> amount),
## so idle workers know what to harvest. Empty when it can all be paid for.
var _needed: Dictionary = {}
## Of those, the types the very next step needs - harvested first.
var _urgent: Dictionary = {}


## Where the AI sends its orders - the same place the human players' go, so
## it plays by exactly the same rules.
var orders: Orders


func _init(p_hub: CentralHub, p_map: HexMap, p_orders: Orders) -> void:
	hub = p_hub
	map = p_map
	orders = p_orders


## Sends an order for our colony. Returns true if it was carried out.
func _order(order: Dictionary) -> bool:
	return orders.submit(hub.faction, order) == ""


func take_turn() -> void:
	var saving_for_unit := _plan_growth()
	if not saving_for_unit:
		_plan_construction()
	_plan_harvesting()


# --- Growth ----------------------------------------------------------------

## Trains the unit we want next if we can afford it. If we can't, puts its
## shortfall in _needed so idle workers gather it, and returns true (we're
## saving up, so don't spend on construction). Returns false when we don't
## want a unit right now, or can't gather what it needs.
func _plan_growth() -> bool:
	_needed = {}
	_urgent = {}
	var bp := _wanted_unit()
	if bp == null:
		return false
	# One at a time: wait for the current one to finish before buying another.
	if hub.training_queue.is_empty() and _order(Orders.train(bp.unit_name)):
		bp = _wanted_unit()  # The next one, which now costs double.
		if bp == null:
			return false
	var short := _shortfall(hub.get_training_cost(bp))
	short.erase(ResourceDeposit.Type.BIOMASS)  # Never harvested by hand.
	if short.is_empty():
		return false  # Can pay already; build in the meantime.
	if not _can_gather_all(short):
		return false  # Something it needs isn't in reach; keep building instead.
	_needed = short
	_urgent = short
	return true


## The blueprint of the unit we want next, or null if we shouldn't grow now
## (not enough biomass income to feed it, or at MAX_UNITS).
func _wanted_unit() -> UnitBlueprint:
	if hub.units.size() + hub.training_queue.size() >= MAX_UNITS:
		return null
	if _biomass_income() < MIN_BIOMASS_INCOME_TO_GROW:
		return null
	var workers := _count_units(func(u: Unit) -> bool: return u is Worker)
	for order in hub.training_queue:
		if order.blueprint.unit_name == "Worker":
			workers += 1
	return hub.get_blueprint("Worker" if workers < WANTED_WORKERS else "Infantry")


## Biomass gained per turn after every unit has eaten.
func _biomass_income() -> int:
	return hub.get_net_income()[ResourceDeposit.Type.BIOMASS]


## Whether every one of these resource types has an unworked deposit within
## harvesting range (or an extractor already bringing it in). Saving up is
## pointless if even one of them can never be got.
func _can_gather_all(types: Dictionary) -> bool:
	var income := hub.get_income()
	for type in types:
		if income.get(type, 0) > 0:
			continue
		var found := false
		for h in map.tiles:
			var tile: HexTile = map.tiles[h]
			if tile.has_deposit() and tile.deposit.type == type \
					and tile.structure != Structure.Type.EXTRACTOR \
					and Hex.distance(hub.hex, h) <= MAX_HARVEST_DISTANCE:
				found = true
				break
		if not found:
			return false
	return true


func _count_units(pred: Callable) -> int:
	var count := 0
	for u in hub.units:
		if pred.call(u):
			count += 1
	return count


# --- Construction ----------------------------------------------------------

## Gives every idle worker the next step of the current project that it can
## afford, then records in _needed / _urgent what the rest of the project is
## short of, so other idle workers harvest it (see _plan_harvesting).
func _plan_construction() -> void:
	_needed = {}
	_urgent = {}
	var tasks := _construction_tasks()
	if tasks.is_empty():
		return
	var taken := _targets_in_progress()
	# Jobs nobody is working on yet, in order. The first is "the next step".
	var open_tasks := tasks.filter(func(task: Array) -> bool: return not taken.has(task[0]))
	# Only jobs from the earliest unfinished phase may start.
	var phase: int = tasks[0][2]
	for u in hub.get_units_needing_orders():
		if open_tasks.is_empty() or open_tasks[0][2] != phase:
			break
		if not u.can_take("build"):
			continue
		if not _order(Orders.mission(u, "build:" + open_tasks[0][1], open_tasks[0][0])):
			break  # Usually: can't afford it yet.
		open_tasks.pop_front()
	# Look ahead over every step still to start - including ones waiting for
	# this phase to finish - and work out what we can't yet pay for.
	if open_tasks.is_empty():
		return
	var total := {}
	for task: Array in open_tasks:
		var cost: Dictionary = hub.get_buildable(task[1]).cost
		for type in cost:
			total[type] = total.get(type, 0) + cost[type]
	_needed = _shortfall(total)
	_urgent = _shortfall(hub.get_buildable(open_tasks[0][1]).cost)


## What we're missing to pay `cost`: ResourceDeposit.Type -> amount.
func _shortfall(cost: Dictionary) -> Dictionary:
	var missing := {}
	for type in cost:
		var short: int = cost[type] - hub.get_resource(type)
		if short > 0:
			missing[type] = short
	return missing


## Every job left in the current project, in order, as
## [hex, buildable id, phase] - one phase finishes before the next starts:
##   0. Roads along the route from our network to the deposit (and on it).
##   1. Conveyor belts along the same route, nearest the hub first.
##   2. The extractor on the deposit.
func _construction_tasks() -> Array:
	var project := _find_project()
	if project.is_empty():
		return []
	var deposit_hex: Vector2i = project["deposit"]
	var belts: Array[Vector2i] = project["belts"]
	var tasks := []
	var road := hub.get_buildable("road")
	for h: Vector2i in belts + [deposit_hex]:
		if road.get_invalid_reason(map, h) == "":
			tasks.append([h, "road", 0])
	for h: Vector2i in belts:
		tasks.append([h, "conveyor", 1])
	if map.get_tile(deposit_hex).structure == Structure.Type.NONE:
		tasks.append([deposit_hex, "extractor", 2])
	return tasks


## Breadth-first search out from our supply network over tiles a conveyor
## could be laid on, stopping at the first deposit we could tap: either a
## free deposit or one of our own extractors that isn't connected yet.
## Returns {"deposit": hex, "belts": [hexes needing a conveyor]} or {}.
func _find_project() -> Dictionary:
	var parent := {}
	var depth := {}
	var frontier: Array[Vector2i] = []
	for h in map.tiles:
		if hub.is_supply_connected(h):
			parent[h] = h
			depth[h] = 0
			frontier.append(h)
	var conveyor := hub.get_buildable("conveyor")
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for n in Hex.neighbors(current):
			if parent.has(n) or not map.has_tile(n):
				continue
			var tile := map.get_tile(n)
			if _is_tappable(tile):
				return {"deposit": n, "belts": _belts_back_from(current, parent)}
			if depth[current] < MAX_BELT_LENGTH and map.get_hub_at(n) == null \
					and conveyor.get_invalid_reason(map, n) == "" \
					and not map.find_path(hub.hex, n).is_empty():
				parent[n] = current
				depth[n] = depth[current] + 1
				frontier.append(n)
	return {}


func _is_tappable(tile: HexTile) -> bool:
	if not tile.has_deposit():
		return false
	if map.find_path(hub.hex, tile.coord).is_empty():
		return false
	if tile.structure == Structure.Type.NONE:
		return true
	return tile.structure == Structure.Type.EXTRACTOR and tile.structure_owner == hub.faction \
		and not hub.is_supply_connected(tile.coord)


## Walks the search tree from `h` back to the network, collecting the tiles
## that still need a conveyor (nearest the hub first).
func _belts_back_from(h: Vector2i, parent: Dictionary) -> Array[Vector2i]:
	var belts: Array[Vector2i] = []
	var current := h
	while parent[current] != current:
		belts.push_front(current)
		current = parent[current]
	return belts


## Tiles our units are already heading to build on or harvest.
func _targets_in_progress() -> Dictionary:
	var taken := {}
	for u in hub.units:
		if u.mission:
			var target: Variant = u.mission.get_target_hex()
			if target != null:
				taken[target] = true
	return taken


# --- Harvesting ------------------------------------------------------------

## Sends idle workers to fetch what construction is short of (_needed),
## counting what's already on its way home. Workers with nothing needed
## stay in the hub. Never Biomass: the rival only gets Biomass from its hub
## and extractors.
func _plan_harvesting() -> void:
	var still_needed := {}
	var incoming := _incoming_resources()
	for type in _needed:
		if type != ResourceDeposit.Type.BIOMASS:
			var short: int = _needed[type] - incoming.get(type, 0)
			if short > 0:
				still_needed[type] = short
	var taken := _targets_in_progress()
	for worker in hub.get_units_needing_orders():
		if still_needed.is_empty():
			return
		if not worker.can_take("harvest"):
			continue
		var target: Variant = _pick_harvest_target(worker, still_needed, taken)
		if target == null or not _order(Orders.mission(worker, "harvest", target)):
			continue
		taken[target] = true
		var type: ResourceDeposit.Type = map.get_tile(target).deposit.type
		still_needed[type] -= HarvestMission.HARVEST_AMOUNT
		if still_needed[type] <= 0:
			still_needed.erase(type)


## Resources our units are bringing home: carried, or about to be harvested.
func _incoming_resources() -> Dictionary:
	var incoming := {}
	for u in hub.units:
		for type in u.cargo:
			incoming[type] = incoming.get(type, 0) + u.cargo[type]
		if u.mission is HarvestMission:
			var tile := map.get_tile(u.mission.target)
			if tile and tile.has_deposit():
				incoming[tile.deposit.type] = incoming.get(tile.deposit.type, 0) + HarvestMission.HARVEST_AMOUNT
	return incoming


## The nearest deposit of a resource in `wanted` (the next step's needs
## first), skipping deposits already being worked, or null.
func _pick_harvest_target(worker: Unit, wanted: Dictionary, taken: Dictionary) -> Variant:
	var types: Array = wanted.keys()
	types.sort_custom(func(a, b) -> bool: return _urgent.has(a) and not _urgent.has(b))
	for type in types:
		var best: Variant = null
		var best_distance := MAX_HARVEST_DISTANCE + 1
		for h in map.tiles:
			var tile: HexTile = map.tiles[h]
			if not tile.has_deposit() or tile.deposit.type != type or taken.has(h):
				continue
			if tile.structure == Structure.Type.EXTRACTOR:
				continue  # Already being mined.
			var d := Hex.distance(hub.hex, h)
			if d < best_distance and HarvestMission.new(h).get_invalid_reason(worker) == "":
				best = h
				best_distance = d
		if best != null:
			return best
	return null
