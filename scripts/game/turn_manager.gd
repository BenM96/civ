class_name TurnManager
extends Node
## Runs the turns. During a turn every colony gives its orders; ending the
## turn then resolves it for all colonies at once, in this order:
##
##   1. Orders      - computer players decide (the player already has).
##   2. Set out     - deployed units leave their hubs; units already out
##                    re-plan their routes and start work if they've arrived.
##   3. Movement    - every unit moves at the same time (see Movement).
##   4. Combat      - border clashes, then battles on shared tiles (Combat).
##                    Then units sharing a tile are laid out side by side.
##   5. Work        - units that spent the turn at their site build,
##                    harvest or demolish. Units killed in combat don't.
##   6. Production  - training, extractors, hub biomass.
##   7. Upkeep      - every unit eats 1 biomass; a colony below 0 starves
##                    (the player loses; a rival is eliminated).
##   8. Victory     - the first colony to hold GOLD_TO_WIN gold wins (once
##                    per game; play can carry on afterwards).
##   9. Next turn   - refresh supply networks, advance the turn counter and
##                    decide whether the next turn can be auto-skipped.
##
## To add something that happens every turn, add it as a step in end_turn().

## About to resolve the turn (e.g. so the game can cancel targeting).
signal turn_ending
## The turn has been resolved; `turn` is the new turn number.
signal turn_started(turn: int)
## A message for the event log (battles, etc.).
signal event_logged(message: String)
## Colonies whose biomass fell below zero. The game decides what happens
## (see remove_colony() and stop()).
signal colonies_starved(starved: Array[CentralHub])
## The first colony (or colonies, if tied) to hold GOLD_TO_WIN gold. Only
## ever happens once per game.
signal gold_goal_reached(winners: Array[CentralHub])

## Seconds to wait after units finish moving before the next skipped turn runs.
const SKIP_PAUSE := 0.5
## Gold a colony must hold at the end of a turn to win.
const GOLD_TO_WIN := 50

var turn := 1
## Skip straight past turns where every unit is already busy when the turn
## starts (nobody needs orders). Turns where the player acts are never skipped.
var auto_skip := true

var map: HexMap
## The colony played from this computer (used to decide when to auto-skip).
var local_hub: CentralHub
## Every colony, the player's included.
var hubs: Array[CentralHub] = []
var ais: Array[AiController] = []

## Someone has already reached GOLD_TO_WIN (so it isn't announced again).
## Part of the saved game.
var gold_goal_reached_already := false
## While true (e.g. a popup is open) turns can't be ended.
var paused := false

var _stopped := false
var _skip_this_turn := false
var _skip_wait := 0.0


func setup(p_map: HexMap, p_local_hub: CentralHub, p_hubs: Array[CentralHub], p_ais: Array[AiController]) -> void:
	map = p_map
	local_hub = p_local_hub
	hubs = p_hubs
	ais = p_ais


## Stops all further turns (the game is over).
func stop() -> void:
	_stopped = true
	_skip_this_turn = false


## Takes an eliminated colony (and the AI playing it) out of the turns.
func remove_colony(hub: CentralHub) -> void:
	hubs.erase(hub)
	for ai in ais.duplicate():
		if ai.hub == hub:
			ais.erase(ai)


func end_turn() -> void:
	if _stopped or paused:
		return
	turn_ending.emit()

	# 1. Orders
	for ai in ais:
		ai.take_turn()

	# 2. Set out
	for hub in hubs:
		hub.start_units_turn()

	# 3. Movement
	var clashes := Movement.run(map)

	# 4. Combat
	for message in Combat.resolve(map, clashes):
		event_logged.emit(message)
	# Now we know who's standing where, fit shared tiles' icons side by side.
	UnitStackLayout.arrange(map)

	# 5. Work
	for hub in hubs:
		hub.units_work()

	# 6. Production
	for hub in hubs:
		hub.produce()

	# 7. Upkeep
	var starved: Array[CentralHub] = []
	for hub in hubs:
		if hub.feed_units():
			starved.append(hub)

	# 8. Victory
	var winners := _gold_winners()

	# 9. Next turn
	for hub in hubs:
		hub.finish_turn()
	turn += 1
	turn_started.emit(turn)
	if not starved.is_empty():
		colonies_starved.emit(starved)  # May end the game (stop()).
	if _stopped:
		return
	if not winners.is_empty():
		gold_goal_reached_already = true
		gold_goal_reached.emit(winners)  # The game shows who won.
	if _stopped or paused:
		return
	_skip_this_turn = auto_skip and _no_units_need_orders()
	_skip_wait = 0.0


## The colonies that win this turn: whoever holds the most gold, if that's
## at least GOLD_TO_WIN (several only on an exact tie). Empty if nobody has
## reached it, or someone already did earlier in the game.
func _gold_winners() -> Array[CentralHub]:
	var winners: Array[CentralHub] = []
	if gold_goal_reached_already:
		return winners
	var best := GOLD_TO_WIN
	for hub in hubs:
		var gold := hub.get_resource(ResourceDeposit.Type.GOLD)
		if gold > best:
			best = gold
			winners.clear()
		if gold >= best:
			winners.append(hub)
	return winners


# --- Auto-skip -------------------------------------------------------------

## The player did something this turn, so it's theirs to end.
func player_acted() -> void:
	_skip_this_turn = false


func set_auto_skip(enabled: bool) -> void:
	auto_skip = enabled
	if not enabled:
		_skip_this_turn = false


## True when no unit needs orders (all busy or waiting) and letting time pass
## would actually change something (units out, or training in progress).
func _no_units_need_orders() -> bool:
	if local_hub.units.is_empty() or not local_hub.get_units_needing_orders().is_empty():
		return false
	return not local_hub.get_field_units().is_empty() or not local_hub.training_queue.is_empty()


func _process(delta: float) -> void:
	if not _skip_this_turn or paused:
		return
	if not auto_skip or not _no_units_need_orders():
		_skip_this_turn = false
		return
	# Let this turn's movement play out before moving on.
	for hub in hubs:
		for unit in hub.units:
			if unit.is_animating():
				_skip_wait = 0.0
				return
	_skip_wait += delta
	if _skip_wait >= SKIP_PAUSE:
		end_turn()
