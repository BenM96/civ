class_name AiController
extends RefCounted
## Plays a computer-controlled colony. It plays by the same rules as the
## players: it only gives orders (through Orders) to units waiting in its hub,
## pays the same costs, researches the same techs, and its units walk out and
## back on their own.
##
## Its economy goes through phases, each ending at a milestone. The phase is
## worked out afresh every turn from what the colony has right now, so losing
## an extractor or a unit (e.g. to an enemy) drops it back to an earlier phase.
##   0. Workforce - while it can train a Miner (if it has none) or another
##      Builder (under the Builder limit, and it can feed one), that comes
##      first: it gets resources first and the Miner fetches what it costs.
##      The Builders it has carry on with the extractor phase meanwhile.
##   1. Core      - a Titanium and a Sediment extractor online.
##   2. Gold      - a Gold extractor online.
##   3. Near      - an extractor on every deposit within NEAR_EXTRACTOR_RADIUS
##                  (local production first: foundations further out cost
##                  far more Sediment - see FoundationBuildable).
##   4. Electrum  - an Electrum extractor online. An Electrum line is only
##                  started once the stockpile covers all of it (its
##                  foundations are far out, so dear); until then the Miner
##                  fetches Electrum by hand.
##   5. Expansion - an extractor on any deposit within MAX_EXTRACTOR_DISTANCE.
##      Once Command Doctrine is researched, the Builders build a command
##      point on every control point they can reach first (nearest first,
##      including ones we captured that aren't linked to the hub yet), and
##      only then go back to extractors. The army's attack waves pick at random
##      between raiding and going for command points (see _plan_attack_wave()).
## Phases 1-5 are passed once their milestone is met, or if there's nowhere
## left to build for them. In each, every Builder works on one extractor at a
## time (the "project": the nearest site for that phase by walk, sticking with
## one already under way), laying its foundations and belts on the way. The
## project gets resources before anything else but the workforce, and the
## Miner fetches whatever it's still short of - what its next job needs
## first. Once the project's costs are covered, the Miner fetches Electrum
## from phase 3 on (for research), or tops up Titanium and Sediment before
## that.
## If a rival has an extractor or belt on a deposit nearer than the project
## (one the same phase would build on), Infantry go to capture it (with an
## escort if there's one spare); once it's ours, it's an open site like any
## other and the Builders connect it (see _plan_capture()).
## Biomass extractors are only built while biomass production is below
## BIOMASS_TARGET - and while it's below zero, a Biomass extractor is the
## project whatever the phase. Gold extractors are only built while the
## stockpile holds less than GOLD_RESERVE times the Gold the next military
## unit costs (it rises with every one trained); above it, phase 2 is passed.
##
## Alongside the economy it trains an army while there's biomass to feed it
## (see _next_army_unit()), builds every hub building it's allowed and
## researches what it can afford, useful techs first. In phases 1-4 these
## get what the project leaves over; in phase 5 they come before the project.
## An aim that can't afford something yet holds back what there is towards
## it (see _save_for()), so lower aims can't spend it.
## A damaged hub is repaired (once a turn) before anything else.
##
## Military:
##   1. QRF - a third of its army stands by on QRF (armour and Guards first).
##   2. Attack - all ready Infantry set off together, escorted by spare
##      armour. A raid demolishes the nearest rival's structures (each its own
##      target) or, now and then or with nothing else left, its hub. In phase 5
##      each wave is a raid or, at random, a command-point wave: capture
##      rivals' command points, or with none to take, guard our own.
##   3. Air - half the aircraft that can intercept stand by on Intercept;
##      Bombers carpet bomb the nearest rival's structures (or its hub); the
##      rest fly sorties at enemies on its structures, then those nearest
##      its hub.

enum Phase { WORKFORCE, CORE, GOLD, NEAR, ELECTRUM, EXPANSION }

