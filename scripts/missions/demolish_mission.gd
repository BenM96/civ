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


func get_description() -> String:
	return "Demolish %s at (%d, %d)" % [_what if _what != "" else "structures", target.x, target.y]


func get_progress_text() -> String:
	if phase == Phase.BUILDING:
		return "Demolishing %s at (%d, %d)" % [_what, target.x, target.y]
	return "Heading to demolish %s at (%d, %d) (%d turn(s) to arrive)" % [
		_what, target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	if unit and unit.map.get_tile(target).terrain == Terrain.Type.CHASM:
		return "brought down the %s at (%d, %d) - it fell into the chasm" % [_what, target.x, target.y]
	return "reduced the %s at (%d, %d) to rubble" % [_what, target.x, target.y]


func get_invalid_reason(u: Unit) -> String:
	var tile := u.map.get_tile(target)
	if tile:
		_what = DemolitionBuildable.describe(tile)
	return super(u)
