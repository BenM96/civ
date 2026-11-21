class_name GuardMission
extends Mission
## Travel to a tile and hold it for GUARD_TURNS turns, then return home.
##
## Guarding is just standing there: while on the tile, a fighting unit starts
## a battle with any enemy that walks onto it or tries to slip past it
## (see Movement and Combat).

## Turns spent holding the tile once there.
const GUARD_TURNS := 20

var target: Vector2i
var _turns_guarded := 0


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Guard"


func get_kind() -> String:
	return "guard"


func get_description() -> String:
	return "Guard (%d, %d) for %d turns" % [target.x, target.y, GUARD_TURNS]


func get_progress_text() -> String:
	if is_working():
		return "Guarding (%d, %d) (%d turn(s) left)" % [target.x, target.y, GUARD_TURNS - _turns_guarded]
	return "Heading to guard (%d, %d) (%d turn(s) to arrive)" % [
		target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	return "guarded (%d, %d) for %d turns" % [target.x, target.y, GUARD_TURNS]


func get_target_hex() -> Variant:
	return target


func get_work_turns() -> int:
	return GUARD_TURNS


func get_invalid_reason(u: Unit) -> String:
	if target == u.hex:
		return "already there"
	if not u.map.is_passable(target):
		return "impassable"
	if u.map.get_player_at(target) != null:
		return "not on a hub"
	if u.map.find_path(u.hex, target).is_empty():
		return "unreachable"
	return ""


## One turn of standing guard (only counts on turns the unit didn't move).
func work() -> void:
	_turns_guarded += 1
	if _turns_guarded >= GUARD_TURNS:
		complete()


func to_dict() -> Dictionary:
	var data := super()
	data["turns_guarded"] = _turns_guarded
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_turns_guarded = int(data["turns_guarded"])
