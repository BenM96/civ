class_name Unit
extends Node2D
## Base class for every unit.
##
## Units are never controlled directly. They live in a Player and are
## handed a Mission. During turn resolution they execute the mission, then
## walk back to the hub on their own, where they wait for the next order.
##
## Subclasses (Miner, Tank, ...) set ALL their data in _init() - stats,
## training cost, training time, upkeep and the short label drawn on their
## icon - and can add new abilities for missions. Units of each type share
## a base: ArmourUnit (fires twice a round) and AirUnit (flies straight to
## its target and home again in one turn, then refits). To make a hub able to
## train a unit, add its class to the list in Player._init().
##
## Icons are shaped by unit type: civilians are round, infantry pentagons and
## armour squares (see draw_icon()). Aircraft are drawn as a top-down outline
## of the aircraft itself (see silhouette and draw_aircraft()), above the
## ground units on their tile, pointing the way they fly.

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
## A repeats_left value meaning "keep repeating forever".
const REPEAT_FOREVER := -1

@export var unit_name := "Unit"
## Short label drawn on the unit's icon, e.g. "MI", "I" or "AA" (1-3 letters).
@export var short_name := ""
## What kind of unit this is (see unit_type). Add new kinds at the end.
enum UnitType { INFANTRY, CIVILIAN, AIR, ARMOUR }

## Resources paid to train one of this unit: ResourceDeposit.Type -> int.
## Always the same, however many you've had.
## Specialist units (ones needing their own tech) add SPECIALIST_COST.
var cost: Dictionary = {}
## What specialist units (Assault, AT and Stinger Infantry, Tank Destroyer,
## Tank, AA Gun, Fighter, Bomber) pay on top of their type's price.
const SPECIALIST_COST := {ResourceDeposit.Type.ELECTRUM: 1}
## Turns a hub spends training this unit.
@export var train_turns := 1
## Biomass this unit eats every turn, wherever it is.
@export var upkeep := 1
## Movement points per turn (open ground costs 3, foundations and bridges 1).
@export var max_movement := 3
## Hit points (HP) a fresh unit has. Losing them all in battle kills it;
## a hit that leaves it at or below half makes it break and flee (see Combat).
@export var max_health := 10
## What kind of unit this is. Decides how much damage each attacker does to
## it (see `damage`), and which hub room it waits in when off duty (Break
## Room, Barracks, Hangar or Garage - see QuartersRoom).
@export var unit_type := UnitType.INFANTRY
## HP this unit takes off an enemy with each shot, by the enemy's type:
## UnitType -> int. Types left out take no damage from it.
@export var damage: Dictionary = {}
## Shots fired one after another each time its turn comes round in a
## battle (armour fires twice - see Combat).
@export var shots_per_turn := 1
## Flies instead of walking: goes out and comes home in a single jump each
## (see AirUnit), ignoring terrain.
@export var flies := false
## Which aircraft outline to draw (see draw_aircraft()): "helicopter",
## "spitfire", "eurofighter" or "lancaster". "" for ground units.
@export var silhouette := ""
## Turns spent refitting in its quarters (e.g. the Hangar) after every trip
## out, before it can go to Mission Briefing again. Refitting also repairs
## it to full HP. 0 = never refits.
@export var refit_turns := 0
@export var body_color := Color.WHITE
## The kinds of mission this unit may be given: "move", "harvest", "build"
## (any structure) and/or "demolish" - the same names orders use (see
## Orders.make_mission). The HUD only offers these, and Orders refuses others.
@export var allowed_missions: Array[String] = ["move"]
## Seconds the move animation spends on each tile.
@export var move_anim_time := 0.18

