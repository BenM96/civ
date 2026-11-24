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
##   {"order": "mission", "unit": id, "kind": kind, "target": [x, y], "repeats": n}
##       repeats: how many times to do it (default 1; REPEAT_FOREVER = forever;
##       Guard can't be forever). For QRF it's the turns of duty instead.
##   {"order": "start_regroup"}   Regroup button (see Player.start_regroup())
##       It's given again each time the unit is back in Mission Briefing
##       (see Player.repeat_orders()).
##       group: true (from the HUD) - a Builder's line job becomes the job all
##       Builders join (see Player.start_builder_group()).
##       kind: "move", "harvest", "guard", "capture", "demolish", "qrf", "regroup", "sortie", "intercept", "carpet_bomb",
##       "escort:<unit id>" or "build:<buildable id>" (see make_mission())
##   {"order": "cancel_mission", "unit": id}
##   {"order": "move_room", "unit": id, "room": room id, "turns": n}   (see Room)
##       turns: off duty in its quarters for that many turns, then back to
##       Mission Briefing (0 = until moved).
##   {"order": "recall_all"}   RTB: every unit drops its mission and comes home
##   {"order": "heal_order", "unit": id, "index": i}   (healing queue, see Room)
##   {"order": "train", "unit_type": "Builder"}
##   {"order": "cancel_training", "index": i}
##   {"order": "build_building", "building": building id}   (see Building)
##   {"order": "cancel_building", "index": i}
##   {"order": "research", "tech": tech id}   (see Tech, TechTrees)
##   {"order": "cancel_research", "tech": tech id}
##   {"order": "repair_hub"}   1 health back for Player.HUB_REPAIR_COST, once a turn
##   {"order": "debug_resources"}   TESTING ONLY - remove before release
##
## To add a new kind of action: add an order here (a helper and a case in
## submit()) and have the HUD / AI send it. Never change game state from the
## HUD or AI directly.

## A mission "repeats" value meaning forever.
const REPEAT_FOREVER := Unit.REPEAT_FOREVER

var map: HexMap
## Every colony, indexed by faction.
var players: Array[Player]


func _init(p_map: HexMap, p_players: Array[Player]) -> void:
	map = p_map
	players = p_players


# --- Making orders ---------------------------------------------------------

## `repeats` how many times in all; REPEAT_FOREVER to keep going.
## `group`: for a Builder's line job, every Builder joins it.
static func mission(unit: Unit, kind: String, target: Vector2i, repeats := 1, group := false) -> Dictionary:
	return {"order": "mission", "unit": unit.id, "kind": kind, "target": [target.x, target.y],
		"repeats": repeats, "group": group}


static func cancel_mission(unit: Unit) -> Dictionary:
	return {"order": "cancel_mission", "unit": unit.id}


## Moves a unit in the hub to another of the hub's rooms (see Room).
## `turns`: for a unit sent off duty, how long before it's back in Mission
## Briefing by itself (0 = until it's moved).
static func move_room(unit: Unit, room_id: String, turns := 0) -> Dictionary:
	return {"order": "move_room", "unit": unit.id, "room": room_id, "turns": turns}


static func recall_all() -> Dictionary:
	return {"order": "recall_all"}


## The Central Hub panel's Regroup button (see Player.start_regroup()).
static func start_regroup() -> Dictionary:
	return {"order": "start_regroup"}


## Whether a mission kind needs a tile picked on the map. Escorts, QRF and Intercept
## don't: the order is given straight away (with the hub as its target).
static func needs_target(kind: String) -> bool:
	return not (kind.begins_with("escort:") or kind == "qrf" or kind == "regroup" or kind == "intercept")


static func train(unit_type: String) -> Dictionary:
	return {"order": "train", "unit_type": unit_type}


static func cancel_training(index: int) -> Dictionary:
	return {"order": "cancel_training", "index": index}


## Moves a unit to `index` (0 = first) in its room's healing queue.
static func heal_order(unit: Unit, index: int) -> Dictionary:
	return {"order": "heal_order", "unit": unit.id, "index": index}


## Pays for a hub building, finished at the end of the turn.
static func build_building(building_id: String) -> Dictionary:
	return {"order": "build_building", "building": building_id}


## Calls off a building still under construction (refunded).
static func cancel_building(index: int) -> Dictionary:
	return {"order": "cancel_building", "index": index}


## Pays for a tech, researched at the end of the turn (see Player.research_tech()).
static func research(tech_id: String) -> Dictionary:
	return {"order": "research", "tech": tech_id}


## Calls off research paid for this turn (refunded).
static func cancel_research(tech_id: String) -> Dictionary:
	return {"order": "cancel_research", "tech": tech_id}


