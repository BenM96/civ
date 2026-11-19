class_name AiController
extends RefCounted
## Plays a computer-controlled colony. It follows the same rules as the
## players: it can only give orders (through Orders) to units waiting in its
## hub, pays the same costs, and its units walk out and back on their own.
##
## Each turn (just before the turn resolves, so its orders depart at the same
## time as everyone else's), in order of priority:
##   1. Grow - if its biomass income is at least MIN_BIOMASS_INCOME_TO_GROW,
##      it wants another unit: whichever is cheapest right now (a Worker on a
##      tie; only Workers until it has WORKERS_BEFORE_INFANTRY). It trains it if it can pay; otherwise idle workers go and
##      harvest what it costs. (If something it costs can't be gathered
##      anywhere in range, it builds extractors instead.)
##   2. Extractors - with less biomass income than that, it builds extractors,
##      nearest deposit first (Biomass deposits first while its biomass
##      income is negative), using the "Build Extractor" order (which also
##      lays the foundations and belts to the hub). A worker is only sent once
##      the whole job can be paid for; until then idle workers harvest what's
##      missing.
##   3. Attack - idle Infantry go and demolish other colonies' extractors and
##      belts, nearest first. With none left to demolish, they guard a tile
##      next to the nearest enemy hub (killing workers who come and go).
## Workers never harvest Biomass by hand - it only comes from the hub and
## extractors.

## Biomass income per turn (hub + extractors - unit upkeep) at which the AI
## trains more units rather than building extractors.
const MIN_BIOMASS_INCOME_TO_GROW := 1
## The AI only trains Infantry once it has this many Workers (if Workers
## die, it rebuilds them before more Infantry).
const WORKERS_BEFORE_INFANTRY := 3
## Workers only travel this far (hex distance) to harvest.
const MAX_HARVEST_DISTANCE := 12
## Extractors are only planned on deposits this close to the hub.
const MAX_EXTRACTOR_DISTANCE := 12

var hub: CentralHub
var map: HexMap
## Where the AI sends its orders - the same place the human players' go, so
## it plays by exactly the same rules.
var orders: Orders
## Resources the current plan is short of (Type -> amount), so idle workers
## know what to harvest. Empty when nothing is needed.
var _needed: Dictionary = {}


func _init(p_hub: CentralHub, p_map: HexMap, p_orders: Orders) -> void:
	hub = p_hub
	map = p_map
	orders = p_orders


## Sends an order for our colony. Returns true if it was carried out.
func _order(order: Dictionary) -> bool:
	return orders.submit(hub.faction, order) == ""


func take_turn() -> void:
	_needed = {}
	var growing := _biomass_income() >= MIN_BIOMASS_INCOME_TO_GROW and _plan_growth()
	if not growing:
		_plan_extractors()
	_plan_harvesting()
	_plan_attacks()


## Biomass gained per turn after every unit has eaten.
func _biomass_income() -> float:
	return hub.get_net_income()[ResourceDeposit.Type.BIOMASS]


# --- 1. Growth -------------------------------------------------------------

## Trains the cheapest unit if we can pay; otherwise sets _needed to what it
## costs so workers gather it. Returns false if growing isn't possible (what
## it costs can't be gathered), so the AI builds extractors instead.
func _plan_growth() -> bool:
	var bp := _cheapest_unit()
	# One at a time: the next is bought once the current one has finished.
	if hub.training_queue.is_empty() and _order(Orders.train(bp.unit_name)):
		bp = _cheapest_unit()  # Gather for the one after.
	var short := _shortfall(hub.get_training_cost(bp))
	short.erase(ResourceDeposit.Type.BIOMASS)
	if short.is_empty():
		return true  # Can pay; trained as soon as the queue is free.
	if not _can_gather_all(short):
		return false
	_needed = short
	return true


## The unit that costs least to train right now (by total resources), a
## Worker if tied. Only Workers until we have WORKERS_BEFORE_INFANTRY.
func _cheapest_unit() -> UnitBlueprint:
	var best: UnitBlueprint = null
	var best_total := 1 << 30
	var workers_only := _worker_count() < WORKERS_BEFORE_INFANTRY
	for bp in hub.blueprints:
		if workers_only and bp.unit_name != "Worker":
			continue
		var total := 0
		var cost := hub.get_training_cost(bp)
		for type in cost:
			total += cost[type]
		if total < best_total or (total == best_total and bp.unit_name == "Worker"):
			best = bp
			best_total = total
	return best


## Workers we have, counting any being trained.
func _worker_count() -> int:
	var count := 0
	for u in hub.units:
		if u.unit_name == "Worker":
			count += 1
	for t in hub.training_queue:
		if t.blueprint.unit_name == "Worker":
			count += 1
	return count