## Permanent number identifying this unit in orders and saves; the same on
## every computer. Given out by the map when the unit joins (0 = not yet).
var id := 0
## Unique name given by the hub, e.g. "Builder 2".
var display_name := ""
var hex: Vector2i
var player: Player
var map: HexMap
var state: State = State.IN_HUB
var mission: Mission
var movement_left := 0
var health := 0
## The hub room (see Room) this unit is in while it's at the hub, e.g.
## "mission_briefing". Kept while it's out, so a unit that comes back to the
## hub partway through a mission (or a QRF between call-outs) is back in the
## same room.
var room_id := ""
## Turns of refitting still to do (see refit_turns); counted down by its
## quarters room.
var refit_turns_left := 0
## The kind of the last mission this unit was given (e.g. "harvest",
## "build:foundation"), so the HUD can offer it again. "" if it's never had one.
var last_mission_kind := ""
## How many more times to do the last mission again once back in Mission
## Briefing (see Player.repeat_orders()): 0 for none, REPEAT_FOREVER for
## forever. repeat_target is the tile it was aimed at.
var repeats_left := 0
var repeat_target := Vector2i.ZERO
## Turns left off duty in its quarters before it goes back to Mission
## Briefing by itself (the Wait button's number - see Player.move_unit_to_room()).
## 0 means it stays until moved.
var wait_turns_left := 0
## A standby duty (QRF, Regroup or Intercept) this unit left to heal or refit, to take up again
## once it's back in Mission Briefing (see Player.repeat_orders()): the
## mission kind ("" for none), and for QRF the turns of duty it had left
## (REPEAT_FOREVER for no limit).
var rejoin_kind := ""
var rejoin_turns := 0
## For QRF: the FOB it was based at (see QrfMission.base), or null for the hub.
var rejoin_base: Variant = null
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
## Which way an aircraft's nose points, in radians (0 = up the screen).
var _heading := 0.0

## Seconds an aircraft hangs over its target before its flight home plays.
const HOVER_TIME := 0.6
## While true (the game is replaying this turn's battles), aircraft hang
## over their targets instead of flying home, until release_return().
static var hold_air_return := false
## Waiting over its target for hold_air_return to end.
var _return_waiting := false
## A tile the map keeps showing as it was until this aircraft heads home
## (see reveal_when_leaving()), or null.
var _reveal_on_leave: Variant = null
## Seconds an aircraft's flight (out or home) takes to show, however far.
const FLIGHT_TIME := 0.7


func _ready() -> void:
	z_index = 12 if flies else 10  # Aircraft over everything on the ground.
	health = max_health


## HP taken off `target` by one shot from this unit: its damage against
## that type, plus its colony's techs for its unit type (Weapons techs, Civil
## Defence). Types it can't hurt at all (0 damage) stay at 0.
func get_damage_against(target: Unit) -> int:
	var base: int = damage.get(target.unit_type, 0)
	if base <= 0:
		return 0
	var bonus := 0
	if player:
		bonus = player.get_type_damage_bonus(unit_type, target.unit_type)
	return base + bonus


## Movement points a turn: max_movement, plus its colony's All-Terrain
## Drives techs for land units (aircraft fly sorties instead).
func get_max_movement() -> int:
	if flies or player == null:
		return max_movement
	return max_movement + player.get_movement_bonus()


## Loses `amount` HP (a hit in battle). Dying is up to Combat.
func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	health -= amount
	queue_redraw()
	state_changed.emit(self)  # So the HUD shows the new HP.


## The unit types this unit would rather shoot at, best first: grouped by
## the damage it does to them, most damage first (types it does equal
## damage to share a group). Civilians always come last, whatever the
## damage. Types it can't hurt at all come before civilians but after every
## type it can. E.g. a Tank: [[INFANTRY], [ARMOUR], [AIR], [CIVILIAN]].
func get_target_preference() -> Array:
	var by_damage := {}  # damage -> [UnitType]
	for type in UnitType.values():
		if type == UnitType.CIVILIAN:
			continue
		var amount: int = damage.get(type, 0)
		if not by_damage.has(amount):
			by_damage[amount] = []
		by_damage[amount].append(type)
	var amounts := by_damage.keys()
	amounts.sort()
	amounts.reverse()
	var groups := []
	for amount in amounts:
		groups.append(by_damage[amount])
	groups.append([UnitType.CIVILIAN])
	return groups


