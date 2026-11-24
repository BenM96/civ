class_name CaptureMission
extends Mission
## Travel to another colony's structure (extractor or conveyor belt), spend
## CAPTURE_TURNS turns on it, and it becomes ours. Supply networks update by
## themselves: a captured extractor feeds our hub if our belts reach it, and
## stops feeding theirs. Foundations and bridges belong to nobody, and hubs can't
## be captured.

## Turns spent on the structure, once there, to take it over.
const CAPTURE_TURNS := 3

var target: Vector2i
var _turns_worked := 0
## What we went to capture, for messages (e.g. "Pink colony's Extractor").
var _what := ""


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Capture"


func get_kind() -> String:
	return "capture"


func get_description() -> String:
	return "Capture %s at (%d, %d)" % [_what if _what != "" else "structure", target.x, target.y]


func get_progress_text() -> String:
	if is_working():
		return "Capturing %s at (%d, %d) (%d turn(s) left)" % [
			_what, target.x, target.y, CAPTURE_TURNS - _turns_worked]
	return "Heading to capture %s at (%d, %d) (%d turn(s) to arrive)" % [
		_what, target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	return "captured %s at (%d, %d)" % [_what, target.x, target.y]


func get_target_hex() -> Variant:
	return target


func get_work_turns() -> int:
	return CAPTURE_TURNS


func get_invalid_reason(u: Unit) -> String:
	var reason := _get_target_invalid_reason(u.map, u.player.id)
	if reason != "":
		return reason
	if u.map.find_path(u.hex, target).is_empty():
		return "unreachable"
	return ""


func work() -> void:
	# It may have been demolished, or captured by someone else, on the way.
	var reason := _get_target_invalid_reason(unit.map, unit.player.id)
	if reason != "":
		fail(reason)
		return
	_turns_worked += 1
	if _turns_worked >= CAPTURE_TURNS:
		var tile := unit.map.get_tile(target)
		unit.map.set_structure(target, tile.structure, unit.player.id)
		complete()


## Why the target isn't something `faction` could capture, or "" if it is.
## Also remembers what's there, for messages.
func _get_target_invalid_reason(map: HexMap, faction: int) -> String:
	var tile := map.get_tile(target)
	if tile == null or tile.structure == Structure.Type.NONE:
		return "nothing to capture there"
	if tile.structure_owner == faction:
		return "it's already ours"
	if map.are_allied(tile.structure_owner, faction):
		return "it belongs to an ally"
	_what = "%s's %s" % [Faction.get_display_name(tile.structure_owner),
		Structure.get_display_name(tile.structure)]
	return ""


func to_dict() -> Dictionary:
	var data := super()
	data["turns_worked"] = _turns_worked
	data["what"] = _what
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_turns_worked = int(data["turns_worked"])
	_what = data["what"]