## The Miner only travels this far (hex distance) to harvest - except Electrum,
## whose deposits all lie more than 10 tiles out.
const MAX_HARVEST_DISTANCE := 12
const ELECTRUM_HARVEST_DISTANCE := 22
## Extractors are only planned on deposits this close to the hub (Electrum:
## ELECTRUM_HARVEST_DISTANCE).
const MAX_EXTRACTOR_DISTANCE := 12
## Phase 3 builds on every deposit this close to the hub (where foundations
## cost 1 Sediment) before going for Electrum.
const NEAR_EXTRACTOR_RADIUS := 5
## Biomass extractors are only built while biomass production is below this.
const BIOMASS_TARGET := 3.0
## Gold extractors are only built while the stockpile holds less than this
## many times the Gold the next military unit costs.
const GOLD_RESERVE := 2
## Army mix: this many Infantry per armour unit, and this many land units
## per aircraft.
const INFANTRY_PER_ARMOUR := 2
const LAND_PER_AIRCRAFT := 3
## One in this many of the army stands by on QRF.
const QRF_SHARE := 3
## The chance a raid goes straight for the rival's hub (demolishing it)
## rather than its structures.
const HUB_RAID_CHANCE := 0.35

var player: Player
var map: HexMap
## Where the AI sends its orders - the same place the human players' go, so
## it plays by exactly the same rules.
var orders: Orders
## The phase this turn (see the class description).
var phase := Phase.WORKFORCE
## The extractor phase this turn (phase, ignoring Workforce).
var extractor_phase := Phase.CORE
## The tile the Builders are working on this turn (a deposit, or a control
## point in phase 5), or null.
var project: Variant = null
## What they build there: "extractor" or "command_point".
var project_kind := "extractor"
## A deposit a rival has an extractor or belt on that's nearer than our
## project (passing the same phase's test): Infantry go to capture it, then
## the Builders connect it (see _plan_capture()). Or null.
var capture_site: Variant = null
## What the last attack wave went for: "raid" or "command_points" ("" before
## the first).
var last_wave := ""
var _rng := RandomNumberGenerator.new()
## What this turn's orders and savings haven't spoken for yet: Type -> int.
var _budget: Dictionary = {}
## What each aim is short of (Type -> amount), highest aim first, for the
## Miner to fetch.
var _wants: Array[Dictionary] = []
## The resource types the project's next job needs (fetched first within the
## project's want).
var _needed_first: Dictionary = {}


func _init(p_player: Player, p_map: HexMap, p_orders: Orders) -> void:
	player = p_player
	map = p_map
	orders = p_orders
	_rng.randomize()


## Sends an order for our colony. Returns true if it was carried out.
func _order(order: Dictionary) -> bool:
	return orders.submit(player.id, order) == ""


func take_turn() -> void:
	_budget = player.inventory.duplicate()
	_wants = []
	_needed_first = {}
	# A damaged hub is repaired first (losing it loses the game).
	if player.get_hub_repair_refusal() == "" and _order(Orders.repair_hub()):
		_spend(Player.HUB_REPAIR_COST)
	_choose_project()
	phase = Phase.WORKFORCE if _wants_workforce() else extractor_phase
	_aim_workers()
	if extractor_phase == Phase.EXPANSION:
		_aim_army()
		_aim_buildings()
		_aim_extractor()
		_aim_research(true)
	else:
		_aim_extractor()
		_aim_research(extractor_phase >= Phase.NEAR)
		_aim_army()
		_aim_buildings()
	_plan_harvesting()
	_plan_qrf()
	_plan_capture()
	_plan_attack_wave()
	_plan_air()


# --- Budget ------------------------------------------------------------------

func _affordable(cost: Dictionary) -> bool:
	return _fits(cost, _budget)


func _spend(cost: Dictionary) -> void:
	for type in cost:
		_budget[type] = _budget.get(type, 0) - cost[type]


## An aim can't afford `cost` yet: hold back what we do have towards it (so
## lower aims don't spend it) and ask the Miner for the rest.
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


# --- Phase 0: Workforce ---------------------------------------------------------

## The civilian we could train now - a Miner if we have none, else a Builder
## if we're under the limit - or null. (Only if we can feed it.)
func _workforce_unit() -> UnitBlueprint:
	for unit_name in [Miner.NAME, Builder.NAME]:
		var bp := player.get_blueprint(unit_name)
		if player.get_training_refusal(bp) == "":
			return bp
	return null


func _wants_workforce() -> bool:
	return _workforce_unit() != null


