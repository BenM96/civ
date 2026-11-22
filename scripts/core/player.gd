class_name Player
extends Node2D
## One colony in the game, human or computer-controlled. A player and its
## central hub are the same thing: this node stands on the map where the hub
## is (`hex`) and draws it, and holds everything the colony owns - its
## stockpile, units, training queue, buildings and supply network.
##
## Every unit belongs to a player: it waits at the hub until given a mission,
## and returns there when it's done. Buildings (see Building) live inside the
## hub rather than on map tiles. Units in the hub are each in one of its
## rooms (see Room): only units in Mission Briefing can be given orders.

## Emitted whenever any unit changes state (joins, departs, returns...).
signal units_changed
## Human-readable message for the event log.
signal unit_event(message: String)

## Emitted when the stockpile changes.
signal inventory_changed
## Emitted when the training queue changes.
signal training_changed
## Emitted when the set of extractors linked to the hub changes.
signal network_changed
## Emitted when a building is added to (or removed from) the hub.
signal buildings_changed
## Emitted when research is started, cancelled or finished.
signal research_changed
## A newly linked extractor started delivering (lets the game report rivals).
signal extractor_connected(h: Vector2i, type: ResourceDeposit.Type)


## A unit being trained. Its cost has already been paid.
class TrainingOrder:
	var blueprint: UnitBlueprint
	var turns_left: int
	## What was paid for it (refunded in full if cancelled).
	var paid: Dictionary

	func _init(p_blueprint: UnitBlueprint, p_paid: Dictionary) -> void:
		blueprint = p_blueprint
		paid = p_paid
		turns_left = p_blueprint.train_turns


## This player's number, 0 and up: its index in Game.players, and what map
## tiles store as their structure_owner. Name and colour come from Faction.
## Set before place().
var id := Faction.NONE
## Played by the computer (an AiController gives its orders) rather than a
## human.
var is_ai := false
## Where the hub stands on the map. Units set out from and return here.
var hex: Vector2i
var map: HexMap
## Eliminated (lost every unit with none in training): no units, no turns,
## left standing as a ruin.
var collapsed := false

## What the hub is called on the map.
const HUB_NAME := "Central Hub"

## Buildings inside the hub, in the order they were added.
var buildings: Array[Building] = []
## Buildings paid for this turn (their ids), finished at the end of the turn
## (see run_hub()).
var building_queue: Array[String] = []
## One of every building type, for looking up names, costs and limits.
var building_types: Array[Building] = Building.create_all()
## This game's tech trees, shared by every colony (set by Game).
var tech_trees: TechTrees
## Techs researched (ids), in the order they finished. Saved.
var researched: Array[String] = []
## Techs paid for this turn (ids), researched in the Hub step. Saved.
var research_queue: Array[String] = []
## The line job every Builder joins (see start_builder_group()): {"kind",
## "target": [x, y], "repeats"}, or {} for none. Idle Builders - and any
## that come home or finish training later - are given it until it's done.
## Saved.
var builder_group_order: Dictionary = {}
## A colony only ever has one Miner (see Miner).
const MINER_LIMIT := 1
## The most Builders a colony may have before any Workforce tech.
const BASE_BUILDER_LIMIT := 1
## The hub's rooms (see Room). Every unit in the hub is in one of them.
var rooms: Array[Room] = Room.create_all()
var units: Array[Unit] = []
## Stockpiled resources: ResourceDeposit.Type -> int.
var inventory: Dictionary = {}
## Units this hub knows how to train.
var blueprints: Array[UnitBlueprint] = []
## Only the first order progresses; the rest wait their turn.
var training_queue: Array[TrainingOrder] = []
## Structures this hub's Builders can construct.
var buildables: Array[Buildable] = []
## Supply network: hex -> next hex towards the hub, for every tile linked
## to the hub through conveyors/extractors (the hub maps to itself).
var _network: Dictionary = {}
## Extractor hexes that were producing last time the network was checked.
var _producing: Dictionary = {}
## Extractor hex -> hundredths of a unit mined towards its next delivery.
var _extractor_progress: Dictionary = {}
## unit_name -> how many of that type this colony has ever had (starting and
## trained; never goes down when one dies). Gives units names that are never
## reused ("Infantry 3").
var _units_ever_had: Dictionary = {}


func _init() -> void:
	# Units this hub can train. Their costs, training times and upkeep are
	# set in each unit's own script (scripts/units/<type>/).
	for unit_script in [
			Miner, Builder, GuardUnit,
			Infantry, AssaultInfantry, AtInfantry, StingerInfantry,
			Apc, TankDestroyer, Tank, AntiAircraftGun,
			Chopper, Fighter, Bomber]:
		blueprints.append(UnitBlueprint.new(unit_script))
	buildables.append(FoundationBuildable.new())
	buildables.append(BridgeBuildable.new())
	buildables.append(ExtractorBuildable.new())
	buildables.append(ConveyorBuildable.new())
	buildables.append(CommandPointBuildable.new())


## "Your colony" for the player at this computer, otherwise e.g. "Pink colony".
func get_display_name() -> String:
	return Faction.get_display_name(id)


func get_color() -> Color:
	return Faction.get_color(id)


func get_buildable(buildable_id: String) -> Buildable:
	for b in buildables:
		if b.id == buildable_id:
			return b
	return null


# --- Buildings -------------------------------------------------------------

## Adds a building to the hub.
func add_building(building: Building) -> void:
	buildings.append(building)
	buildings_changed.emit()


## How many of the hub's finished buildings have this id, e.g. "greenhouse".
func count_buildings(building_id: String) -> int:
	var count := 0
	for b in buildings:
		if b.id == building_id:
			count += 1
	return count


## Finished plus under construction: what counts towards the limit.
func count_planned_buildings(building_id: String) -> int:
	return count_buildings(building_id) + building_queue.count(building_id)


## One of every building type by id (for names, costs, limits), or null.
func get_building_type(building_id: String) -> Building:
	for b in building_types:
		if b.id == building_id:
			return b
	return null


