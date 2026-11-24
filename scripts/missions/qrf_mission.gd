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
## Needs no target tile.

## Turns of duty when a unit is dragged into the QRF room.
const DRAG_TURNS := 20

## Turns of duty left, or Unit.REPEAT_FOREVER for no limit.
var turns_left := Unit.REPEAT_FOREVER
## The enemy-held tile being headed for, or null (standing by, or going home).
var _chasing: Variant = null
## Finished because it went off to heal (comes back afterwards).
var _off_to_heal := false


func _init(p_turns := Unit.REPEAT_FOREVER) -> void:
	turns_left = p_turns


func get_display_name() -> String:
	return "QRF"


func get_kind() -> String:
	return "qrf"


func get_description() -> String:
	return "QRF (quick reaction force)%s" % _turns_text()


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
	if unit.hex != unit.player.hex or unit.engaged:
		return  # Out chasing (or fighting): decides once home.
	if turns_left == 0:
		complete()
	elif unit.is_injured() and unit.player.get_healing_room_for(unit) != null:
		_off_to_heal = true
		unit.rejoin_kind = get_kind()
		unit.rejoin_turns = turns_left
		complete()


## Broke in battle: back on duty once home and healed.
func on_broken() -> void:
	if turns_left != 0:
		unit.rejoin_kind = get_kind()
		unit.rejoin_turns = turns_left


func get_progress_text() -> String:
	if _chasing != null:
		return "QRF: heading for the enemy at (%d, %d)" % [_chasing.x, _chasing.y]
	if unit.hex == unit.player.hex:
		return "QRF: standing by"
	return "QRF: no enemies on our structures - returning to the hub (%d turn(s) left)" % unit.estimate_turns(unit.get_remaining_path())


func get_target_hex() -> Variant:
	if _chasing != null:
		return _chasing
	return unit.player.hex if unit else null


func get_move_phase() -> MovePhase:
	return MovePhase.REACTION


func get_departure_room_id() -> String:
	return QrfRoom.ID


## On standby in the hub it can be taken off duty.
func can_cancel_at_hub() -> bool:
	return true


## Sets out on standby: nowhere to go until an enemy turns up.
func begin() -> void:
	pass



## Arriving somewhere starts no work: a QRF only fights.
func on_arrived() -> void:
	pass


## Called by Movement once every other unit has finished moving: heads for
## the nearest enemy on one of our structures, or home if there are none.
func react() -> void:
	if unit.engaged:
		return  # Already fighting: stays put this turn.
	_chasing = _nearest_intruder()
	if _chasing != null:
		unit.set_destination(_chasing)
	else:
		unit.set_destination(unit.player.hex)


## The tile of the nearest enemy unit (by walking cost) standing on one of
## our structures or next to our hub, or null.
func _nearest_intruder() -> Variant:
	var map := unit.map
	var best: Variant = null
	var best_cost := 1 << 30
	for enemy in map.get_units_in_world():
		if unit.player.is_ally(enemy.player):  # Ours, or an ally's.
			continue
		var tile := map.get_tile(enemy.hex)
		var on_ours := tile != null and tile.structure != Structure.Type.NONE and tile.structure_owner == unit.player.id
		if not on_ours and Hex.distance(enemy.hex, unit.player.hex) != 1:
			continue
		var cost := 0
		if enemy.hex != unit.hex:
			var path := map.find_path(unit.hex, enemy.hex)
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
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_chasing = SaveGame.hex_from_data(data["chasing"]) if data["chasing"] != null else null
	turns_left = int(data["turns_left"])
