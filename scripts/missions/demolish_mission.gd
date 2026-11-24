class_name DemolishMission
extends BuildMission
## Travel to a tile (or, for a bridge or an enemy hub, a tile beside it),
## spend DemolitionBuildable's build turns (3) tearing down everything
## man-made on it (leaving Rubble, or the Chasm for a bridge), then return
## home. On an enemy hub it knocks 1 off the hub's health instead (see
## Player.damage_hub()). Free; Infantry only.

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
	var hub := unit.map.get_player_at(target) if unit else null
	if hub:
		return "damaged %s (%d/%d health left)" % [_what, hub.hub_health, Player.HUB_MAX_HEALTH]
	return "demolished the %s at (%d, %d)" % [_what, target.x, target.y]


func get_invalid_reason(u: Unit) -> String:
	var hub := u.map.get_player_at(target)
	if hub:
		if u.player.is_ally(hub):
			return "can't demolish our own hub" if hub == u.player else "can't demolish an ally's hub"
		_what = "the %s's %s" % [Faction.get_display_name(hub.id).to_lower(), Player.HUB_NAME]
		var reason := buildable.get_invalid_reason(u.map, target)
		if reason != "":
			return reason
		return "" if find_work_site(u.map, u.hex, u.player.id) != null else "unreachable"
	var tile := u.map.get_tile(target)
	if tile:
		_what = DemolitionBuildable.describe(tile)
		if tile.structure_owner != u.player.id and u.map.are_allied(tile.structure_owner, u.player.id):
			return "that belongs to an ally"
	return super(u)
