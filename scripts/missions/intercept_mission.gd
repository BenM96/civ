class_name InterceptMission
extends QrfMission
## The air force's quick reaction force: an aircraft stands by in the Hangar
## and, when enemy aircraft come into our territory (onto one of our
## structures, or on or next to our hub), flies straight at them in the same turn.
##
## Interceptors move straight after the sorties, before anyone on the
## ground (see Movement): each
## colony looks at the enemy aircraft in its territory, nearest its hub
## first, and sends standby interceptors to each until it has 2 aircraft
## there for every enemy one (counting any of ours already there), then
## moves on to the next (see Movement._plan_intercepts()). They fight like
## anyone else, and in the air return phase fly home, refit in the Hangar
## (which repairs them), and go straight back on duty (Unit.rejoin_kind) -
## unless their turns of duty have run out.
##
## Turns of duty work as for the QRF (see QrfMission): the number picked in
## Mission Briefing, or no limit; dragging it out of the Hangar takes it off
## duty. Needs no target tile.

## Set when it's been called out this turn (for messages).
var _launched := false


func get_display_name() -> String:
	return "Intercept"


func get_kind() -> String:
	return "intercept"


func get_description() -> String:
	return "Intercept enemy aircraft%s" % _turns_text()


func get_deploying_text() -> String:
	return "Goes on intercept standby in the Hangar at the end of the turn"


func get_completion_text() -> String:
	if _launched:
		var back := ", then refits and goes back on duty" if unit and unit.rejoin_kind == get_kind() else ", then refits"
		return "intercepted enemy aircraft at (%d, %d)%s" % [_chasing.x, _chasing.y, back]
	return "finished intercept duty"


func get_progress_text() -> String:
	if _chasing != null and unit.hex != unit.player.hex:
		return "Intercepting enemy aircraft at (%d, %d) - flies home at the end of the turn" % [_chasing.x, _chasing.y]
	return "Intercept: standing by in the Hangar"


func get_move_phase() -> MovePhase:
	return MovePhase.INTERCEPT


func get_departure_room_id() -> String:
	return HangarRoom.ID


func get_invalid_reason(u: Unit) -> String:
	if not u.flies:
		return "%s can't fly" % u.display_name
	return ""


## Ready to be called out this turn: on standby at the hub, not fighting.
func is_standing_by() -> bool:
	return unit.hex == unit.player.hex and not unit.engaged


## Called out by Movement: flies straight at the enemy aircraft at `h`.
func launch(h: Vector2i) -> void:
	_chasing = h
	_launched = true
	unit.fly_to(h)


## Interceptors are sent by Movement, not by themselves.
func react() -> void:
	pass


## Back from a call-out: home to refit, then on duty again (if any turns
## are left).
func air_return() -> void:
	if turns_left != 0:
		unit.rejoin_kind = get_kind()
		unit.rejoin_turns = turns_left
	complete()


## Broke in battle: back on duty once home and refitted.
func on_broken() -> void:
	if turns_left != 0:
		unit.rejoin_kind = get_kind()
		unit.rejoin_turns = turns_left
