class_name DemolishMission
extends BuildMission
## Travel to a tile (or, for a bridge, the bank beside it), spend a turn
## tearing down everything man-made on it (leaving Rubble, or the Chasm for a
## bridge), then return home. Free; Infantry only.

## What was on the tile when the order was given, for messages.
var _what := ""


func _init(p_target: Vector2i) -> void:
	super(p_target, DemolitionBuildable.new())


func get_display_name() -> String:
	return "Demolish"


func get_kind() -> String:
	return "demolish"


func to_dict() -> Dictionary:
	var data := super()
	data["what"] = _what
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_what = data["what"]


func get_description() -> String:
	return "Demolish %s at (%d, %d)" % [_what if _what != "" else "structures", target.x, target.y]


func get_progress_text() -> String:
	if is_working():
		return "Demolishing %s at (%d, %d) (%d turn(s) left)" % [
			_what, target.x, target.y, buildable.build_turns - _turns_worked]
	return "Heading to demolish %s at (%d, %d) (%d turn(s) to arrive)" % [
		_what, target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	return "demolished the %s at (%d, %d)" % [_what, target.x, target.y]


func get_invalid_reason(u: Unit) -> String:
	var tile := u.map.get_tile(target)
	if tile:
		_what = DemolitionBuildable.describe(tile)
	return super(u)
