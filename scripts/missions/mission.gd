class_name Mission
extends RefCounted
## Base class for a job a unit goes out and does. A mission is given with a
## "mission" order (see Orders); its kind ("move", "guard"...) names it in
## orders, saves and Unit.allowed_missions.
##
## Missions never move their unit themselves - all movement happens at once
## for every unit (see Movement). A mission just says where to go and what
## to do there. Lifecycle (see TurnManager for when each step runs):
##   1. Hub validates with is_valid_for() and assigns it -> unit is DEPLOYING.
##   2. Set out: on the next turn resolution the unit leaves the hub and
##      begin() runs. Every turn after, prepare() runs at the same point.
##   3. Movement: the unit walks to get_travel_hex(); on_arrived() runs the
##      moment it gets there.
##   4. Work: on each turn the unit starts at the site (didn't move), work()
##      runs, until complete() or fail() is called.
##   5. The unit then walks home on its own.
##
## To add a new kind of mission, extend this class, override the virtuals,
## and add it to Orders.make_mission().
##
## Wording - every mission's text follows the same pattern, e.g. Harvest:
##   get_description()     command       "Harvest Titanium at (5, 7)"
##   get_progress_text()   on the way    "Heading to harvest Titanium at (5, 7) (2 turn(s) to arrive)"
##                         at the site   "Harvesting Titanium at (5, 7) (1 turn(s) left)"
##   get_completion_text() past tense    "harvested 1 Titanium at (5, 7)"
##                         (shown after the unit's name: "Miner 1 harvested...")

enum Result { IN_PROGRESS, COMPLETE, FAILED }
## TRAVELLING: heading for get_travel_hex(). WORKING: there, doing the job.
enum Phase { TRAVELLING, WORKING }
## When in the movement phase the unit moves (see get_move_phase()).
enum MovePhase { NORMAL, REACTION, AIR, INTERCEPT }

var unit: Unit
var result := Result.IN_PROGRESS
var fail_reason := ""
var phase := Phase.TRAVELLING


# --- Virtuals --------------------------------------------------------------

## Short name for buttons, e.g. "Move".
func get_display_name() -> String:
	return "Mission"


## Longer description for status text, e.g. "Move to (3, 4)".
func get_description() -> String:
	return get_display_name()


## Status line while the mission is in progress (see Wording above).
func get_progress_text() -> String:
	return "Heading out: %s (%d turn(s) to arrive)" % [
		get_description(), unit.estimate_turns(unit.get_remaining_path())]


## Turns spent working at the target after arriving (used for estimates).
func get_work_turns() -> int:
	return 0


## Why `u` can't take this mission right now, or "" if it can.
## (Affordability is checked separately by the hub, using get_cost().)
func get_invalid_reason(_u: Unit) -> String:
	return ""


## Resources the hub pays when assigning this mission. The unit carries
## them (Unit.materials); whatever isn't used goes back into the hub when it
## gets home (cancelled, failed...). ResourceDeposit.Type -> int.
func get_cost() -> Dictionary:
	return {}


## The hex this mission is heading for, or null if it has none.
func get_target_hex() -> Variant:
	return null


## The hex the unit walks to before working. Usually the target itself.
func get_travel_hex() -> Variant:
	return get_target_hex()


## Called once when the order is given (the unit is still in the hub, and
## has already been handed get_cost() as Unit.materials). Missions that pay
## as they go take their first job's materials here.
func on_assigned() -> void:
	pass


## Called once, on the turn the unit leaves the hub. Plans the route.
func begin() -> void:
	_plan_route()


## Called at the start of every later turn, before anyone moves: re-plans a
## lost route (e.g. a bridge was demolished) and starts work if the unit is
## already at the site.
func prepare() -> void:
	if phase != Phase.TRAVELLING:
		return
	if unit.hex == get_travel_hex():
		on_arrived()
	elif not unit.has_destination():
		_plan_route()


## The unit has reached get_travel_hex(). By default it starts working (on
## the next turn it doesn't move - usually the next turn).
func on_arrived() -> void:
	phase = Phase.WORKING


## One turn of work at the site. Call complete() when the job is done.
func work() -> void:
	complete()


## Whether the unit sets out (begin() / prepare()) after the rest of its
## colony's units each turn - for missions that follow another unit's plans
## (e.g. Escort).
func sets_out_last() -> bool:
	return false


## Which part of the movement phase the unit moves in (see Movement):
## NORMAL with everyone else; REACTION once they've all finished (a QRF,
## which reacts to where enemies ended up); AIR before anyone (a sortie or a
## carpet bombing - see fly()); INTERCEPT straight after AIR (see
## InterceptMission).
func get_move_phase() -> MovePhase:
	return MovePhase.NORMAL


## AIR phase missions: called by Movement before anyone on the ground
## moves, to fly the unit straight to its target (Unit.fly_to()).
func fly() -> void:
	pass


## Aircraft only: the air return phase, after combat (see
## Unit.return_from_air()). The trip is over: finish (or fail) the mission
## so the unit flies home. A Carpet Bomb drops its bombs here first.
func air_return() -> void:
	complete()


## The hub room (see Room) the unit waits in once given this mission.
func get_departure_room_id() -> String:
	return AirlockRoom.ID


## Status line between being given the mission and setting out.
func get_deploying_text() -> String:
	return "Departs at end of turn - %s" % get_description()


## Whether the player may call this mission off while the unit is back at
## its hub partway through (e.g. waiting there for resources). Before the
## unit leaves, any mission can be cancelled.
func can_cancel_at_hub() -> bool:
	return false


## Event log message when the mission succeeds, in the past tense, shown
## after the unit's name (see Wording above).
func get_completion_text() -> String:
	return "completed %s" % get_description()


## The order kind that creates this mission (see Orders.make_mission), e.g.
## "move" or "build:foundation".
func get_kind() -> String:
	return ""


## This mission's progress as plain data (see SaveGame). Subclasses with
## more progress to remember add to it (call super() first).
func to_dict() -> Dictionary:
	return {
		"kind": get_kind(),
		"target": SaveGame.hex_to_data(get_target_hex()),
		"result": Result.keys()[result],
		"fail_reason": fail_reason,
		"phase": Phase.keys()[phase],
	}


## Restores what to_dict() saved, onto a mission freshly made from the same
## kind and target.
func load_dict(data: Dictionary) -> void:
	result = Result[data["result"]]
	fail_reason = data["fail_reason"]
	phase = Phase[data["phase"]]


# --- Helpers ---------------------------------------------------------------

## Whether this mission can be given to `u` right now (unit is in its hub).
func is_valid_for(u: Unit) -> bool:
	return get_invalid_reason(u) == ""


func is_working() -> bool:
	return phase == Phase.WORKING


## The unit broke in battle and is dropping this mission to flee home.
func on_broken() -> void:
	pass


func complete() -> void:
	result = Result.COMPLETE


func fail(reason: String) -> void:
	result = Result.FAILED
	fail_reason = reason


func is_complete() -> bool:
	return result == Result.COMPLETE


func is_failed() -> bool:
	return result == Result.FAILED


## Sets the unit walking to get_travel_hex(), failing if there's no way.
func _plan_route() -> void:
	var dest: Variant = get_travel_hex()
	if dest == null or not unit.set_destination(dest):
		var where: Variant = get_target_hex() if get_target_hex() != null else dest
		fail("no route to (%d, %d)" % [where.x, where.y] if where != null else "nowhere to go")
	elif unit.hex == dest:
		on_arrived()
