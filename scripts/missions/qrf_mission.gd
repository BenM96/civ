class_name QrfMission
extends Mission
## Quick reaction force: stands by in the hub's QRF room and sets off to
## fight any enemy unit standing on one of its colony's structures
## (extractors and conveyor belts - foundations and bridges belong to no one).
##
## QRF units don't move with everyone else. Once every other unit has
## finished moving (see Movement), each QRF unit looks at where the enemies
## ended up, heads for the nearest one standing on one of our structures, and
## moves - hoping to start a battle. It picks again every turn. When no
## enemies are left on our structures it walks back to the hub and stands by
## in the QRF room again.
##
## It's a standing duty: it never completes. It ends when the player drags
## the unit out of the QRF room (or cancels it while it's at the hub), or
## when the unit breaks in battle (it then comes home to the Med Bay).
## Needs no target tile.

## The enemy-held tile being headed for, or null (standing by, or going home).
var _chasing: Variant = null


func get_display_name() -> String:
	return "QRF"


func get_kind() -> String:
	return "qrf"


func get_description() -> String:
	return "QRF (quick reaction force)"


func get_deploying_text() -> String:
	return "Joins the QRF at the end of the turn"


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


## Routes are chosen in react(), after everyone else has moved.
func prepare() -> void:
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
## our structures, or null.
func _nearest_intruder() -> Variant:
	var map := unit.map
	var best: Variant = null
	var best_cost := 1 << 30
	for enemy in map.get_units_in_world():
		if enemy.player == unit.player:
			continue
		var tile := map.get_tile(enemy.hex)
		if tile == null or tile.structure == Structure.Type.NONE or tile.structure_owner != unit.player.id:
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
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_chasing = SaveGame.hex_from_data(data["chasing"]) if data["chasing"] != null else null
