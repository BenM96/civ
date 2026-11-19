class_name HarvestMission
extends Mission
## Travel to a resource deposit, spend a full turn extracting from it, then
## carry the haul back to the hub (the unit's normal return trip). How much
## one trip brings back is the resource's harvest_amount (see
## scripts/resources/).

## Turns spent extracting once on the deposit.
const EXTRACT_TURNS := 1

var target: Vector2i
var _turns_extracting := 0
var _resource_name := "resource"
var _harvested := 0


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Harvest"


func get_kind() -> String:
	return "harvest"


func to_dict() -> Dictionary:
	var data := super()
	data["turns_extracting"] = _turns_extracting
	data["resource_name"] = _resource_name
	data["harvested"] = _harvested
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_turns_extracting = int(data["turns_extracting"])
	_resource_name = data["resource_name"]
	_harvested = int(data["harvested"])


func get_description() -> String:
	var deposit := _deposit()
	if deposit:
		_resource_name = deposit.get_display_name()
	return "Harvest %s at (%d, %d)" % [_resource_name, target.x, target.y]


func get_progress_text() -> String:
	if is_working():
		return "Harvesting %s at (%d, %d) (%d turn(s) left)" % [
			_resource_name, target.x, target.y, EXTRACT_TURNS - _turns_extracting]
	return "Heading to harvest %s at (%d, %d) (%d turn(s) to arrive)" % [
		_resource_name, target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	return "harvested %d %s at (%d, %d)" % [_harvested, _resource_name, target.x, target.y]


func get_target_hex() -> Variant:
	return target


func get_work_turns() -> int:
	return EXTRACT_TURNS


func get_invalid_reason(u: Unit) -> String:
	if target == u.hex:
		return "already there"
	var tile := u.map.get_tile(target)
	if tile == null or not tile.is_passable():
		return "impassable"
	if not tile.has_deposit():
		return "no deposit here"
	if u.map.find_path(u.hex, target).is_empty():
		return "unreachable"
	return ""


func begin() -> void:
	if _check_deposit():
		super()


func prepare() -> void:
	if _check_deposit():
		super()


func work() -> void:
	# Another harvester or extractor may have emptied it this turn.
	if not _check_deposit():
		return
	_turns_extracting += 1
	if _turns_extracting >= EXTRACT_TURNS:
		var deposit := _deposit()
		_harvested = deposit.extract(ResourceDeposit.get_info(deposit.type).harvest_amount)
		unit.add_cargo(deposit.type, _harvested)
		unit.map.queue_redraw()  # Deposit may now be depleted.
		complete()


## Fails the mission if the deposit has gone. Returns whether it's still there.
func _check_deposit() -> bool:
	var deposit := _deposit()
	if deposit == null:
		fail("the %s deposit at (%d, %d) was used up" % [_resource_name, target.x, target.y])
		return false
	_resource_name = deposit.get_display_name()
	return true


## The live deposit on the target tile, or null if missing/depleted.
func _deposit() -> ResourceDeposit:
	if unit == null or unit.map == null:
		return null
	var tile := unit.map.get_tile(target)
	if tile == null or not tile.has_deposit():
		return null
	return tile.deposit
