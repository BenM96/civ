class_name AiController
extends RefCounted
## Plays a rival colony. It follows the same rules as the player: it can only
## give missions to units waiting in its hub, pays the same costs, and its
## units walk out and back on their own.
##
## Each turn (called just before the turn resolves, so its orders depart at
## the same time as the player's) it:
##   1. Queues training when it is short of workers/builders.
##   2. Sends builders to grow its supply network: an extractor on the
##      nearest free deposit plus the conveyor line linking it to the hub.
##   3. Sends every idle worker to harvest whatever resource it has least of.

## How many of each unit the rival tries to keep.
const WANTED_WORKERS := 3
const WANTED_BUILDERS := 2
const MAX_UNITS := 8
## Longest conveyor line it will lay to reach a deposit.
const MAX_BELT_LENGTH := 8
## Workers only travel this far (hex distance) to harvest.
const MAX_HARVEST_DISTANCE := 12

var hub: CentralHub
var map: HexMap


func _init(p_hub: CentralHub, p_map: HexMap) -> void:
	hub = p_hub
	map = p_map


func take_turn() -> void:
	_plan_training()
	_plan_construction()
	_plan_harvesting()


# --- Training --------------------------------------------------------------

func _plan_training() -> void:
	if not hub.training_queue.is_empty() or hub.units.size() >= MAX_UNITS:
		return
	var workers := _count_units(func(u: Unit) -> bool: return u.can_harvest)
	var builders := _count_units(func(u: Unit) -> bool: return u.can_build)
	if workers < WANTED_WORKERS:
		_train("Worker")
	elif builders < WANTED_BUILDERS:
		_train("Builder")


func _train(unit_name: String) -> void:
	for bp in hub.blueprints:
		if bp.unit_name == unit_name:
			hub.queue_training(bp)  # Does nothing if we can't afford it.
			return


func _count_units(pred: Callable) -> int:
	var count := 0
	for u in hub.units:
		if pred.call(u):
			count += 1
	return count


# --- Construction ----------------------------------------------------------

func _plan_construction() -> void:
	var builders: Array[Unit] = []
	for u in hub.get_units_needing_orders():
		if u.can_build:
			builders.append(u)
	if builders.is_empty():
		return
	var tasks := _construction_tasks()
	var taken := _targets_in_progress()
	for builder in builders:
		for task in tasks:
			var target: Vector2i = task[0]
			if taken.has(target):
				continue
			var mission := BuildMission.new(target, hub.get_buildable(task[1]))
			if hub.can_afford(mission.get_cost()) and hub.assign_mission(builder, mission):
				taken[target] = true
				break


## The jobs needed to connect the nearest unclaimed deposit: [hex, id] pairs,
## extractor first, then the conveyors nearest the hub first.
func _construction_tasks() -> Array:
	var project := _find_project()
	if project.is_empty():
		return []
	var tasks := []
	var deposit_hex: Vector2i = project["deposit"]
	if map.get_tile(deposit_hex).structure == Structure.Type.NONE:
		tasks.append([deposit_hex, "extractor"])
	for h: Vector2i in project["belts"]:
		tasks.append([h, "conveyor"])
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

func _plan_harvesting() -> void:
	var taken := _targets_in_progress()
	for worker in hub.get_units_needing_orders():
		if not worker.can_harvest:
			continue
		var target: Variant = _pick_harvest_target(worker, taken)
		if target == null:
			continue
		if hub.assign_mission(worker, HarvestMission.new(target)):
			taken[target] = true


## The nearest deposit of the resource we have least of (falling back to
## any resource), skipping deposits already being worked.
func _pick_harvest_target(worker: Unit, taken: Dictionary) -> Variant:
	var types: Array = ResourceDeposit.DATA.keys()
	types.sort_custom(func(a, b) -> bool: return hub.get_resource(a) < hub.get_resource(b))
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
