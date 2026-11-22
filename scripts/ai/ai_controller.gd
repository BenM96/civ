class_name AiController
extends RefCounted
## Plays a computer-controlled colony, following scripts/ai/aiStratergy.txt
## (the plain-English plan - keep the two in step). It plays by the same
## rules as the players: it only gives orders (through Orders) to units
## waiting in its hub, pays the same costs, researches the same techs, and
## its units walk out and back on their own.
##
## Each turn (just before the turn resolves, so its orders depart at the same
## time as everyone else's) it works through its economic aims in priority
## order, then its military ones:
##   1. Workers - train one whenever it's under the Worker limit.
##   2. Extractors - a Titanium, Sediment and Gold extractor first, then any
##      extractor it can, nearest deposit first (Biomass first while biomass
##      production is below zero). Built in stages: foundations to the
##      deposit, then belts, then the extractor - one worker per job it can
##      pay for, so several build side by side.
##   3. Army - trains fighting units while there's biomass to feed them (see
##      _next_army_unit() for which).
##   4. Buildings - builds every hub building it's allowed, in list order.
##   5. Electrum - keeps a Worker harvesting Electrum (until an extractor
##      brings it in).
##   6. Research - researches what it can afford, useful techs first.
## Higher aims get resources first: an aim that can't afford something yet
## holds back what there is towards it (see _save_for()), so lower aims
## can't spend it, and idle Workers fetch what each aim is missing, highest
## aim first (_plan_harvesting()).
##
## Military:
##   1. QRF - a third of its army stands by on QRF (armour and Guards first).
##   2. Attack - all ready Infantry set off together to demolish the nearest
##      rival's structures (each its own target), escorted by spare armour;
##      with nothing left there, they guard next to that rival's hub.
##   3. Air - aircraft fly sorties at enemies on its structures, then those
##      nearest its hub.

## Workers only travel this far (hex distance) to harvest - except Electrum,
## whose deposits all lie more than 10 tiles out.
const MAX_HARVEST_DISTANCE := 12
const ELECTRUM_HARVEST_DISTANCE := 22
## Extractors are only planned on deposits this close to the hub.
const MAX_EXTRACTOR_DISTANCE := 12
## Aim 2 gets one of each of these first.
const CORE_EXTRACTOR_TYPES: Array[ResourceDeposit.Type] = [
	ResourceDeposit.Type.TITANIUM, ResourceDeposit.Type.SEDIMENT, ResourceDeposit.Type.GOLD]
## Army mix (aim 3): this many Infantry per armour unit, and this many land
## units per aircraft.
const INFANTRY_PER_ARMOUR := 2
const LAND_PER_AIRCRAFT := 3
## One in this many of the army stands by on QRF.
const QRF_SHARE := 3

var player: Player
var map: HexMap
## Where the AI sends its orders - the same place the human players' go, so
## it plays by exactly the same rules.
var orders: Orders
## What this turn's orders and savings haven't spoken for yet: Type -> int.
var _budget: Dictionary = {}
## What each aim is short of (Type -> amount), highest aim first, for idle
## Workers to fetch.
var _wants: Array[Dictionary] = []
## The resource types the next extractor job needs first (fetched first
## within aim 2's want).
var _needed_first: Dictionary = {}


func _init(p_player: Player, p_map: HexMap, p_orders: Orders) -> void:
	player = p_player
	map = p_map
	orders = p_orders


## Sends an order for our colony. Returns true if it was carried out.
func _order(order: Dictionary) -> bool:
	return orders.submit(player.id, order) == ""


func take_turn() -> void:
	_budget = player.inventory.duplicate()
	_wants = []
	_needed_first = {}
	_release_waiting_builders()
	_aim_workers()
	_aim_extractors()
	_aim_army()
	_aim_buildings()
	_aim_electrum()
	_aim_research()
	_plan_harvesting()
	_plan_qrf()
	_plan_attack_wave()
	_plan_sorties()


