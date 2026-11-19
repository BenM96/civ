class_name Unit
extends Node2D
## Base class for every unit.
##
## Units are never controlled directly. They live in a CentralHub and are
## handed a Mission. During turn resolution they execute the mission, then
## walk back to the hub on their own, where they wait for the next order.
##
## Subclasses (Worker, Scout, ...) set ALL their data in _init() - stats,
## training cost, training time and upkeep - and can override
## get_short_label() / _draw() for visuals or add new abilities for missions.
## To make a hub able to train a unit, add its class to the hub's list in
## CentralHub._init().

signal state_changed(unit: Unit)
signal mission_completed(unit: Unit, mission: Mission)
signal mission_failed(unit: Unit, mission: Mission, reason: String)
signal returned_to_hub(unit: Unit)

enum State {
	IN_HUB,     ## Garrisoned, available for orders.
	DEPLOYING,  ## Has a mission, leaves the hub when the turn ends.
	ON_MISSION, ## Out in the world executing its mission.
	RETURNING,  ## Mission over, walking back to the hub.
}

const RADIUS := 13.0

@export var unit_name := "Unit"
## How the training price rises with each one built (see cost_rises_after):
##   DOUBLE  - each costs double the last: x1, x2, x4, x8...
##   ADD_ONE - each costs 1 more of every resource in `cost` than the last:
##             1 Gold + 1 Titanium, then 2 + 2, then 3 + 3...
enum CostGrowth { DOUBLE, ADD_ONE }

## Resources paid to train the first of this unit: ResourceDeposit.Type -> int.
## Later ones cost more (see cost_growth and cost_rises_after).
var cost: Dictionary = {}
@export var cost_growth := CostGrowth.DOUBLE
## How many of this unit a colony can have built before its training cost
## starts rising. E.g. 1: after 1 the next costs `cost`, then it rises with
## each one after that. Every one ever had counts (starting units, ones in
## training, and ones since lost), so losing units doesn't lower the price.
@export var cost_rises_after := 0
## Turns a hub spends training this unit.
@export var train_turns := 1
## Biomass this unit eats every turn, wherever it is.
@export var upkeep := 1
## Movement points per turn (open ground costs 3, foundations and bridges 1).
@export var max_movement := 3
@export var max_health := 10
@export var body_color := Color.WHITE
## The kinds of mission this unit may be given: "move", "harvest", "build"
## (any structure) and/or "demolish" - the same names orders use (see
## Orders.make_mission). The HUD only offers these, and Orders refuses others.
@export var allowed_missions: Array[String] = ["move"]
## Whether this unit fights (see Combat). Fighters stop when they run into
## enemy fighters, and kill enemy non-fighters sharing their tile.
@export var can_fight := false
## Seconds the move animation spends on each tile.
@export var move_anim_time := 0.18

## Permanent number identifying this unit in orders and saves; the same on
## every computer. Given out by the map when the unit joins (0 = not yet).
var id := 0
## Unique name given by the hub, e.g. "Worker 2".
var display_name := ""
var hex: Vector2i
var hub: CentralHub
var map: HexMap
var state: State = State.IN_HUB
var mission: Mission
var movement_left := 0
var health := 0
## Told to stay home: the unit doesn't count as needing orders. Cleared when
## it is given a mission (or woken).
var waiting := false
## The kind of the last mission this unit was given (e.g. "harvest",
## "build:foundation"), so the HUD can offer it again. "" if it's never had one.
var last_mission_kind := ""
## Resources being carried home: ResourceDeposit.Type -> int.
## The hub unloads this when the unit returns.
var cargo: Dictionary = {}
## Resources taken out of the hub for this unit's job (Type -> int): paid
## when it's given the job (or picks its next job at the hub), used up as it
## builds. Anything left - the job was cancelled, failed or done by someone
## else - goes back into the hub when the unit gets home. Lost if it dies.
var materials: Dictionary = {}
## Ran into enemy fighters this turn: can't move again until next turn.
var engaged := false
## Took at least one step this turn (so it can't also work this turn).
var moved_this_turn := false

## Icon placement within the tile (see set_icon_layout).
var _icon_offset := Vector2.ZERO
var _icon_scale := 1.0

var _path: Array[Vector2i] = []
var _anim_steps: Array[Vector2] = []
var _move_tween: Tween