## Of the enemies `candidates`, the ones this unit prefers to shoot at: those
## of the most preferred type present (see get_target_preference()).
func pick_preferred_targets(candidates: Array[Unit]) -> Array[Unit]:
	for group: Array in get_target_preference():
		var chosen: Array[Unit] = []
		for u in candidates:
			if u.unit_type in group:
				chosen.append(u)
		if not chosen.is_empty():
			return chosen
	return candidates


## Gets back up to `amount` HP (never above max_health), e.g. in the Med Bay.
func heal(amount: int) -> void:
	var healed := mini(health + amount, max_health)
	if healed == health:
		return
	health = healed
	queue_redraw()
	state_changed.emit(self)


func is_injured() -> bool:
	return health < max_health


## At or below half its max HP (but alive). A hit that leaves a unit like
## this breaks it (see Combat) - so a 10 HP Builder hit for 5 runs.
func is_broken() -> bool:
	return health > 0 and health <= max_health / 2.0


## Called by the hub when the unit joins it.
func setup(p_player: Player, p_map: HexMap) -> void:
	player = p_player
	map = p_map
	hex = player.hex
	global_position = map.hex_to_world(hex)
	_refresh_visibility()


func get_short_label() -> String:
	return short_name if short_name != "" else unit_name.left(1)


## Whether this unit may take a mission of `kind`. "build:foundation" counts as
## "build", so a unit that can build can build any structure. Regroup is for
## military units that can do QRF duty.
func can_take(kind: String) -> bool:
	if kind == "regroup":
		return unit_type != UnitType.CIVILIAN and can_take("qrf")
	return kind.get_slice(":", 0) in allowed_missions


func is_available() -> bool:
	return state == State.IN_HUB


## Out on the map (not garrisoned), so it can fight or be attacked.
func is_in_world() -> bool:
	return state == State.ON_MISSION or state == State.RETURNING


## Inside its hub, so it's in one of the hub's rooms: at home, about to set
## out, or back at the hub partway through a mission (e.g. a QRF on standby).
func is_in_hub() -> bool:
	return player != null and hex == player.hex and state != State.RETURNING


## At home in Mission Briefing - the player should give it something to do.
## (Only units in Mission Briefing can be given orders.)
func needs_orders() -> bool:
	return state == State.IN_HUB and room_id == MissionBriefingRoom.ID


## Records which hub room the unit is in. Moves the player asks for go
## through Player.move_unit_to_room(), which checks the rules first.
func set_room(new_room_id: String) -> void:
	if room_id == new_room_id:
		return
	room_id = new_room_id
	wait_turns_left = 0  # A new room ends any timed wait.
	state_changed.emit(self)


## Adds SPECIALIST_COST to this unit's price (on top of what it already
## costs of the same resource - e.g. aircraft already pay Electrum).
func add_specialist_cost() -> void:
	for type: ResourceDeposit.Type in SPECIALIST_COST:
		cost[type] = cost.get(type, 0) + SPECIALIST_COST[type]


## A `damage` table: HP taken off each type of enemy per shot.
## Order: civilian, infantry, armour, air.
static func damage_vs(civilian: int, infantry: int, armour: int, air: int) -> Dictionary:
	return {
		UnitType.CIVILIAN: civilian,
		UnitType.INFANTRY: infantry,
		UnitType.ARMOUR: armour,
		UnitType.AIR: air,
	}