func _aim_workers() -> void:
	var bp := _workforce_unit()
	if bp:
		_train(bp)


# --- Phases 1-5: Extractors ------------------------------------------------------

## Works out the extractor phase and picks this turn's project (see the class
## description).
func _choose_project() -> void:
	project = null
	project_kind = "extractor"
	var producing := {}  # Types we have an extractor online for.
	for h in player.get_producing_extractors():
		producing[map.get_tile(h).deposit.type] = true
	var biomass := player.get_biomass_production()
	var biomass_ok := biomass < BIOMASS_TARGET
	var unit_gold: int = player.get_training_cost(player.get_blueprint("Infantry")).get(ResourceDeposit.Type.GOLD, 0)
	var gold_ok := player.get_resource(ResourceDeposit.Type.GOLD) < GOLD_RESERVE * unit_gold
	var allowed := func(type: ResourceDeposit.Type) -> bool:
		if type == ResourceDeposit.Type.BIOMASS:
			return biomass_ok
		if type == ResourceDeposit.Type.GOLD:
			return gold_ok
		return true
	var milestones: Array = [
		[Phase.CORE, func(type: ResourceDeposit.Type, distance: int) -> bool:
			return type in [ResourceDeposit.Type.TITANIUM, ResourceDeposit.Type.SEDIMENT] \
				and not producing.has(type) and distance <= MAX_EXTRACTOR_DISTANCE],
		[Phase.GOLD, func(type: ResourceDeposit.Type, distance: int) -> bool:
			return type == ResourceDeposit.Type.GOLD and gold_ok and not producing.has(type) \
				and distance <= MAX_EXTRACTOR_DISTANCE],
		[Phase.NEAR, func(type: ResourceDeposit.Type, distance: int) -> bool:
			return allowed.call(type) and distance <= NEAR_EXTRACTOR_RADIUS],
		[Phase.ELECTRUM, func(type: ResourceDeposit.Type, distance: int) -> bool:
			return type == ResourceDeposit.Type.ELECTRUM and not producing.has(type) \
				and distance <= ELECTRUM_HARVEST_DISTANCE],
		[Phase.EXPANSION, func(type: ResourceDeposit.Type, distance: int) -> bool:
			return allowed.call(type) and distance <= _extractor_range(type)],
	]
	extractor_phase = Phase.EXPANSION
	var chosen: Callable = milestones[-1][1]
	for milestone: Array in milestones:
		var site: Variant = _pick_site(milestone[1])
		if site != null:
			extractor_phase = milestone[0]
			project = site
			chosen = milestone[1]
			break
	# A rival holds a deposit nearer than the one we're building on: take it
	# (see _plan_capture()); once it's ours it's reconnected like any site.
	capture_site = _rival_site_before(chosen, project)
	# Phase 5: command points before more extractors.
	if extractor_phase == Phase.EXPANSION:
		var point: Variant = _pick_command_point_site()
		if point != null:
			project = point
			project_kind = CommandPointBuildable.ID
	# Starving: food comes first, whatever the phase.
	if biomass < 0:
		var food: Variant = _pick_site(func(type: ResourceDeposit.Type, distance: int) -> bool:
			return type == ResourceDeposit.Type.BIOMASS and distance <= MAX_EXTRACTOR_DISTANCE)
		if food != null:
			project = food
			project_kind = "extractor"


## The rival-held deposit passing `wanted` with the shortest walk from the
## hub, if that walk is shorter than to `project` (or there's no project);
## else null. Rival-held: their extractor or conveyor belt is on it.
func _rival_site_before(wanted: Callable, target: Variant) -> Variant:
	var limit := 1 << 30
	if target != null:
		var to_project := map.find_path(player.hex, target, player.id)
		if not to_project.is_empty():
			limit = map.get_path_cost(to_project)
	var best: Variant = null
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		if not tile.has_deposit() or tile.structure_owner == Faction.NONE or map.are_allied(tile.structure_owner, player.id):
			continue
		if tile.structure != Structure.Type.EXTRACTOR and tile.structure != Structure.Type.CONVEYOR:
			continue
		if not wanted.call(tile.deposit.type, Hex.distance(player.hex, h)):
			continue
		var path := map.find_path(player.hex, h, player.id)
		if path.is_empty():
			continue
		var cost := map.get_path_cost(path)
		if cost < limit:
			limit = cost
			best = h
	return best


