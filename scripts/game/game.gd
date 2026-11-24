class_name Game
extends Node2D
## Main game controller: builds (or loads) the world, routes input and
## connects the HUD.
##
## The local player opens their hub and gives orders to units at home, then
## presses End Turn. Every action goes through Orders; how the turn is then
## resolved lives in TurnManager. Nothing here assumes which colony is the
## local one, or how many colonies there are - see local_player.
##
## F5 saves the game, F9 loads it (see SaveGame).

## A saved game to load instead of starting a new one. Set it, then reload
## the scene (see load_game()).
static var pending_load: Dictionary = {}

## Every hub gets at least one deposit of every resource within this many
## tiles (added at map creation if the map didn't already have one there).
@export var starting_deposit_radius := 4
## Skip straight past turns where every unit is already busy when the turn
## starts (nobody needs orders). Turns where the player acts are never skipped.
@export var auto_skip_turns := true
## How many computer-controlled rival colonies to add (see AiController).
## As many as the map has room for are placed.
@export var rival_count := 4
## Hubs are never placed closer together than this many tiles.
@export var min_player_distance := 10
## Hubs are at least this many tiles in from the edge of the map (a hub in
## column 5 has 5 tiles between it and the edge).
@export var min_edge_distance := 5
## How many random layouts to try on each map before generating another.
const HUB_LAYOUT_TRIES := 300
## Most seconds the battle replays wait for this turn's moves to play first.
const MAX_MOVE_WAIT := 5.0

@onready var map: HexMap = $HexMap
@onready var players_root: Node2D = $Players
@onready var overlay: HexOverlay = $HexOverlay
@onready var camera: CameraController = $Camera
@onready var hud: Hud = $Hud

## Every player in the game, indexed by Player.id. Those with is_ai set
## get an AiController; the rest are played by humans. (One human for now -
## more for hot-seat or network play later.)
var players: Array[Player] = []
## The AI playing each computer-controlled colony.
var ais: Array[AiController] = []
## The player at this computer: the first human player.
var local_player: Player
var orders: Orders
var turns: TurnManager
## What the player could still do this turn - drives the Next button and
## stops auto-skip (see Attention).
var attention: Attention

var _hover_hex := Vector2i.ZERO
var _has_hover := false
## The unit we're choosing a destination for, or null.
var _targeting_unit: Unit = null
## Mission id being targeted ("move", "harvest").
var _targeting_kind := "move"
## How many times the unit being targeted should do it (see Orders.mission()).
var _targeting_repeats := 1
## Set once someone wins or loses; stops input.
var _game_over := false
## A starvation report (see Player.starve()) waiting for this turn's battle
## replays to finish before its popup shows; {} if none.
var _pending_starvation: Dictionary = {}
## Hub hits this turn involving us, for the banners at the start of the
## next: "attacker id:defender id" -> health left (the latest).
var _hub_hits: Dictionary = {}
## Our structures an enemy took this turn, for the next turn's banner:
## [[Structure.Type, by faction, captured?, hex]].
var _lost_structures: Array = []
## Enemy units standing on our structures (our territory) last we looked:
## unit id -> true. Only newcomers get a banner (see _check_intruders()).
var _intruders: Dictionary = {}
## Banners waiting for the battle replays to finish (see Notices).
var _pending_notices: Array[Dictionary] = []