func _ready() -> void:
	z_index = 10
	health = max_health


## Called by the hub when the unit joins it.
func setup(p_hub: CentralHub, p_map: HexMap) -> void:
	hub = p_hub
	map = p_map
	hex = hub.hex
	global_position = map.hex_to_world(hex)
	_refresh_visibility()


func get_short_label() -> String:
	return unit_name.left(1)


## Whether this unit may take a mission of `kind`. "build:foundation" counts as
## "build", so a unit that can build can build any structure.
func can_take(kind: String) -> bool:
	return kind.get_slice(":", 0) in allowed_missions


func is_available() -> bool:
	return state == State.IN_HUB


## Out on the map (not garrisoned), so it can fight or be attacked.
func is_in_world() -> bool:
	return state == State.ON_MISSION or state == State.RETURNING


## At home and not told to wait - the player should give it something to do.
func needs_orders() -> bool:
	return state == State.IN_HUB and not waiting


## Wait (stay home without needing orders) or wake up. Only for units at home.
func set_waiting(value: bool) -> bool:
	if state != State.IN_HUB or waiting == value:
		return false
	waiting = value
	state_changed.emit(self)
	return true


# --- Saving ----------------------------------------------------------------

## Everything about this unit's current situation, as plain data (see
## SaveGame). Its stats come from its script, so only "type" is saved.
func to_dict() -> Dictionary:
	var path := []
	for h in _path:
		path.append(SaveGame.hex_to_data(h))
	return {
		"id": id,
		"type": unit_name,
		"name": display_name,
		"hex": SaveGame.hex_to_data(hex),
		"state": State.keys()[state],
		"waiting": waiting,
		"last_mission_kind": last_mission_kind,
		"health": health,
		"cargo": SaveGame.resources_to_data(cargo),
		"materials": SaveGame.resources_to_data(materials),
		"path": path,
		"mission": mission.to_dict() if mission else null,
	}


## Restores what to_dict() saved. The unit must already be in its hub.
func load_dict(data: Dictionary) -> void:
	hex = SaveGame.hex_from_data(data["hex"])
	state = State[data["state"]]
	waiting = data["waiting"]
	last_mission_kind = data.get("last_mission_kind", "")  # Older saves lack it.
	health = int(data["health"])
	cargo = SaveGame.resources_from_data(data["cargo"])
	materials = SaveGame.resources_from_data(data.get("materials", {}))  # Older saves lack it.
	_path.clear()
	for h in data["path"]:
		_path.append(SaveGame.hex_from_data(h))
	if data["mission"] != null:
		var m_data: Dictionary = data["mission"]
		mission = Orders.make_mission(hub, m_data["kind"], SaveGame.hex_from_data(m_data["target"]))
		mission.unit = self
		mission.load_dict(m_data)
	global_position = map.hex_to_world(hex)
	_refresh_visibility()


# --- Cargo -----------------------------------------------------------------

func add_cargo(type: ResourceDeposit.Type, amount: int) -> void:
	if amount > 0:
		cargo[type] = cargo.get(type, 0) + amount


func has_cargo() -> bool:
	return not cargo.is_empty()


## Empties the unit's cargo and returns what it was carrying.
func take_cargo() -> Dictionary:
	var taken := cargo
	cargo = {}
	return taken


func add_materials(cost: Dictionary) -> void:
	for type in cost:
		if cost[type] > 0:
			materials[type] = materials.get(type, 0) + cost[type]


func has_materials(cost: Dictionary) -> bool:
	for type in cost:
		if materials.get(type, 0) < cost[type]:
			return false
	return true


## Uses `cost` from the materials carried. Returns false (using nothing) if
## they don't cover it.
func use_materials(cost: Dictionary) -> bool:
	if not has_materials(cost):
		return false
	for type in cost:
		materials[type] -= cost[type]
		if materials[type] <= 0:
			materials.erase(type)
	return true


## Empties the materials carried and returns them.
func take_materials() -> Dictionary:
	var taken := materials
	materials = {}
	return taken


func get_cargo_text() -> String:
	var parts: PackedStringArray = []
	for type in cargo:
		parts.append("%d %s" % [cargo[type], ResourceDeposit.get_type_name(type)])
	return ", ".join(parts)


# --- Missions --------------------------------------------------------------