## Whether we have the tech (if any) that lets the hub build `building_id`.
func has_building_tech(building_id: String) -> bool:
	var tech := TechList.unlocking_building(building_id)
	return tech == null or _has_unlock(tech)


## Why the hub can't order a `building_id` right now, or "" if it can.
func get_building_refusal(building_id: String) -> String:
	var type := get_building_type(building_id)
	if type == null:
		return "no such building"
	var tech := TechList.unlocking_building(building_id)
	if not has_building_tech(building_id):
		return "needs the %s tech" % tech.display_name
	var limit := get_building_limit(building_id)
	if count_planned_buildings(building_id) >= limit:
		return "the hub already has the most it can (%d)" % limit
	if type.requires != "" and count_buildings(type.requires) == 0:
		return "needs a %s first" % Building.get_name_for(type.requires)
	if not can_afford(type.cost):
		return "need %s" % ResourceDeposit.format_cost(type.cost)
	return ""


## Pays for a new building; it's finished at the end of the turn. Returns ""
## if it was ordered, otherwise why not.
func order_building(building_id: String) -> String:
	var reason := get_building_refusal(building_id)
	if reason != "":
		return reason
	var type := get_building_type(building_id)
	_change_resources(type.cost, -1)
	building_queue.append(building_id)
	unit_event.emit("Started building a %s (%s) - ready at the end of the turn" % [type.display_name, ResourceDeposit.format_cost(type.cost)])
	buildings_changed.emit()
	return ""


## Calls off a building still under construction, refunding it in full.
func cancel_building(index: int) -> bool:
	if index < 0 or index >= building_queue.size():
		return false
	var type := get_building_type(building_queue[index])
	building_queue.remove_at(index)
	_change_resources(type.cost, 1)
	unit_event.emit("Cancelled the %s (refunded %s)" % [type.display_name, ResourceDeposit.format_cost(type.cost)])
	buildings_changed.emit()
	return true


func _finish_buildings() -> void:
	if building_queue.is_empty():
		return
	for building_id in building_queue:
		var building := Building.create(building_id)
		buildings.append(building)
		unit_event.emit("The %s is finished" % building.display_name)
	building_queue.clear()
	buildings_changed.emit()


# --- Research (see Tech, TechList, TechTrees) --------------------------------

## Whether `tech_id` has been researched (finished, not just paid for).
func has_tech(tech_id: String) -> bool:
	return tech_id in researched


## Whether what `tech` unlocks is available to us.
func _has_unlock(tech: Tech) -> bool:
	return has_tech(tech.id)


## The techs we've researched.
func _researched_techs() -> Array[Tech]:
	var result: Array[Tech] = []
	for tech_id in researched:
		result.append(TechList.get_tech(tech_id))
	return result


## The most of `building_id` the hub may have: its base max_count, raised
## by techs (e.g. Hydroponics for Greenhouses).
func get_building_limit(building_id: String) -> int:
	var type := get_building_type(building_id)
	var limit := type.max_count if type else 0
	for tech in _researched_techs():
		limit += tech.building_limit_bonus.get(building_id, 0)
	return limit


## The most Builders we may have (alive and in training):
## BASE_BUILDER_LIMIT, raised by the Workforce techs.
func get_builder_limit() -> int:
	var limit := BASE_BUILDER_LIMIT
	for tech in _researched_techs():
		limit += tech.builder_limit_bonus
	return limit


## How many units called `unit_name` (e.g. "Builder") we have, alive and in
## training.
func count_units_named(unit_name: String) -> int:
	var count := units.filter(func(u: Unit) -> bool: return u.unit_name == unit_name).size()
	for order in training_queue:
		if order.blueprint.unit_name == unit_name:
			count += 1
	return count


## The most of `unit_name` we may have, or -1 for no limit: the Miner
## (MINER_LIMIT) and Builder (get_builder_limit()) are capped.
func get_unit_limit(unit_name: String) -> int:
	if unit_name == Miner.NAME:
		return MINER_LIMIT
	if unit_name == Builder.NAME:
		return get_builder_limit()
	return -1


## Extra damage a unit called `unit_name` does to every target (Weapons techs).
func get_damage_bonus(unit_name: String) -> int:
	var bonus := 0
	for tech in _researched_techs():
		if tech.damage_bonus_unit == unit_name:
			bonus += 1
	return bonus


## Extra movement points for every land unit (All-Terrain Drives).
func get_movement_bonus() -> int:
	var bonus := 0
	for tech in _researched_techs():
		bonus += tech.movement_bonus
	return bonus


## What one of our extractors on a deposit of `type` delivers per turn: the
## resource's own rate plus any tech bonus (Advanced Drilling).
func get_extractor_output(type: ResourceDeposit.Type) -> float:
	var output := ExtractorBuildable.output_for(type)
	for tech in _researched_techs():
		output += tech.extractor_bonus.get(type, 0.0)
	return output


## Why Builders can't build `buildable` yet (a tech it needs), or "".
func get_buildable_refusal(buildable: Buildable) -> String:
	var tech := TechList.unlocking_buildable(buildable.id)
	if tech and not _has_unlock(tech):
		return "needs the %s tech" % tech.display_name
	return ""


## Why `tech_id` can't be researched right now, or "" if it can: it must be
## the next one on its tree (the one before researched, not just paid for),
## its prerequisite researched, and the Electrum to hand.
func get_research_refusal(tech_id: String) -> String:
	var tech := TechList.get_tech(tech_id)
	if tech == null or tech_trees == null:
		return "no such tech"
	if has_tech(tech_id):
		return "already researched"
	if tech_id in research_queue:
		return "being researched - done at the end of the turn"
	var previous := tech_trees.get_previous(tech_id)
	if previous != "" and not has_tech(previous):
		return "research %s first" % TechList.get_tech(previous).display_name
	if tech.requires != "" and not has_tech(tech.requires):
		return "needs the %s tech" % TechList.get_tech(tech.requires).display_name
	var cost := get_research_cost(tech_id)
	if not can_afford(cost):
		return "need %s" % ResourceDeposit.format_cost(cost)
	return ""