## Repairs 1 of the hub's health (see Player.repair_hub()).
static func repair_hub() -> Dictionary:
	return {"order": "repair_hub"}


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
	var player := get_player(faction)
	if player == null or player.collapsed:
		return "no such colony"
	match order.get("order", ""):
		"mission":
			var unit := _own_unit(player, order)
			if unit == null:
				return "no such unit"
			var m := make_mission(player, str(order.get("kind", "")), _to_hex(order.get("target")))
			if m == null:
				return "unknown mission"
			var reason := get_invalid_reason(player, unit, m)
			if reason != "":
				return reason
			if m is GuardMission and int(order.get("repeats", 1)) == REPEAT_FOREVER:
				return "Guard can't repeat forever - pick a number of times"
			# QRF and Regroup are standing duties, never repeated: for QRF the
			# repeat number is how many turns of duty instead.
			if m is QrfMission and not m is RegroupMission:
				var turns := int(order.get("repeats", REPEAT_FOREVER))
				(m as QrfMission).turns_left = turns if turns > 0 else REPEAT_FOREVER
			if not player.assign_mission(unit, m):
				return "can't do that"
			if m is QrfMission:
				unit.set_repeats(_to_hex(order.get("target")), 0)
				return ""
			var repeats := int(order.get("repeats", 1))
			unit.set_repeats(_to_hex(order.get("target")), repeats - 1 if repeats > 0 else Unit.REPEAT_FOREVER)
			if order.get("group", false) and unit is Builder and m is LineBuildMission:
				player.start_builder_group(m.get_kind(), _to_hex(order.get("target")), unit.repeats_left)
			return ""
		"cancel_mission":
			var unit := _own_unit(player, order)
			if unit == null:
				return "no such unit"
			return "" if player.cancel_mission(unit) else "it's out on its mission and can't be called back now"
		"move_room":
			var unit := _own_unit(player, order)
			if unit == null:
				return "no such unit"
			return player.move_unit_to_room(unit, str(order.get("room", "")), int(order.get("turns", 0)))
		"recall_all":
			player.recall_all()
			return ""
		"start_regroup":
			return player.start_regroup()
		"heal_order":
			var unit := _own_unit(player, order)
			if unit == null:
				return "no such unit"
			return player.move_in_healing_queue(unit, int(order.get("index", 0)))
		"build_building":
			return player.order_building(str(order.get("building", "")))
		"cancel_building":
			return "" if player.cancel_building(int(order.get("index", -1))) else "nothing to cancel"
		"research":
			return player.research_tech(str(order.get("tech", "")))
		"cancel_research":
			return "" if player.cancel_research(str(order.get("tech", ""))) else "not being researched"
		"repair_hub":
			return player.repair_hub()
		"train":
			var bp := player.get_blueprint(str(order.get("unit_type", "")))
			if bp == null:
				return "unknown unit type"
			var needs := player.get_training_refusal(bp)
			if needs != "":
				return needs
			var cost := player.get_training_cost(bp)
			if not player.can_afford(cost):
				return "need %s" % ResourceDeposit.format_cost(cost)
			return "" if player.queue_training(bp) else "can't train that"
		"cancel_training":
			return "" if player.cancel_training(int(order.get("index", -1))) else "nothing to cancel"
		"debug_resources":  # TESTING ONLY - remove before release.
			for type in ResourceDeposit.Type.values():
				player.add_resource(type, DEBUG_RESOURCE_AMOUNT)
			return ""
	return "unknown order"


func get_player(faction: int) -> Player:
	if faction < 0 or faction >= players.size():
		return null
	return players[faction]


## Why `unit` can't take `m` right now ("" if it can): everything the
## mission's own get_invalid_reason() checks, plus whether this unit may do
## that kind of mission at all, is at home, and can be paid for.
static func get_invalid_reason(player: Player, unit: Unit, m: Mission) -> String:
	if unit.state != Unit.State.IN_HUB:
		return "%s is already out" % unit.display_name
	if unit.room_id != MissionBriefingRoom.ID:
		return "%s must be in Mission Briefing to get orders" % unit.display_name
	if not unit.can_take(m.get_kind()):
		return "%s can't %s" % [unit.display_name, m.get_kind().get_slice(":", 0)]
	if m.get_kind().begins_with("build:"):
		var locked := player.get_buildable_refusal(player.get_buildable(m.get_kind().trim_prefix("build:")))
		if locked != "":
			return locked
	m.unit = unit  # Lets the mission plan its route (e.g. a bridge's work site).
	var reason := m.get_invalid_reason(unit)
	if reason != "":
		return reason
	if not player.can_afford(m.get_cost()):
		return "need %s" % ResourceDeposit.format_cost(m.get_cost())
	return ""


## Builds the mission for a mission kind: "move", "harvest", "guard",
## "capture", "demolish", "escort:<unit id>" or "build:<buildable id>".
## (An escort's target hex is ignored.) Returns null for an
## unknown kind. Add new mission kinds here (and give the mission a matching
## get_kind()).
static func make_mission(player: Player, kind: String, target: Vector2i) -> Mission:
	if kind == "build:road":
		kind = "build:foundation"  # Renamed; older saves may still say road.
	if kind.begins_with("escort:"):
		return EscortMission.new(int(kind.trim_prefix("escort:")))
	if kind.begins_with("build:"):
		var buildable := player.get_buildable(kind.trim_prefix("build:"))
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
		"qrf":
			return QrfMission.new()
		"regroup":
			return RegroupMission.new()
		"sortie":
			return SortieMission.new(target)
		"intercept":
			return InterceptMission.new()
		"carpet_bomb":
			return CarpetBombMission.new(target)
	return null


## The order's unit, if it exists and belongs to `hub` (so nobody can order
## another colony's units about).
func _own_unit(player: Player, order: Dictionary) -> Unit:
	return player.get_unit(int(order.get("unit", 0)))


static func _to_hex(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
