class_name MoveToTileMission
extends Mission
## Travel to a target tile. Once there the mission is complete and the unit
## heads back to its hub.

var target: Vector2i


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Move"


func get_description() -> String:
	return "Moving to (%d, %d)" % [target.x, target.y]


func get_completion_text() -> String:
	return "reached (%d, %d)" % [target.x, target.y]


func get_target_hex() -> Variant:
	return target


func get_invalid_reason(u: Unit) -> String:
	if target == u.hex:
		return "already there"
	if not u.map.is_passable(target):
		return "impassable"
	if u.map.find_path(u.hex, target).is_empty():
		return "unreachable"
	return ""


func begin() -> void:
	if not unit.set_destination(target):
		fail("no route to (%d, %d)" % [target.x, target.y])


func process_turn() -> void:
	if not unit.has_destination() and unit.hex != target:
		# Path was lost (e.g. map changed) - try to re-plan.
		if not unit.set_destination(target):
			fail("no route to (%d, %d)" % [target.x, target.y])
			return
	unit.advance_along_path()
	if unit.hex == target:
		complete()