## What researching `tech_id` costs: its place on its tree, in Electrum.
func get_research_cost(tech_id: String) -> Dictionary:
	return {ResourceDeposit.Type.ELECTRUM: tech_trees.get_cost_of(tech_id)}


## Pays for a tech; it's researched at the end of the turn. Returns "" if
## it was started, otherwise why not.
func research_tech(tech_id: String) -> String:
	var reason := get_research_refusal(tech_id)
	if reason != "":
		return reason
	var cost := get_research_cost(tech_id)
	_change_resources(cost, -1)
	research_queue.append(tech_id)
	unit_event.emit("Started researching %s (%s) - done at the end of the turn" % [
		TechList.get_tech(tech_id).display_name, ResourceDeposit.format_cost(cost)])
	research_changed.emit()
	return ""


## Calls off research paid for this turn, refunding it in full.
func cancel_research(tech_id: String) -> bool:
	if not tech_id in research_queue:
		return false
	research_queue.erase(tech_id)
	var cost := get_research_cost(tech_id)
	_change_resources(cost, 1)
	unit_event.emit("Cancelled researching %s (refunded %s)" % [
		TechList.get_tech(tech_id).display_name, ResourceDeposit.format_cost(cost)])
	research_changed.emit()
	return true


func _finish_research() -> void:
	if research_queue.is_empty():
		return
	for tech_id in research_queue:
		researched.append(tech_id)
		unit_event.emit("Research complete: %s - %s" % [
			TechList.get_tech(tech_id).display_name, TechList.get_tech(tech_id).get_effect_text()])
	research_queue.clear()
	research_changed.emit()


## What every building in the hub produces in a turn: Type -> int.
func get_building_output() -> Dictionary:
	var total := {}
	for b in buildings:
		for type in b.output:
			total[type] = total.get(type, 0) + b.output[type]
	return total


## The blueprint for training a unit type, e.g. "Builder", or null.
func get_blueprint(unit_name: String) -> UnitBlueprint:
	for bp in blueprints:
		if bp.unit_name == unit_name:
			return bp
	return null


## One of this colony's units by its id, or null.
func get_unit(unit_id: int) -> Unit:
	for u in units:
		if u.id == unit_id:
			return u
	return null


## Adds a unit to the colony. A new unit gets an id and a name here; a unit
## being restored from a save keeps the ones it already has.
func add_unit(unit: Unit) -> void:
	add_child(unit)
	if unit.id == 0:
		unit.id = map.take_unit_id()
	if unit.display_name == "":
		_units_ever_had[unit.unit_name] = _units_ever_had.get(unit.unit_name, 0) + 1
		unit.display_name = "%s %d" % [unit.unit_name, _units_ever_had[unit.unit_name]]
	if unit.room_id == "":
		unit.room_id = MissionBriefingRoom.ID
	units.append(unit)
	unit.setup(self, map)
	unit.state_changed.connect(_on_unit_state_changed)
	unit.mission_completed.connect(_on_unit_mission_completed)
	unit.mission_failed.connect(_on_unit_mission_failed)
	unit.returned_to_hub.connect(_on_unit_returned)
	units_changed.emit()
	queue_redraw()


## Takes a unit killed in combat out of the colony. Whatever it was carrying,
## and anything already paid for its mission, is lost.
func remove_unit(unit: Unit) -> void:
	if not units.has(unit):
		return
	units.erase(unit)
	unit.state_changed.disconnect(_on_unit_state_changed)
	unit.mission_completed.disconnect(_on_unit_mission_completed)
	unit.mission_failed.disconnect(_on_unit_mission_failed)
	unit.returned_to_hub.disconnect(_on_unit_returned)
	unit.die()
	units_changed.emit()
	queue_redraw()


func get_garrison() -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.state == Unit.State.IN_HUB:
			result.append(u)
	return result


## Units at home in Mission Briefing, waiting for orders.
func get_units_needing_orders() -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.needs_orders():
			result.append(u)
	return result


# --- Rooms -----------------------------------------------------------------

## One of the hub's rooms by its id, e.g. MedBayRoom.ID, or null.
func get_room(room_id: String) -> Room:
	for room in rooms:
		if room.id == room_id:
			return room
	return null


## The units in the hub that are in a room (units out on the map aren't in
## any), in the order they joined the colony.
func get_units_in_room(room_id: String) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.room_id == room_id and u.is_in_hub():
			result.append(u)
	return result


## Where an off-duty `unit` waits: the Break Room, Barracks, Hangar or Garage
## for its type. Null if the hub has none for it (or it isn't built yet).
func get_quarters_for(unit: Unit) -> Room:
	for room in rooms:
		if room is QuartersRoom and room.get_refusal(unit) == "" and is_room_open(room):
			return room
	return null


## Whether the hub has built what `room` needs (see Room.required_building).
func is_room_open(room: Room) -> bool:
	return room.required_building == "" or count_buildings(room.required_building) > 0


## Why `room` is locked (e.g. "build a Barracks to open it"), or "" if it's open.
func get_room_lock_text(room: Room) -> String:
	if is_room_open(room):
		return ""
	return "build a %s to open it" % Building.get_name_for(room.required_building)


## The open room that heals units like `unit`, or null if there's none.
func get_healing_room_for(unit: Unit) -> Room:
	for room in rooms:
		if room.heals_unit(unit) and is_room_open(room):
			return room
	return null


## Moves `unit` to `index` (0 = first) in its room's healing queue. Returns
## "" if it moved, otherwise why not.
func move_in_healing_queue(unit: Unit, index: int) -> String:
	if unit.player != self or not unit.is_in_hub():
		return "%s isn't in the hub" % unit.display_name
	return get_room(unit.room_id).move_in_healing_queue(self, unit, index)