func _ready() -> void:
	overlay.map = map
	var save := pending_load
	pending_load = {}
	var start_turn := 1
	if save.is_empty():
		_new_world()
	else:
		start_turn = _load_world(save)
	# One set of tech trees for everyone, shuffled from the map's seed (so a
	# loaded game gets the same ones back).
	var tech_trees := TechTrees.new(map.last_seed)
	for player in players:
		player.tech_trees = tech_trees
	for player in players:
		if not player.is_ai:
			local_player = player
			break
	Faction.local_faction = local_player.id
	orders = Orders.new(map, players)
	for player in players:
		if player.is_ai and not player.collapsed:
			ais.append(AiController.new(player, map, orders))
	_setup_turns(start_turn)
	turns.win_goal_reached_already = bool(save.get("gold_goal_reached", false))
	UnitStackLayout.arrange(map)

	for player in players:
		player.hub_damaged.connect(_on_hub_damaged.bind(player))
	map.structure_lost.connect(_on_structure_lost)
	local_player.unit_event.connect(hud.log_event)
	local_player.units_changed.connect(_refresh_markers)
	hud.end_turn_requested.connect(_on_end_turn_pressed)
	hud.section_closed.connect(func(section: Hud.Section) -> void: attention.dismiss_section(section))
	hud.mission_requested.connect(_begin_targeting)
	hud.cancel_mission_requested.connect(func(unit: Unit) -> void:
		if _submit(Orders.cancel_mission(unit)) == "":
			hud.log_event("%s's mission was cancelled" % unit.display_name))
	hud.focus_requested.connect(func(unit: Unit) -> void: camera.focus_on(map.hex_to_world(unit.hex)))
	hud.room_move_requested.connect(func(unit: Unit, room_id: String, wait_turns: int) -> void:
		var reason := _submit(Orders.move_room(unit, room_id, wait_turns))
		if reason != "":
			hud.log_event("Can't move %s: %s" % [unit.display_name, reason]))
	hud.hub_panel_closed.connect(_cancel_targeting)
	hud.recall_all_requested.connect(func() -> void:
		_cancel_targeting()
		_submit(Orders.recall_all()))
	hud.notice_shown.connect(func(notice: Dictionary) -> void:
		if notice.get("at") != null:
			camera.focus_on(map.hex_to_world(notice["at"])))
	hud.regroup_requested.connect(func() -> void:
		var reason := _submit(Orders.start_regroup())
		if reason != "":
			hud.log_event("Can't regroup: %s" % reason)
		hud.refresh())
	hud.auto_end_toggled.connect(turns.set_auto_skip)
	hud.train_requested.connect(func(bp: UnitBlueprint) -> void:
		_submit(Orders.train(bp.unit_name)))
	hud.cancel_training_requested.connect(func(index: int) -> void:
		_submit(Orders.cancel_training(index)))
	hud.build_building_requested.connect(func(building_id: String) -> void:
		var reason := _submit(Orders.build_building(building_id))
		if reason != "":
			hud.log_event("Can't build that: %s" % reason))
	hud.cancel_building_requested.connect(func(index: int) -> void:
		_submit(Orders.cancel_building(index)))
	hud.research_requested.connect(func(tech_id: String) -> void:
		var reason := _submit(Orders.research(tech_id))
		if reason != "":
			hud.log_event("Can't research that: %s" % reason))
	hud.cancel_research_requested.connect(func(tech_id: String) -> void:
		_submit(Orders.cancel_research(tech_id)))
	hud.repair_hub_requested.connect(func() -> void:
		var reason := _submit(Orders.repair_hub())
		if reason == "":
			hud.log_event("Repaired the hub (%d/%d health)." % [local_player.hub_health, Player.HUB_MAX_HEALTH])
		else:
			hud.log_event("Can't repair the hub: %s" % reason)
		hud.refresh())
	hud.heal_order_requested.connect(func(unit: Unit, index: int) -> void:
		var reason := _submit(Orders.heal_order(unit, index))
		if reason != "":
			hud.log_event("Can't reorder %s: %s" % [unit.display_name, reason])
		hud.refresh())
	# TESTING ONLY - remove before release.
	hud.debug_resources_requested.connect(func() -> void:
		if _submit(Orders.debug_resources()) == "":
			hud.log_event("Testing: added %d of every resource." % Orders.DEBUG_RESOURCE_AMOUNT))
	local_player.inventory_changed.connect(_update_inventory)
	local_player.network_changed.connect(_update_inventory)
	# Unit count changes biomass upkeep, so the per-turn figure must refresh.
	local_player.units_changed.connect(_update_inventory)

	camera.set_bounds(map.get_world_rect())
	camera.focus_on(local_player.global_position)

	hud.set_turn(turns.turn)
	_update_inventory()
	hud.set_player(local_player)
	_refresh_markers()
	if save.is_empty():
		hud.log_event("Your colony hub has landed on Mars. Open Mission Briefing (bottom bar) to give orders, or Central Hub to see its rooms.")
	else:
		hud.log_event("Game loaded (turn %d)." % turns.turn)


