class_name Game
extends Node2D
## Main game controller: builds (or loads) the world, routes input and
## connects the HUD.
##
## The local player opens their hub and gives orders to units at home, then
## presses End Turn. Every action goes through Orders; how the turn is then
## resolved lives in TurnManager. Nothing here assumes which colony is the
## local one, or how many colonies there are - see local_faction.
##
## F5 saves the game, F9 loads it (see SaveGame).

## A saved game to load instead of starting a new one. Set it, then reload
## the scene (see load_game()).
static var pending_load: Dictionary = {}

## Workers every colony starts with.
@export var starting_workers := 1
## Every hub gets at least one deposit of every resource within this many
## tiles (added at map creation if the map didn't already have one there).
@export var starting_deposit_radius := 4
## Skip straight past turns where every unit is already busy when the turn
## starts (nobody needs orders). Turns where the player acts are never skipped.
@export var auto_skip_turns := true
## How many computer-controlled rival colonies to add (see AiController).
## As many as the map has room for are placed.
@export var rival_count := 4
## Hubs are never placed closer together than this many tiles. Rivals are
## spread out as far from every other hub as the map allows.
@export var rival_min_distance := 8

@onready var map: HexMap = $HexMap
@onready var buildings_root: Node2D = $Buildings
@onready var overlay: HexOverlay = $HexOverlay
@onready var camera: CameraController = $Camera
@onready var hud: Hud = $Hud

## Every colony in the game, indexed by faction.
var colonies: Array[CentralHub] = []
## Factions played by humans; every other colony gets an AI. (One for now -
## more for hot-seat or network play later.)
var human_factions: Array[int] = [Faction.PLAYER]
## The faction played from this computer.
var local_faction := Faction.PLAYER
## The AI playing each computer-controlled colony.
var ais: Array[AiController] = []
## The local player's colony (colonies[local_faction]).
var hub: CentralHub
var orders: Orders
var turns: TurnManager

var _hover_hex := Vector2i.ZERO
var _has_hover := false
## The unit we're choosing a destination for, or null.
var _targeting_unit: Unit = null
## Mission id being targeted ("move", "harvest").
var _targeting_kind := "move"
## Set once someone wins or loses; stops input.
var _game_over := false


func _ready() -> void:
	overlay.map = map
	var save := pending_load
	pending_load = {}
	var start_turn := 1
	if save.is_empty():
		_new_world()
	else:
		start_turn = _load_world(save)
	Faction.local_faction = local_faction
	hub = colonies[local_faction]
	orders = Orders.new(map, colonies)
	for colony in colonies:
		if not colony.faction in human_factions and not colony.collapsed:
			ais.append(AiController.new(colony, map, orders))
	_setup_turns(start_turn)
	turns.win_goal_reached_already = bool(save.get("gold_goal_reached", false))
	UnitStackLayout.arrange(map)

	hub.unit_event.connect(hud.log_event)
	hub.units_changed.connect(_refresh_markers)
	hud.end_turn_requested.connect(turns.end_turn)
	hud.mission_requested.connect(_begin_targeting)
	hud.cancel_mission_requested.connect(func(unit: Unit) -> void:
		if _submit(Orders.cancel_mission(unit)) == "":
			hud.log_event("%s's mission was cancelled" % unit.display_name))
	hud.focus_requested.connect(func(unit: Unit) -> void: camera.focus_on(map.hex_to_world(unit.hex)))
	hud.wait_requested.connect(func(unit: Unit, value: bool) -> void:
		_submit(Orders.wait(unit, value)))
	hud.hub_panel_closed.connect(_cancel_targeting)
	hud.auto_end_toggled.connect(turns.set_auto_skip)
	hud.train_requested.connect(func(bp: UnitBlueprint) -> void:
		_submit(Orders.train(bp.unit_name)))
	hud.cancel_training_requested.connect(func(index: int) -> void:
		_submit(Orders.cancel_training(index)))
	# TESTING ONLY - remove before release.
	hud.debug_resources_requested.connect(func() -> void:
		if _submit(Orders.debug_resources()) == "":
			hud.log_event("Testing: added %d of every resource." % Orders.DEBUG_RESOURCE_AMOUNT))
	hub.inventory_changed.connect(_update_inventory)
	hub.network_changed.connect(_update_inventory)
	# Unit count changes biomass upkeep, so the per-turn figure must refresh.
	hub.units_changed.connect(_update_inventory)

	camera.set_bounds(map.get_world_rect())
	camera.focus_on(hub.global_position)

	hud.set_turn(turns.turn)
	_update_inventory()
	hud.set_hub(hub)
	_refresh_markers()
	if save.is_empty():
		hud.log_event("Your colony hub has landed on Mars. Open Units (bottom bar) to give orders.")
	else:
		hud.log_event("Game loaded (turn %d)." % turns.turn)