## Display name of a unit type, e.g. "Civilian".
static func get_type_name(type: UnitType) -> String:
	return UnitType.keys()[type].capitalize()


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
		"room": room_id,
		"refit_turns_left": refit_turns_left,
		"last_mission_kind": last_mission_kind,
		"repeats_left": repeats_left,
		"repeat_target": SaveGame.hex_to_data(repeat_target),
		"wait_turns_left": wait_turns_left,
		"rejoin_kind": rejoin_kind,
		"rejoin_turns": rejoin_turns,
		"rejoin_base": SaveGame.hex_to_data(rejoin_base) if rejoin_base != null else null,
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
	room_id = data["room"]
	refit_turns_left = int(data["refit_turns_left"])
	last_mission_kind = data.get("last_mission_kind", "")  # Older saves lack it.
	repeats_left = int(data["repeats_left"])
	repeat_target = SaveGame.hex_from_data(data["repeat_target"])
	wait_turns_left = int(data["wait_turns_left"])
	rejoin_kind = str(data["rejoin_kind"])
	rejoin_turns = int(data["rejoin_turns"])
	rejoin_base = SaveGame.hex_from_data(data["rejoin_base"]) if data.get("rejoin_base") != null else null
	health = int(data["health"])
	cargo = SaveGame.resources_from_data(data["cargo"])
	materials = SaveGame.resources_from_data(data.get("materials", {}))  # Older saves lack it.
	_path.clear()
	for h in data["path"]:
		_path.append(SaveGame.hex_from_data(h))
	if data["mission"] != null:
		var m_data: Dictionary = data["mission"]
		mission = Orders.make_mission(player, m_data["kind"], SaveGame.hex_from_data(m_data["target"]))
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

## Do the mission just given (aimed at `target`) `more` more times after
## this one (REPEAT_FOREVER for forever, 0 for just once).
func set_repeats(target: Vector2i, more: int) -> void:
	repeats_left = more
	repeat_target = target


## "2 more times", "forever", or "" if it isn't repeating.
func get_repeat_text() -> String:
	if repeats_left == REPEAT_FOREVER:
		return "repeating forever"
	if repeats_left > 0:
		return "%d more time%s" % [repeats_left, "" if repeats_left == 1 else "s"]
	return ""


func can_accept_mission(m: Mission) -> bool:
	return state == State.IN_HUB and m.is_valid_for(self)


## Use Player.assign_mission() rather than calling this directly.
func assign_mission(m: Mission) -> void:
	mission = m
	last_mission_kind = m.get_kind()
	m.unit = self
	_set_state(State.DEPLOYING)


## RTB: drops the mission of a unit out on the map and heads home with
## whatever it carries (walking units set off next turn; aircraft fly home
## at the start of it). Use Player.recall_all().
func recall() -> void:
	if state != State.ON_MISSION:
		return
	mission = null
	repeats_left = 0
	rejoin_kind = ""
	_path.clear()
	if hex == player.hex:
		_arrive_home()
		return
	_set_state(State.RETURNING)


## Withdraws the mission from a unit that hasn't left yet. Use
## Player.cancel_mission() (which also refunds the cost) rather than
## calling this directly.
func cancel_mission() -> bool:
	if not can_cancel_mission():
		return false
	mission = null
	repeats_left = 0  # Calling it off stops any repeats too.
	rejoin_kind = ""
	_path.clear()
	_set_state(State.IN_HUB)
	return true


## Whether this unit's mission can be called off right now: before it has
## left, or while it's back at its hub and the mission allows it (e.g. a
## worker waiting there for resources).
func can_cancel_mission() -> bool:
	if state == State.DEPLOYING:
		return true
	return state == State.ON_MISSION and hex == player.hex and mission.can_cancel_at_hub()


# --- Turn steps (run by TurnManager, in this order) ------------------------

## "Set out" step, before anyone moves: refresh movement, leave the hub if
## deployed, and let the mission re-plan its route.
func start_turn() -> void:
	movement_left = get_max_movement()
	engaged = false
	moved_this_turn = false
	if state == State.DEPLOYING:
		_set_state(State.ON_MISSION)
		mission.begin()
	elif state == State.ON_MISSION:
		mission.prepare()
	_check_mission_end()
	if state == State.RETURNING and flies:
		fly_to(player.hex)  # Normally home already (see return_from_air()).
	elif state == State.RETURNING and not has_destination():
		set_destination(player.hex)  # If cut off from home, try again next turn.


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
	if hex == player.hex:
		_arrive_home()
		return
	_set_state(State.RETURNING)
	if flies:
		fly_to(player.hex)
	else:
		set_destination(player.hex)


