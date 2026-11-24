class_name CarpetBombMission
extends Mission
## The Bomber's mission: fly to a tile and flatten everything man-made on it
## (foundations, bridges, extractors, conveyors, command points - leaving
## Rubble, or the Chasm for a bridge), or knock 1 off an enemy hub's health
## (see DemolitionBuildable, the same as Infantry demolishing - but in one
## turn, and straight onto the tile).
##
## Flies like a sortie (see SortieMission): out before anyone on the ground
## moves, fights anyone there, and in the air return phase of the same turn
## - if it's still on the mission (didn't die or break) - drops its bombs
## (air_return()) and flies home to refit.

var target: Vector2i
## What was on the tile when the order was given, for messages.
var _what := ""


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Carpet Bomb"


func get_kind() -> String:
	return "carpet_bomb"


func get_description() -> String:
	return "Carpet bomb %s at (%d, %d)" % [_what if _what != "" else "structures", target.x, target.y]


func get_progress_text() -> String:
	return "Over (%d, %d) - bombs and flies home at the end of the turn" % [target.x, target.y]


func get_deploying_text() -> String:
	return "Flies out to bomb %s at (%d, %d) at the end of the turn" % [_what, target.x, target.y]


func get_completion_text() -> String:
	var hub := unit.map.get_player_at(target) if unit else null
	if hub:
		return "bombed %s (%d/%d health left)" % [_what, hub.hub_health, Player.HUB_MAX_HEALTH]
	return "carpet bombed the %s at (%d, %d)" % [_what, target.x, target.y]


func get_target_hex() -> Variant:
	return target


func get_move_phase() -> MovePhase:
	return MovePhase.AIR


func get_invalid_reason(u: Unit) -> String:
	if not u.flies:
		return "%s can't fly" % u.display_name
	if not u.map.has_tile(target):
		return "off the map"
	var hub := u.map.get_player_at(target)
	if hub:
		if u.player.is_ally(hub):
			return "can't bomb our own hub" if hub == u.player else "can't bomb an ally's hub"
		_what = "the %s's %s" % [Faction.get_display_name(hub.id).to_lower(), Player.HUB_NAME]
	else:
		var tile := u.map.get_tile(target)
		_what = DemolitionBuildable.describe(tile)
		if tile.structure_owner != u.player.id and u.map.are_allied(tile.structure_owner, u.player.id):
			return "that belongs to an ally"
	return DemolitionBuildable.new().get_invalid_reason(u.map, target)


## Leaves the hub, but flies only in the air phase (see fly()).
func begin() -> void:
	pass


func prepare() -> void:
	pass


func fly() -> void:
	if phase != Phase.TRAVELLING or unit.engaged:
		return
	unit.fly_to(target)
	on_arrived()


func work() -> void:
	pass


## Bombs away (if there's still something to hit), then home.
func air_return() -> void:
	if unit.hex != target:
		fail("never reached (%d, %d)" % [target.x, target.y])
		return
	var reason := DemolitionBuildable.new().get_invalid_reason(unit.map, target)
	if reason != "":
		fail(reason)
		return
	# On the map the tile changes once the Bomber turns for home, after its
	# flight there and the battle have been shown.
	unit.map.show_as_before(target)
	unit.reveal_when_leaving(target)
	DemolitionBuildable.new().apply(unit.map, target, unit.player.id)
	complete()


func to_dict() -> Dictionary:
	var data := super()
	data["what"] = _what
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_what = data["what"]