## Sends one of the local player's orders. Returns "" if it was carried out,
## otherwise why not. (Later, for network play, this is where an order would
## be sent to the host instead.)
func _submit(order: Dictionary) -> String:
	turns.player_acted()
	return orders.submit(local_faction, order)


# --- Saving and loading ----------------------------------------------------

func save_game() -> void:
	if _game_over:
		hud.log_event("The game is over - nothing to save.")
		return
	var data := SaveGame.capture(map, colonies, turns.turn, human_factions, turns.win_goal_reached_already)
	var err := SaveGame.write_file(data)
	hud.log_event("Game saved (turn %d)." % turns.turn if err == OK else "Couldn't save the game (error %d)." % err)


## Replaces the current game with the saved one, by reloading the scene.
func load_game() -> void:
	var data := SaveGame.read_file()
	if data.is_empty():
		hud.log_event("No saved game to load.")
		return
	pending_load = data
	get_tree().reload_current_scene()


## Rebuilds a saved game. Returns the turn it was saved on.
func _load_world(data: Dictionary) -> int:
	map.load_dict(data["map"])
	human_factions.clear()
	for f in data["human_factions"]:
		human_factions.append(int(f))
	local_faction = human_factions[0]
	for colony_data: Dictionary in data["colonies"]:
		var colony := CentralHub.new()
		colony.faction = int(colony_data["faction"])
		buildings_root.add_child(colony)
		colony.place(map, SaveGame.hex_from_data(colony_data["hex"]))
		colony.load_dict(colony_data)
		colonies.append(colony)
	return int(data["turn"])


# --- World -----------------------------------------------------------------

## Where each colony's hub goes, indexed by faction (player first).
var _hub_spots: Array[Vector2i] = []


## A fresh game: a new map with a hub for every colony, each with every kind
## of resource nearby but none right next to it.
func _new_world() -> void:
	_generate_world()
	map.clear_deposits_around(_hub_spots)
	map.guarantee_deposits_near(_hub_spots, starting_deposit_radius)
	map.place_remote_deposits(_hub_spots)  # Unobtainium, far from everyone.
	for faction in _hub_spots.size():
		colonies.append(_create_hub(faction, _hub_spots[faction]))


## Generates maps until one has room for the player and every rival. If none
## does, keeps the attempt that fitted the most.
func _generate_world() -> void:
	var best_seed := -1
	var best_spots: Array[Vector2i] = []
	for attempt in 20:
		map.generate()
		var spot: Variant = _find_hub_spot()
		if spot == null:
			continue
		var spots := _place_hubs(spot)
		if spots.size() == rival_count + 1:
			_hub_spots = spots
			return
		if spots.size() > best_spots.size():
			best_spots = spots
			best_seed = map.last_seed
	if best_seed == -1:
		push_error("Couldn't find anywhere to put the player's hub.")
		_hub_spots = [Hex.offset_to_axial(map.width >> 1, map.height >> 1)]
		return
	push_warning("Only found room for %d of %d rivals." % [best_spots.size() - 1, rival_count])
	map.generate(best_seed)
	_hub_spots = best_spots