## Jumps straight to `target` (a flying unit; see AirUnit), whatever lies
## between. Landing on its own hub brings it home. The flight is shown after
## any move already playing or waiting to play (see play_movement()).
func fly_to(target: Vector2i) -> void:
	_path.clear()
	var from := hex
	hex = target
	moved_this_turn = true
	if from != target:
		_anim_steps.append(map.hex_to_world(hex))
	if hex == player.hex and state == State.RETURNING:
		if _anim_steps.is_empty() and not is_animating():
			global_position = map.hex_to_world(hex)  # Nothing to show.
		_arrive_home()


## The air return phase, after combat (see TurnManager): an aircraft out on
## the map ends its mission (see Mission.air_return() - e.g. a Carpet Bomb
## drops its bombs first) and flies home. One on standby at the hub (an
## interceptor that wasn't called out) stays put.
func return_from_air() -> void:
	if not flies or not is_in_world() or hex == player.hex:
		return
	if state == State.ON_MISSION:
		mission.air_return()
		_check_mission_end()  # Flies home (see _begin_return()).
	if state == State.RETURNING:
		fly_to(player.hex)


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
	var path := map.find_path(hex, target, player.id if player else Faction.NONE)
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
	var spent := get_max_movement() - movement_left
	return mini(spent + cost, get_max_movement())


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


## Caught in a battle: stop moving for the rest of this turn.
func engage() -> void:
	engaged = true
	movement_left = 0


func _reached_destination() -> void:
	if state == State.ON_MISSION and hex == mission.get_travel_hex():
		mission.on_arrived()
		# A finished mission (e.g. Move) starts the walk home straight away,
		# using whatever movement is left this turn.
		_check_mission_end()
	elif state == State.RETURNING and hex == player.hex:
		_arrive_home()


## Broke in battle (see Combat): drops its mission and retreats one tile
## towards its hub, then carries on home like any returning unit. Anything
## it carries comes home with it.
func break_off() -> void:
	if state == State.ON_MISSION:
		var abandoned := mission
		abandoned.fail_reason = "broke in battle and fled"
		abandoned.on_broken()  # e.g. QRF: back on duty once healed.
		mission_failed.emit(self, abandoned, abandoned.fail_reason)
		mission = null
	if hex == player.hex:
		_arrive_home()
		return
	_set_state(State.RETURNING)
	if flies:
		return  # Flies home in the air return phase (see return_from_air()).
	if not set_destination(player.hex) or _path.is_empty():
		return  # Cut off from home: tries again next turn.
	hex = _path.pop_front()
	if _path.is_empty():
		_arrive_home()
	_animate_retreat(map.hex_to_world(hex))


## Plays the retreat step once this turn's move has finished playing.
func _animate_retreat(to: Vector2) -> void:
	if is_animating():
		await _move_tween.finished
	_anim_steps.append(to)
	play_movement()


## Killed in combat. The hub has already removed it from the colony; this
## lets its last move finish playing, then fades it out.
func die() -> void:
	_reveal_target()  # Won't be heading home to show it.
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
	var mp := get_max_movement()
	for h in path:
		var step := map.get_tile(h).get_move_cost()
		if not _can_enter(step, mp):
			turns += 1
			mp = get_max_movement()
		mp = maxi(mp - step, 0)
	return turns


## Whether a unit with `mp` movement left may enter a tile costing `step`.
func _can_enter(step: int, mp: int) -> bool:
	return mp > 0 and (step <= mp or mp == get_max_movement())


# --- Presentation ----------------------------------------------------------

## One line for the hovered-tile panel, e.g. "Builder 2 (Pink colony) - HP
## 7/10 - Harvest Biomass at (3, 4)".
func get_hover_text() -> String:
	var doing := "Returning to hub"
	if state == State.ON_MISSION and mission:
		doing = mission.get_description()
	return "%s (%s) - HP %d/%d - %s" % [display_name, player.get_display_name(), health, max_health, doing]