## Turns `unit` refits for after a trip out: its own refit_turns, less one
## for each Flight Crew Quarters (never below 1).
func get_refit_turns(unit: Unit) -> int:
	return maxi(1, unit.refit_turns - count_buildings(FlightCrewQuarters.ID))


## Why the player can't move `unit` into the room `room_id` right now, or ""
## if they can (see move_unit_to_room()).
func get_room_move_refusal(unit: Unit, room_id: String) -> String:
	var room := get_room(room_id)
	if room == null:
		return "no such room"
	if unit.player != self:
		return "not one of our units"
	if not unit.is_in_hub():
		return "%s isn't in the hub" % unit.display_name
	if unit.room_id == room_id:
		return "%s is already in the %s" % [unit.display_name, room.display_name]
	if unit.mission and not unit.can_cancel_mission():
		return "%s can't be called off its mission right now" % unit.display_name
	var current := get_room(unit.room_id)
	if current:
		var stuck := current.get_leave_refusal(unit)
		if stuck != "":
			return stuck
	if not is_room_open(room):
		return "the %s isn't built yet - %s" % [room.display_name, get_room_lock_text(room)]
	return room.get_refusal(unit)


## The player moves a unit in the hub to another room. A unit with a mission
## it hasn't set out on (in the Airlock, or on QRF duty) has it called off,
## as with cancel_mission(). Returns "" if it moved, otherwise why not.
## `wait_turns` (for a unit sent off duty to its quarters): after that many
## turns it goes back to Mission Briefing by itself; 0 keeps it there until
## it's moved.
func move_unit_to_room(unit: Unit, room_id: String, wait_turns := 0) -> String:
	var reason := get_room_move_refusal(unit, room_id)
	if reason != "":
		return reason
	if unit.mission:
		var called_off := unit.mission.get_description()
		cancel_mission(unit)
		unit_event.emit("%s's mission was called off (%s)" % [unit.display_name, called_off])
	unit.set_room(room_id)
	if wait_turns > 0 and get_room(room_id) is QuartersRoom:
		unit.wait_turns_left = wait_turns
		unit_event.emit("%s is off duty in the %s for %d turn(s)" % [unit.display_name, get_room(room_id).display_name, wait_turns])
		return ""
	unit_event.emit("%s moved to the %s" % [unit.display_name, get_room(room_id).display_name])
	return ""


## The room a unit coming home goes to: the room that heals it (the Med Bay
## or the Garage) if it's hurt and the hub has one, otherwise Mission
## Briefing.
func _room_for_returning(unit: Unit) -> String:
	if unit.is_injured():
		var healer := get_healing_room_for(unit)
		if healer:
			return healer.id
	return MissionBriefingRoom.ID


func get_field_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.state != Unit.State.IN_HUB:
			result.append(u)
	return result


## Gives `mission` to a garrisoned unit. Its cost leaves the stockpile at
## once and goes with the unit (Unit.materials), so no other order can spend
## the same resources. The unit departs when the turn ends.
func assign_mission(unit: Unit, mission: Mission) -> bool:
	if unit.player != self or not unit.can_accept_mission(mission):
		return false
	var cost := mission.get_cost()
	if not can_afford(cost):
		return false
	_change_resources(cost, -1)
	unit.assign_mission(mission)
	unit.set_room(mission.get_departure_room_id())
	unit.add_materials(cost)
	mission.on_assigned()  # Line builds take their first job's materials.
	unit_event.emit("%s ordered: %s" % [unit.display_name, mission.get_description()])
	return true


## Withdraws an order from a unit that hasn't left yet (or is back at the hub
## waiting), putting the materials it was given back in the stockpile.
func cancel_mission(unit: Unit) -> bool:
	if unit.player != self:
		return false
	if not unit.cancel_mission():
		return false
	_change_resources(unit.take_materials(), 1)
	unit.set_room(_room_for_returning(unit))
	return true


## Hands the hub's resources to `unit` to carry for a job (Unit.materials).
## Returns false (taking nothing) if the stockpile can't cover `cost`.
func give_materials(unit: Unit, cost: Dictionary) -> bool:
	if not pay(cost):
		return false
	unit.add_materials(cost)
	return true


## Puts whatever `unit` is carrying for its job back in the stockpile.
## Returns what came back.
func take_back_materials(unit: Unit) -> Dictionary:
	var returned := unit.take_materials()
	_change_resources(returned, 1)
	return returned


## Adds to the stockpile. Resources that aren't stored (Biomass - see
## ResourceType.stored) are ignored: they count as production instead.
func add_resource(type: ResourceDeposit.Type, amount: int) -> void:
	if not ResourceDeposit.get_info(type).stored:
		return
	inventory[type] = get_resource(type) + amount
	inventory_changed.emit()


func get_resource(type: ResourceDeposit.Type) -> int:
	return inventory.get(type, 0)


## Takes `cost` from the stockpile if the colony can afford it. Returns
## whether it did.
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	_change_resources(cost, -1)
	return true


func can_afford(cost: Dictionary) -> bool:
	for type in cost:
		if get_resource(type) < cost[type]:
			return false
	return true


func _change_resources(cost: Dictionary, direction: int) -> void:
	if cost.is_empty():
		return
	for type in cost:
		inventory[type] = get_resource(type) + cost[type] * direction
	inventory_changed.emit()


# --- Training --------------------------------------------------------------

## What training one more of `blueprint` costs (always the same price).
func get_training_cost(blueprint: UnitBlueprint) -> Dictionary:
	return blueprint.base_cost.duplicate()


## Whether we have the tech (if any) that unlocks `blueprint`.
func has_unit_tech(blueprint: UnitBlueprint) -> bool:
	var tech := TechList.unlocking_unit(blueprint.unit_name)
	return tech == null or _has_unlock(tech)


## Whether the room that holds `blueprint` while training (its quarters)
## is open, i.e. its building has been built.
func has_training_building(blueprint: UnitBlueprint) -> bool:
	return get_missing_training_building(blueprint) == ""


