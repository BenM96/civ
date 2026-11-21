class_name LineBuildMission
extends Mission
## Builds something together with everything it needs, along the route from
## the hub to the target (for buildables with a line_of):
##   Build Foundations to X     - a foundation on every tile of the route.
##   Build Conveyor Belts to X  - a foundation (if missing), then a belt, on
##                                every tile of the route.
##   Build Extractor on X       - foundations and belts from the hub to the
##                                deposit, then a foundation, a belt and the
##                                extractor on top on the deposit itself.
## So each tile has a stack of jobs ("layers": a buildable's `requires`, then
## the buildable), and anything already in place is skipped.
##
## Which job next: the worker does one job per turn, choosing each time -
##   1. the lowest layer first (all the foundations, then belts, then the
##      extractor), nearest the hub first;
##   2. but only jobs the colony can pay for right now - so with no Sediment
##      for a foundation but Titanium to spare, it lays a belt on a tile that
##      already has a foundation instead of waiting.
## After each job the worker walks back to the hub before setting out for the
## next, exactly as if it had been given one order at a time - a line order
## saves the player clicks, not time.
##
## Each job's materials leave the hub when the worker picks it - when the
## order is given, then at the hub before each trip - and the worker carries
## them (Unit.materials), so two workers can never count on the same
## resources. If it can't afford any job on the line, it waits at the hub
## ("waiting for resources") until it can, then carries on. Materials it
## doesn't use (someone finished that tile first, the job became impossible)
## go back in the stockpile when it's next at the hub. If a job becomes
## impossible (e.g. another colony builds in the way) the mission fails and
## the worker heads home; whatever was built stays.
##
## The route avoids tiles where a job couldn't be done (e.g. belts can't go on
## another colony's structure) and is the cheapest in materials, so it runs
## along foundations (and belts) already in place. It may cross deposits: an
## extractor can later go on top of a belt there and the line still carries
## resources through it. It's re-planned
## each time the worker sets out from the hub, to use anything built since.
##
## Several workers given the same order share it: each claims the tile it's
## working towards and the others pick different tiles.

## Route cost of a tile: TILE_COST for its length, plus RESOURCE_COST for
## every resource its remaining jobs cost. So the cheapest line in materials
## wins (a tile with a foundation already down is cheaper for a belt than a
## bare one), and length only settles ties or near-ties.
const TILE_COST := 1
const RESOURCE_COST := 4

var target: Vector2i
var buildable: Buildable
## Every tile from just outside the hub to the target, in order.
var _route: Array[Vector2i] = []
## The tile this worker is heading for or working on, or null.
var _job_tile: Variant = null
var _turns_worked := 0
## Display name -> how many we've built, for the completion message.
var _built: Dictionary = {}
## Can't afford any job on the line: back at (or heading to) the hub until we can.
var _waiting_for_resources := false
## Just finished a job: walking back to the hub before the next one.
var _going_home := false


func _init(p_target: Vector2i, p_buildable: Buildable) -> void:
	target = p_target
	buildable = p_buildable


## True for foundation and belt lines; false for "an extractor, connected".
func _is_plain_line() -> bool:
	return buildable.line_of == buildable.id


func get_display_name() -> String:
	return "Build %ss" % buildable.display_name if _is_plain_line() else "Build %s" % buildable.display_name


func get_kind() -> String:
	return "build:" + buildable.id


func _what() -> String:
	if _is_plain_line():
		return "%ss to (%d, %d)" % [buildable.display_name, target.x, target.y]
	return "%s at (%d, %d)" % [buildable.display_name, target.x, target.y]


func get_description() -> String:
	if _is_plain_line():
		return "Build %s" % _what()
	return "Build %s, connected to the hub" % _what()


func get_progress_text() -> String:
	var left := _count_jobs(unit.player, unit.map, _route)
	if _waiting_for_resources:
		var job := _cheapest_blocked_job()
		var needs := ResourceDeposit.format_cost(_shortfall(job.cost)) if job else "resources"
		var where := "Waiting at the hub" if unit.hex == unit.player.hex else "Heading back to the hub to wait"
		return "%s for resources (needs %s) to build %s" % [where, needs, _what()]
	if _going_home:
		return "Heading back to the hub before the next job on %s (%d job(s) left)" % [_what(), left]
	if is_working():
		return "Building %s (%d job(s) left)" % [_what(), left]
	return "Heading to build %s (%d job(s) left)" % [_what(), left]