func get_status_text() -> String:
	var text := _get_activity_text()
	var repeat := get_repeat_text()
	if repeat != "":
		text += "  [%s]" % repeat
	if health < max_health:
		text += "  [HP %d/%d]" % [health, max_health]
	return text


func _get_activity_text() -> String:
	match state:
		State.IN_HUB:
			var room := player.get_room(room_id) if player else null
			return room.get_activity_text(self) if room else "In hub"
		State.DEPLOYING:
			if mission:
				return mission.get_deploying_text()
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
	# Mid-move (or with a move still to show), the move's end sorts it out.
	if not is_animating() and _anim_steps.is_empty():
		_refresh_visibility()
	state_changed.emit(self)


## True while the unit's move animation is still playing.
func is_animating() -> bool:
	return _move_tween != null and _move_tween.is_running()


## Seconds play_movement() will take to show the steps taken this turn.
func get_movement_anim_time() -> float:
	return _anim_steps.size() * _get_step_time()


## Seconds each step (for an aircraft, each whole flight) takes to show.
func _get_step_time() -> float:
	return FLIGHT_TIME if flies else move_anim_time


## Animates the steps taken this turn. Called once movement is resolved.
## `delay` holds the unit still first (a QRF waits for everyone else's move
## to finish playing, since it moves after them). If a move is still
## playing, these steps play once it ends instead (see _on_move_played()).
## Aircraft turn to face each way they fly.
func play_movement(delay := 0.0) -> void:
	if _anim_steps.is_empty() or is_animating():
		return
	_play_steps(delay)


func _play_steps(delay: float) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	visible = true
	_move_tween = create_tween()
	if delay > 0.0:
		_move_tween.tween_interval(delay)
	var from := global_position
	for p in _anim_steps:
		if flies and p != from:
			_move_tween.tween_callback(_set_heading.bind((p - from).angle() + PI / 2.0))
		_move_tween.tween_property(self, "global_position", p, _get_step_time())
		from = p
	_anim_steps.clear()
	_move_tween.tween_callback(_on_move_played)


## A move finished playing: play any steps added meanwhile (an aircraft's
## flight home, after hanging over its target a moment - or until the
## battle replays are over, see hold_air_return), or hide the unit if it's
## now at home.
func _on_move_played() -> void:
	if not _anim_steps.is_empty():
		if flies and hold_air_return:
			_return_waiting = true  # Stays shown over its target.
			return
		_reveal_target()
		_play_steps(HOVER_TIME if flies else 0.0)
	else:
		_refresh_visibility()


## The battle replays are over: an aircraft held over its target flies home.
func release_return() -> void:
	if _return_waiting:
		_return_waiting = false
		_reveal_target()
		_play_steps(0.2)


## The map keeps showing `h` as it was (HexMap.show_as_before()) until this
## aircraft heads home - e.g. a Bomber's target, so the rubble appears once
## the player has seen it get there and come through the battle.
func reveal_when_leaving(h: Vector2i) -> void:
	_reveal_on_leave = h
	if not is_animating():
		_reveal_target()  # Nothing being shown: no need to wait.


func _reveal_target() -> void:
	if _reveal_on_leave != null:
		map.show_now(_reveal_on_leave)
		_reveal_on_leave = null


func _set_heading(angle: float) -> void:
	_heading = angle
	queue_redraw()


## Units are only drawn while out in the world (not on their own hub, e.g.
## a Builder waiting there for resources).
func _refresh_visibility() -> void:
	visible = (state == State.ON_MISSION or state == State.RETURNING) and not (player and hex == player.hex)
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


