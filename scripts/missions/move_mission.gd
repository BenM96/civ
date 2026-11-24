class_name MoveMission
extends Mission
## Travel to a target tile. Once there the mission is complete and the unit
## heads back to its hub.

var target: Vector2i


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Move"


func get_kind() -> String:
	return "move"


func get_description() -> String:
	return "Move to (%d, %d)" % [target.x, target.y]


func get_progress_text() -> String:
	return "Heading to (%d, %d) (%d turn(s) to arrive)" % [
		target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	return "moved to (%d, %d)" % [target.x, target.y]


func get_target_hex() -> Variant:
	return target


func get_invalid_reason(u: Unit) -> String:
	if target == u.hex:
		return "already there"
	if not u.map.is_passable(target):
		return "impassable"
	if u.map.find_path(u.hex, target, u.player.id).is_empty():
		return "unreachable"
	return ""


## Nothing to do once there: done the moment it arrives, so the unit uses
## any movement it has left to start heading home.
func on_arrived() -> void:
	complete()