func can_accept_mission(m: Mission) -> bool:
	return state == State.IN_HUB and m.is_valid_for(self)


## Use CentralHub.assign_mission() rather than calling this directly.
func assign_mission(m: Mission) -> void:
	waiting = false
	mission = m
	last_mission_kind = m.get_kind()
	m.unit = self
	_set_state(State.DEPLOYING)


## Withdraws the mission from a unit that hasn't left yet. Use
## CentralHub.cancel_mission() (which also refunds the cost) rather than
## calling this directly.
func cancel_mission() -> bool:
	if not can_cancel_mission():
		return false
	mission = null
	_path.clear()
	_set_state(State.IN_HUB)
	return true


## Whether this unit's mission can be called off right now: before it has
## left, or while it's back at its hub and the mission allows it (e.g. a
## worker waiting there for resources).
func can_cancel_mission() -> bool:
	if state == State.DEPLOYING:
		return true
	return state == State.ON_MISSION and hex == hub.hex and mission.can_cancel_at_hub()


# --- Turn steps (run by TurnManager, in this order) ------------------------

## "Set out" step, before anyone moves: refresh movement, leave the hub if
## deployed, and let the mission re-plan its route.
func start_turn() -> void:
	movement_left = max_movement
	engaged = false
	moved_this_turn = false
	if state == State.DEPLOYING:
		_set_state(State.ON_MISSION)
		mission.begin()
	elif state == State.ON_MISSION:
		mission.prepare()
	_check_mission_end()
	if state == State.RETURNING and not has_destination():
		set_destination(hub.hex)  # If cut off from home, try again next turn.


## "Work" step, after movement and combat: a unit that spent the whole turn
## at its work site does a turn's work there.
func do_work() -> void:
	if state != State.ON_MISSION or moved_this_turn or not mission.is_working():
		return
	mission.work()
	_check_mission_end()  # Done: heads home next turn.


func _check_mission_end() -> void:
	if state != State.ON_MISSION:
		return
	if mission.is_failed():
		_end_mission(false)
	elif mission.is_complete():
		_end_mission(true)


func _end_mission(success: bool) -> void:
	var finished := mission
	# Listeners (e.g. the HUD) may query this unit, so emit while it still
	# has its mission and only then clear it and head home.
	if success:
		mission_completed.emit(self, finished)
	else:
		mission_failed.emit(self, finished, finished.fail_reason)
	mission = null
	_begin_return()


func _begin_return() -> void:
	_path.clear()
	if hex == hub.hex:
		_arrive_home()
		return
	_set_state(State.RETURNING)
	set_destination(hub.hex)


func _arrive_home() -> void:
	_path.clear()
	_set_state(State.IN_HUB)
	returned_to_hub.emit(self)


# --- Movement --------------------------------------------------------------

## Plans a path to `target`. Returns false if it is unreachable.
func set_destination(target: Vector2i) -> bool:
	if target == hex:
		_path.clear()
		return true
	var path := map.find_path(hex, target)
	if path.is_empty():
		return false
	_path = path
	return true


func has_destination() -> bool:
	return not _path.is_empty()


func get_remaining_path() -> Array[Vector2i]:
	return _path.duplicate()


## The movement tick on which this unit's next step would land, or -1 if it
## isn't moving any further this turn. Movement points double as time: a
## foundation step (cost 1) lands one tick after the last, open ground (cost 3)
## three ticks after. A unit counts as on its old tile until it lands.
##
## A unit may only enter a tile it has enough movement left for - except
## that a unit with full movement can always take one step, so nothing ever
## gets stuck in front of a tile that costs more than its whole allowance.
func get_next_step_tick() -> int:
	if engaged or _path.is_empty() or not is_in_world():
		return -1
	var tile := map.get_tile(_path[0])
	if tile == null or not tile.is_passable():
		_path.clear()  # Blocked; the mission re-plans next turn.
		return -1
	var cost := tile.get_move_cost()
	if not _can_enter(cost, movement_left):
		return -1  # Not enough movement left; carry on next turn.
	var spent := max_movement - movement_left
	return mini(spent + cost, max_movement)


## The tile this unit's next step goes to. Only valid while it has a path.
func get_next_step_hex() -> Vector2i:
	return _path[0]