## Sends Infantry waiting for orders to capture capture_site: one to take
## it and one more as its escort (if there's a spare). Not if some are
## already on their way.
func _plan_capture() -> void:
	if capture_site == null:
		return
	for u in player.units:
		if u.mission is CaptureMission and u.mission.target == capture_site:
			return
	var taker: Unit = null
	for u in player.get_units_needing_orders():
		if u.can_take("capture") and _order(Orders.mission(u, "capture", capture_site)):
			taker = u
			break
	if taker == null:
		return
	for u in player.get_units_needing_orders():
		if u.can_take("escort") and _order(Orders.mission(u, "escort:%d" % taker.id, player.hex)):
			return


## Sends idle Builders to the project, one per job we can pay for (the
## Builder pays job by job as it goes), then holds back what the rest of it
## costs and asks the Miner for what's missing - what its next job needs
## first.
func _aim_extractor() -> void:
	if project == null:
		return
	var target: Vector2i = project
	var order_kind := "build:" + project_kind
	var plan: LineBuildMission = Orders.make_mission(player, order_kind, target)
	var idle: Array[Unit] = []
	for u in player.get_units_needing_orders():
		if u.can_take("build"):
			idle.append(u)
	# Tiles builders already took materials for aren't up for grabs.
	var claimed := {}
	for u in player.units:
		if u.mission is LineBuildMission and u.mission.target == target:
			var tile: Variant = u.mission.get_claimed_tile()
			if tile != null:
				claimed[tile] = true
	var jobs := plan.take_startable(player, map, player.hex, _budget.duplicate(), idle.size(), claimed)
	for j in jobs:
		var builder: Unit = idle.pop_front()
		if _order(Orders.mission(builder, order_kind, target)):
			_spend(builder.materials)
	# What's still to pay for: everything left on the line, less what our
	# Builders are already carrying for it.
	var left := plan.get_total_cost(player, map, player.hex)
	for u in player.units:
		if u.mission is LineBuildMission and u.mission.target == target:
			for type in u.materials:
				left[type] = maxi(left.get(type, 0) - u.materials[type], 0)
	var next_jobs := plan.get_next_jobs(player, map, player.hex)
	if not next_jobs.is_empty():
		for type in next_jobs[0].cost:
			_needed_first[type] = true
	_save_for(left)


## The deposit to build on among those passing `wanted` (type, hex distance
## from the hub), or null: one our Builders are already working on if there
## is one (so they finish what they started), else the shortest walk from the
## hub. Only deposits we can run belts to.
func _pick_site(wanted: Callable) -> Variant:
	var sites := _open_sites(wanted)
	if sites.is_empty():
		return null
	for u in player.units:
		if u.mission is LineBuildMission and u.mission.target in sites:
			return u.mission.target
	for h in sites:
		var m: LineBuildMission = Orders.make_mission(player, "build:extractor", h)
		if m.plan_route(player, map, player.hex, h).is_empty():
			continue
		# Electrum lines run far out, where foundations are dear: only start
		# one we can pay for in full.
		if map.get_tile(h).deposit.type == ResourceDeposit.Type.ELECTRUM \
				and not _fits(m.get_total_cost(player, map, player.hex), player.inventory):
			continue
		return h
	return null


## Deposits passing `wanted` that we could put an extractor on (or reconnect
## ours to), shortest walk from the hub first. Unreachable ones are left out.
func _open_sites(wanted: Callable) -> Array[Vector2i]:
	var walk := {}
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		if not tile.has_deposit() or not _is_open_site(h, tile):
			continue
		if not wanted.call(tile.deposit.type, Hex.distance(player.hex, h)):
			continue
		var path := map.find_path(player.hex, h, player.id)
		if not path.is_empty():
			walk[h] = map.get_path_cost(path)
	var result: Array[Vector2i] = []
	result.assign(walk.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return walk[a] < walk[b])
	return result