func get_completion_text() -> String:
	if _built.is_empty():
		return "left the work on (%d, %d) to other workers" % [target.x, target.y]
	var parts: PackedStringArray = []
	for name in _built:
		var n: int = _built[name]
		parts.append("%d %s%s" % [n, name, "" if n == 1 else "s"])
	var joined := ", ".join(parts.slice(0, -1)) + " and " + parts[-1] if parts.size() > 1 else parts[0]
	return "built %s %s (%d, %d)" % [joined, "to" if _is_plain_line() else "at", target.x, target.y]


func get_target_hex() -> Variant:
	return target


## Where the worker is heading: the hub between jobs or while waiting for
## resources, else the tile of its current job; before setting off, the target.
func get_travel_hex() -> Variant:
	if (_waiting_for_resources or _going_home) and unit:
		return unit.player.hex
	if _job_tile != null:
		return _job_tile
	return target


## Turns of work still to do along the whole route, for the HUD's estimate.
func get_work_turns() -> int:
	if unit == null:
		return 0
	var turns := 0
	for h in plan_route(unit.player, unit.map, unit.hex, target):
		for layer in _pending_layers(unit.player, unit.map, h):
			turns += layer.build_turns
	return turns


## The jobs that could be done next on the route - each tile's next job -
## lowest layer first (the order workers pick them in), for planners.
func get_next_jobs(player: Player, map: HexMap, from: Vector2i) -> Array[Buildable]:
	var jobs: Array[Buildable] = []
	for entry in _next_jobs_by_tile(player, map, from, {}):
		jobs.append(entry[1])
	return jobs


## [tile, next job there] for every tile with work left (except tiles in
## `skip`), lowest layer first.
func _next_jobs_by_tile(player: Player, map: HexMap, from: Vector2i, skip: Dictionary) -> Array:
	var jobs := []
	for h in plan_route(player, map, from, target):
		if skip.has(h):
			continue
		var pending := _pending_layers(player, map, h)
		if not pending.is_empty():
			jobs.append([h, pending[0]])
	jobs.sort_custom(func(a: Array, b: Array) -> bool: return _depth_in(player, a[1]) < _depth_in(player, b[1]))
	return jobs


## How many of those next jobs `budget` (Type -> int) pays for, cheapest
## layers first - i.e. how many more workers could set to work right now.
## Leaves out tiles in `skip` (e.g. ones builders already took materials
## for). Takes what they'd cost out of `budget`, at most `limit` jobs' worth.
func take_startable(player: Player, map: HexMap, from: Vector2i, budget: Dictionary, limit: int,
		skip: Dictionary = {}) -> int:
	var count := 0
	for entry in _next_jobs_by_tile(player, map, from, skip):
		var job: Buildable = entry[1]
		if count >= limit:
			break
		var fits := true
		for type in job.cost:
			if budget.get(type, 0) < job.cost[type]:
				fits = false
		if fits:
			for type in job.cost:
				budget[type] -= job.cost[type]
			count += 1
	return count


## Everything the route still needs, in total: ResourceDeposit.Type -> int.
func get_total_cost(player: Player, map: HexMap, from: Vector2i) -> Dictionary:
	var total := {}
	for h in plan_route(player, map, from, target):
		for layer in _pending_layers(player, map, h):
			for type in layer.cost:
				total[type] = total.get(type, 0) + layer.cost[type]
	return total


## Every job the route still needs, grouped by buildable, lowest layer first:
## [[Buildable, count], ...]. e.g. 3 Foundations, 4 Conveyor Belts, 1 Extractor.
func get_job_counts(player: Player, map: HexMap, from: Vector2i) -> Array:
	var counts := {}
	for h in plan_route(player, map, from, target):
		for layer in _pending_layers(player, map, h):
			counts[layer] = counts.get(layer, 0) + 1
	var jobs := []
	for layer in _expand(player, buildable.line_of) + _expand(player, buildable.id):
		if counts.has(layer):
			jobs.append([layer, counts[layer]])
			counts.erase(layer)
	return jobs