## Draws a unit icon on `canvas`: its type's shape (see shape_points()) in
## `body` colour, with a ring of the owner's colour and `label` on it.
## Shared with the battle replay (BattleView).
static func draw_icon(canvas: CanvasItem, type: UnitType, c: Vector2, r: float,
		faction_color: Color, body: Color, label: String, alpha := 1.0) -> void:
	var ring := faction_color
	ring.a *= alpha
	var gap := Color(0, 0, 0, 0.8 * alpha)
	var fill := body
	fill.a *= alpha
	if type == UnitType.CIVILIAN:
		canvas.draw_circle(c, r + r * 0.27, ring)
		canvas.draw_circle(c, r + r * 0.12, gap)
		canvas.draw_circle(c, r, fill)
	else:
		canvas.draw_colored_polygon(shape_points(type, c, r + r * 0.3), ring)
		canvas.draw_colored_polygon(shape_points(type, c, r + r * 0.14), gap)
		canvas.draw_colored_polygon(shape_points(type, c, r), fill)
	# Label shrinks to fit (e.g. "APC"), and sits a little low in a triangle.
	var font := ThemeDB.fallback_font
	var font_size := maxi(6, roundi(r * 1.15))
	var max_width := r * (1.3 if type == UnitType.AIR else 1.75)
	while font_size > 6 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		font_size -= 1
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var drop := r * 0.25 if type == UnitType.AIR else 0.0
	canvas.draw_string(font, c + Vector2(-text_width / 2.0, baseline + drop), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.1, 0.1, 0.1, alpha))


## Top-down outlines of each aircraft (see `silhouette`), nose up, in units
## of about half the wingspan: [nose y, right-hand outline from nose to tail,
## tail y]. The left half is the mirror image.
const SILHOUETTES := {
	"helicopter": [-0.62, [Vector2(0.12, -0.58), Vector2(0.2, -0.4), Vector2(0.22, -0.1),
		Vector2(0.17, 0.12), Vector2(0.06, 0.25), Vector2(0.04, 0.78), Vector2(0.18, 0.76),
		Vector2(0.2, 0.84), Vector2(0.18, 0.92), Vector2(0.04, 0.9)], 0.95],
	"spitfire": [-1.0, [Vector2(0.07, -0.97), Vector2(0.1, -0.8), Vector2(0.11, -0.42),
		Vector2(0.45, -0.4), Vector2(0.75, -0.34), Vector2(0.93, -0.25), Vector2(1.0, -0.15),
		Vector2(0.96, -0.07), Vector2(0.78, -0.01), Vector2(0.45, 0.03), Vector2(0.11, 0.06),
		Vector2(0.08, 0.58), Vector2(0.3, 0.62), Vector2(0.38, 0.69), Vector2(0.34, 0.78),
		Vector2(0.07, 0.8)], 0.95],
	"eurofighter": [-1.0, [Vector2(0.05, -0.82), Vector2(0.09, -0.6), Vector2(0.3, -0.5),
		Vector2(0.3, -0.45), Vector2(0.1, -0.43), Vector2(0.12, -0.15), Vector2(0.78, 0.55),
		Vector2(0.78, 0.66), Vector2(0.15, 0.66), Vector2(0.13, 0.88), Vector2(0.03, 0.88)], 0.84],
	"lancaster": [-0.95, [Vector2(0.07, -0.9), Vector2(0.09, -0.72), Vector2(0.1, -0.42),
		Vector2(0.2, -0.42), Vector2(0.21, -0.58), Vector2(0.28, -0.58), Vector2(0.29, -0.41),
		Vector2(0.43, -0.4), Vector2(0.44, -0.55), Vector2(0.51, -0.55), Vector2(0.52, -0.39),
		Vector2(1.0, -0.33), Vector2(1.0, -0.24), Vector2(0.1, -0.14), Vector2(0.07, 0.6),
		Vector2(0.34, 0.62), Vector2(0.34, 0.54), Vector2(0.42, 0.54), Vector2(0.42, 0.8),
		Vector2(0.34, 0.8), Vector2(0.34, 0.74), Vector2(0.05, 0.74)], 0.82],
}