# --- Budget ------------------------------------------------------------------

func _affordable(cost: Dictionary) -> bool:
	return _fits(cost, _budget)


func _spend(cost: Dictionary) -> void:
	for type in cost:
		_budget[type] = _budget.get(type, 0) - cost[type]


## An aim can't afford `cost` yet: hold back what we do have towards it (so
## lower aims don't spend it) and ask Workers for the rest.
func _save_for(cost: Dictionary) -> void:
	var short := {}
	for type in cost:
		var have := maxi(_budget.get(type, 0), 0)
		if have < cost[type]:
			short[type] = cost[type] - have
		_budget[type] = maxi(have - cost[type], 0)
	if not short.is_empty() and _can_gather_all(short):
		_wants.append(short)


func _fits(cost: Dictionary, budget: Dictionary) -> bool:
	for type in cost:
		if budget.get(type, 0) < cost[type]:
			return false
	return true


## Trains `bp` if the queue is free and it fits the budget; otherwise saves
## up for it. (One unit in training at a time.)
func _train(bp: UnitBlueprint) -> void:
	if not player.training_queue.is_empty():
		return
	var cost := player.get_training_cost(bp)
	if _affordable(cost) and _order(Orders.train(bp.unit_name)):
		_spend(cost)
	else:
		_save_for(cost)


# --- Aim 1: Workers -------------------------------------------------------------

func _aim_workers() -> void:
	var bp := player.get_blueprint(Player.WORKER_NAME)
	if player.get_training_refusal(bp) == "":  # Under the limit, and we can feed it.
		_train(bp)


# --- Aim 2: Extractors ----------------------------------------------------------

## Sends idle workers to build extractors (with their foundations and belts),
## as soon as a job on the way can be paid for - the worker pays job by job
## as it goes. Builds under way come first; a new one is only started when
## spare workers and resources can begin on it straight away. Then asks
## Workers for whatever the first build is still short of.
func _aim_extractors() -> void:
	var idle: Array[Unit] = []
	for u in player.get_units_needing_orders():
		if u.can_take("build"):
			idle.append(u)
	var projects: Array[LineBuildMission] = []
	var taken := {}
	for m in _line_builds_in_progress():
		if not taken.has(m.target):
			taken[m.target] = true
			projects.append(Orders.make_mission(player, "build:extractor", m.target))
	var started := projects.size()
	var i := 0
	while true:
		if i >= projects.size():
			if idle.is_empty():
				break
			var project := _next_extractor_project(taken)
			if project.is_empty():
				break
			projects.append(project[1])
			taken[project[0]] = true
		var plan: LineBuildMission = projects[i]
		# In stages: foundations all the way first, then belts, then the
		# extractor - each its own order, so we only gather one thing at a time.
		var stage := _current_stage(plan)
		var m: LineBuildMission = Orders.make_mission(player, stage, plan.target)
		# Tiles builders already took materials for aren't up for grabs.
		var claimed := {}
		for u in player.units:
			if u.mission is LineBuildMission and u.mission.target == m.target:
				var tile: Variant = u.mission.get_claimed_tile()
				if tile != null:
					claimed[tile] = true
		var jobs := m.take_startable(player, map, player.hex, _budget, idle.size(), claimed)
		for j in jobs:
			if _order(Orders.mission(idle.pop_front(), stage, m.target)):
				started = maxi(started, i + 1)
		if i >= started:
			break  # Nothing affordable on this new one: gather for it first.
		i += 1
	# Workers gather what the first build is short of - what its next job
	# needs first.
	for m in projects:
		var short := {}
		var total := m.get_total_cost(player, map, player.hex)
		for type in total:
			var missing: int = total[type] - maxi(_budget.get(type, 0), 0)
			if missing > 0:
				short[type] = missing
		if short.is_empty():
			continue
		_wants.append(short)
		var next_jobs := m.get_next_jobs(player, map, player.hex)
		if not next_jobs.is_empty():
			_needed_first = _shortfall(next_jobs[0].cost)
		break