## The building `blueprint` needs before it can train, or "" if none.
func get_missing_training_building(blueprint: UnitBlueprint) -> String:
	for room in rooms:
		if room.holds_training(blueprint) and not is_room_open(room):
			return room.required_building
	return ""


## Why `blueprint` can't be trained at all right now (e.g. "needs a
## Barracks"), or "" if it can - not counting whether we can afford it. A
## unit needs the room that holds it while training (its quarters) to be
## built, and its unlock tech if it has one (see TechList); the Miner and
## Builders are capped (get_unit_limit()).
func get_training_refusal(blueprint: UnitBlueprint) -> String:
	if not has_unit_tech(blueprint):
		return "needs the %s tech" % TechList.unlocking_unit(blueprint.unit_name).display_name
	var missing := get_missing_training_building(blueprint)
	if missing != "":
		return "needs a %s" % Building.get_name_for(missing)
	var limit := get_unit_limit(blueprint.unit_name)
	if limit >= 0 and count_units_named(blueprint.unit_name) >= limit:
		return "%s limit reached (%d)" % [blueprint.unit_name, limit]
	# Never train a unit we couldn't feed (counting the ones already training).
	var after := get_biomass_production() - blueprint.upkeep
	for order in training_queue:
		after -= order.blueprint.upkeep
	if after < 0:
		return "not enough biomass (would be %s a turn)" % ResourceDeposit.format_change(after)
	return ""


## Pays for and queues a new unit. Returns false if we can't afford it or
## haven't the building it needs.
func queue_training(blueprint: UnitBlueprint) -> bool:
	var cost := get_training_cost(blueprint)
	if not can_afford(cost) or get_training_refusal(blueprint) != "":
		return false
	_change_resources(cost, -1)
	training_queue.append(TrainingOrder.new(blueprint, cost))
	unit_event.emit("Started training a %s (%s)" % [blueprint.unit_name, ResourceDeposit.format_cost(cost)])
	training_changed.emit()
	return true


## Removes an order from the queue and refunds what was paid for it.
func cancel_training(index: int) -> bool:
	if index < 0 or index >= training_queue.size():
		return false
	var order := training_queue[index]
	training_queue.remove_at(index)
	_change_resources(order.paid, 1)
	unit_event.emit("Cancelled %s training (refunded %s)" % [order.blueprint.unit_name, ResourceDeposit.format_cost(order.paid)])
	training_changed.emit()
	return true


func _process_training() -> void:
	if training_queue.is_empty():
		return
	var order := training_queue[0]
	order.turns_left -= 1
	if order.turns_left <= 0:
		training_queue.remove_at(0)
		var unit := order.blueprint.create_unit()
		add_unit(unit)
		unit_event.emit("%s has finished training and is ready for orders" % unit.display_name)
	training_changed.emit()


# --- Supply network --------------------------------------------------------

## Puts the hub on the map. The player must already be in the tree.
func place(p_map: HexMap, p_hex: Vector2i) -> void:
	map = p_map
	hex = p_hex
	global_position = map.hex_to_world(hex)
	map.register_player(self)
	queue_redraw()
	if not map.tile_changed.is_connected(_on_tile_changed):
		map.tile_changed.connect(_on_tile_changed)
	update_network()


func _on_tile_changed(_h: Vector2i) -> void:
	update_network()


## Flood-fills out from the hub through this player's own conveyors and
## extractors (a rival's belts never carry our resources). Called
## whenever a tile changes.
func update_network() -> void:
	var network := {hex: hex}
	var frontier: Array[Vector2i] = [hex]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for n in Hex.neighbors(current):
			if network.has(n):
				continue
			var tile := map.get_tile(n)
			if tile and Structure.carries_resources(tile.structure) and tile.structure_owner == id:
				network[n] = current
				frontier.append(n)
	# Redraw only the tiles whose link to the hub changed (lights, flow arrows).
	for h in network:
		if _network.get(h) != network[h]:
			map.mark_dirty(h)
	for h in _network:
		if not network.has(h):
			map.mark_dirty(h)
	_network = network

	var producing := {}
	for h in get_producing_extractors():
		producing[h] = true
		if not _producing.has(h):
			var deposit := map.get_tile(h).deposit
			extractor_connected.emit(h, deposit.type)
			unit_event.emit("Extractor at (%d, %d) is connected: %s %s per turn"
				% [h.x, h.y, ResourceDeposit.format_change(get_extractor_output(deposit.type)), deposit.get_display_name()])
	for h in _producing:
		if not producing.has(h) and map.get_tile(h).has_deposit():
			unit_event.emit("Extractor at (%d, %d) lost its connection to the hub" % [h.x, h.y])
	_producing = producing
	network_changed.emit()


## Whether `h` is linked to the hub by conveyor belts.
func get_network_parent(h: Vector2i) -> Vector2i:
	return _network.get(h, h)


## Whether `h` is linked to the hub by conveyor belts.
func is_supply_connected(h: Vector2i) -> bool:
	return _network.has(h)


## How many of the map's control points have one of our command points on
## them, linked to the hub by belts (only those count towards victory).
func count_linked_command_points() -> int:
	var count := 0
	for h in map.control_points:
		var tile := map.get_tile(h)
		if tile.structure == Structure.Type.COMMAND_POINT and tile.structure_owner == id and is_supply_connected(h):
			count += 1
	return count


## Initiative this turn: +1 for every linked command point, plus the
## Initiative techs. Not stored - like biomass production, it's worked out
## from what we have right now. In a battle the colony with the most fires
## first (ties at random - see Combat).
func get_initiative() -> int:
	var initiative := count_linked_command_points()
	for tech in _researched_techs():
		initiative += tech.initiative_bonus
	return initiative


## The win condition: a linked command point on every control point.
func holds_every_control_point() -> bool:
	return not map.control_points.is_empty() and count_linked_command_points() == map.control_points.size()


