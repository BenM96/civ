class_name BuildMission
extends Mission
## Travel to a tile, spend the buildable's build turns working there, then
## return home. The cost is paid by the hub when the order is given and
## refunded if the mission fails.
##
## Buildables with build_from_adjacent (bridges) are worked on from the
## nearest reachable neighbouring tile instead of the target itself.

enum Phase { TRAVELLING, BUILDING }

var target: Vector2i
var buildable: Buildable
var phase := Phase.TRAVELLING
var _turns_worked := 0
## Where the builder stands while working (chosen when the mission begins).
var _site: Variant = null


func _init(p_target: Vector2i, p_buildable: Buildable) -> void:
	target = p_target
	buildable = p_buildable


func get_display_name() -> String:
	return "Build %s" % buildable.display_name


func get_description() -> String:
	return "Build %s at (%d, %d)" % [buildable.display_name, target.x, target.y]


func get_progress_text() -> String:
	if phase == Phase.BUILDING:
		return "Building %s at (%d, %d) (%d turn(s) left)" % [
			buildable.display_name, target.x, target.y, buildable.build_turns - _turns_worked]
	return "Heading to build %s at (%d, %d) (%d turn(s) to arrive)" % [
		buildable.display_name, target.x, target.y, unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	var article := "an" if buildable.display_name.left(1) in "AEIOU" else "a"
	return "built %s %s at (%d, %d)" % [article, buildable.display_name, target.x, target.y]


func get_target_hex() -> Variant:
	return target


## Where the builder will stand. Before the unit sets off this is planned
## from the hub; afterwards it is fixed.
func get_travel_hex() -> Variant:
	if _site != null:
		return _site
	if unit:
		return find_work_site(unit.map, unit.hex)
	return target


func get_work_turns() -> int:
	return buildable.build_turns


func get_cost() -> Dictionary:
	return buildable.cost


## The tile to work from when starting at `from`, or null if none is
## reachable. For build_from_adjacent: the passable neighbour of the target
## with the cheapest route.
func find_work_site(map: HexMap, from: Vector2i) -> Variant:
	if not buildable.works_from_adjacent(map, target):
		return target if from == target or not map.find_path(from, target).is_empty() else null
	var best: Variant = null
	var best_cost := 0
	for n in Hex.neighbors(target):
		if not map.is_passable(n):
			continue
		var cost := 0
		if n != from:
			var path := map.find_path(from, n)
			if path.is_empty():
				continue
			cost = map.get_path_cost(path)
		if best == null or cost < best_cost:
			best = n
			best_cost = cost
	return best


func get_invalid_reason(u: Unit) -> String:
	var unit_reason := buildable.get_unit_reason(u)
	if unit_reason != "":
		return unit_reason
	if u.map.get_hub_at(target) != null:
		return "not on a hub"
	var reason := buildable.get_invalid_reason(u.map, target)
	if reason != "":
		return reason
	if find_work_site(u.map, u.hex) == null:
		return "unreachable"
	return ""


func begin() -> void:
	_site = find_work_site(unit.map, unit.hex)
	if _site == null or not unit.set_destination(_site):
		fail("no route to (%d, %d)" % [target.x, target.y])


func process_turn() -> void:
	match phase:
		Phase.TRAVELLING:
			if not unit.has_destination() and unit.hex != _site:
				if not unit.set_destination(_site):
					fail("no route to (%d, %d)" % [target.x, target.y])
					return
			unit.advance_along_path()
			if unit.hex == _site:
				phase = Phase.BUILDING  # Work starts next turn.
		Phase.BUILDING:
			# Someone else may have changed the tile while we travelled.
			var reason := buildable.get_invalid_reason(unit.map, target)
			if reason != "":
				fail(reason)
				return
			unit.movement_left = 0  # Building takes the whole turn.
			_turns_worked += 1
			if _turns_worked >= buildable.build_turns:
				buildable.apply(unit.map, target, unit.hub.faction)
				complete()
