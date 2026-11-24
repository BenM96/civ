class_name QrfMission
extends Mission
## Quick reaction force: stands by in the hub's QRF room and sets off to
## fight any enemy unit standing on one of its colony's structures
## (extractors and conveyor belts - foundations and bridges belong to no one)
## or right next to its hub (where Infantry demolish it).
##
## QRF units don't move with everyone else. Once every other unit has
## finished moving (see Movement), each QRF unit looks at where the enemies
## ended up, heads for the nearest one standing on one of our structures, and
## moves - hoping to start a battle. It picks again every turn. When no
## enemies are left on our structures it walks back to the hub and stands by
## in the QRF room again.
##
## It's on duty for a set number of turns (turns_left - the number picked in
## Mission Briefing, DRAG_TURNS when dragged into the QRF room, or no limit),
## counted down every turn. When they run out the unit goes to Mission
## Briefing - straight away if it's standing by, otherwise once it's back
## (it doesn't break off a chase early). The player can also drag it out of
## the QRF room (or cancel it while it's at the hub).
## Hurt: standing by at the hub, a hurt unit goes off to be healed (Med Bay
## or Garage) and comes back on duty once healed, with the turns it had left
## (Unit.rejoin_kind; the count pauses meanwhile). One that breaks in battle
## does the same once it's home.
## Needs no target tile - unless the colony has an FOB linked to its hub by
## belts (see FobBuildable): then the player picks the hub or one of those
## FOBs as its base. Based at an FOB, the unit walks there and stands by on
## it instead of in the QRF room, sets off from there, and comes back there
## (enemies next to the FOB count as intruders too). If the FOB is lost or
## cut off from the hub, the unit is based at the hub again and heads home.
## Hurt or broken, it goes home to heal and comes back to the same FOB.

## Turns of duty when a unit is dragged into the QRF room.
const DRAG_TURNS := 20

## Turns of duty left, or Unit.REPEAT_FOREVER for no limit.
var turns_left := Unit.REPEAT_FOREVER
## The enemy-held tile being headed for, or null (standing by, or going home).
var _chasing: Variant = null
## Finished because it went off to heal (comes back afterwards).
var _off_to_heal := false
## The FOB it's based at, or null for the hub (see base_hex()).
var base: Variant = null


func _init(p_turns := Unit.REPEAT_FOREVER, p_base: Variant = null) -> void:
	turns_left = p_turns
	base = p_base


## Where it stands by: its FOB, or the hub.
func base_hex() -> Vector2i:
	return base if base != null else unit.player.hex


## Whether `h` can be a QRF base for `player`: the hub, or one of its FOBs
## linked to the hub by belts.
static func is_valid_base(player: Player, h: Vector2i) -> bool:
	return h == player.hex or h in player.get_fob_bases()


func get_invalid_reason(u: Unit) -> String:
	if base != null and not is_valid_base(u.player, base):
		return "pick your hub or one of your FOBs linked to it by belts"
	return ""


func get_display_name() -> String:
	return "QRF"


func get_kind() -> String:
	return "qrf"


func get_description() -> String:
	var at := " at the FOB at (%d, %d)" % [base.x, base.y] if base != null else ""
	return "QRF (quick reaction force)%s%s" % [at, _turns_text()]


## E.g. " for 12 more turns", or "" with no limit.
func _turns_text() -> String:
	if turns_left == Unit.REPEAT_FOREVER:
		return ""
	if turns_left <= 0:
		return " (duty over)"
	return " for %d more turn%s" % [turns_left, "" if turns_left == 1 else "s"]


func get_deploying_text() -> String:
	return "Joins the QRF at the end of the turn"


func get_completion_text() -> String:
	if _off_to_heal:
		return "left the QRF to be healed (back on duty afterwards)"
	return "finished QRF duty"


