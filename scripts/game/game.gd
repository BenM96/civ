extends Node2D
## Main game controller: builds the world, routes input and runs turns.
##
## Flow of a turn:
##   - The player opens the hub and assigns missions to units at home.
##   - Pressing End Turn resolves the turn: every unit out of the hub (or
##     about to leave it) executes its mission / walks home.

@export var starting_workers := 1
@export var starting_builders := 2
## TESTING ONLY: amount of every resource the hub starts with, so features
## can be tested without harvesting first. Set to 0 for normal play.
@export var starting_resources := 100
## Skip straight past turns where every unit is already busy when the turn
## starts (nobody needs orders). Turns where the player acts are never skipped.
@export var auto_skip_turns := true
## Adds a computer-controlled rival colony (see AiController).
@export var enable_rival := true
## How far apart (in tiles) the two hubs should ideally be, and at least.
@export var rival_distance := 16
@export var rival_min_distance := 10

## Brief beat after units finish moving before the next skipped turn runs.
const SKIP_PAUSE := 0.15

@onready var map: HexMap = $HexMap
@onready var buildings_root: Node2D = $Buildings
@onready var overlay: HexOverlay = $HexOverlay
@onready var camera: CameraController = $Camera
@onready var hud: Hud = $Hud

var hub: CentralHub
## The computer-controlled opponent's hub and brain (null if disabled).
var rival_hub: CentralHub
var ai: AiController
var turn := 1

var _hover_hex := Vector2i.ZERO
var _has_hover := false
## The unit we're choosing a destination for, or null.
var _targeting_unit: Unit = null
## Mission id being targeted ("move", "harvest").
var _targeting_kind := "move"


func _ready() -> void:
	overlay.map = map
	_generate_world()

	hub = _create_hub(Faction.PLAYER, _hub_spot)
	if enable_rival and _rival_spot != null:
		rival_hub = _create_hub(Faction.RIVAL, _rival_spot)
		ai = AiController.new(rival_hub, map)
		rival_hub.extractor_connected.connect(func(h: Vector2i, type: ResourceDeposit.Type) -> void:
			hud.log_event("The rival colony connected a %s extractor at (%d, %d)"
				% [ResourceDeposit.get_type_name(type), h.x, h.y]))

	hub.unit_event.connect(hud.log_event)
	hub.units_changed.connect(_refresh_markers)
	hud.end_turn_requested.connect(end_turn)
	hud.mission_requested.connect(_begin_targeting)
	hud.cancel_order_requested.connect(_on_cancel_order)
	hud.focus_requested.connect(func(unit: Unit) -> void: camera.focus_on(map.hex_to_world(unit.hex)))
	hud.wait_requested.connect(func(unit: Unit, value: bool) -> void:
		_on_player_action()
		hub.set_unit_waiting(unit, value))
	hud.hub_panel_closed.connect(_cancel_targeting)
	hud.auto_end_toggled.connect(func(on: bool) -> void:
		auto_skip_turns = on
		if not on:
			_skip_this_turn = false)
	hud.train_requested.connect(func(bp: UnitBlueprint) -> void:
		_on_player_action()
		hub.queue_training(bp))
	hud.cancel_training_requested.connect(func(index: int) -> void:
		_on_player_action()
		hub.cancel_training(index))
	hub.inventory_changed.connect(_update_inventory)
	hub.network_changed.connect(_update_inventory)

	camera.set_bounds(map.get_world_rect())
	camera.focus_on(hub.global_position)

	hud.set_turn(turn)
	_update_inventory()
	hud.set_hub(hub)
	hud.log_event("Your colony hub has landed on Mars. Open Units (bottom bar) to give orders.")


# --- World -----------------------------------------------------------------

var _hub_spot := Vector2i.ZERO
var _rival_spot: Variant = null


func _generate_world() -> void:
	for attempt in 20:
		map.generate()
		var spot: Variant = _find_hub_spot()
		if spot == null:
			continue
		_hub_spot = spot
		_rival_spot = _find_rival_spot(spot)
		if _rival_spot != null or not enable_rival:
			return
	push_warning("Couldn't find good hub locations; using what we have.")
	if _rival_spot == null:
		_hub_spot = Hex.offset_to_axial(map.width >> 1, map.height >> 1)