# --- 2. Extractors ---------------------------------------------------------

## Sends idle workers to build extractors (with their foundations and belts),
## nearest deposit first, as long as each whole job can be paid for. Then
## sets _needed to what the next one is short of.
func _plan_extractors() -> void:
	var budget := hub.inventory.duplicate()  # What's left after this turn's orders.
	var taken := _targets_in_progress()
	var idle: Array[Unit] = []
	for u in hub.get_units_needing_orders():
		if u.can_take("build"):
			idle.append(u)
	while true:
		var project := _next_extractor_project(taken)
		if project.is_empty():
			return
		var dep: Vector2i = project[0]
		var cost: Dictionary = project[1]
		if idle.is_empty() or not _fits(cost, budget):
			# Can't start it now: gather what it's missing.
			var short := {}
			for type in cost:
				var s: int = cost[type] - budget.get(type, 0)
				if s > 0:
					short[type] = s
			_needed = short
			return
		if not _order(Orders.mission(idle.pop_front(), "build:extractor", dep)):
			return
		taken[dep] = true
		for type in cost:
			budget[type] = budget.get(type, 0) - cost[type]


## The deposit with the shortest walk from the hub that we could put an
## extractor on (and run belts to), as [hex, total cost of everything to
## build], or [] if there's none. While biomass income is negative (heading
## for starvation), Biomass deposits come first.
func _next_extractor_project(taken: Dictionary) -> Array:
	var biomass_first := _biomass_income() < 0
	var walk := {}
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		var free := tile.structure == Structure.Type.NONE \
			or (tile.structure == Structure.Type.CONVEYOR and tile.structure_owner == hub.faction)
		if tile.has_deposit() and free and not taken.has(h) \
				and Hex.distance(hub.hex, h) <= MAX_EXTRACTOR_DISTANCE:
			var path := map.find_path(hub.hex, h)
			if not path.is_empty():
				walk[h] = map.get_path_cost(path)
	var candidates: Array[Vector2i] = []
	candidates.assign(walk.keys())
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if biomass_first:
			var a_bio := map.get_tile(a).deposit.type == ResourceDeposit.Type.BIOMASS
			var b_bio := map.get_tile(b).deposit.type == ResourceDeposit.Type.BIOMASS
			if a_bio != b_bio:
				return a_bio
		return walk[a] < walk[b])
	for h in candidates:
		var m: LineBuildMission = Orders.make_mission(hub, "build:extractor", h)
		if m.plan_route(hub, map, hub.hex, h).is_empty():
			continue  # No way to run belts there.
		return [h, m.get_total_cost(hub, map, hub.hex)]
	return []


func _fits(cost: Dictionary, budget: Dictionary) -> bool:
	for type in cost:
		if budget.get(type, 0) < cost[type]:
			return false
	return true


# --- 3. Attack -------------------------------------------------------------

## Sends idle Infantry to demolish other colonies' extractors and belts,
## nearest first; with none left, to guard beside the nearest enemy hub.
func _plan_attacks() -> void:
	var taken := _targets_in_progress()
	for u in hub.get_units_needing_orders():
		if not u.can_take("demolish"):
			continue
		var target: Variant = _nearest_enemy_structure(u, taken)
		if target != null and _order(Orders.mission(u, "demolish", target)):
			taken[target] = true
			continue
		if not u.can_take("guard"):
			continue
		var post: Variant = _post_by_enemy_hub(u, taken)
		if post != null and _order(Orders.mission(u, "guard", post)):
			taken[post] = true


## The nearest structure belonging to another colony that `u` could
## demolish, or null.
func _nearest_enemy_structure(u: Unit, taken: Dictionary) -> Variant:
	var candidates: Array[Vector2i] = []
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		if tile.structure != Structure.Type.NONE and tile.structure_owner != hub.faction \
				and tile.structure_owner != Faction.NONE and not taken.has(h):
			candidates.append(h)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Hex.distance(hub.hex, a) < Hex.distance(hub.hex, b))
	for h in candidates:
		var m := Orders.make_mission(hub, "demolish", h)
		if Orders.get_invalid_reason(hub, u, m) == "":
			return h
	return null


## A free tile next to the nearest other colony's hub that `u` can guard,
## or null.
func _post_by_enemy_hub(u: Unit, taken: Dictionary) -> Variant:
	var enemies: Array = []
	for faction in map.hubs:
		var other: CentralHub = map.hubs[faction]
		if other != hub and not other.collapsed:
			enemies.append(other)
	enemies.sort_custom(func(a: CentralHub, b: CentralHub) -> bool:
		return Hex.distance(hub.hex, a.hex) < Hex.distance(hub.hex, b.hex))
	for enemy: CentralHub in enemies:
		for n in Hex.neighbors(enemy.hex):
			if taken.has(n):
				continue
			var m := Orders.make_mission(hub, "guard", n)
			if Orders.get_invalid_reason(hub, u, m) == "":
				return n
	return null