## Which order the extractor `plan` needs next: "build:foundation" while
## any foundation is missing on the way, then "build:conveyor", then
## "build:extractor".
func _current_stage(plan: LineBuildMission) -> String:
	var next_jobs := plan.get_next_jobs(player, map, player.hex)
	if next_jobs.is_empty():
		return "build:extractor"
	var id := next_jobs[0].id
	if id == "foundation" or id == "conveyor":
		return "build:" + id
	return "build:extractor"


## Our workers' extractor builds still under way.
func _line_builds_in_progress() -> Array[LineBuildMission]:
	var result: Array[LineBuildMission] = []
	for u in player.units:
		if u.mission is LineBuildMission and u.mission not in result:
			result.append(u.mission)
	return result


## Builders waiting at the hub for resources are called off, so they can go
## and harvest what's missing instead of standing idle (otherwise a colony
## with one worker would wait for ever). The build is ordered again - and
## carries on from where it stopped - once a job can be paid for.
func _release_waiting_builders() -> void:
	for u in player.units.duplicate():
		if u.mission is LineBuildMission and u.can_cancel_mission():
			_order(Orders.cancel_mission(u))


## The next extractor to build, as [hex, its LineBuildMission], or [] if
## there's none: a Titanium, Sediment or Gold deposit while we lack an
## extractor (built or being built) for one of those, otherwise any deposit -
## the shortest walk from the hub first, but Biomass first while biomass
## production is below zero.
func _next_extractor_project(taken: Dictionary) -> Array:
	var covered := {}  # Types we already have (or are building) an extractor for.
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		if tile.structure == Structure.Type.EXTRACTOR and tile.structure_owner == player.id and tile.has_deposit():
			covered[tile.deposit.type] = true
	for h in taken:
		var tile := map.get_tile(h)
		if tile and tile.has_deposit():
			covered[tile.deposit.type] = true
	var core_missing: Array[ResourceDeposit.Type] = []
	for type in CORE_EXTRACTOR_TYPES:
		if not covered.has(type):
			core_missing.append(type)
	var biomass_first := player.get_biomass_production() < 0
	var walk := {}
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		var free := tile.structure == Structure.Type.NONE \
			or (tile.structure == Structure.Type.CONVEYOR and tile.structure_owner == player.id)
		if not tile.has_deposit() or not free or taken.has(h) \
				or Hex.distance(player.hex, h) > MAX_EXTRACTOR_DISTANCE:
			continue
		if not core_missing.is_empty() and not tile.deposit.type in core_missing:
			continue
		var path := map.find_path(player.hex, h)
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
		var m: LineBuildMission = Orders.make_mission(player, "build:extractor", h)
		if m.plan_route(player, map, player.hex, h).is_empty():
			continue  # No way to run belts there.
		return [h, m]
	return []


# --- Aim 3: Army ----------------------------------------------------------------

func _aim_army() -> void:
	var bp := _next_army_unit()
	if bp:
		_train(bp)


## The fighting unit to train next, or null if we can't train any (no
## building or tech for them, or no biomass to feed one). Keeps about
## INFANTRY_PER_ARMOUR Infantry per armour unit and LAND_PER_AIRCRAFT land
## units per aircraft, among the types we can train; within the type, the
## unit that hits the nearest rival's army hardest (_best_counter()).
func _next_army_unit() -> UnitBlueprint:
	var options := {}  # UnitType -> Array[UnitBlueprint] we can train now.
	for bp in player.blueprints:
		if bp.unit_type == Unit.UnitType.CIVILIAN or player.get_training_refusal(bp) != "":
			continue
		if not options.has(bp.unit_type):
			options[bp.unit_type] = []
		options[bp.unit_type].append(bp)
	if options.is_empty():
		return null
	var counts := _army_counts()
	var infantry: int = counts.get(Unit.UnitType.INFANTRY, 0)
	var armour: int = counts.get(Unit.UnitType.ARMOUR, 0)
	var air: int = counts.get(Unit.UnitType.AIR, 0)
	var order: Array[Unit.UnitType] = []
	if (air + 1) * LAND_PER_AIRCRAFT <= infantry + armour:
		order.append(Unit.UnitType.AIR)
	if (armour + 1) * INFANTRY_PER_ARMOUR <= infantry:
		order.append(Unit.UnitType.ARMOUR)
	for type in [Unit.UnitType.INFANTRY, Unit.UnitType.ARMOUR, Unit.UnitType.AIR]:
		if not type in order:
			order.append(type)
	for type in order:
		if options.has(type):
			return _best_counter(options[type])
	return null