## Builds a hub for `faction` at `spot` with the starting units and stockpile.
func _create_hub(faction: int, spot: Vector2i) -> CentralHub:
	var new_hub := CentralHub.new()
	new_hub.faction = faction
	buildings_root.add_child(new_hub)
	new_hub.place(map, spot)
	map.remove_deposit(spot)
	for i in starting_workers:
		new_hub.add_unit(Worker.new())
	for i in starting_builders:
		new_hub.add_unit(Builder.new())
	# TESTING ONLY: start with a stockpile of every resource so new features
	# (training, roads, extractors, conveyors...) can be tried straight away
	# without harvesting first. Set starting_resources to 0 for real games.
	# The rival gets the same so the contest stays fair.
	for type in ResourceDeposit.Type.values():
		new_hub.add_resource(type, starting_resources)
	return new_hub


## A spot for the rival's hub: open ground the player can walk to, as close
## as possible to rival_distance tiles away (so neither side is crowded).
func _find_rival_spot(player_spot: Vector2i) -> Variant:
	var best: Variant = null
	var best_score := 0
	for h in map.tiles:
		var d := Hex.distance(h, player_spot)
		if d < rival_min_distance or not map.is_passable(h):
			continue
		var open := 0
		for n in Hex.neighbors(h):
			if map.is_passable(n):
				open += 1
		if open < 5:
			continue
		var score := absi(d - rival_distance)
		if best == null or score < best_score:
			if not map.find_path(player_spot, h).is_empty():
				best = h
				best_score = score
	return best


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

func end_turn() -> void:
	_cancel_targeting()
	# The rival decides first so its orders depart at the same time as ours.
	if ai:
		ai.take_turn()
	hub.process_turn()
	if rival_hub:
		rival_hub.process_turn()
	turn += 1
	hud.set_turn(turn)
	_refresh_markers()
	_start_turn()


## Decides, once, whether the new turn needs the player at all. A turn is
## skipped only if every unit was already busy when it began - a turn where
## the player is giving orders is never ended for them.
func _start_turn() -> void:
	_skip_this_turn = auto_skip_turns and _no_units_need_orders()
	_skip_wait = 0.0


var _skip_this_turn := false
var _skip_wait := 0.0


## True when no unit needs orders (all busy or waiting) and letting time pass
## would actually change something (units out, or training in progress).
func _no_units_need_orders() -> bool:
	if hub.units.is_empty() or not hub.get_units_needing_orders().is_empty():
		return false
	return not hub.get_field_units().is_empty() or not hub.training_queue.is_empty()


## The player did something this turn, so it's theirs to end.
func _on_player_action() -> void:
	_skip_this_turn = false


func _update_auto_skip(delta: float) -> void:
	if not _skip_this_turn:
		return
	if not auto_skip_turns or not _no_units_need_orders():
		_skip_this_turn = false
		return
	# Let this turn's movement play out before moving on.
	var all_units: Array[Unit] = hub.units.duplicate()
	if rival_hub:
		all_units.append_array(rival_hub.units)
	for unit in all_units:
		if unit.is_animating():
			_skip_wait = 0.0
			return
	_skip_wait += delta
	if _skip_wait >= SKIP_PAUSE:
		end_turn()


# --- Input -----------------------------------------------------------------

func _process(delta: float) -> void:
	_update_auto_skip(delta)
	var h := map.world_to_hex(get_global_mouse_position())
	var has := map.has_tile(h)
	if h != _hover_hex or has != _has_hover:
		_hover_hex = h
		_has_hover = has
		overlay.set_hover(h, has)
		_update_hover_info()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_targeting()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			end_turn()
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
		var mission := _make_mission(_targeting_kind, _hover_hex)
		mission.unit = unit  # Lets the mission plan its route (e.g. bridge work site).
		var reason := _invalid_reason(unit, mission)
		if reason == "" and hub.assign_mission(unit, mission):
			_cancel_targeting()
		else:
			hud.set_hint("%s: %s. Pick another tile (right-click/Esc to cancel)."
				% [unit.display_name, reason if reason != "" else "can't do that"])
		return
	if _hover_hex == hub.hex:
		hud.show_hub(hub)
	else:
		hud.hide_hub()