## Sends one of the local player's orders. Returns "" if it was carried out,
## otherwise why not. (Later, for network play, this is where an order would
## be sent to the host instead.)
func _submit(order: Dictionary) -> String:
	turns.player_acted()
	return orders.submit(local_player.id, order)


# --- Saving and loading ----------------------------------------------------

func save_game() -> void:
	if _game_over:
		hud.log_event("The game is over - nothing to save.")
		return
	var data := SaveGame.capture(map, players, turns.turn, turns.win_goal_reached_already)
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
	# Older saves listed the human players separately and called players
	# "colonies".
	var humans: Array = data.get("human_factions", [Faction.PLAYER])
	for player_data: Dictionary in data.get("players", data.get("colonies", [])):
		var player := Player.new()
		player.id = int(player_data.get("id", player_data.get("faction")))
		player.is_ai = bool(player_data.get("is_ai", not humans.any(func(f: Variant) -> bool: return int(f) == player.id)))
		players_root.add_child(player)
		player.place(map, SaveGame.hex_from_data(player_data["hex"]))
		player.load_dict(player_data)
		players.append(player)
	return int(data["turn"])


# --- World -----------------------------------------------------------------

## Where each colony's hub goes, indexed by faction (player first).
var _hub_spots: Array[Vector2i] = []


## A fresh game: a new map with a hub for every colony, each with every kind
## of resource nearby but none right next to it, and a control point.
func _new_world() -> void:
	_generate_world()
	map.clear_deposits_around(_hub_spots)
	map.guarantee_deposits_near(_hub_spots, starting_deposit_radius)
	map.place_remote_deposits(_hub_spots)  # Electrum, far from everyone.
	map.place_control_points(_hub_spots)
	for faction in _hub_spots.size():
		players.append(_create_player(faction, _hub_spots[faction]))


## Generates maps until one has room for the player and every rival. If none
## does, keeps the attempt that fitted the most.
func _generate_world() -> void:
	var best_seed := -1
	var best_spots: Array[Vector2i] = []
	for attempt in 20:
		map.generate()
		var spots := _pick_hub_spots(rival_count + 1)
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


## A new player with id `faction` and its hub at `spot`, with the starting
## units and buildings. Players start with an empty stockpile. The first
## (Faction.PLAYER) is played from this computer; the rest are AIs.
func _create_player(faction: int, spot: Vector2i) -> Player:
	var new_player := Player.new()
	new_player.id = faction
	new_player.is_ai = faction != Faction.PLAYER
	new_player.team = Player.AI_TEAM if new_player.is_ai else Player.HUMAN_TEAM
	players_root.add_child(new_player)
	new_player.place(map, spot)
	map.remove_deposit(spot)
	new_player.add_unit(Miner.new())  # Every colony starts with its Miner, but no Builder.
	new_player.add_building(Greenhouse.new())
	return new_player


