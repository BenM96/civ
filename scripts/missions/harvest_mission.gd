class_name HarvestMission
extends Mission
## Travel to a resource deposit, spend a full turn extracting from it, then
## carry the haul back to the hub (the unit's normal return trip).

enum Phase { TRAVELLING, EXTRACTING }

## How much one trip extracts.
const HARVEST_AMOUNT := 1
## Turns spent extracting once on the deposit.
const EXTRACT_TURNS := 1

var target: Vector2i
var phase := Phase.TRAVELLING
var _turns_extracting := 0
var _resource_name := "resource"
var _harvested := 0


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Harvest"


func get_description() -> String:
	var deposit := _deposit()
	if deposit:
		_resource_name = deposit.get_display_name()
	return "Harvest %s at (%d, %d)" % [_resource_name, target.x, target.y]


func get_progress_text() -> String:
	if phase == Phase.EXTRACTING:
		return "Extracting %s at (%d, %d)" % [_resource_name, target.x, target.y]
	return "Heading to %s at (%d, %d) (%d turn(s) to arrive)" % [
		_resource_name, target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	return "extracted %d %s" % [_harvested, _resource_name]


func get_target_hex() -> Variant:
	return target


func get_work_turns() -> int:
	return EXTRACT_TURNS


func get_invalid_reason(u: Unit) -> String:
	if not u.can_harvest:
		return "%s can't harvest" % u.unit_name
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
	if _deposit() == null:
		fail("the %s deposit is gone" % _resource_name)
	elif not unit.set_destination(target):
		fail("no route to (%d, %d)" % [target.x, target.y])


func process_turn() -> void:
	var deposit := _deposit()
	if deposit == null:
		fail("the %s deposit at (%d, %d) was used up" % [_resource_name, target.x, target.y])
		return
	_resource_name = deposit.get_display_name()

	match phase:
		Phase.TRAVELLING:
			if not unit.has_destination() and unit.hex != target:
				if not unit.set_destination(target):
					fail("no route to (%d, %d)" % [target.x, target.y])
					return
			unit.advance_along_path()
			if unit.hex == target:
				phase = Phase.EXTRACTING  # Extraction starts next turn.
		Phase.EXTRACTING:
			# Extracting takes the unit's whole turn.
			unit.movement_left = 0
			_turns_extracting += 1
			if _turns_extracting >= EXTRACT_TURNS:
				_harvested = deposit.extract(HARVEST_AMOUNT)
				unit.add_cargo(deposit.type, _harvested)
				unit.map.queue_redraw()  # Deposit may now be depleted.
				complete()


## The live deposit on the target tile, or null if missing/depleted.
func _deposit() -> ResourceDeposit:
	if unit == null or unit.map == null:
		return null
	var tile := unit.map.get_tile(target)
	if tile == null or not tile.has_deposit():
		return null
	return tile.deposit
