class_name Orders
extends RefCounted
## The one way anyone - human or AI - changes the game between turns.
##
## An order is a plain Dictionary holding only numbers, strings, bools and
## arrays, so it can be saved, logged or sent over a network as-is. Units are
## named by their id, colonies by their faction. submit() checks the order
## and carries it out, so whoever runs submit() (later: the host of a
## multiplayer game) has the final say on what's allowed.
##
## Every order says what it is under "order". Build them with the helpers
## below rather than by hand:
##   {"order": "mission", "unit": id, "kind": kind, "target": [x, y]}
##       kind: "move", "harvest", "guard", "capture", "demolish",
##       "escort:<unit id>" or "build:<buildable id>" (see make_mission())
##   {"order": "cancel_mission", "unit": id}
##   {"order": "wait", "unit": id, "value": bool}
##   {"order": "train", "unit_type": "Worker"}
##   {"order": "cancel_training", "index": i}
##   {"order": "debug_resources"}   TESTING ONLY - remove before release
##
## To add a new kind of action: add an order here (a helper and a case in
## submit()) and have the HUD / AI send it. Never change game state from the
## HUD or AI directly.

var map: HexMap
## Every colony, indexed by faction.
var colonies: Array[CentralHub]


func _init(p_map: HexMap, p_colonies: Array[CentralHub]) -> void:
	map = p_map
	colonies = p_colonies


# --- Making orders ---------------------------------------------------------

static func mission(unit: Unit, kind: String, target: Vector2i) -> Dictionary:
	return {"order": "mission", "unit": unit.id, "kind": kind, "target": [target.x, target.y]}


static func cancel_mission(unit: Unit) -> Dictionary:
	return {"order": "cancel_mission", "unit": unit.id}


static func wait(unit: Unit, value: bool) -> Dictionary:
	return {"order": "wait", "unit": unit.id, "value": value}


static func train(unit_type: String) -> Dictionary:
	return {"order": "train", "unit_type": unit_type}


static func cancel_training(index: int) -> Dictionary:
	return {"order": "cancel_training", "index": index}


## TESTING ONLY - remove before release (with its case in submit() and the
## HUD's "+50 all" button). Gives the colony DEBUG_RESOURCE_AMOUNT of every
## resource.
static func debug_resources() -> Dictionary:
	return {"order": "debug_resources"}


const DEBUG_RESOURCE_AMOUNT := 50


# --- Carrying them out -----------------------------------------------------

## Checks `order` from `faction` and, if it's allowed, carries it out.
## Returns "" on success, otherwise why it was refused.
func submit(faction: int, order: Dictionary) -> String:
	var hub := get_colony(faction)
	if hub == null or hub.collapsed:
		return "no such colony"
	match order.get("order", ""):
		"mission":
			var unit := _own_unit(hub, order)
			if unit == null:
				return "no such unit"
			var m := make_mission(hub, str(order.get("kind", "")), _to_hex(order.get("target")))
			if m == null:
				return "unknown mission"
			var reason := get_invalid_reason(hub, unit, m)
			if reason != "":
				return reason
			return "" if hub.assign_mission(unit, m) else "can't do that"
		"cancel_mission":
			var unit := _own_unit(hub, order)
			if unit == null:
				return "no such unit"
			return "" if hub.cancel_mission(unit) else "it's out on its mission and can't be called back now"
		"wait":
			var unit := _own_unit(hub, order)
			if unit == null:
				return "no such unit"
			return "" if hub.set_unit_waiting(unit, bool(order.get("value", true))) else "can't wait now"
		"train":
			var bp := hub.get_blueprint(str(order.get("unit_type", "")))
			if bp == null:
				return "unknown unit type"
			var cost := hub.get_training_cost(bp)
			if not hub.can_afford(cost):
				return "need %s" % ResourceDeposit.format_cost(cost)
			return "" if hub.queue_training(bp) else "can't train that"
		"cancel_training":
			return "" if hub.cancel_training(int(order.get("index", -1))) else "nothing to cancel"
		"debug_resources":  # TESTING ONLY - remove before release.
			for type in ResourceDeposit.Type.values():
				hub.add_resource(type, DEBUG_RESOURCE_AMOUNT)
			return ""
	return "unknown order"


func get_colony(faction: int) -> CentralHub:
	if faction < 0 or faction >= colonies.size():
		return null
	return colonies[faction]


## Why `unit` can't take `m` right now ("" if it can): everything the
## mission's own get_invalid_reason() checks, plus whether this unit may do
## that kind of mission at all, is at home, and can be paid for.
static func get_invalid_reason(hub: CentralHub, unit: Unit, m: Mission) -> String:
	if unit.state != Unit.State.IN_HUB:
		return "%s is already out" % unit.display_name
	if not unit.can_take(m.get_kind()):
		return "%s can't %s" % [unit.display_name, m.get_kind().get_slice(":", 0)]
	m.unit = unit  # Lets the mission plan its route (e.g. a bridge's work site).
	var reason := m.get_invalid_reason(unit)
	if reason != "":
		return reason
	if not hub.can_afford(m.get_cost()):
		return "need %s" % ResourceDeposit.format_cost(m.get_cost())
	return ""


## Builds the mission for a mission kind: "move", "harvest", "guard",
## "capture", "demolish", "escort:<unit id>" or "build:<buildable id>".
## (An escort's target hex is ignored.) Returns null for an
## unknown kind. Add new mission kinds here (and give the mission a matching
## get_kind()).
static func make_mission(hub: CentralHub, kind: String, target: Vector2i) -> Mission:
	if kind == "build:road":
		kind = "build:foundation"  # Renamed; older saves may still say road.
	if kind.begins_with("escort:"):
		return EscortMission.new(int(kind.trim_prefix("escort:")))
	if kind.begins_with("build:"):
		var buildable := hub.get_buildable(kind.trim_prefix("build:"))
		if buildable == null:
			return null
		if buildable.line_of != "":
			return LineBuildMission.new(target, buildable)
		return BuildMission.new(target, buildable)
	match kind:
		"move":
			return MoveMission.new(target)
		"harvest":
			return HarvestMission.new(target)
		"guard":
			return GuardMission.new(target)
		"capture":
			return CaptureMission.new(target)
		"demolish":
			return DemolishMission.new(target)
	return null


## The order's unit, if it exists and belongs to `hub` (so nobody can order
## another colony's units about).
func _own_unit(hub: CentralHub, order: Dictionary) -> Unit:
	return hub.get_unit(int(order.get("unit", 0)))


static func _to_hex(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