## Draws an aircraft on `canvas`: its top-down outline (see SILHOUETTES) in
## `body` colour, edged in the owner's colour, centred on `c`, about `r`
## (an icon's radius) across each wing, its nose pointing `heading` radians
## clockwise from straight up. Shared with the battle replay (BattleView).
static func draw_aircraft(canvas: CanvasItem, kind: String, c: Vector2, r: float,
		faction_color: Color, body: Color, heading := 0.0, alpha := 1.0) -> void:
	var size := r * 1.5
	var outline := aircraft_points(kind, c, size, heading)
	var closed := outline.duplicate()
	closed.append(outline[0])
	var edge := maxf(1.5, r * 0.2)
	canvas.draw_polyline(closed, Color(0, 0, 0, 0.7 * alpha), edge + 2.0, true)
	var ring := faction_color
	ring.a *= alpha
	canvas.draw_polyline(closed, ring, edge, true)
	var fill := body
	fill.a *= alpha
	canvas.draw_colored_polygon(outline, fill)
	if kind == "helicopter":
		# Main rotor: two blades across a faint disc.
		var hub := c + Vector2(0, -0.15 * size).rotated(heading)
		var disc := ring
		disc.a *= 0.35
		canvas.draw_arc(hub, size * 0.95, 0.0, TAU, 24, disc, maxf(1.0, r * 0.08), true)
		# Blades along and across the body, so they don't read as a cross-out.
		var blade := Color(0.2, 0.2, 0.22, 0.75 * alpha)
		for angle in [0.0, PI / 2.0]:
			var tip := Vector2(0, -size * 0.9).rotated(heading + angle)
			canvas.draw_line(hub - tip, hub + tip, blade, maxf(1.0, r * 0.09), true)
		canvas.draw_circle(hub, maxf(1.5, r * 0.12), blade)


## The outline of aircraft `kind` (see SILHOUETTES) around `c`, `size`
## pixels per unit, turned `heading` radians.
static func aircraft_points(kind: String, c: Vector2, size: float, heading := 0.0) -> PackedVector2Array:
	var data: Array = SILHOUETTES.get(kind, SILHOUETTES["spitfire"])
	var half: Array = data[1]
	var local: Array[Vector2] = [Vector2(0, data[0])]
	local.append_array(half)
	local.append(Vector2(0, data[2]))
	for i in range(half.size() - 1, -1, -1):
		local.append(Vector2(-half[i].x, half[i].y))
	var points := PackedVector2Array()
	for p in local:
		points.append(c + (p * size).rotated(heading))
	return points


## The outline of a unit type's icon around `c`, sized to look about as big
## as a circle of radius `r`: a pentagon (infantry), square (armour) or
## triangle (air). Civilians are round - this gives a 20-sided polygon.
static func shape_points(type: UnitType, c: Vector2, r: float) -> PackedVector2Array:
	var sides := 20
	var radius := r
	var turn := -PI / 2.0  # First corner straight up.
	match type:
		UnitType.INFANTRY:
			sides = 5
			radius = r * 1.12
		UnitType.ARMOUR:
			sides = 4
			radius = r * 1.2
			turn = -PI / 4.0  # Flat top.
		UnitType.AIR:
			sides = 3
			radius = r * 1.4
			c += Vector2(0, r * 0.2)  # Balance the point on top.
	var points := PackedVector2Array()
	for i in sides:
		var a := turn + TAU * i / sides
		points.append(c + Vector2(cos(a), sin(a)) * radius)
	return points


func _draw() -> void:
	var c := _icon_offset
	var s := _icon_scale
	# Ring in the owner's colour so rival units are easy to tell apart.
	var faction_color := Faction.get_color(player.id) if player else Color.BLACK
	if flies:
		draw_aircraft(self, silhouette, c, RADIUS * s, faction_color, body_color, _heading)
	else:
		draw_icon(self, unit_type, c, RADIUS * s, faction_color, body_color, get_short_label())
	# Health bar under the icon once it has taken damage.
	if health < max_health:
		var bar := Rect2(c + Vector2(-RADIUS, RADIUS + 5.0) * s, Vector2(RADIUS * 2.0, 4.0) * s)
		draw_rect(bar, Color(0, 0, 0, 0.8))
		var fraction := clampf(float(health) / max_health, 0.0, 1.0)
		var fill := Color(0.95, 0.3, 0.25) if is_broken() else Color(0.4, 0.9, 0.35)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), fill)