# --- Targeting -------------------------------------------------------------

## Builds the mission for a mission id coming from the HUD:
## "move", "harvest", "demolish" or "build:<buildable id>". Add new mission kinds here.
func _make_mission(kind: String, target: Vector2i) -> Mission:
	if kind.begins_with("build:"):
		return BuildMission.new(target, hub.get_buildable(kind.trim_prefix("build:")))
	match kind:
		"demolish":
			return DemolishMission.new(target)
		"harvest":
			return HarvestMission.new(target)
		_:
			return MoveToTileMission.new(target)


func _begin_targeting(unit: Unit, kind: String) -> void:
	_targeting_unit = unit
	_targeting_kind = kind
	var what := "a destination"
	if kind == "demolish":
		what = "something man-made to demolish"
	elif kind == "harvest":
		what = "a deposit to harvest"
	elif kind.begins_with("build:"):
		what = "where to build a %s" % hub.get_buildable(kind.trim_prefix("build:")).display_name
	hud.set_hint("Choose %s for %s (right-click/Esc to cancel)" % [what, unit.display_name])
	_update_hover_info()


func _cancel_targeting() -> void:
	if _targeting_unit == null:
		return
	_targeting_unit = null
	overlay.clear_preview()
	hud.set_hint("")
	_update_hover_info()


func _on_cancel_order(unit: Unit) -> void:
	_on_player_action()
	if hub.cancel_mission(unit):
		hud.log_event("%s's order was cancelled" % unit.display_name)


## Why `unit` can't take `mission`, or "" if it can (includes affordability).
func _invalid_reason(unit: Unit, mission: Mission) -> String:
	var reason := mission.get_invalid_reason(unit)
	if reason != "":
		return reason
	if not hub.can_afford(mission.get_cost()):
		return "need %s" % ResourceDeposit.format_cost(mission.get_cost())
	return ""


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
		var unit := _targeting_unit
		var mission := _make_mission(_targeting_kind, _hover_hex)
		mission.unit = unit  # Lets the mission plan its route (e.g. bridge work site).
		var reason := _invalid_reason(unit, mission)
		var valid := reason == ""
		var preview: Array[Vector2i] = []
		var label := ""
		if valid:
			var path := map.find_path(hub.hex, mission.get_travel_hex())
			preview.append(hub.hex)
			preview.append_array(path)
			var turns := unit.estimate_turns(path)
			label = "%d turn%s" % [turns, "" if turns == 1 else "s"]
			var work := mission.get_work_turns()
			if work > 0:
				label += " + %d working" % work
			info += "\nRoute: %d tiles, ~%s (then returns home)" % [path.size(), label]
			if not mission.get_cost().is_empty():
				info += "\nCost: %s" % ResourceDeposit.format_cost(mission.get_cost())
		else:
			preview.append(_hover_hex)
			label = reason.left(1).to_upper() + reason.substr(1)
			info += "\n" + label
		overlay.set_preview(preview, valid, label)

	hud.set_tile_info(info)


func _structure_info(tile: HexTile) -> String:
	var text := Structure.get_display_name(tile.structure)
	if tile.structure_owner != Faction.PLAYER:
		text = "%s's %s" % [Faction.get_display_name(tile.structure_owner), text]
	var owner_hub: CentralHub = map.hubs.get(tile.structure_owner)
	var connected := owner_hub != null and owner_hub.is_supply_connected(tile.coord)
	if tile.structure == Structure.Type.EXTRACTOR:
		if not tile.has_deposit():
			return text + " - deposit exhausted"
		if connected:
			return text + " - connected, +%d %s per turn" % [
				CentralHub.EXTRACTOR_OUTPUT, tile.deposit.get_display_name()]
		return text + " - NOT connected (needs conveyor belts to the hub)"
	return text + (" - connected to the hub" if connected else " - not connected to the hub")


func _update_inventory() -> void:
	hud.set_inventory(hub.inventory, hub.get_income())


func _refresh_markers() -> void:
	var markers: Array[Vector2i] = []
	for unit in hub.units:
		if unit.mission:
			var target: Variant = unit.mission.get_target_hex()
			if target != null:
				markers.append(target)
	overlay.set_markers(markers)