## Our fighting units by type, counting any in training.
func _army_counts() -> Dictionary:
	var counts := {}
	for u in player.units:
		if u.unit_type != Unit.UnitType.CIVILIAN:
			counts[u.unit_type] = counts.get(u.unit_type, 0) + 1
	for t in player.training_queue:
		if t.blueprint.unit_type != Unit.UnitType.CIVILIAN:
			counts[t.blueprint.unit_type] = counts.get(t.blueprint.unit_type, 0) + 1
	return counts


## Of `choices`, the one doing the most damage against what the nearest
## rival has (its fighting units, or all its units if it has none). Ties go
## to the cheapest.
func _best_counter(choices: Array) -> UnitBlueprint:
	var enemy_types := {}
	var rival := _nearest_rival()
	if rival:
		for u in rival.units:
			if u.unit_type != Unit.UnitType.CIVILIAN:
				enemy_types[u.unit_type] = enemy_types.get(u.unit_type, 0) + 1
		if enemy_types.is_empty():
			for u in rival.units:
				enemy_types[u.unit_type] = enemy_types.get(u.unit_type, 0) + 1
	var best: UnitBlueprint = null
	var best_score := -1
	var best_price := 0
	for bp: UnitBlueprint in choices:
		var score := 0
		for type in enemy_types:
			score += enemy_types[type] * bp.get_damage(type)
		var price := _total(player.get_training_cost(bp))
		if score > best_score or (score == best_score and price < best_price):
			best = bp
			best_score = score
			best_price = price
	return best


# --- Aim 4: Buildings -----------------------------------------------------------

## Orders every hub building we're allowed (tech researched, under the
## limit, anything it needs built), in list order (Greenhouses first). Saves
## up for the first one we can't afford yet.
func _aim_buildings() -> void:
	for type in player.building_types:
		var reason := player.get_building_refusal(type.id)
		if reason != "" and not reason.begins_with("need "):
			continue  # Locked, or at its limit.
		if reason == "" and _affordable(type.cost) and _order(Orders.build_building(type.id)):
			_spend(type.cost)
			continue
		_save_for(type.cost)
		return


# --- Aim 5: Electrum ------------------------------------------------------------

## Keeps a Worker harvesting Electrum (counting one already on the way), until
## an extractor brings it in.
func _aim_electrum() -> void:
	if player.get_income().get(ResourceDeposit.Type.ELECTRUM, 0.0) > 0:
		return
	var want := {ResourceDeposit.Type.ELECTRUM: 1}
	if _can_gather_all(want):
		_wants.append(want)


# --- Aim 6: Research ------------------------------------------------------------