## Each turn: counts down the duty, and at the hub ends it if it's over, or
## goes off to heal if hurt (see the class description).
func prepare() -> void:
	if turns_left > 0:
		turns_left -= 1
	if base != null and not is_valid_base(unit.player, base):
		unit.player.unit_event.emit("%s: the FOB at (%d, %d) is gone or cut off - back to QRF duty at the hub" % [
			unit.display_name, base.x, base.y])
		base = null
	if unit.hex != base_hex() or unit.engaged:
		return  # Out chasing (or fighting, or on the way to its base): decides once there.
	if turns_left == 0:
		complete()
	elif unit.is_injured() and unit.player.get_healing_room_for(unit) != null:
		_off_to_heal = true
		_leave_to_heal()
		complete()


## Broke in battle: back on duty once home and healed.
func on_broken() -> void:
	if turns_left != 0:
		_leave_to_heal()


## Remembers the duty, so the unit takes it up again once healed.
func _leave_to_heal() -> void:
	unit.rejoin_kind = get_kind()
	unit.rejoin_turns = turns_left
	unit.rejoin_base = base


func get_progress_text() -> String:
	if _chasing != null:
		return "QRF: heading for the enemy at (%d, %d)" % [_chasing.x, _chasing.y]
	if unit.hex == base_hex():
		return "QRF: standing by" + (" at the FOB" if base != null else "")
	return "QRF: no enemies on our structures - returning to %s (%d turn(s) left)" % [
		"the FOB" if base != null else "the hub", unit.estimate_turns(unit.get_remaining_path())]


func get_target_hex() -> Variant:
	if _chasing != null:
		return _chasing
	return base_hex() if unit else null


func get_move_phase() -> MovePhase:
	return MovePhase.REACTION


func get_departure_room_id() -> String:
	return QrfRoom.ID


## On standby in the hub it can be taken off duty (based at an FOB, it
## can be recalled from the Field panel instead).
func can_cancel_at_hub() -> bool:
	return true


## Sets out on standby: nowhere to go until an enemy turns up.
func begin() -> void:
	pass



## Arriving somewhere starts no work: a QRF only fights.
func on_arrived() -> void:
	pass


## Called by Movement once every other unit has finished moving: heads for
## the nearest enemy on one of our structures, or back to its base (the hub
## or its FOB) if there are none.
func react() -> void:
	if unit.engaged:
		return  # Already fighting: stays put this turn.
	_chasing = _nearest_intruder()
	if _chasing != null:
		unit.set_destination(_chasing)
	else:
		unit.set_destination(base_hex())


## The tile of the nearest enemy unit (by walking cost) standing on one of
## our structures or next to our hub or this unit's FOB, or null.
func _nearest_intruder() -> Variant:
	var map := unit.map
	var best: Variant = null
	var best_cost := 1 << 30
	for enemy in map.get_units_in_world():
		if unit.player.is_ally(enemy.player):  # Ours, or an ally's.
			continue
		var tile := map.get_tile(enemy.hex)
		var on_ours := tile != null and tile.structure != Structure.Type.NONE and tile.structure_owner == unit.player.id
		var near_base := Hex.distance(enemy.hex, unit.player.hex) == 1 or (base != null and Hex.distance(enemy.hex, base) <= 1)
		if not on_ours and not near_base:
			continue
		var cost := 0
		if enemy.hex != unit.hex:
			var path := map.find_path(unit.hex, enemy.hex, unit.player.id)
			if path.is_empty():
				continue
			cost = map.get_path_cost(path)
		# Ties go to the lowest hex, so every computer picks the same.
		if cost < best_cost or (cost == best_cost and _hex_less(enemy.hex, best)):
			best = enemy.hex
			best_cost = cost
	return best


static func _hex_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


func to_dict() -> Dictionary:
	var data := super()
	data["chasing"] = SaveGame.hex_to_data(_chasing) if _chasing != null else null
	data["turns_left"] = turns_left
	data["base"] = SaveGame.hex_to_data(base) if base != null else null
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_chasing = SaveGame.hex_from_data(data["chasing"]) if data["chasing"] != null else null
	turns_left = int(data["turns_left"])
	base = SaveGame.hex_from_data(data["base"]) if data.get("base") != null else null