## Whether we could build an extractor on deposit tile `h`: nothing there, or
## our own belt - or our own extractor that's been cut off from the hub (the
## line is rebuilt).
func _is_open_site(h: Vector2i, tile: HexTile) -> bool:
	match tile.structure:
		Structure.Type.NONE:
			return true
		Structure.Type.CONVEYOR:
			return tile.structure_owner == player.id
		Structure.Type.EXTRACTOR:
			return tile.structure_owner == player.id and not player.is_supply_connected(h)
	return false


## The control point to build a command point on (or relink ours to), or
## null: none once we can't build them yet. One our Builders are already on
## if there is one, else the shortest walk from the hub that a line can reach.
func _pick_command_point_site() -> Variant:
	if player.get_buildable_refusal(player.get_buildable(CommandPointBuildable.ID)) != "":
		return null
	var walk := {}
	for h in map.control_points:
		var tile := map.get_tile(h)
		var open := false
		match tile.structure:
			Structure.Type.NONE:
				open = true
			Structure.Type.CONVEYOR:
				open = tile.structure_owner == player.id
			Structure.Type.COMMAND_POINT:
				open = tile.structure_owner == player.id and not player.is_supply_connected(h)
		if not open:
			continue
		var path := map.find_path(player.hex, h, player.id)
		if not path.is_empty():
			walk[h] = map.get_path_cost(path)
	var sites: Array = walk.keys()
	sites.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return walk[a] < walk[b])
	for u in player.units:
		if u.mission is LineBuildMission and u.mission.target in sites:
			return u.mission.target
	for h: Vector2i in sites:
		var m: LineBuildMission = Orders.make_mission(player, "build:" + CommandPointBuildable.ID, h)
		if not m.plan_route(player, map, player.hex, h).is_empty():
			return h
	return null


func _extractor_range(type: ResourceDeposit.Type) -> int:
	return ELECTRUM_HARVEST_DISTANCE if type == ResourceDeposit.Type.ELECTRUM else MAX_EXTRACTOR_DISTANCE


# --- Army ------------------------------------------------------------------------

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


# --- Buildings -------------------------------------------------------------------

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


# --- Research --------------------------------------------------------------------

## Researches the techs on offer (the next on each tree) that we can afford,
## most useful first (_research_rank()), cheapest on a tie. If the most
## useful one is out of reach and `ask_miner`, asks the Miner for the
## Electrum.
func _aim_research(ask_miner: bool) -> void:
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
			if ask_miner:
				_save_for(cost)
			asked = true


## How much we want `tech` (lower first): more Builders and food, then the
## basic buildings, then units, then Weapons for units we have, the rest,
## and Command Doctrine last - except in phase 5, where it comes first (we
## build command points then).
func _research_rank(tech: Tech) -> int:
	if tech.builder_limit_bonus > 0:
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
	if tech.unlocks_buildable == CommandPointBuildable.ID:
		return 0 if extractor_phase == Phase.EXPANSION else 7
	if tech.unlocks_buildable != "":
		return 7
	return 5


# --- Harvesting -----------------------------------------------------------------

## Sends the Miner (if idle) to fetch what the aims are short of (_wants),
## highest aim first, counting what's already on its way home. With nothing
## short, it fetches Electrum from phase 3 on (until an extractor brings it
## in), otherwise whichever of Titanium and Sediment we have least of (every
## extractor needs both). It goes to the nearest deposit of the most wanted
## resource it can reach.
func _plan_harvesting() -> void:
	var idle: Array[Unit] = []
	for worker in player.get_units_needing_orders():
		if worker.can_take("harvest"):
			idle.append(worker)
	if idle.is_empty():
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
		queue.append([_spare_harvest_type(), idle.size()])
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


## What the Miner fetches when nothing is short (see _plan_harvesting()).
func _spare_harvest_type() -> ResourceDeposit.Type:
	var electrum := ResourceDeposit.Type.ELECTRUM
	if extractor_phase >= Phase.NEAR and player.get_income().get(electrum, 0.0) <= 0 \
			and _can_gather_all({electrum: 1}):
		return electrum
	var titanium := ResourceDeposit.Type.TITANIUM
	var sediment := ResourceDeposit.Type.SEDIMENT
	return titanium if player.get_resource(titanium) <= player.get_resource(sediment) else sediment


