class_name CentralHub
extends Building
## The player's main building. Every unit belongs to a hub: it waits here in
## the garrison until given a mission, and returns here when it's done.

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


## Who owns this hub (see Faction). Set before place().
var faction := Faction.NONE
## Starved and eliminated: no units, no turns, left standing as a ruin.
var collapsed := false

## Biomass the hub itself grows every turn.
const HUB_BIOMASS_OUTPUT := 3

var units: Array[Unit] = []
## Stockpiled resources: ResourceDeposit.Type -> int.
var inventory: Dictionary = {}
## Units this hub knows how to train.
var blueprints: Array[UnitBlueprint] = []
## Only the first order progresses; the rest wait their turn.
var training_queue: Array[TrainingOrder] = []
## Structures this hub's workers can construct.
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
## reused ("Infantry 3") and sets training prices (get_training_cost()).
var _units_ever_had: Dictionary = {}


func _init() -> void:
	building_name = "Central Hub"
	max_health = 100
	# Units this hub can train. Their costs, training times and upkeep are
	# set in each unit's own script (scripts/units/).
	for unit_script in [Worker, Infantry]:
		blueprints.append(UnitBlueprint.new(unit_script))
	buildables.append(FoundationBuildable.new())
	buildables.append(BridgeBuildable.new())
	buildables.append(ExtractorBuildable.new())
	buildables.append(ConveyorBuildable.new())


func get_buildable(id: String) -> Buildable:
	for b in buildables:
		if b.id == id:
			return b
	return null


## The blueprint for training a unit type, e.g. "Worker", or null.
func get_blueprint(unit_name: String) -> UnitBlueprint:
	for bp in blueprints:
		if bp.unit_name == unit_name:
			return bp
	return null


## One of this colony's units by its id, or null.
func get_unit(id: int) -> Unit:
	for u in units:
		if u.id == id:
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


## Units at home that haven't been given orders or told to wait.
func get_units_needing_orders() -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.needs_orders():
			result.append(u)
	return result


## Tells a unit at home to wait (or wakes it).
func set_unit_waiting(unit: Unit, value: bool) -> bool:
	if unit.hub != self or not unit.set_waiting(value):
		return false
	if value:
		unit_event.emit("%s is waiting at the hub" % unit.display_name)
	else:
		unit_event.emit("%s is ready for orders" % unit.display_name)
	return true


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
	if unit.hub != self or not unit.can_accept_mission(mission):
		return false
	var cost := mission.get_cost()
	if not can_afford(cost):
		return false
	_change_resources(cost, -1)
	unit.assign_mission(mission)
	unit.add_materials(cost)
	mission.on_assigned()  # Line builds take their first job's materials.
	unit_event.emit("%s ordered: %s" % [unit.display_name, mission.get_description()])
	return true


## Withdraws an order from a unit that hasn't left yet (or is back at the hub
## waiting), putting the materials it was given back in the stockpile.
func cancel_mission(unit: Unit) -> bool:
	if unit.hub != self:
		return false
	if not unit.cancel_mission():
		return false
	_change_resources(unit.take_materials(), 1)
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


func add_resource(type: ResourceDeposit.Type, amount: int) -> void:
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

## What training one more of `blueprint` costs right now. The price rises
## with each one the colony has ever had - starting units, ones trained and
## ones still in training - so losing units doesn't make the next cheaper
## (see UnitBlueprint.cost_for()).
func get_training_cost(blueprint: UnitBlueprint) -> Dictionary:
	var built: int = _units_ever_had.get(blueprint.unit_name, 0)
	for order in training_queue:
		if order.blueprint == blueprint:
			built += 1
	return blueprint.cost_for(built)


## Pays for and queues a new unit. Returns false if we can't afford it.
func queue_training(blueprint: UnitBlueprint) -> bool:
	var cost := get_training_cost(blueprint)
	if not can_afford(cost):
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

func place(p_map: HexMap, p_hex: Vector2i) -> void:
	super.place(p_map, p_hex)
	map.register_hub(self)
	if not map.tile_changed.is_connected(_on_tile_changed):
		map.tile_changed.connect(_on_tile_changed)
	update_network()


func _on_tile_changed(_h: Vector2i) -> void:
	update_network()