## Paid job by job as the worker goes, not up front.
func get_cost() -> Dictionary:
	return {}


## A worker waiting at the hub for resources can be called off (anything it
## already built stays; nothing was paid for the jobs it hasn't started).
func can_cancel_at_hub() -> bool:
	return _waiting_for_resources


func get_invalid_reason(u: Unit) -> String:
	if u.map.get_player_at(target) != null:
		return "not on a hub"
	var target_problem := _site_problem(u.player, u.map, target)
	if target_problem != "":
		return target_problem
	var route := plan_route(u.player, u.map, u.hex, target)
	if route.is_empty():
		return "no way to build a line there"
	if _count_jobs(u.player, u.map, route) == 0:
		return "nothing left to build there"
	return ""  # Can't afford it yet? The worker waits at the hub until we can.


## Ordered: pick the first job and take its materials from the hub straight
## away, so nothing else can spend them before we set off.
func on_assigned() -> void:
	_route = plan_route(unit.player, unit.map, unit.hex, target)
	var job := _pick_job(unit.player.inventory)
	if not job.is_empty() and unit.player.give_materials(unit, job[1].cost):
		_job_tile = job[0]


func begin() -> void:
	_route = plan_route(unit.player, unit.map, unit.hex, target)
	var job_still_there := _job_tile != null and _route.has(_job_tile) \
		and not _pending_layers(unit.player, unit.map, _job_tile).is_empty()
	if job_still_there:
		_turns_worked = 0
		phase = Phase.TRAVELLING
		_plan_route()  # Off to the job we took materials for.
	else:
		_choose_next_job()


## Each turn before moving: a worker back at the hub after a job sets off for
## the next; one waiting for resources sets off as soon as the colony can
## afford a job on the line.
func prepare() -> void:
	if _going_home:
		if unit.hex == unit.player.hex:
			_going_home = false
			_choose_next_job()
		elif not unit.has_destination():
			unit.set_destination(unit.player.hex)
		return
	if not _waiting_for_resources:
		super()
		return
	if not _pick_job(unit.player.inventory).is_empty() or _count_jobs(unit.player, unit.map, _route) == 0:
		_choose_next_job()
	elif unit.hex != unit.player.hex and not unit.has_destination():
		unit.set_destination(unit.player.hex)


## One job on the current tile, then back to the hub before the next.
func work() -> void:
	if _waiting_for_resources or _going_home or _job_tile == null:
		return
	var map := unit.map
	var h: Vector2i = _job_tile
	var pending := _pending_layers(unit.player, map, h)
	if pending.is_empty():
		_choose_next_job()  # Someone else finished it while we were on our way.
		return
	var layer: Buildable = pending[0]
	var problem := layer.get_invalid_reason(map, h)
	if problem != "":
		fail("(%d, %d): %s" % [h.x, h.y, problem])
		return
	if _turns_worked == 0 and not unit.use_materials(layer.cost):
		# What we brought doesn't fit what this tile needs now (someone built
		# part of it meanwhile): back to the hub to swap it and choose again.
		_go_home()
		return
	_turns_worked += 1
	if _turns_worked < layer.build_turns:
		return
	layer.apply(map, h, unit.player.id)
	_built[layer.display_name] = _built.get(layer.display_name, 0) + 1
	_turns_worked = 0
	if _has_unclaimed_jobs():
		_go_home()
	else:
		_choose_next_job()  # Nothing left for us: finish (the unit heads home).


## Walks back to the hub after a job; the next job is chosen from there.
func _go_home() -> void:
	_job_tile = null
	_going_home = true
	phase = Phase.TRAVELLING
	unit.set_destination(unit.player.hex)