## Extractors linked to the hub that still have something to mine.
func get_producing_extractors() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in _network:
		var tile := map.get_tile(h)
		if tile.structure == Structure.Type.EXTRACTOR and tile.has_deposit():
			result.append(h)
	return result


## Biomass made per turn (Greenhouses and Biomass extractors) less what every
## unit eats. Below zero, a unit starves each turn (see starve()).
func get_biomass_production() -> float:
	return get_net_income()[ResourceDeposit.Type.BIOMASS]


## Biomass eaten per turn by all of this hub's units.
func get_upkeep() -> int:
	var total := 0
	for u in units:
		total += u.upkeep
	return total


## Overall change per turn, on average: extractors + buildings - unit
## upkeep. Type -> float (may be fractional or negative).
func get_net_income() -> Dictionary:
	var net := get_income()
	var made := get_building_output()
	for type in made:
		net[type] = net.get(type, 0.0) + made[type]
	var biomass := ResourceDeposit.Type.BIOMASS
	net[biomass] = net.get(biomass, 0.0) - get_upkeep()
	return net


## Resources delivered per turn by the supply network, on average:
## Type -> float.
func get_income() -> Dictionary:
	var income := {}
	for h in get_producing_extractors():
		var type := map.get_tile(h).deposit.type
		income[type] = income.get(type, 0.0) + get_extractor_output(type)
	return income


## Each producing extractor adds its output to its progress (in hundredths);
## every full 100 delivers 1 unit from its deposit. An extractor whose
## deposit runs dry is dismantled, leaving the conveyor belt it was built on
## (so a line running through it stays connected).
func _process_extractors() -> void:
	# Forget progress on tiles that are no longer our extractors.
	for h in _extractor_progress.keys():
		var tile := map.get_tile(h)
		if tile.structure != Structure.Type.EXTRACTOR or tile.structure_owner != id:
			_extractor_progress.erase(h)
	for h in get_producing_extractors():
		var deposit := map.get_tile(h).deposit
		var rate := roundi(get_extractor_output(deposit.type) * 100)
		var progress: int = _extractor_progress.get(h, 0) + rate
		var whole := progress / 100
		_extractor_progress[h] = progress % 100
		if whole > 0:
			add_resource(deposit.type, deposit.extract(whole))
		if deposit.is_depleted():
			map.set_structure(h, Structure.Type.CONVEYOR, id)
			_extractor_progress.erase(h)
			unit_event.emit("Extractor at (%d, %d) has exhausted its %s deposit and was removed (the belt stays)"
				% [h.x, h.y, deposit.get_display_name()])
	# Older saves may still have extractors on deposits that ran dry.
	for h in _network.keys():  # A copy: changing a tile rebuilds _network.
		var tile := map.get_tile(h)
		if tile.structure == Structure.Type.EXTRACTOR and tile.structure_owner == id and not tile.has_deposit():
			map.set_structure(h, Structure.Type.CONVEYOR, id)


# --- Turn steps (run by TurnManager, in this order) ------------------------

## "Set out" step: deployed units leave, units out in the world get ready.
func start_units_turn() -> void:
	# Units following others (escorts) go last, so they see this turn's plans.
	var last: Array[Unit] = []
	for unit in units.duplicate():
		if unit.state == Unit.State.IN_HUB:
			continue
		if unit.mission and unit.mission.sets_out_last():
			last.append(unit)
		else:
			unit.start_turn()
	for unit in last:
		unit.start_turn()


## "Work" step: units at their work sites build, harvest or demolish.
func units_work() -> void:
	for unit in units.duplicate():
		unit.do_work()


## "Production" step: extractors deliver and the hub's buildings make
## resources (e.g. a Greenhouse grows biomass).
func produce() -> void:
	_process_extractors()
	for building in buildings:
		building.produce(self)


## "Hub" step: buildings ordered this turn are finished, training progresses
## and the rooms work on their units (the Med Bay and Garage heal, the
## Hangar refits). (After movement, so a freshly trained unit just waits in
## the hub. After production, so a new Greenhouse first grows next turn.)
func run_hub() -> void:
	_finish_research()
	_finish_buildings()
	_process_training()
	for room in rooms:
		room.process_turn(self)
	repeat_orders()


## Makes the line job `kind` at `target` (e.g. "build:conveyor") the one all
## Builders work on: every idle Builder in Mission Briefing joins now, and
## any that come home or finish training join later (_join_builder_group())
## until it's done. `more` is how many more times each repeats it (see
## Unit.repeats_left). Only line jobs are shared - Builders split their tiles
## between them (see LineBuildMission).
func start_builder_group(kind: String, target: Vector2i, more: int) -> void:
	builder_group_order = {"kind": kind, "target": [target.x, target.y], "repeats": more}
	_join_builder_group()


## Gives the group job (builder_group_order) to every idle Builder that isn't
## repeating something of its own. Ends the group once there's nothing left
## to build, or the job can't be given any more.
func _join_builder_group() -> void:
	if builder_group_order.is_empty():
		return
	var kind: String = builder_group_order["kind"]
	var target := Vector2i(int(builder_group_order["target"][0]), int(builder_group_order["target"][1]))
	var plan := Orders.make_mission(self, kind, target)
	if not plan is LineBuildMission or plan.get_next_jobs(self, map, hex).is_empty():
		builder_group_order = {}  # Done (or nothing to share).
		return
	for u in units:
		if not u is Builder or not u.needs_orders() or u.repeats_left != 0:
			continue
		var m := Orders.make_mission(self, kind, target)
		var reason := Orders.get_invalid_reason(self, u, m)
		if reason == "" and assign_mission(u, m):
			u.set_repeats(target, int(builder_group_order["repeats"]))
		elif reason != "":
			unit_event.emit("Builders stopped joining %s: %s" % [m.get_description(), reason])
			builder_group_order = {}
			return