## Flood-fills out from the hub through this faction's own conveyors and
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
			if tile and Structure.carries_resources(tile.structure) and tile.structure_owner == faction:
				network[n] = current
				frontier.append(n)
	_network = network
	map.queue_redraw()

	var producing := {}
	for h in get_producing_extractors():
		producing[h] = true
		if not _producing.has(h):
			var deposit := map.get_tile(h).deposit
			extractor_connected.emit(h, deposit.type)
			unit_event.emit("Extractor at (%d, %d) is connected: %s %s per turn"
				% [h.x, h.y, ResourceDeposit.format_change(ExtractorBuildable.output_for(deposit.type)), deposit.get_display_name()])
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


## Extractors linked to the hub that still have something to mine.
func get_producing_extractors() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in _network:
		var tile := map.get_tile(h)
		if tile.structure == Structure.Type.EXTRACTOR and tile.has_deposit():
			result.append(h)
	return result


## Biomass eaten per turn by all of this hub's units.
func get_upkeep() -> int:
	var total := 0
	for u in units:
		total += u.upkeep
	return total


## Overall change per turn, on average: extractors + hub production - unit
## upkeep. Type -> float (may be fractional or negative).
func get_net_income() -> Dictionary:
	var net := get_income()
	var biomass := ResourceDeposit.Type.BIOMASS
	net[biomass] = net.get(biomass, 0.0) + HUB_BIOMASS_OUTPUT - get_upkeep()
	return net


## Resources delivered per turn by the supply network, on average:
## Type -> float.
func get_income() -> Dictionary:
	var income := {}
	for h in get_producing_extractors():
		var type := map.get_tile(h).deposit.type
		income[type] = income.get(type, 0.0) + ExtractorBuildable.output_for(type)
	return income


## Each producing extractor adds its output to its progress (in hundredths);
## every full 100 delivers 1 unit from its deposit. An extractor whose
## deposit runs dry is dismantled, leaving the conveyor belt it was built on
## (so a line running through it stays connected).
func _process_extractors() -> void:
	# Forget progress on tiles that are no longer our extractors.
	for h in _extractor_progress.keys():
		var tile := map.get_tile(h)
		if tile.structure != Structure.Type.EXTRACTOR or tile.structure_owner != faction:
			_extractor_progress.erase(h)
	for h in get_producing_extractors():
		var deposit := map.get_tile(h).deposit
		var rate := ResourceDeposit.get_info(deposit.type).extractor_output_hundredths()
		var progress: int = _extractor_progress.get(h, 0) + rate
		var whole := progress / 100
		_extractor_progress[h] = progress % 100
		if whole > 0:
			add_resource(deposit.type, deposit.extract(whole))
		if deposit.is_depleted():
			map.set_structure(h, Structure.Type.CONVEYOR, faction)
			_extractor_progress.erase(h)
			unit_event.emit("Extractor at (%d, %d) has exhausted its %s deposit and was removed (the belt stays)"
				% [h.x, h.y, deposit.get_display_name()])
	# Older saves may still have extractors on deposits that ran dry.
	for h in _network.keys():  # A copy: changing a tile rebuilds _network.
		var tile := map.get_tile(h)
		if tile.structure == Structure.Type.EXTRACTOR and tile.structure_owner == faction and not tile.has_deposit():
			map.set_structure(h, Structure.Type.CONVEYOR, faction)


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


## "Production" step: training progresses, extractors deliver, the hub
## grows its biomass. (After movement, so a freshly trained unit just
## waits in the garrison.)
func produce() -> void:
	_process_training()
	_process_extractors()
	add_resource(ResourceDeposit.Type.BIOMASS, HUB_BIOMASS_OUTPUT)


## "Upkeep" step: every unit eats. Returns true if biomass went below zero.
func feed_units() -> bool:
	add_resource(ResourceDeposit.Type.BIOMASS, -get_upkeep())
	return get_resource(ResourceDeposit.Type.BIOMASS) < 0


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
	return {
		"extractor_progress": progress,
		"faction": faction,
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
		var paid := SaveGame.resources_from_data(entry[2]) if entry.size() > 2 else bp.cost_for(0)
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
	if data["collapsed"]:
		collapse()


## Eliminated (starved): every unit dies and the hub stops working. The
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
		return "%s (%s) - collapsed, abandoned" % [building_name, Faction.get_display_name(faction)]
	var text := "%s (%s) - %d/%d units home" % [
		building_name, Faction.get_display_name(faction), get_garrison().size(), units.size()]
	if faction != Faction.local_faction:
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


## Home: unloads what it harvested, and puts back any materials its job
## didn't use.
func _on_unit_returned(unit: Unit) -> void:
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
	draw_polyline(outline, Faction.get_color(faction), 3.0, true)
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