## Unmined deposits of the wanted resource types within harvesting range,
## shortest walk from the hub first (deposits we can't reach are left out).
func _harvestable_deposits_by_walk(wanted: Dictionary) -> Array[Vector2i]:
	var building_on := {}  # An extractor is coming; harvesting there is wasted.
	for u in player.units:
		if u.mission is LineBuildMission:
			building_on[u.mission.target] = true
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
		var path := map.find_path(player.hex, h, player.id)
		if not path.is_empty():
			walk[h] = map.get_path_cost(path)
	var result: Array[Vector2i] = []
	result.assign(walk.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return walk[a] < walk[b])
	return result


## How far the Miner will go to harvest `type`.
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
		if _order(Orders.mission(u, "qrf", player.hex, Orders.REPEAT_FOREVER)):
			on_qrf += 1


# --- Military 2: Attack waves ---------------------------------------------------

## Every ready Infantry sets off together, and spare armour each escort one
## of them. Before phase 5 every wave is a raid (_raid()); in phase 5 it's a
## raid or a command-point wave (_take_command_points()), at random - a
## command-point wave with nothing to go for raids instead.
func _plan_attack_wave() -> void:
	var infantry: Array[Unit] = []
	for u in player.get_units_needing_orders():
		if u.can_take("demolish"):
			infantry.append(u)
	if infantry.is_empty():
		return
	var wave: Array[Unit] = []
	if extractor_phase == Phase.EXPANSION and _rng.randf() < 0.5:
		wave = _take_command_points(infantry)
		if not wave.is_empty():
			last_wave = "command_points"
	if wave.is_empty():
		wave = _raid(infantry)
		if not wave.is_empty():
			last_wave = "raid"
	if wave.is_empty():
		return
	var escort_index := 0
	for u in player.get_units_needing_orders():
		if not u.can_take("escort") or u.can_take("demolish"):
			continue  # Armour only (Infantry are in the wave).
		var escortee := wave[escort_index % wave.size()]
		if _order(Orders.mission(u, "escort:%d" % escortee.id, player.hex)):
			escort_index += 1


## Raids the nearest rival that has anything to hit. Some waves (one in
## about 1/HUB_RAID_CHANCE) all go to demolish its hub; otherwise each of
## `infantry` demolishes one of its structures (nearest to us first), and
## with none left they demolish the hub (or, if they can't reach it, guard
## beside it). Returns the units sent.
func _raid(infantry: Array[Unit]) -> Array[Unit]:
	var taken := _targets_in_progress()
	var wave: Array[Unit] = []
	var at_hub := _rng.randf() < HUB_RAID_CHANCE
	for rival in _rivals_by_distance():
		for u in infantry:
			if u in wave:
				continue
			if at_hub and _order(Orders.mission(u, "demolish", rival.hex)):
				wave.append(u)
				continue
			var target: Variant = _nearest_structure_of(rival, u, taken)
			if target != null and _order(Orders.mission(u, "demolish", target)):
				taken[target] = true
				wave.append(u)
				continue
			if _order(Orders.mission(u, "demolish", rival.hex)):
				wave.append(u)
				continue
			var post: Variant = _post_by_hub(rival, u, taken)
			if post != null and _order(Orders.mission(u, "guard", post)):
				taken[post] = true
				wave.append(u)
		if not wave.is_empty():
			break  # One wave, one rival.
	return wave