## Picks the next job and sets off for it - or waits at the hub if none can
## be paid for, or finishes if there's nothing left. At the hub, unused
## materials go back in the stockpile and the job's materials are taken out;
## out in the field, only a job the materials we carry cover will do (else we
## head home to swap them).
func _choose_next_job() -> void:
	var at_hub := unit.hex == unit.player.hex
	if at_hub:
		unit.player.take_back_materials(unit)
		var route := plan_route(unit.player, unit.map, unit.hex, target)
		if not route.is_empty():
			_route = route  # Picks up foundations etc. built since we last planned.
	var job := _pick_job(unit.player.inventory if at_hub else unit.materials)
	if not job.is_empty() and at_hub and not unit.player.give_materials(unit, job[1].cost):
		job = []
	if job.is_empty():
		_job_tile = null
		if _has_unclaimed_jobs():
			if at_hub:
				_wait_for_resources()
			else:
				_go_home()
		elif _built.is_empty() and not _others_building():
			fail("nothing left to build")
		else:
			complete()  # Done, or the rest is in other workers' hands.
		return
	_waiting_for_resources = false
	_job_tile = job[0]
	_turns_worked = 0
	if unit.hex == _job_tile:
		phase = Phase.WORKING  # Already here; work starts next turn.
		unit.set_destination(unit.hex)
	else:
		phase = Phase.TRAVELLING
		_plan_route()  # Sets the unit walking to get_travel_hex(), i.e. _job_tile.


## The best job `budget` (Type -> int) pays for, as [tile, layer], or [] if
## none: the lowest layer first (foundations before belts before the
## extractor), then the tile nearest the hub. Skips tiles other workers on
## this order claimed.
func _pick_job(budget: Dictionary) -> Array:
	var best: Array = []
	var best_depth := 1 << 30
	for h in _route:
		if _claimed_by_another(h):
			continue
		var pending := _pending_layers(unit.player, unit.map, h)
		if pending.is_empty():
			continue
		var layer: Buildable = pending[0]
		var depth := _depth(layer)
		if depth < best_depth and _covers(budget, layer.cost):
			best = [h, layer]
			best_depth = depth
	return best


static func _covers(budget: Dictionary, cost: Dictionary) -> bool:
	for type in cost:
		if budget.get(type, 0) < cost[type]:
			return false
	return true


## Whether any tile on the line still needs a job no other worker has claimed.
func _has_unclaimed_jobs() -> bool:
	for h in _route:
		if not _claimed_by_another(h) and not _pending_layers(unit.player, unit.map, h).is_empty():
			return true
	return false


## For the waiting message: the cheapest job on the line we can't yet pay for.
func _cheapest_blocked_job() -> Buildable:
	var best: Buildable = null
	var best_depth := 1 << 30
	for h in _route:
		var pending := _pending_layers(unit.player, unit.map, h)
		if not pending.is_empty() and _depth(pending[0]) < best_depth:
			best = pending[0]
			best_depth = _depth(best)
	return best


## Goes back to the hub (or stays there) until a job can be paid for.
func _wait_for_resources() -> void:
	if not _waiting_for_resources:
		var job := _cheapest_blocked_job()
		unit.player.unit_event.emit("%s is waiting at the hub for resources (needs %s)" % [
			unit.display_name, ResourceDeposit.format_cost(_shortfall(job.cost)) if job else "resources"])
	_waiting_for_resources = true
	unit.set_destination(unit.player.hex)  # Just clears the path if already there.
	phase = Phase.WORKING if unit.hex == unit.player.hex else Phase.TRAVELLING


## What the colony is short of to pay `cost`.
func _shortfall(cost: Dictionary) -> Dictionary:
	var missing := {}
	for type in cost:
		var short: int = cost[type] - unit.player.get_resource(type)
		if short > 0:
			missing[type] = short
	return missing


# --- What each tile needs --------------------------------------------------

## The jobs tile `h` needs, in order: the line's buildable (and what it
## requires) on route tiles, the ordered buildable (and its requirements) on
## the target.
func _layers(player: Player, h: Vector2i) -> Array[Buildable]:
	return _expand(player, buildable.id if h == target else buildable.line_of)


func _expand(player: Player, id: String) -> Array[Buildable]:
	var b := player.get_buildable(id)
	var layers: Array[Buildable] = []
	for required in b.requires:
		for layer in _expand(player, required):
			if layer not in layers:
				layers.append(layer)
	layers.append(b)
	return layers


## How far down the stack a buildable sits: 0 for one that needs nothing
## (a foundation), 1 for one that needs that (a belt)...
func _depth(b: Buildable) -> int:
	return _depth_in(unit.player, b)