## Researches the techs on offer (the next on each tree) that we can afford,
## most useful first (_research_rank()), cheapest on a tie. If the most
## useful one is out of reach, asks for the Electrum.
func _aim_research() -> void:
	if player.tech_trees == null:
		return
	var offered: Array[String] = []
	for tree: Array in player.tech_trees.trees:
		for tech_id: String in tree:
			if not player.has_tech(tech_id):
				if not tech_id in player.research_queue:
					offered.append(tech_id)
				break
	offered.sort_custom(func(a: String, b: String) -> bool:
		var rank_a := _research_rank(TechList.get_tech(a))
		var rank_b := _research_rank(TechList.get_tech(b))
		if rank_a != rank_b:
			return rank_a < rank_b
		return player.tech_trees.get_cost_of(a) < player.tech_trees.get_cost_of(b))
	var asked := false
	for tech_id in offered:
		var reason := player.get_research_refusal(tech_id)
		var cost := player.get_research_cost(tech_id)
		if reason == "" and _affordable(cost) and _order(Orders.research(tech_id)):
			_spend(cost)
		elif reason.begins_with("need ") and not asked:
			_save_for(cost)
			asked = true


## How much we want `tech` (lower first): more Workers and food, then the
## basic buildings, then units, then Weapons for units we have, the rest,
## and Command Doctrine last (we don't build command points yet).
func _research_rank(tech: Tech) -> int:
	if tech.worker_limit_bonus > 0:
		return 0
	if tech.building_limit_bonus.has(Greenhouse.ID):
		return 1
	if tech.unlocks_building in [BarracksBuilding.ID, MedBayBuilding.ID, GarageBuilding.ID, HangarBuilding.ID]:
		return 2
	if tech.unlocks_unit != "":
		return 3
	if tech.damage_bonus_unit != "":
		var have := player.units.any(func(u: Unit) -> bool: return u.unit_name == tech.damage_bonus_unit)
		return 4 if have else 6
	if tech.unlocks_buildable != "":
		return 7
	return 5


# --- Harvesting -----------------------------------------------------------------

## Sends idle workers to fetch what the aims are short of (_wants), highest
## aim first, counting what's already on its way home. Each goes to the
## nearest deposit of the most wanted resource it can reach; several can
## share one deposit while it has enough left for all of them.
func _plan_harvesting() -> void:
	var idle: Array[Unit] = []
	for worker in player.get_units_needing_orders():
		if worker.can_take("harvest"):
			idle.append(worker)
	if idle.is_empty() or _wants.is_empty():
		return
	# What's still to fetch, most wanted first: [[type, amount], ...].
	var incoming := _incoming_resources()
	var queue: Array = []
	for want in _wants:
		var types: Array = want.keys()
		types.sort_custom(func(a: int, b: int) -> bool: return _needed_first.has(a) and not _needed_first.has(b))
		for type in types:
			var covered: int = mini(incoming.get(type, 0), want[type])
			incoming[type] = incoming.get(type, 0) - covered
			if want[type] - covered > 0:
				queue.append([type, want[type] - covered])
	if queue.is_empty():
		return
	var wanted_types := {}
	for entry in queue:
		wanted_types[entry[0]] = true
	var deposits := _harvestable_deposits_by_walk(wanted_types)
	var reserved := {}  # Deposit -> our workers already heading there.
	for u in player.units:
		if u.mission is HarvestMission:
			reserved[u.mission.target] = reserved.get(u.mission.target, 0) + 1
	for worker in idle:
		for entry in queue:
			if entry[1] <= 0:
				continue
			var sent := false
			for h: Vector2i in deposits:
				var deposit := map.get_tile(h).deposit
				if deposit == null or deposit.type != entry[0]:
					continue
				var per_trip := ResourceDeposit.get_info(deposit.type).harvest_amount
				if deposit.amount <= reserved.get(h, 0) * per_trip:
					continue  # Others will empty it before this worker gets there.
				if _order(Orders.mission(worker, "harvest", h)):
					reserved[h] = reserved.get(h, 0) + 1
					entry[1] -= per_trip
					sent = true
					break
			if sent:
				break


