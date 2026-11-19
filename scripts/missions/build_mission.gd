class_name BuildMission
extends Mission
## Travel to a tile, spend the buildable's build turns working there, then
## return home. The cost leaves the hub when the order is given and the
## builder carries it (Unit.materials); if the mission fails or is
## cancelled it's put back when the builder gets home.
##
## Buildables with build_from_adjacent (bridges) are worked on from the
## nearest reachable neighbouring tile instead of the target itself.

var target: Vector2i
var buildable: Buildable
var _turns_worked := 0
## Where the builder stands while working (chosen when the mission begins).
var _site: Variant = null


func _init(p_target: Vector2i, p_buildable: Buildable) -> void:
	target = p_target
	buildable = p_buildable


func get_display_name() -> String:
	return "Build %s" % buildable.display_name


func get_kind() -> String:
	return "build:" + buildable.id


func to_dict() -> Dictionary:
	var data := super()
	data["turns_worked"] = _turns_worked
	data["site"] = SaveGame.hex_to_data(_site) if _site != null else null
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_turns_worked = int(data["turns_worked"])
	_site = SaveGame.hex_from_data(data["site"]) if data["site"] != null else null


func get_description() -> String:
	return "Build %s at (%d, %d)" % [buildable.display_name, target.x, target.y]


func get_progress_text() -> String:
	if is_working():
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
	if _site == null:
		fail("no route to (%d, %d)" % [target.x, target.y])
		return
	super()


func work() -> void:
	# Someone else may have changed the tile while we travelled.
	var reason := buildable.get_invalid_reason(unit.map, target)
	if reason != "":
		fail(reason)
		return
	_turns_worked += 1
	if _turns_worked >= buildable.build_turns:
		unit.use_materials(buildable.cost)  # Brought from the hub. (Older saves: already spent.)
		buildable.apply(unit.map, target, unit.hub.faction)
		complete()