static func _depth_in(player: Player, b: Buildable) -> int:
	var depth := 0
	for required in b.requires:
		depth = maxi(depth, _depth_in(player, player.get_buildable(required)) + 1)
	return depth


## The jobs still to do on `h` (in order).
func _pending_layers(player: Player, map: HexMap, h: Vector2i) -> Array[Buildable]:
	var pending: Array[Buildable] = []
	for layer in _layers(player, h):
		if not layer.is_built_at(map, h, player.id):
			pending.append(layer)
	return pending


## Why the jobs on `h` could never be done ("" if they can, or are done).
func _site_problem(player: Player, map: HexMap, h: Vector2i) -> String:
	for layer in _pending_layers(player, map, h):
		var reason := layer.get_site_reason(map, h)
		if reason != "":
			return reason
	return ""


func _count_jobs(player: Player, map: HexMap, route: Array[Vector2i]) -> int:
	var count := 0
	for h in route:
		count += _pending_layers(player, map, h).size()
	return count


# --- Route -----------------------------------------------------------------

## The tiles from `from` (not included) to the target that the line runs
## along, or [] if there's no way. Cheapest route over passable tiles whose
## jobs can be done, preferring ones already built.
func plan_route(player: Player, map: HexMap, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var dist := {from: 0}
	var parent := {from: from}
	var open: Array[Vector2i] = [from]
	var closed := {}
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best_i]]:
				best_i = i
		var current: Vector2i = open.pop_at(best_i)
		if current == to:
			var route: Array[Vector2i] = []
			while current != from:
				route.push_front(current)
				current = parent[current]
			return route
		closed[current] = true
		for n in Hex.neighbors(current):
			if closed.has(n) or not map.is_passable(n) or map.get_player_at(n) != null:
				continue
			if _site_problem(player, map, n) != "":
				continue
			var step := TILE_COST
			for layer in _pending_layers(player, map, n):
				for type in layer.cost:
					step += RESOURCE_COST * int(layer.cost[type])
			var d: int = dist[current] + step
			if not dist.has(n) or d < dist[n]:
				if not dist.has(n):
					open.append(n)
				dist[n] = d
				parent[n] = current
	return []


# --- Sharing the work ------------------------------------------------------

## The tile this worker has claimed (is heading for or working on), or null.
func get_claimed_tile() -> Variant:
	if result != Result.IN_PROGRESS or _waiting_for_resources:
		return null
	return _job_tile


func _claimed_by_another(h: Vector2i) -> bool:
	for other in _fellow_builders():
		if other.get_claimed_tile() == h:
			return true
	return false


func _others_building() -> bool:
	for other in _fellow_builders():
		if other.get_claimed_tile() != null:
			return true
	return false


## Our other units' line missions for the same kind of order (their tiles
## need exactly the same jobs, so splitting them up is safe).
func _fellow_builders() -> Array[LineBuildMission]:
	var others: Array[LineBuildMission] = []
	for u in unit.player.units:
		if u != unit and u.mission is LineBuildMission and u.mission.get_kind() == get_kind():
			others.append(u.mission)
	return others


# --- Saving ----------------------------------------------------------------

func to_dict() -> Dictionary:
	var data := super()
	var route := []
	for h in _route:
		route.append(SaveGame.hex_to_data(h))
	data["route"] = route
	data["job_tile"] = SaveGame.hex_to_data(_job_tile) if _job_tile != null else null
	data["turns_worked"] = _turns_worked
	data["built"] = _built.duplicate()
	data["waiting_for_resources"] = _waiting_for_resources
	data["going_home"] = _going_home
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_route.clear()
	for h in data["route"]:
		_route.append(SaveGame.hex_from_data(h))
	_job_tile = null
	if data.get("job_tile") != null:
		_job_tile = SaveGame.hex_from_data(data["job_tile"])
	elif data.has("next") and int(data["next"]) < _route.size():
		_job_tile = _route[int(data["next"])]  # Saves from before job picking.
	_turns_worked = int(data["turns_worked"])
	_waiting_for_resources = bool(data.get("waiting_for_resources", false))
	_going_home = bool(data.get("going_home", false))
	_built = {}
	var built: Variant = data.get("built", {})
	if built is Dictionary:
		for name in built:
			_built[name] = int(built[name])