## RTB (return to base): every unit drops what it's doing and comes home.
## Units still waiting to set out (or waiting at the hub, like the QRF or a
## Builder short of resources) are stood down on the spot, getting back
## whatever they were given for the job; units out on the map turn for home,
## bringing back anything they carry. No repeats or group job carry on.
## Units off duty in their quarters stay there. Returns how many were
## recalled.
func recall_all() -> int:
	builder_group_order = {}
	var count := 0
	for u in units.duplicate():
		u.repeats_left = 0
		if u.mission == null:
			continue
		if u.can_cancel_mission():
			cancel_mission(u)
		else:
			u.recall()
		count += 1
	if count > 0:
		unit_event.emit("RTB: %d unit(s) recalled to the hub" % count)
	return count


## Gives a repeating unit (see Unit.repeats_left) its last mission again
## once it's back in Mission Briefing; it sets out next turn. If the hub
## can't pay for it yet, it waits and tries again next turn. If the order
## can't be given any more (e.g. the deposit has run out), the unit stops
## repeating and waits for new orders.
func repeat_orders() -> void:
	for u in units:
		if u.repeats_left == 0 or not u.needs_orders():
			continue
		var m := Orders.make_mission(self, u.last_mission_kind, u.repeat_target)
		if m != null and m.is_valid_for(u) and not can_afford(m.get_cost()):
			continue  # Waits until it can afford it.
		var reason := "it isn't a mission any more" if m == null else Orders.get_invalid_reason(self, u, m)
		var more := u.repeats_left
		if reason == "" and not assign_mission(u, m):
			reason = "it can't be given"
		if reason != "":
			u.repeats_left = 0
			unit_event.emit("%s stopped repeating its order: %s" % [u.display_name, reason])
			continue
		u.repeats_left = more - 1 if more > 0 else more
	_join_builder_group()


## "Starvation" step: if biomass production is below zero, one unit starves
## to death - the most injured non-Worker (Miner or Builder) first (ties at random, so healthy
## ones go at random), and the Miner and Builders only once nobody else is left. Returns
## what happened (for the event log and the starvation popup):
## {"unit": its name, "production": before it died, "after": production now,
## "eaten": what the units ate, "units": how many there were}, or {} if
## nobody starved.
func starve(rng: RandomNumberGenerator) -> Dictionary:
	var production := get_biomass_production()
	if production >= 0 or units.is_empty():
		return {}
	var others: Array[Unit] = []
	var workers: Array[Unit] = []
	for u in units:
		if u is Worker:
			workers.append(u)
		else:
			others.append(u)
	var victim := _most_injured(others if not others.is_empty() else workers, rng)
	var report := {"unit": victim.display_name, "production": production,
		"eaten": get_upkeep(), "units": units.size()}
	remove_unit(victim)
	report["after"] = get_biomass_production()
	unit_event.emit("%s has starved to death - biomass production is %s a turn" % [
		victim.display_name, ResourceDeposit.format_change(production)])
	return report


## The unit with the lowest share of its HP left; a random one of those tied.
static func _most_injured(candidates: Array[Unit], rng: RandomNumberGenerator) -> Unit:
	var lowest := INF
	var tied: Array[Unit] = []
	for u in candidates:
		var share := float(u.health) / u.max_health
		if share < lowest - 0.0001:
			lowest = share
			tied.clear()
		if share < lowest + 0.0001:
			tied.append(u)
	return tied[rng.randi_range(0, tied.size() - 1)]


## Out of the game: no units left and none in training (see TurnManager).
func is_wiped_out() -> bool:
	return units.is_empty() and training_queue.is_empty()


## End of turn: deposits may have run dry or structures changed, so refresh
## the supply network and redraw.
func finish_turn() -> void:
	update_network()
	queue_redraw()


# --- Saving ----------------------------------------------------------------

## Everything about this colony, as plain data (see SaveGame).
func to_dict() -> Dictionary:
	var training := []
	for order in training_queue:
		training.append([order.blueprint.unit_name, order.turns_left, SaveGame.resources_to_data(order.paid)])
	var unit_data := []
	for u in units:
		unit_data.append(u.to_dict())
	var progress := []
	for h in _extractor_progress:
		progress.append([h.x, h.y, _extractor_progress[h]])
	var healing := {}
	for room in rooms:
		if not room.healing_order.is_empty():
			healing[room.id] = room.healing_order.duplicate()
	return {
		"extractor_progress": progress,
		"id": id,
		"is_ai": is_ai,
		"buildings": buildings.map(func(b: Building) -> String: return b.id),
		"building_queue": building_queue.duplicate(),
		"researched": researched.duplicate(),
		"research_queue": research_queue.duplicate(),
		"builder_group_order": builder_group_order.duplicate(),
		"healing_order": healing,
		"hex": SaveGame.hex_to_data(hex),
		"collapsed": collapsed,
		"inventory": SaveGame.resources_to_data(inventory),
		"units_named": _units_ever_had.duplicate(),
		"training": training,
		"units": unit_data,
	}