## Goes for the control points with `infantry`: each to capture a rival's
## command point (nearest to us first, one each); with none to take, each
## to guard one of ours (or the one our Builders are building) that nobody
## is guarding yet. Infantry left over escort the others. Returns the units
## sent (empty if there was nothing to go for).
func _take_command_points(infantry: Array[Unit]) -> Array[Unit]:
	var taken := _targets_in_progress()
	var captures: Array[Vector2i] = []
	var posts: Array[Vector2i] = []
	for h in map.control_points:
		if taken.has(h):
			continue
		var tile := map.get_tile(h)
		if tile.structure == Structure.Type.COMMAND_POINT and not map.are_allied(tile.structure_owner, player.id):
			captures.append(h)
		elif (tile.structure == Structure.Type.COMMAND_POINT and tile.structure_owner == player.id) \
				or (project_kind == CommandPointBuildable.ID and h == project):
			posts.append(h)
	var by_distance := func(a: Vector2i, b: Vector2i) -> bool:
		return Hex.distance(player.hex, a) < Hex.distance(player.hex, b)
	captures.sort_custom(by_distance)
	posts.sort_custom(by_distance)
	var kind := "capture" if not captures.is_empty() else "guard"
	var targets := captures if not captures.is_empty() else posts
	var wave: Array[Unit] = []
	for u in infantry:
		for h in targets:
			if not taken.has(h) and _order(Orders.mission(u, kind, h)):
				taken[h] = true
				wave.append(u)
				break
	if wave.is_empty():
		return wave
	var i := 0
	for u in infantry:
		if u in wave:
			continue
		if _order(Orders.mission(u, "escort:%d" % wave[i % wave.size()].id, player.hex)):
			i += 1
	return wave


## `rival`'s structure nearest our hub that `u` could demolish (or, with
## `kind` "carpet_bomb", bomb), or null.
func _nearest_structure_of(rival: Player, u: Unit, taken: Dictionary, kind := "demolish") -> Variant:
	var candidates: Array[Vector2i] = []
	for h in map.tiles:
		var tile: HexTile = map.tiles[h]
		if tile.structure != Structure.Type.NONE and tile.structure_owner == rival.id and not taken.has(h):
			candidates.append(h)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Hex.distance(player.hex, a) < Hex.distance(player.hex, b))
	for h in candidates:
		var m := Orders.make_mission(player, kind, h)
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

## Our aircraft: half of those that can intercept stand by on Intercept;
## Bombers carpet bomb; the rest fly sorties.
func _plan_air() -> void:
	_plan_intercepts()
	_plan_carpet_bombing()
	_plan_sorties()


## Keeps half our interceptor-capable aircraft (rounded down) on Intercept
## duty - counting those refitting before going back on it.
func _plan_intercepts() -> void:
	var total := 0
	var on_duty := 0
	for u in player.units:
		if not u.can_take("intercept"):
			continue
		total += 1
		if u.mission is InterceptMission or u.rejoin_kind == "intercept":
			on_duty += 1
	for u in player.get_units_needing_orders():
		if on_duty >= total / 2:
			return
		if u.can_take("intercept") and _order(Orders.mission(u, "intercept", player.hex, Orders.REPEAT_FOREVER)):
			on_duty += 1


## Sends ready Bombers at the nearest rival's structures nearest us (one
## each), or its hub when there's nothing else.
func _plan_carpet_bombing() -> void:
	var taken := _targets_in_progress()
	for u in player.get_units_needing_orders():
		if not u.can_take("carpet_bomb"):
			continue
		for rival in _rivals_by_distance():
			var target: Variant = _nearest_structure_of(rival, u, taken, "carpet_bomb")
			if target != null and _order(Orders.mission(u, "carpet_bomb", target)):
				taken[target] = true
				break
			if _order(Orders.mission(u, "carpet_bomb", rival.hex)):
				break


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
		if u.player == null or player.is_ally(u.player) or map.get_player_at(u.hex) != null:
			continue
		if not u.hex in targets:
			targets.append(u.hex)
	if targets.is_empty():
		return
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_ours := map.are_allied(map.get_tile(a).structure_owner, player.id)
		var b_ours := map.are_allied(map.get_tile(b).structure_owner, player.id)
		if a_ours != b_ours:
			return a_ours
		return Hex.distance(player.hex, a) < Hex.distance(player.hex, b))
	for i in aircraft.size():
		_order(Orders.mission(aircraft[i], "sortie", targets[mini(i, targets.size() - 1)]))


# --- Shared helpers -------------------------------------------------------------

## The enemy colonies (not on our team - Player.team) still in the game,
## nearest hub first.
func _rivals_by_distance() -> Array[Player]:
	var rivals: Array[Player] = []
	for faction in map.players:
		var other: Player = map.players[faction]
		if player.is_enemy(other) and not other.collapsed:
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