# --- Shared helpers --------------------------------------------------------

## What we're missing to pay `cost`: ResourceDeposit.Type -> amount.
func _shortfall(cost: Dictionary) -> Dictionary:
	var missing := {}
	for type in cost:
		var short: int = cost[type] - hub.get_resource(type)
		if short > 0:
			missing[type] = short
	return missing


## Whether every one of these resource types has an unworked deposit within
## harvesting range (or an extractor already bringing it in). Saving up is
## pointless if even one of them can never be got.
func _can_gather_all(types: Dictionary) -> bool:
	var income := hub.get_income()
	for type in types:
		if income.get(type, 0) > 0:
			continue
		if not ResourceDeposit.get_info(type).can_harvest:
			return false
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


## Tiles our units are already heading to build on, harvest or attack.
func _targets_in_progress() -> Dictionary:
	var taken := {}
	for u in hub.units:
		if u.mission:
			var target: Variant = u.mission.get_target_hex()
			if target != null:
				taken[target] = true
	return taken


# --- Harvesting ------------------------------------------------------------

## Sends idle workers to fetch what the plan is short of (_needed), counting
## what's already on its way home. Each goes to the deposit of any needed
## resource that's the shortest walk from the hub; several can share one
## deposit while it has enough left for all of them. Workers with nothing
## needed stay in the hub. Never Biomass.
func _plan_harvesting() -> void:
	var still_needed := {}
	var incoming := _incoming_resources()
	for type in _needed:
		if type != ResourceDeposit.Type.BIOMASS:
			var short: int = _needed[type] - incoming.get(type, 0)
			if short > 0:
				still_needed[type] = short
	if still_needed.is_empty():
		return
	var idle: Array[Unit] = []
	for worker in hub.get_units_needing_orders():
		if worker.can_take("harvest"):
			idle.append(worker)
	if idle.is_empty():
		return
	var deposits := _harvestable_deposits_by_walk(still_needed)
	# How many of our workers are already heading for each deposit.
	var reserved := {}
	for u in hub.units:
		if u.mission is HarvestMission:
			reserved[u.mission.target] = reserved.get(u.mission.target, 0) + 1
	for worker in idle:
		if still_needed.is_empty():
			return
		for h: Vector2i in deposits:
			var deposit := map.get_tile(h).deposit
			if deposit == null or not still_needed.has(deposit.type):
				continue
			if deposit.amount <= reserved.get(h, 0) * ResourceDeposit.get_info(deposit.type).harvest_amount:
				continue  # Others will empty it before this worker gets there.
			if not _order(Orders.mission(worker, "harvest", h)):
				continue
			reserved[h] = reserved.get(h, 0) + 1
			still_needed[deposit.type] -= ResourceDeposit.get_info(deposit.type).harvest_amount
			if still_needed[deposit.type] <= 0:
				still_needed.erase(deposit.type)
			break


## Unmined deposits of the wanted resource types within harvesting range,
## shortest walk from the hub first (deposits we can't reach are left out).
func _harvestable_deposits_by_walk(wanted: Dictionary) -> Array[Vector2i]:
	var walk := {}
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		if not tile.has_deposit() or not wanted.has(tile.deposit.type):
			continue
		if not ResourceDeposit.get_info(tile.deposit.type).can_harvest:
			continue  # Extractors only.
		if tile.structure == Structure.Type.EXTRACTOR:
			continue  # Already being mined.
		if Hex.distance(hub.hex, h) > MAX_HARVEST_DISTANCE:
			continue
		var path := map.find_path(hub.hex, h)
		if not path.is_empty():
			walk[h] = map.get_path_cost(path)
	var result: Array[Vector2i] = []
	result.assign(walk.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return walk[a] < walk[b])
	return result


## Resources our units are bringing home: carried, or about to be harvested.
func _incoming_resources() -> Dictionary:
	var incoming := {}
	for u in hub.units:
		for type in u.cargo:
			incoming[type] = incoming.get(type, 0) + u.cargo[type]
		if u.mission is HarvestMission:
			var tile := map.get_tile(u.mission.target)
			if tile and tile.has_deposit():
				var amount := ResourceDeposit.get_info(tile.deposit.type).harvest_amount
				incoming[tile.deposit.type] = incoming.get(tile.deposit.type, 0) + amount
	return incoming