## Builds a hub for `faction` at `spot` with the starting units. Colonies
## start with an empty stockpile.
func _create_hub(faction: int, spot: Vector2i) -> CentralHub:
	var new_hub := CentralHub.new()
	new_hub.faction = faction
	buildings_root.add_child(new_hub)
	new_hub.place(map, spot)
	map.remove_deposit(spot)
	for i in starting_workers:
		new_hub.add_unit(Worker.new())
	return new_hub


## Hub spots for the player and up to rival_count rivals, indexed by
## faction. Rivals are placed one at a time: each on open ground the player
## can walk to, as far as possible from every hub placed so far (and at
## least rival_min_distance away), so they spread out.
func _place_hubs(player_spot: Vector2i) -> Array[Vector2i]:
	var candidates := _open_ground_reachable_from(player_spot)
	var placed: Array[Vector2i] = [player_spot]
	for i in rival_count:
		var best: Variant = null
		var best_gap := rival_min_distance - 1
		for h in candidates:
			var gap := 1 << 30
			for other in placed:
				gap = mini(gap, Hex.distance(h, other))
			if gap > best_gap:
				best = h
				best_gap = gap
		if best == null:
			break  # No room left.
		placed.append(best)
	return placed


## Passable tiles with at least 5 passable neighbours that can be walked to
## from `start`.
func _open_ground_reachable_from(start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var h: Vector2i = frontier.pop_back()
		var open := 0
		for n in Hex.neighbors(h):
			if map.is_passable(n):
				open += 1
				if not seen.has(n):
					seen[n] = true
					frontier.append(n)
		if open >= 5:
			result.append(h)
	return result


## The passable tile nearest the map centre that has open neighbours and
## sits on a reasonably large landmass.
func _find_hub_spot() -> Variant:
	var center := Hex.offset_to_axial(map.width >> 1, map.height >> 1)
	var candidates: Array[Vector2i] = []
	for h in map.tiles:
		if not map.is_passable(h):
			continue
		var open := 0
		for n in Hex.neighbors(h):
			if map.is_passable(n):
				open += 1
		if open >= 5:
			candidates.append(h)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Hex.distance(a, center) < Hex.distance(b, center))
	var min_land := int(map.tiles.size() * 0.25)
	for h in candidates.slice(0, 30):
		if map.count_reachable(h) >= min_land:
			return h
	return null


# --- Turns -----------------------------------------------------------------
# The turn order itself is in TurnManager; this just connects it up.

func _setup_turns(start_turn: int) -> void:
	turns = TurnManager.new()
	turns.name = "TurnManager"
	add_child(turns)
	var active: Array[CentralHub] = []
	for colony in colonies:
		if not colony.collapsed:
			active.append(colony)
	turns.setup(map, hub, active, ais.duplicate())
	turns.turn = start_turn
	turns.auto_skip = auto_skip_turns
	turns.turn_ending.connect(_cancel_targeting)
	turns.event_logged.connect(hud.log_event)
	turns.turn_started.connect(func(turn: int) -> void:
		hud.set_turn(turn)
		_refresh_markers())
	turns.colonies_starved.connect(_on_colonies_starved)
	turns.win_goal_reached.connect(_on_win_goal_reached)
	hud.popup_closed.connect(func() -> void: turns.paused = false)


## Someone reached the win goal first: say who won. Play can carry on.
func _on_win_goal_reached(winners: Array[CentralHub]) -> void:
	_cancel_targeting()
	turns.paused = true  # Until the popup is closed.
	var goal := "%d %s" % [TurnManager.AMOUNT_TO_WIN, ResourceDeposit.get_type_name(TurnManager.WIN_RESOURCE)]
	var title: String
	var message: String
	var color: Color
	if winners.size() > 1:
		var names: PackedStringArray = []
		for w in winners:
			names.append(Faction.get_display_name(w.faction))
		title = "It's a Tie!"
		message = "%s reached %s on the same turn and share the win." % [" and ".join(names), goal]
		color = ResourceDeposit.get_type_color(TurnManager.WIN_RESOURCE)
	elif winners[0] == hub:
		title = "You Win!"
		message = "Your colony was the first to gather %s." % goal
		color = Faction.get_color(local_faction)
	else:
		var name := Faction.get_display_name(winners[0].faction)
		title = "%s Wins" % name
		message = "The %s was the first to gather %s." % [name.to_lower(), goal]
		color = Faction.get_color(winners[0].faction)
	message += "\n\nYou can keep playing, or start a new game."
	hud.log_event("%s (turn %d)" % [title, turns.turn])
	hud.show_winner(title, message, color)