## Random hub spots for `count` players, indexed by faction, following the
## rules: every hub is at least min_player_distance from every other and
## min_edge_distance in from the map's edge, on open ground, and all on the
## same landmass so everyone can walk to everyone else. Nobody gets a
## special spot - the local player's is as random as the rest.
##
## Tries HUB_LAYOUT_TRIES random orders, each time placing hubs one by one on
## the first spot far enough from those already placed. Returns fewer than
## `count` spots if no layout fitted them all (the best one found). Random
## but repeatable: the same map seed gives the same spots.
func _pick_hub_spots(count: int) -> Array[Vector2i]:
	var candidates := _hub_candidates()
	var rng := RandomNumberGenerator.new()
	rng.seed = map.last_seed + 7
	var best: Array[Vector2i] = []
	for attempt in HUB_LAYOUT_TRIES:
		# Fisher-Yates with our own rng (Array.shuffle() would use the global one).
		for i in range(candidates.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = swap
		var placed: Array[Vector2i] = []
		for h in candidates:
			if placed.all(func(other: Vector2i) -> bool: return Hex.distance(h, other) >= min_player_distance):
				placed.append(h)
				if placed.size() == count:
					return placed
		if placed.size() > best.size():
			best = placed
	return best


## Every tile a hub may stand on: passable, with at least 5 passable
## neighbours (room to build out from), at least min_edge_distance from the
## map's edge, and on the biggest landmass - which must cover at least a
## quarter of the map. Empty if there's no such landmass.
func _hub_candidates() -> Array[Vector2i]:
	# Split the passable tiles into landmasses (tiles you can walk between).
	var landmass := {}  # hex -> landmass number
	var sizes: Array[int] = []
	for start in map.tiles:
		if landmass.has(start) or not map.is_passable(start):
			continue
		var number := sizes.size()
		landmass[start] = number
		var frontier: Array[Vector2i] = [start]
		var size := 0
		while not frontier.is_empty():
			var h: Vector2i = frontier.pop_back()
			size += 1
			for n in Hex.neighbors(h):
				if not landmass.has(n) and map.is_passable(n):
					landmass[n] = number
					frontier.append(n)
		sizes.append(size)
	var biggest := -1
	for number in sizes.size():
		if sizes[number] >= map.tiles.size() / 4 and (biggest < 0 or sizes[number] > sizes[biggest]):
			biggest = number
	var result: Array[Vector2i] = []
	if biggest < 0:
		return result
	for h in map.tiles:
		if landmass.get(h, -1) != biggest or _distance_from_edge(h) < min_edge_distance:
			continue
		var open := 0
		for n in Hex.neighbors(h):
			if map.is_passable(n):
				open += 1
		if open >= 5:
			result.append(h)
	result.sort()  # map.tiles order isn't guaranteed; keep picks repeatable.
	return result


## How many tiles lie between `h` and the nearest edge of the map (0 for a
## tile on the edge).
func _distance_from_edge(h: Vector2i) -> int:
	var o := Hex.axial_to_offset(h)
	return mini(mini(o.x, map.width - 1 - o.x), mini(o.y, map.height - 1 - o.y))


# --- Turns -----------------------------------------------------------------
# The turn order itself is in TurnManager; this just connects it up.

func _setup_turns(start_turn: int) -> void:
	turns = TurnManager.new()
	turns.name = "TurnManager"
	add_child(turns)
	var active: Array[Player] = []
	for colony in players:
		if not colony.collapsed:
			active.append(colony)
	turns.setup(map, local_player, active, ais.duplicate())
	attention = Attention.new(local_player)
	turns.attention = attention
	turns.turn = start_turn
	turns.auto_skip = auto_skip_turns
	turns.turn_ending.connect(_cancel_targeting)
	turns.event_logged.connect(hud.log_event)
	turns.turn_started.connect(func(turn: int) -> void:
		hud.set_turn(turn)
		_check_intruders()
		_show_notices.call_deferred()  # After any battles start (see there).
		_update_inventory()
		_refresh_markers())
	turns.battles_fought.connect(_show_battles)
	turns.unit_starved.connect(_on_unit_starved)
	turns.colonies_eliminated.connect(_on_colonies_eliminated)
	turns.win_goal_reached.connect(_on_win_goal_reached)
	hud.popup_closed.connect(func() -> void: turns.paused = false)


## Replays this turn's battles that our units were in, one after another,
## moving the camera to each (the rest are only in the event log). Turns
## can't be ended until they've finished (or been skipped).
func _show_battles(reports: Array[Dictionary]) -> void:
	var ours := reports.filter(_involves_us)
	if ours.is_empty():
		return
	turns.showing_battles = true
	_cancel_targeting()
	# Let this turn's moves play out on the map first; aircraft then hang
	# over their targets until the replays are over (see Unit.hold_air_return).
	Unit.hold_air_return = true
	await _moves_shown(MAX_MOVE_WAIT)
	for report: Dictionary in ours:
		if _game_over:
			break
		var center := Vector2.ZERO
		for h: Vector2i in report["core"]:
			center += map.hex_to_world(h)
		camera.focus_on(center / report["core"].size())
		if await hud.play_battle(report, map):
			break
	Unit.hold_air_return = false
	for colony: Player in map.players.values():
		for u in colony.units:
			u.release_return()
	turns.showing_battles = false
	_show_pending_starvation()
	_show_notices()


## Waits until no unit is still playing its move (or `limit` seconds).
func _moves_shown(limit: float) -> void:
	var waited := 0.0
	while waited < limit:
		var moving := false
		for colony: Player in map.players.values():
			for u in colony.units:
				if u.is_animating():
					moving = true
					break
			if moving:
				break
		if not moving:
			return
		await get_tree().process_frame
		waited += get_process_delta_time()


## Whether any of our units fought in a battle (see Combat's report).
func _involves_us(report: Dictionary) -> bool:
	for info: Dictionary in report["units"].values():
		if int(info["faction"]) == local_player.id:
			return true
	return false


## Someone holds every control point (see TurnManager._winners()): say who
## won. Play can carry on.
func _on_win_goal_reached(winners: Array[Player]) -> void:
	_cancel_targeting()
	turns.paused = true  # Until the popup is closed.
	var winner := winners[0]
	var goal := "a command point on all %d control points, every one linked to its hub" % map.control_points.size()
	var title: String
	var message: String
	if local_player in winners:
		title = "You Win!"
		message = "Your %s the first to hold %s." % ["colony was" if winners.size() == 1 else "team was", goal]
	elif winners.size() == 1:
		var name := Faction.get_display_name(winner.id)
		title = "%s Wins" % name
		message = "The %s was the first to hold %s." % [name.to_lower(), goal]
	else:
		var names: PackedStringArray = []
		for w in winners:
			names.append(Faction.get_display_name(w.id).to_lower())
		title = "The Enemy Team Wins"
		message = "Together, the %s were the first to hold %s." % [", ".join(names), goal]
	var color := winner.get_color()
	message += "\n\nYou can keep playing, or start a new game."
	hud.log_event("%s (turn %d)" % [title, turns.turn])
	camera.focus_on(winner.global_position)
	hud.show_winner(title, message, color)


## One of the local player's units starved (see Player.starve()): make sure
## they notice, with a popup explaining why. Waits until this turn's battles
## have been replayed.
func _on_unit_starved(player: Player, report: Dictionary) -> void:
	if player != local_player:
		return
	_pending_starvation = report
	if not turns.showing_battles:
		_show_pending_starvation()


func _show_pending_starvation() -> void:
	if _pending_starvation.is_empty() or _game_over:
		_pending_starvation = {}
		return
	var report := _pending_starvation
	_pending_starvation = {}
	_cancel_targeting()
	turns.paused = true  # Until the popup is closed.
	camera.focus_on(local_player.global_position)
	hud.show_starvation(report)


## Losing every unit (with none in training), or the hub's health, knocks a
## colony out: for the local player that's a loss (even if others went on
## the same turn). Any other colony collapses (with a triumphant popup if
## our Infantry knocked its hub out); once only the local player's is left,
## they win.
func _on_colonies_eliminated(eliminated: Array[Player]) -> void:
	if local_player in eliminated:
		if local_player.hub_health <= 0:
			var by := Faction.get_display_name(local_player.last_attacker.id).to_lower() if local_player.last_attacker else "enemy"
			camera.focus_on(local_player.global_position)
			_end_game("Hub Destroyed",
				"The %s's Infantry have torn down your hub (turn %d). Your colony is lost." % [by, turns.turn],
				Color(1.0, 0.25, 0.2))
			hud.log_event("Your hub has been destroyed - your colony is lost.")
		else:
			_end_game("Colony Lost",
				"Your colony has no units left (turn %d)." % turns.turn,
				Color(1.0, 0.4, 0.35))
			hud.log_event("Your last unit is gone - your colony is lost.")
		return
	for colony in eliminated:
		turns.remove_colony(colony)
		colony.collapse()
		var colony_name := Faction.get_display_name(colony.id).to_lower()
		if colony.hub_health <= 0:
			var by := colony.last_attacker
			if by == local_player:
				hud.log_event("We destroyed the %s's hub - it has collapsed!" % colony_name)
				_hub_hits.erase("%d:%d" % [local_player.id, colony.id])  # The popup says it all.
				turns.paused = true  # Until the popup is closed.
				camera.focus_on(colony.global_position)
				hud.show_colony_destroyed(colony_name)
			else:
				hud.log_event("The %s's hub was destroyed%s - it has collapsed." % [colony_name,
					" by the %s" % Faction.get_display_name(by.id).to_lower() if by else ""])
		else:
			hud.log_event("The %s has lost every unit and collapsed." % colony_name)
	if local_player in turns.players and turns.players.all(local_player.is_ally):
		_end_game("Victory",
			"Every rival colony has collapsed. Mars is yours (turn %d)." % turns.turn,
			Color(0.45, 0.95, 0.4))


## A hub lost health: log it if we're involved, and remember it for this
## turn's banner (see _show_notices()).
func _on_hub_damaged(attacker: Player, health: int, defender: Player) -> void:
	if attacker != local_player and defender != local_player:
		return
	_hub_hits["%d:%d" % [attacker.id if attacker else -1, defender.id]] = health
	if defender == local_player:
		hud.log_event("Enemy Infantry damaged our hub: %d/%d health left!" % [health, Player.HUB_MAX_HEALTH])


## Another colony demolished or captured one of our structures: log it and
## remember it for this turn's banner.
func _on_structure_lost(h: Vector2i, type: Structure.Type, owner_faction: int, by_faction: int) -> void:
	if owner_faction != local_player.id:
		return
	var captured := map.get_tile(h).structure_owner == by_faction
	_lost_structures.append([type, by_faction, captured, h])
	hud.log_event("The %s %s our %s at (%d, %d)" % [_colony(by_faction), "captured" if captured else "demolished",
		Structure.get_display_name(type).to_lower(), h.x, h.y])


## Looks for enemy units that have just stepped onto one of our structures
## (our territory) or our hub, and queues a banner for the newcomers.
func _check_intruders() -> void:
	var now := {}
	var newcomers: Array[Unit] = []
	for colony in players:
		if local_player.is_ally(colony) or colony.collapsed:
			continue
		for u in colony.units:
			if not u.is_in_world():
				continue
			var tile := map.get_tile(u.hex)
			if u.hex != local_player.hex and (tile == null or tile.structure_owner != local_player.id):
				continue
			now[u.id] = true
			if not _intruders.has(u.id):
				newcomers.append(u)
	_intruders = now
	if newcomers.is_empty():
		return
	var first := newcomers[0]
	var where := "your hub" if first.hex == local_player.hex \
		else "your " + Structure.get_display_name(map.get_tile(first.hex).structure).to_lower()
	var who := "The %s's %s" % [_colony(first.player.id), first.display_name]
	if newcomers.size() > 1:
		who = "%d enemy units" % newcomers.size()
		where = "your structures"
	_notify(Notices.Kind.ENEMY_IN_TERRITORY, {"who": who, "where": where}, first.hex)
	hud.log_event("%s moved onto %s" % [who, where])


## Queues an event banner (see Notices) for after any battle replays. `at`:
## where it happened (the camera moves there), or null.
func _notify(kind: Notices.Kind, values: Dictionary, at: Variant = null) -> void:
	_pending_notices.append(Notices.make(kind, values, at))


## Shows this turn's event banners (after the battle replays, if there are
## any) and stops Skip idle turns so the player sees what happened.
func _show_notices() -> void:
	if turns.showing_battles or _game_over:
		return  # Shown once the battles have been replayed.
	for key: String in _hub_hits:
		var attacker := int(key.get_slice(":", 0))
		var defender := int(key.get_slice(":", 1))
		var health: int = _hub_hits[key]
		if health <= 0:
			continue  # Knocked out: the elimination handles it.
		var left := "%d/%d health left" % [health, Player.HUB_MAX_HEALTH]
		if defender == local_player.id:
			_notify(Notices.Kind.HUB_ATTACKED, {"other": _colony(attacker) if attacker >= 0 else "enemy", "left": left}, local_player.hex)
		else:
			var hub: Variant = map.players[defender].hex if map.players.has(defender) else null
			_notify(Notices.Kind.HUB_BREACHED, {"other": _colony(defender), "left": left,
				"cheer": "One more strike and they're finished!" if health == 1 else "Keep up the pressure!"}, hub)
	_hub_hits = {}
	if not _lost_structures.is_empty():
		var what: String
		if _lost_structures.size() == 1:
			var lost: Array = _lost_structures[0]
			what = "Your %s was %s by the %s" % [Structure.get_display_name(lost[0]).to_lower(),
				"captured" if lost[2] else "demolished", _colony(lost[1])]
		else:
			var by := {}
			for lost: Array in _lost_structures:
				by[_colony(lost[1])] = true
			what = "%d of your structures were demolished or captured by the %s" % [
				_lost_structures.size(), " and the ".join(by.keys())]
		_notify(Notices.Kind.STRUCTURE_LOST, {"what": what}, _lost_structures[0][3])
		_lost_structures = []
	if _pending_notices.is_empty():
		return
	for notice in _pending_notices:
		hud.show_notice(notice)
	_pending_notices = []
	turns.player_acted()  # Don't skip past it.


## A colony's name for messages, e.g. "pink colony".
func _colony(faction: int) -> String:
	return Faction.get_display_name(faction).to_lower()


func _end_game(title: String, message: String, color: Color) -> void:
	_game_over = true
	turns.stop()
	_cancel_targeting()
	hud.show_game_over(title, message, color)


# --- Input -----------------------------------------------------------------

func _process(_delta: float) -> void:
	if attention:
		var issue := attention.first_active()
		hud.set_next_turn_hint(issue != Attention.Issue.NONE, attention.describe(issue))
	var h := map.world_to_hex(get_global_mouse_position())
	var has := map.has_tile(h)
	if h != _hover_hex or has != _has_hover:
		_hover_hex = h
		_has_hover = has
		overlay.set_hover(h, has)
		_update_hover_info()


## End Turn / Next: while something wants the player's attention (see
## Attention) the button says Next and opens the panel for it; otherwise
## it ends the turn.
func _on_end_turn_pressed() -> void:
	var issue := attention.first_active() if attention else Attention.Issue.NONE
	if issue == Attention.Issue.NONE:
		turns.end_turn()
		return
	_cancel_targeting()
	hud.open_section(Attention.SECTIONS[issue])


## Enter: ends the turn without stopping at Next - except that units
## waiting for orders always stop it (a hard stop): Mission Briefing opens.
func _end_turn_skipping_next() -> void:
	if attention and attention.blocks_end_turn():
		_cancel_targeting()
		hud.open_section(Hud.Section.BRIEFING)
		hud.log_event(attention.describe(Attention.Issue.ORDERS))
		return
	turns.end_turn()


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
			_end_turn_skipping_next()
		elif key.keycode == KEY_SPACE:
			_on_end_turn_pressed()
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
		var reason := _submit(Orders.mission(unit, _targeting_kind, _hover_hex, _targeting_repeats, true))
		if reason == "":
			_cancel_targeting()
		else:
			hud.set_hint("%s: %s. Pick another tile (right-click/Esc to cancel)."
				% [unit.display_name, reason])
		return
	if _hover_hex == local_player.hex:
		hud.show_hub(local_player)
	else:
		hud.hide_hub()


# --- Targeting -------------------------------------------------------------

func _begin_targeting(unit: Unit, kind: String, repeats := 1) -> void:
	if not Orders.needs_target(kind):
		# Nothing to pick on the map: order it straight away.
		_cancel_targeting()
		var reason := _submit(Orders.mission(unit, kind, local_player.hex, repeats, true))
		hud.set_hint("" if reason == "" else "%s: %s" % [unit.display_name, reason])
		return
	_targeting_unit = unit
	_targeting_kind = kind
	_targeting_repeats = repeats
	var what := "a destination"
	if kind == "demolish":
		what = "something man-made, or an enemy hub, to demolish"
	elif kind == "carpet_bomb":
		what = "something man-made, or an enemy hub, to bomb"
	elif kind == "sortie":
		what = "any tile but a hub to fly a sortie to"
	elif kind == "harvest":
		what = "a deposit to harvest"
	elif kind == "guard":
		what = "a tile to guard"
	elif kind == "capture":
		what = "another colony's structure to capture"
	elif kind.begins_with("build:"):
		var b := local_player.get_buildable(kind.trim_prefix("build:"))
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
	if tile.control_point and tile.structure != Structure.Type.COMMAND_POINT:
		info += "\nControl point - build a Command Point here (and on every other control point), linked to your hub, to win"
	if tile.structure != Structure.Type.NONE:
		info += "\n" + _structure_info(tile)
	var player_here := map.get_player_at(_hover_hex)
	if player_here:
		info += "\n" + player_here.get_info_text()
	var units_here := map.get_units_at(_hover_hex)
	if not units_here.is_empty():
		info += "\nUnits here:"
		for u in units_here:
			info += "\n  " + u.get_hover_text()

	if _targeting_unit:
		# Preview: the same checks the order will get, without sending it.
		var unit := _targeting_unit
		var mission := Orders.make_mission(local_player, _targeting_kind, _hover_hex)
		var reason := Orders.get_invalid_reason(local_player, unit, mission) if mission else "unknown mission"
		var valid := reason == ""
		var preview: Array[Vector2i] = []
		var label := ""
		if valid:
			var line := mission as LineBuildMission
			var path: Array[Vector2i] = line.plan_route(local_player, map, local_player.hex, _hover_hex) if line \
				else map.find_path(local_player.hex, mission.get_travel_hex())
			preview.append(local_player.hex)
			preview.append_array(path)
			if line:
				# Line jobs: everything to build and what it all costs.
				var total := line.get_total_cost(local_player, map, local_player.hex)
				label = ResourceDeposit.format_cost(total)
				info += "\nRoute: %d tiles. To build:" % path.size()
				for job in line.get_job_counts(local_player, map, local_player.hex):
					var b: Buildable = job[0]
					var n: int = job[1]
					info += "\n  %d %s%s - %s" % [n, b.display_name, "" if n == 1 else "s",
						ResourceDeposit.format_cost(job[2])]
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
	if tile.structure_owner != local_player.id:
		text = "%s's %s" % [Faction.get_display_name(tile.structure_owner), text]
	var owner_player: Player = map.players.get(tile.structure_owner)
	var connected := owner_player != null and owner_player.is_supply_connected(tile.coord)
	if tile.structure == Structure.Type.EXTRACTOR:
		if not tile.has_deposit():
			return text + " - deposit exhausted"
		if connected:
			return text + " - connected, %s %s per turn" % [
				ResourceDeposit.format_change(owner_player.get_extractor_output(tile.deposit.type)), tile.deposit.get_display_name()]
		return text + " - NOT connected (needs conveyor belts to the hub)"
	if tile.structure == Structure.Type.COMMAND_POINT:
		if connected:
			return text + " on a control point - linked to the hub, counts towards victory"
		return text + " on a control point - NOT linked to the hub, doesn't count towards victory"
	return text + (" - connected to the hub" if connected else " - not connected to the hub")


func _update_inventory() -> void:
	hud.set_inventory(local_player.inventory, local_player.get_net_income())
	hud.set_command_points(local_player.count_linked_command_points(), map.control_points.size(), local_player.get_initiative())


func _refresh_markers() -> void:
	var markers: Array[Vector2i] = []
	for unit in local_player.units:
		if unit.mission:
			var target: Variant = unit.mission.get_target_hex()
			if target != null:
				markers.append(target)
	overlay.set_markers(markers)
