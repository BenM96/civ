class_name Mission
extends RefCounted
## Base class for an order a hub gives to one of its units.
##
## Lifecycle (driven by Unit.process_turn):
##   1. Hub validates with is_valid_for() and assigns it -> unit is DEPLOYING.
##   2. On the next turn resolution the unit leaves the hub and begin() runs.
##   3. process_turn() runs every turn until complete() or fail() is called.
##   4. The unit then walks home on its own.
##
## To add a new kind of order, extend this class and override the virtuals.

enum Result { IN_PROGRESS, COMPLETE, FAILED }

var unit: Unit
var result := Result.IN_PROGRESS
var fail_reason := ""


# --- Virtuals --------------------------------------------------------------

## Short name for buttons, e.g. "Move".
func get_display_name() -> String:
	return "Mission"


## Longer description for status text, e.g. "Move to (3, 4)".
func get_description() -> String:
	return get_display_name()


## Status line while the mission is in progress.
func get_progress_text() -> String:
	return "%s (%d turn(s) left)" % [get_description(), unit.estimate_turns(unit.get_remaining_path())]


## Turns spent working at the target after arriving (used for estimates).
func get_work_turns() -> int:
	return 0


## Why `u` can't take this mission right now, or "" if it can.
## (Affordability is checked separately by the hub, using get_cost().)
func get_invalid_reason(_u: Unit) -> String:
	return ""


## Resources the hub pays when assigning this mission (refunded if it is
## cancelled before departure or fails). ResourceDeposit.Type -> int.
func get_cost() -> Dictionary:
	return {}


## The hex this mission is heading for, or null if it has none.
func get_target_hex() -> Variant:
	return null


## The hex the unit walks to before working. Usually the target itself.
func get_travel_hex() -> Variant:
	return get_target_hex()


## Called once, on the turn the unit leaves the hub.
func begin() -> void:
	pass


## Called each turn while the mission is in progress. The unit's movement
## points have already been refreshed.
func process_turn() -> void:
	pass


## Message for the event log when the mission succeeds.
func get_completion_text() -> String:
	return "%s complete" % get_display_name()


# --- Helpers ---------------------------------------------------------------

## Whether this mission can be given to `u` right now (unit is in its hub).
func is_valid_for(u: Unit) -> bool:
	return get_invalid_reason(u) == ""


func complete() -> void:
	result = Result.COMPLETE


func fail(reason: String) -> void:
	result = Result.FAILED
	fail_reason = reason


func is_complete() -> bool:
	return result == Result.COMPLETE


func is_failed() -> bool:
	return result == Result.FAILED