## The local player starving is a loss (even if others starved on the same
## turn). Any other starving colony is eliminated; once only the local
## player's is left, they win.
func _on_colonies_starved(starved: Array[CentralHub]) -> void:
	if hub in starved:
		_end_game("Colony Lost",
			"Your biomass fell below zero on turn %d and your units could no longer be fed." % turns.turn,
			Color(1.0, 0.4, 0.35))
		hud.log_event("Biomass has run out - your colony has starved.")
		return
	for colony in starved:
		turns.remove_colony(colony)
		colony.collapse()
		hud.log_event("The %s has run out of biomass and collapsed." % Faction.get_display_name(colony.faction).to_lower())
	if turns.hubs.size() == 1 and hub in turns.hubs:
		_end_game("Victory",
			"Every rival colony has run out of biomass and collapsed. Mars is yours (turn %d)." % turns.turn,
			Color(0.45, 0.95, 0.4))


func _end_game(title: String, message: String, color: Color) -> void:
	_game_over = true
	turns.stop()
	_cancel_targeting()
	hud.show_game_over(title, message, color)


# --- Input -----------------------------------------------------------------

func _process(_delta: float) -> void:
	var h := map.world_to_hex(get_global_mouse_position())
	var has := map.has_tile(h)
	if h != _hover_hex or has != _has_hover:
		_hover_hex = h
		_has_hover = has
		overlay.set_hover(h, has)
		_update_hover_info()


func _unhandled_input(event: InputEvent) -> void:
	if _game_over or hud.is_popup_open():
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_targeting()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			turns.end_turn()
		elif key.keycode == KEY_F5:
			save_game()
		elif key.keycode == KEY_F9:
			load_game()
		elif key.keycode == KEY_ESCAPE:
			if _targeting_unit:
				_cancel_targeting()
			else:
				hud.hide_hub()


func _on_left_click() -> void:
	if not _has_hover:
		return
	if _targeting_unit:
		var unit := _targeting_unit
		var reason := _submit(Orders.mission(unit, _targeting_kind, _hover_hex))
		if reason == "":
			_cancel_targeting()
		else:
			hud.set_hint("%s: %s. Pick another tile (right-click/Esc to cancel)."
				% [unit.display_name, reason])
		return
	if _hover_hex == hub.hex:
		hud.show_hub(hub)
	else:
		hud.hide_hub()


# --- Targeting -------------------------------------------------------------

func _begin_targeting(unit: Unit, kind: String) -> void:
	if kind.begins_with("escort:"):
		# Nothing to pick on the map: order it straight away.
		_cancel_targeting()
		var reason := _submit(Orders.mission(unit, kind, hub.hex))
		hud.set_hint("" if reason == "" else "%s: %s" % [unit.display_name, reason])
		return
	_targeting_unit = unit
	_targeting_kind = kind
	var what := "a destination"
	if kind == "demolish":
		what = "something man-made to demolish"
	elif kind == "harvest":
		what = "a deposit to harvest"
	elif kind == "guard":
		what = "a tile to guard"
	elif kind == "capture":
		what = "another colony's structure to capture"
	elif kind.begins_with("build:"):
		var b := hub.get_buildable(kind.trim_prefix("build:"))
		if b.line_of == b.id:
			what = "where to build %ss to (every tile from the hub gets one)" % b.display_name
		elif b.line_of != "":
			what = "a deposit for the %s (it gets connected to the hub)" % b.display_name
		else:
			what = "where to build a %s" % b.display_name
	hud.set_hint("Choose %s for %s (right-click/Esc to cancel)" % [what, unit.display_name])
	_update_hover_info()


func _cancel_targeting() -> void:
	if _targeting_unit == null:
		return
	_targeting_unit = null
	overlay.clear_preview()
	hud.set_hint("")
	_update_hover_info()