## Unmined deposits of the wanted resource types within harvesting range,
## shortest walk from the hub first (deposits we can't reach are left out).
func _harvestable_deposits_by_walk(wanted: Dictionary) -> Array[Vector2i]:
	var building_on := {}  # An extractor is coming; harvesting there is wasted.
	for m in _line_builds_in_progress():
		building_on[m.target] = true
	var walk := {}
	for h in map.tiles:
		if building_on.has(h):
			continue
		var tile: HexTile = map.tiles[h]
		if not tile.has_deposit() or not wanted.has(tile.deposit.type):
			continue
		if not ResourceDeposit.get_info(tile.deposit.type).can_harvest:
			continue  # Extractors only.
		if tile.structure == Structure.Type.EXTRACTOR:
			continue  # Already being mined.
		if Hex.distance(player.hex, h) > _harvest_range(tile.deposit.type):
			continue
		var path := map.find_path(player.hex, h)
		if not path.is_empty():
			walk[h] = map.get_path_cost(path)
	var result: Array[Vector2i] = []
	result.assign(walk.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return walk[a] < walk[b])
	return result


## How far Workers will go to harvest `type`.
func _harvest_range(type: ResourceDeposit.Type) -> int:
	return ELECTRUM_HARVEST_DISTANCE if type == ResourceDeposit.Type.ELECTRUM else MAX_HARVEST_DISTANCE


## Resources our units are bringing home: carried, or about to be harvested.
func _incoming_resources() -> Dictionary:
	var incoming := {}
	for u in player.units:
		for type in u.cargo:
			incoming[type] = incoming.get(type, 0) + u.cargo[type]
		if u.mission is HarvestMission:
			var tile := map.get_tile(u.mission.target)
			if tile and tile.has_deposit():
				var amount := ResourceDeposit.get_info(tile.deposit.type).harvest_amount
				incoming[tile.deposit.type] = incoming.get(tile.deposit.type, 0) + amount
	return incoming


# --- Military 1: QRF ------------------------------------------------------------

## Keeps a third of the army (at least 1 once there is one) on QRF duty,
## sending armour and Guards before Infantry so Infantry are free to attack.
func _plan_qrf() -> void:
	var army := 0
	var on_qrf := 0
	for u in player.units:
		if u.can_take("qrf"):
			army += 1
			if u.mission is QrfMission:
				on_qrf += 1
	var wanted := maxi(1, army / QRF_SHARE) if army > 0 else 0
	if on_qrf >= wanted:
		return
	var ready: Array[Unit] = []
	for u in player.get_units_needing_orders():
		if u.can_take("qrf"):
			ready.append(u)
	ready.sort_custom(func(a: Unit, b: Unit) -> bool:
		return not a.can_take("demolish") and b.can_take("demolish"))
	for u in ready:
		if on_qrf >= wanted:
			return
		if _order(Orders.mission(u, "qrf", player.hex)):
			on_qrf += 1


# --- Military 2: Attack waves ---------------------------------------------------

## Every ready Infantry sets off together against the nearest rival that has
## anything to hit: each to demolish one of its structures (nearest to us
## first), or, with none left, to guard beside its hub. Spare armour each
## escort one of them.
func _plan_attack_wave() -> void:
	var infantry: Array[Unit] = []
	for u in player.get_units_needing_orders():
		if u.can_take("demolish"):
			infantry.append(u)
	if infantry.is_empty():
		return
	var taken := _targets_in_progress()
	var wave: Array[Unit] = []
	for rival in _rivals_by_distance():
		for u in infantry:
			if u in wave:
				continue
			var target: Variant = _nearest_structure_of(rival, u, taken)
			if target != null and _order(Orders.mission(u, "demolish", target)):
				taken[target] = true
				wave.append(u)
				continue
			var post: Variant = _post_by_hub(rival, u, taken)
			if post != null and _order(Orders.mission(u, "guard", post)):
				taken[post] = true
				wave.append(u)
		if not wave.is_empty():
			break  # One wave, one rival.
	if wave.is_empty():
		return
	var escort_index := 0
	for u in player.get_units_needing_orders():
		if not u.can_take("escort") or u.can_take("demolish"):
			continue  # Armour only (Infantry are in the wave).
		var escortee := wave[escort_index % wave.size()]
		if _order(Orders.mission(u, "escort:%d" % escortee.id, player.hex)):
			escort_index += 1