## Restores what to_dict() saved. The hub must already be placed.
func load_dict(data: Dictionary) -> void:
	inventory = SaveGame.resources_from_data(data["inventory"])
	_extractor_progress = {}
	for entry in data.get("extractor_progress", []):  # Older saves lack it.
		_extractor_progress[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
	for entry in data["training"]:
		var bp := get_blueprint(entry[0])
		# Older saves didn't record what was paid; assume the base price.
		var paid := SaveGame.resources_from_data(entry[2]) if entry.size() > 2 else bp.base_cost.duplicate()
		var order := TrainingOrder.new(bp, paid)
		order.turns_left = int(entry[1])
		training_queue.append(order)
	for unit_data: Dictionary in data["units"]:
		var unit := get_blueprint(unit_data["type"]).create_unit()
		unit.id = int(unit_data["id"])
		unit.display_name = unit_data["name"]
		add_unit(unit)
		unit.load_dict(unit_data)
	# After adding units (which would otherwise count towards the names).
	_units_ever_had = {}
	for unit_name in data["units_named"]:
		_units_ever_had[unit_name] = int(data["units_named"][unit_name])
	buildings.clear()
	for building_id in data["buildings"]:
		var building := Building.create(str(building_id))
		if building:
			buildings.append(building)
	building_queue.clear()
	researched.clear()
	for tech_id in data["researched"]:
		researched.append(str(tech_id))
	research_queue.clear()
	for tech_id in data["research_queue"]:
		research_queue.append(str(tech_id))
	builder_group_order = data["builder_group_order"]
	for building_id in data["building_queue"]:
		building_queue.append(str(building_id))
	for room in rooms:
		room.healing_order.clear()
		for unit_id in data["healing_order"].get(room.id, []):
			room.healing_order.append(int(unit_id))
	buildings_changed.emit()
	if data["collapsed"]:
		collapse()


## Eliminated (wiped out): every unit dies and the hub stops working. The
## TurnManager stops running its turns separately.
func collapse() -> void:
	collapsed = true
	for unit in units.duplicate():
		remove_unit(unit)
	training_queue.clear()
	training_changed.emit()
	modulate = Color(0.55, 0.5, 0.5, 0.7)  # Faded out, as a ruin.


func get_info_text() -> String:
	if collapsed:
		return "%s (%s) - collapsed, abandoned" % [HUB_NAME, get_display_name()]
	var text := "%s (%s) - %d/%d units home" % [
		HUB_NAME, get_display_name(), get_garrison().size(), units.size()]
	if id != Faction.local_faction:
		# Scouting report on a rival's stockpile.
		text += "\nStockpile: %s" % (ResourceDeposit.format_cost(inventory) if not inventory.is_empty() else "empty")
		var income := get_income()
		if not income.is_empty():
			text += "\nExtractors deliver %s per turn" % ResourceDeposit.format_cost(income)
		text += "\nBiomass: %s per turn" % ResourceDeposit.format_change(get_net_income()[ResourceDeposit.Type.BIOMASS])
	return text


func _on_unit_state_changed(_unit: Unit) -> void:
	queue_redraw()
	units_changed.emit()


func _on_unit_mission_completed(unit: Unit, mission: Mission) -> void:
	unit_event.emit("%s %s" % [unit.display_name, mission.get_completion_text()])


## (Unused materials come back when the unit gets home - see _on_unit_returned.)
func _on_unit_mission_failed(unit: Unit, _mission: Mission, reason: String) -> void:
	var carrying := "" if unit.materials.is_empty() \
		else " (bringing back %s)" % ResourceDeposit.format_cost(unit.materials)
	unit_event.emit("%s failed: %s%s" % [unit.display_name, reason, carrying])


## Home: unloads what it harvested, puts back any materials its job didn't
## use, and goes to Mission Briefing (or the Med Bay / Garage if it's hurt).
func _on_unit_returned(unit: Unit) -> void:
	var quarters := get_quarters_for(unit)
	if unit.refit_turns > 0 and quarters:
		# Refits (and is repaired) in its quarters, e.g. an aircraft in the Hangar.
		unit.refit_turns_left = get_refit_turns(unit)
		unit.set_room(quarters.id)
		unit_event.emit("%s is back and refitting in the %s (%d turns)" % [unit.display_name, quarters.display_name, unit.refit_turns_left])
	else:
		unit.set_room(_room_for_returning(unit))
		if unit.room_id != MissionBriefingRoom.ID:
			unit_event.emit("%s came home injured and went to the %s" % [unit.display_name, get_room(unit.room_id).display_name])
		elif unit.is_injured():
			unit_event.emit("%s came home injured, but the hub has nowhere to treat it" % unit.display_name)
	var parts: PackedStringArray = []
	if unit.has_cargo():
		parts.append("delivered %s" % unit.get_cargo_text())
		var cargo := unit.take_cargo()
		for type in cargo:
			add_resource(type, cargo[type])
	var returned := take_back_materials(unit)
	if not returned.is_empty():
		parts.append("put back %s unused" % ResourceDeposit.format_cost(returned))
	if parts.is_empty():
		unit_event.emit("%s returned to the hub" % unit.display_name)
	else:
		unit_event.emit("%s returned and %s" % [unit.display_name, " and ".join(parts)])


func _draw() -> void:
	var size := map.hex_size if map else 36.0
	var outer := Hex.corners(Vector2.ZERO, size * 0.82)
	# Landing pad.
	draw_colored_polygon(outer, Color(0.32, 0.34, 0.38))
	var outline := outer.duplicate()
	outline.append(outer[0])
	draw_polyline(outline, get_color(), 3.0, true)
	# Habitat dome with an antenna.
	var base_y := size * 0.25
	var r := size * 0.42
	draw_line(Vector2(r * 0.3, base_y - r * 0.8), Vector2(r * 0.55, base_y - r * 1.35), Color(0.8, 0.82, 0.85), 2.0)
	draw_circle(Vector2(r * 0.55, base_y - r * 1.35), size * 0.05, Color(1.0, 0.3, 0.25))
	var dome := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		dome.append(Vector2(cos(a), sin(a)) * r + Vector2(0, base_y))
	draw_colored_polygon(dome, Color(0.75, 0.9, 1.0, 0.85))
	draw_polyline(dome, Color(0.95, 0.98, 1.0), 2.0, true)
	draw_arc(Vector2(0, base_y), r * 0.6, PI * 1.15, PI * 1.45, 6, Color(1, 1, 1, 0.8), 2.0)
	draw_rect(Rect2(-r * 1.1, base_y, r * 2.2, size * 0.1), Color(0.6, 0.62, 0.66))
	draw_rect(Rect2(-size * 0.07, base_y - size * 0.18, size * 0.14, size * 0.18), Color(0.2, 0.25, 0.32))
	# Badge: units at home.
	var badge := Vector2(size * 0.55, -size * 0.55)
	draw_circle(badge, size * 0.24, Color(0.1, 0.1, 0.1))
	var font := ThemeDB.fallback_font
	var font_size := 14
	var text := str(get_garrison().size())
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, badge + Vector2(-tw / 2.0, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