func _update_hover_info() -> void:
	if not _has_hover:
		hud.set_tile_info("")
		if _targeting_unit:
			overlay.clear_preview()
		return

	var tile := map.get_tile(_hover_hex)
	var info := "%s (%d, %d)" % [tile.get_display_name(), _hover_hex.x, _hover_hex.y]
	info += "  -  move cost %d" % tile.get_move_cost() if tile.is_passable() else "  -  impassable"
	if tile.has_deposit():
		info += "\n" + tile.deposit.get_info_text()
	if tile.structure != Structure.Type.NONE:
		info += "\n" + _structure_info(tile)
	var hub_here := map.get_hub_at(_hover_hex)
	if hub_here:
		info += "\n" + hub_here.get_info_text()

	if _targeting_unit:
		# Preview: the same checks the order will get, without sending it.
		var unit := _targeting_unit
		var mission := Orders.make_mission(hub, _targeting_kind, _hover_hex)
		var reason := Orders.get_invalid_reason(hub, unit, mission) if mission else "unknown mission"
		var valid := reason == ""
		var preview: Array[Vector2i] = []
		var label := ""
		if valid:
			var line := mission as LineBuildMission
			var path: Array[Vector2i] = line.plan_route(hub, map, hub.hex, _hover_hex) if line \
				else map.find_path(hub.hex, mission.get_travel_hex())
			preview.append(hub.hex)
			preview.append_array(path)
			if line:
				# Line jobs: everything to build and what it all costs.
				var total := line.get_total_cost(hub, map, hub.hex)
				label = ResourceDeposit.format_cost(total)
				info += "\nRoute: %d tiles. To build:" % path.size()
				for job in line.get_job_counts(hub, map, hub.hex):
					var b: Buildable = job[0]
					var n: int = job[1]
					var each := {}
					for type in b.cost:
						each[type] = b.cost[type] * n
					info += "\n  %d %s%s - %s" % [n, b.display_name, "" if n == 1 else "s",
						ResourceDeposit.format_cost(each)]
				info += "\nTotal %s, paid job by job" % label
			else:
				var trip_turns := unit.estimate_turns(path)
				label = "%d turn%s" % [trip_turns, "" if trip_turns == 1 else "s"]
				var work := mission.get_work_turns()
				if work > 0:
					label += " + %d working" % work
				info += "\nRoute: %d tiles, ~%s (then returns home)" % [path.size(), label]
			if not line and not mission.get_cost().is_empty():
				info += "\nCost: %s" % ResourceDeposit.format_cost(mission.get_cost())
		else:
			preview.append(_hover_hex)
			label = reason.left(1).to_upper() + reason.substr(1)
			info += "\n" + label
		overlay.set_preview(preview, valid, label)

	hud.set_tile_info(info)


func _structure_info(tile: HexTile) -> String:
	var text := Structure.get_display_name(tile.structure)
	if tile.structure_owner != local_faction:
		text = "%s's %s" % [Faction.get_display_name(tile.structure_owner), text]
	var owner_hub: CentralHub = map.hubs.get(tile.structure_owner)
	var connected := owner_hub != null and owner_hub.is_supply_connected(tile.coord)
	if tile.structure == Structure.Type.EXTRACTOR:
		if not tile.has_deposit():
			return text + " - deposit exhausted"
		if connected:
			return text + " - connected, %s %s per turn" % [
				ResourceDeposit.format_change(ExtractorBuildable.output_for(tile.deposit.type)), tile.deposit.get_display_name()]
		return text + " - NOT connected (needs conveyor belts to the hub)"
	return text + (" - connected to the hub" if connected else " - not connected to the hub")


func _update_inventory() -> void:
	hud.set_inventory(hub.inventory, hub.get_net_income())


func _refresh_markers() -> void:
	var markers: Array[Vector2i] = []
	for unit in hub.units:
		if unit.mission:
			var target: Variant = unit.mission.get_target_hex()
			if target != null:
				markers.append(target)
	overlay.set_markers(markers)