## `rival`'s structure nearest our hub that `u` could demolish, or null.
func _nearest_structure_of(rival: Player, u: Unit, taken: Dictionary) -> Variant:
	var candidates: Array[Vector2i] = []
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		if tile.structure != Structure.Type.NONE and tile.structure_owner == rival.id and not taken.has(h):
			candidates.append(h)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Hex.distance(player.hex, a) < Hex.distance(player.hex, b))
	for h in candidates:
		var m := Orders.make_mission(player, "demolish", h)
		if Orders.get_invalid_reason(player, u, m) == "":
			return h
	return null


## A free tile next to `rival`'s hub that `u` can guard, or null.
func _post_by_hub(rival: Player, u: Unit, taken: Dictionary) -> Variant:
	for n in Hex.neighbors(rival.hex):
		if taken.has(n):
			continue
		var m := Orders.make_mission(player, "guard", n)
		if Orders.get_invalid_reason(player, u, m) == "":
			return n
	return null


# --- Military 3: Air ------------------------------------------------------------

## Sends ready aircraft on sorties: at enemies standing on our structures
## first, then the enemy units nearest our hub. Never at a hub.
func _plan_sorties() -> void:
	var aircraft: Array[Unit] = []
	for u in player.get_units_needing_orders():
		if u.can_take("sortie"):
			aircraft.append(u)
	if aircraft.is_empty():
		return
	var targets: Array[Vector2i] = []
	for u in map.get_units_in_world():
		if u.player == player or u.player == null or map.get_player_at(u.hex) != null:
			continue
		if not u.hex in targets:
			targets.append(u.hex)
	if targets.is_empty():
		return
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_ours := map.get_tile(a).structure_owner == player.id
		var b_ours := map.get_tile(b).structure_owner == player.id
		if a_ours != b_ours:
			return a_ours
		return Hex.distance(player.hex, a) < Hex.distance(player.hex, b))
	for i in aircraft.size():
		_order(Orders.mission(aircraft[i], "sortie", targets[mini(i, targets.size() - 1)]))


# --- Shared helpers -------------------------------------------------------------

## The other colonies still in the game, nearest hub first.
func _rivals_by_distance() -> Array[Player]:
	var rivals: Array[Player] = []
	for faction in map.players:
		var other: Player = map.players[faction]
		if other != player and not other.collapsed:
			rivals.append(other)
	rivals.sort_custom(func(a: Player, b: Player) -> bool:
		return Hex.distance(player.hex, a.hex) < Hex.distance(player.hex, b.hex))
	return rivals


func _nearest_rival() -> Player:
	var rivals := _rivals_by_distance()
	return rivals[0] if not rivals.is_empty() else null


## What we're missing to pay `cost` from the stockpile: Type -> amount.
func _shortfall(cost: Dictionary) -> Dictionary:
	var missing := {}
	for type in cost:
		var short: int = cost[type] - player.get_resource(type)
		if short > 0:
			missing[type] = short
	return missing


func _total(cost: Dictionary) -> int:
	var total := 0
	for type in cost:
		total += cost[type]
	return total


## Whether every one of these resource types has an unworked deposit within
## harvesting range (or an extractor already bringing it in). Saving up is
## pointless if even one of them can never be got.
func _can_gather_all(types: Dictionary) -> bool:
	var income := player.get_income()
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
					and Hex.distance(player.hex, h) <= _harvest_range(type):
				found = true
				break
		if not found:
			return false
	return true


## Tiles our units are already heading to build on, harvest or attack.
func _targets_in_progress() -> Dictionary:
	var taken := {}
	for u in player.units:
		if u.mission:
			var target: Variant = u.mission.get_target_hex()
			if target != null:
				taken[target] = true
	return taken