## Takes the step get_next_step_tick() planned. Called by Movement.
func take_step() -> void:
	var next: Vector2i = _path.pop_front()
	movement_left = maxi(movement_left - map.get_tile(next).get_move_cost(), 0)
	hex = next
	moved_this_turn = true
	_anim_steps.append(map.hex_to_world(hex))
	if _path.is_empty():
		_reached_destination()


## Met enemy fighters: stop moving for the rest of this turn.
func engage() -> void:
	engaged = true
	movement_left = 0


func _reached_destination() -> void:
	if state == State.ON_MISSION and hex == mission.get_travel_hex():
		mission.on_arrived()
		# A finished mission (e.g. Move) starts the walk home straight away,
		# using whatever movement is left this turn.
		_check_mission_end()
	elif state == State.RETURNING and hex == hub.hex:
		_arrive_home()


## Killed in combat. The hub has already removed it from the colony; this
## lets its last move finish playing, then fades it out.
func die() -> void:
	if is_animating():
		await _move_tween.finished
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.4)
	fade.tween_callback(queue_free)


## How many turns this unit needs to walk `path` (not including the start).
func estimate_turns(path: Array[Vector2i]) -> int:
	if path.is_empty():
		return 0
	var turns := 1
	var mp := max_movement
	for h in path:
		var step := map.get_tile(h).get_move_cost()
		if not _can_enter(step, mp):
			turns += 1
			mp = max_movement
		mp = maxi(mp - step, 0)
	return turns


## Whether a unit with `mp` movement left may enter a tile costing `step`.
func _can_enter(step: int, mp: int) -> bool:
	return mp > 0 and (step <= mp or mp == max_movement)


# --- Presentation ----------------------------------------------------------

func get_status_text() -> String:
	match state:
		State.IN_HUB:
			return "Waiting in hub" if waiting else "In hub"
		State.DEPLOYING:
			if mission:
				return "Departs at end of turn - %s" % mission.get_description()
		State.ON_MISSION:
			if mission:
				var carrying := " - carrying %s" % ResourceDeposit.format_cost(materials) if not materials.is_empty() else ""
				return mission.get_progress_text() + carrying
		State.RETURNING:
			var carrying := " with %s" % get_cargo_text() if has_cargo() else ""
			if not materials.is_empty():
				carrying += " (bringing back unused %s)" % ResourceDeposit.format_cost(materials)
			return "Returning to hub%s (%d turn(s) left)" % [carrying, estimate_turns(_path)]
	return ""


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	if _move_tween == null or not _move_tween.is_running():
		_refresh_visibility()
	state_changed.emit(self)


## True while the unit's move animation is still playing.
func is_animating() -> bool:
	return _move_tween != null and _move_tween.is_running()


## Animates the steps taken this turn. Called once movement is resolved.
func play_movement() -> void:
	if _anim_steps.is_empty():
		return
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	visible = true
	_move_tween = create_tween()
	for p in _anim_steps:
		_move_tween.tween_property(self, "global_position", p, move_anim_time)
	_move_tween.tween_callback(_refresh_visibility)
	_anim_steps.clear()


## Units are only drawn while out in the world (not on their own hub, e.g.
## a worker waiting there for resources).
func _refresh_visibility() -> void:
	visible = (state == State.ON_MISSION or state == State.RETURNING) and not (hub and hex == hub.hex)
	if not visible and map:
		global_position = map.hex_to_world(hex)


## Where on its tile this unit's icon sits, and how big it is, when it shares
## the tile with other units. Set by UnitStackLayout.
func set_icon_layout(offset: Vector2, icon_scale: float) -> void:
	if offset == _icon_offset and is_equal_approx(icon_scale, _icon_scale):
		return
	_icon_offset = offset
	_icon_scale = icon_scale
	queue_redraw()


func _draw() -> void:
	var c := _icon_offset
	var s := _icon_scale
	# Ring in the owner's colour so rival units are easy to tell apart.
	var faction_color := Faction.get_color(hub.faction) if hub else Color.BLACK
	draw_circle(c, (RADIUS + 3.5) * s, faction_color)
	draw_circle(c, (RADIUS + 1.5) * s, Color(0, 0, 0, 0.8))
	draw_circle(c, RADIUS * s, body_color)
	var font := ThemeDB.fallback_font
	var font_size := maxi(7, roundi(15 * s))
	var label := get_short_label()
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, c + Vector2(-text_width / 2.0, baseline), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.1, 0.1))
