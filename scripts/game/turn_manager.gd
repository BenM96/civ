class_name TurnManager
extends Node
## Runs the turns. During a turn every colony gives its orders; ending the
## turn then resolves it for all colonies at once, in this order:
##
##   1. Orders      - computer players decide (the player already has).
##   2. Set out     - deployed units leave their hubs; units already out
##                    re-plan their routes and start work if they've arrived.
##   3. Movement    - every unit moves at the same time; units of opposing
##                    colonies that meet start battles and stop. QRF
##                    units move last, once everyone else has. The
##                    movement phase then passes the battles (each an array
##                    of hexes) to Combat (see Movement).
##   4. Layout      - units sharing a tile are laid out side by side.
##   5. Work        - units that spent the turn at their site build,
##                    harvest or demolish. Units killed in combat don't.
##   6. Production  - extractors deliver, hub buildings make resources
##                    (Greenhouse biomass).
##   7. Hub         - buildings ordered this turn are finished, training
##                    progresses and the hub rooms work on their units
##                    (the Med Bay and Garage heal, the Hangar refits), and
##                    units back in Mission Briefing with a repeating order
##                    are given it again.
##   8. Starvation  - a colony whose biomass production is below zero (it
##                    makes less than its units eat) loses one unit: the
##                    most injured first, Workers last (see Player.starve()).
##   9. Victory     - the first colony with a command point on every
##                    control point on the map, each linked to its hub by
##                    belts, wins (once per game; play can carry on
##                    afterwards). A colony with no units left and none in
##                    training is eliminated (the player loses; a rival
##                    collapses, and outlasting every rival wins).
##  10. Next turn   - refresh supply networks, advance the turn counter and
##                    decide whether the next turn can be auto-skipped.
##
## To add something that happens every turn, add it as a step in end_turn().

## About to resolve the turn (e.g. so the game can cancel targeting).
signal turn_ending
## The turn has been resolved; `turn` is the new turn number.
signal turn_started(turn: int)
## A message for the event log (battles, etc.).
signal event_logged(message: String)
## Battles were fought this turn: one report each (see Combat), for the game
## to replay. Emitted after the turn has fully resolved.
signal battles_fought(reports: Array[Dictionary])
## A unit starved this turn (see Player.starve() for `report`). Emitted
## after the turn has fully resolved, after battles_fought.
signal unit_starved(player: Player, report: Dictionary)
## Colonies with no units left and none in training. The game decides what
## happens (see remove_colony() and stop()).
signal colonies_eliminated(eliminated: Array[Player])
## The colony that has a linked command point on every control point (see
## _winners()). Only ever happens once per game.
signal win_goal_reached(winners: Array[Player])

## Seconds to wait after units finish moving before the next skipped turn runs.
const SKIP_PAUSE := 0.5

var turn := 1
## Skip straight past turns where every unit is already busy when the turn
## starts (nobody needs orders). Turns where the player acts are never skipped.
var auto_skip := true

var map: HexMap
## The colony played from this computer (used to decide when to auto-skip).
var local_player: Player
## Every colony, the player's included.
var players: Array[Player] = []
var ais: Array[AiController] = []

## Someone has already won (so it isn't announced again).
## Part of the saved game.
var win_goal_reached_already := false
## While true (e.g. a popup is open) turns can't be ended.
var paused := false
## While true (battles are being replayed) turns can't be ended.
var showing_battles := false

var _stopped := false
var _skip_this_turn := false
var _skip_wait := 0.0


func setup(p_map: HexMap, p_local_player: Player, p_players: Array[Player], p_ais: Array[AiController]) -> void:
	map = p_map
	local_player = p_local_player
	players = p_players
	ais = p_ais


## Stops all further turns (the game is over).
func stop() -> void:
	_stopped = true
	_skip_this_turn = false


## Takes an eliminated colony (and the AI playing it) out of the turns.
func remove_colony(player: Player) -> void:
	players.erase(player)
	for ai in ais.duplicate():
		if ai.player == player:
			ais.erase(ai)


func end_turn() -> void:
	if _stopped or paused or showing_battles:
		return
	turn_ending.emit()

	# 1. Orders
	for ai in ais:
		ai.take_turn()

	# 2. Set out
	for player in players:
		player.start_units_turn()

	# 3. Movement (and the combat it leads to)
	var battles := Movement.run(map, turn)
	for report in battles:
		event_logged.emit(report["message"])

	# 4. Layout - now we know who's standing where, fit shared tiles' icons
	# side by side.
	UnitStackLayout.arrange(map)

	# 5. Work
	for player in players:
		player.units_work()

	# 6. Production
	for player in players:
		player.produce()

	# 7. Hub
	for player in players:
		player.run_hub()

	# 8. Starvation
	var starvations: Array = []  # [player, report] pairs.
	for player in players:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([map.last_seed, turn, player.id, "starve"])  # Repeatable.
		var report := player.starve(rng)
		if not report.is_empty():
			starvations.append([player, report])

	# 9. Victory
	var winners := _winners()
	var eliminated: Array[Player] = []
	for player in players:
		if player.is_wiped_out():
			eliminated.append(player)

	# 10. Next turn
	for player in players:
		player.finish_turn()
	turn += 1
	turn_started.emit(turn)
	if not battles.is_empty():
		battles_fought.emit(battles)
	for entry: Array in starvations:
		unit_starved.emit(entry[0], entry[1])
	if not eliminated.is_empty():
		colonies_eliminated.emit(eliminated)  # May end the game (stop()).
	if _stopped:
		return
	if not winners.is_empty():
		win_goal_reached_already = true
		win_goal_reached.emit(winners)  # The game shows who won.
	if _stopped or paused:
		return
	_skip_this_turn = auto_skip and _no_units_need_orders()
	_skip_wait = 0.0


## The colony that wins this turn - the one with a command point on every
## control point, each linked to its hub (see
## Player.holds_every_control_point()) - in an array, or an empty array if
## nobody has done it, or someone already did earlier in the game. (Only one
## colony can own every control point, so there are no ties.)
func _winners() -> Array[Player]:
	var winners: Array[Player] = []
	if win_goal_reached_already:
		return winners
	for player in players:
		if player.holds_every_control_point():
			winners.append(player)
	return winners


# --- Auto-skip -------------------------------------------------------------

## The player did something this turn, so it's theirs to end.
func player_acted() -> void:
	_skip_this_turn = false


func set_auto_skip(enabled: bool) -> void:
	auto_skip = enabled
	if not enabled:
		_skip_this_turn = false


## True when no unit needs orders (all busy, or off duty in the hub) and
## letting time pass would actually change something (units out, training
## in progress, or a hub room at work - units healing or refitting).
func _no_units_need_orders() -> bool:
	if local_player.units.is_empty() or not local_player.get_units_needing_orders().is_empty():
		return false
	if not local_player.get_field_units().is_empty() or not local_player.training_queue.is_empty():
		return true
	return local_player.rooms.any(func(room: Room) -> bool: return room.has_work(local_player))


func _process(delta: float) -> void:
	if not _skip_this_turn or paused or showing_battles:
		return
	if not auto_skip or not _no_units_need_orders():
		_skip_this_turn = false
		return
	# Let this turn's movement play out before moving on.
	for player in players:
		for unit in player.units:
			if unit.is_animating():
				_skip_wait = 0.0
				return
	_skip_wait += delta
	if _skip_wait >= SKIP_PAUSE:
		end_turn()
