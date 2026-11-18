class_name Unit
extends Node2D
## Base class for every unit.
##
## Units are never controlled directly. They live in a CentralHub and are
## handed a Mission. During turn resolution they execute the mission, then
## walk back to the hub on their own, where they wait for the next order.
##
## Subclasses (Worker, Scout, ...) set their stats in _init() and can override
## get_short_label() / _draw() for visuals or add new abilities for missions.

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
## Movement points per turn (open ground costs 2, rough 4, road 1).
@export var max_movement := 4
@export var max_health := 10
@export var body_color := Color.WHITE
## Whether this unit can take Harvest missions.
@export var can_harvest := false
## Whether this unit can take Build missions.
@export var can_build := false
## Whether this unit can take Demolish missions.
@export var can_demolish := false
## Seconds the move animation spends on each tile.
@export var move_anim_time := 0.18

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
## Resources being carried home: ResourceDeposit.Type -> int.
## The hub unloads this when the unit returns.
var cargo: Dictionary = {}

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


func is_available() -> bool:
	return state == State.IN_HUB


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


func get_cargo_text() -> String:
	var parts: PackedStringArray = []
	for type in cargo:
		parts.append("%d %s" % [cargo[type], ResourceDeposit.DATA[type]["name"]])
	return ", ".join(parts)


# --- Missions --------------------------------------------------------------

func can_accept_mission(m: Mission) -> bool:
	return state == State.IN_HUB and m.is_valid_for(self)


## Use CentralHub.assign_mission() rather than calling this directly.
func assign_mission(m: Mission) -> void:
	waiting = false
	mission = m
	m.unit = self
	_set_state(State.DEPLOYING)


## A unit that hasn't left yet can have its order withdrawn.
func cancel_deployment() -> bool:
	if state != State.DEPLOYING:
		return false
	mission = null
	_set_state(State.IN_HUB)
	return true


## Runs this unit's turn. Called by the hub during turn resolution.
func process_turn() -> void:
	movement_left = max_movement

	if state == State.DEPLOYING:
		_set_state(State.ON_MISSION)
		mission.begin()

	if state == State.ON_MISSION:
		if not mission.is_failed():
			mission.process_turn()
		if mission.is_failed():
			_end_mission(false)
		elif mission.is_complete():
			_end_mission(true)

	# Not elif: a unit that finished its mission this turn uses any
	# movement it has left to start heading home.
	if state == State.RETURNING:
		_process_return()

	_play_movement()


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


func _process_return() -> void:
	if not has_destination() and not set_destination(hub.hex):
		return  # Cut off from home; try again next turn.
	advance_along_path()
	if hex == hub.hex:
		_arrive_home()


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


## Moves along the planned path using the movement points left this turn.
## Civ-style: a unit with any movement left may always enter the next tile.
func advance_along_path() -> void:
	while movement_left > 0 and not _path.is_empty():
		var next: Vector2i = _path[0]
		var tile := map.get_tile(next)
		if tile == null or not tile.is_passable():
			_path.clear()  # Blocked; the mission will re-plan.
			return
		_path.pop_front()
		hex = next
		movement_left = maxi(movement_left - tile.get_move_cost(), 0)
		_anim_steps.append(map.hex_to_world(hex))


## How many turns this unit needs to walk `path` (not including the start).
func estimate_turns(path: Array[Vector2i]) -> int:
	if path.is_empty():
		return 0
	var turns := 1
	var mp := max_movement
	for h in path:
		if mp <= 0:
			turns += 1
			mp = max_movement
		mp -= map.get_tile(h).get_move_cost()
	return turns


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
				return mission.get_progress_text()
		State.RETURNING:
			var carrying := " with %s" % get_cargo_text() if has_cargo() else ""
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


func _play_movement() -> void:
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


## Units are only drawn while out in the world.
func _refresh_visibility() -> void:
	visible = state == State.ON_MISSION or state == State.RETURNING
	if not visible and map:
		global_position = map.hex_to_world(hex)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 2.0, Color(0, 0, 0, 0.7))
	draw_circle(Vector2.ZERO, RADIUS, body_color)
	var font := ThemeDB.fallback_font
	var font_size := 15
	var label := get_short_label()
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, Vector2(-text_width / 2.0, baseline), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.1, 0.1))
