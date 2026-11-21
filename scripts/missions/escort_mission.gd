class_name EscortMission
extends Mission
## Follow another unit of our colony (the "escortee") wherever it goes, so a
## fighter can guard a worker. The escortee must be at the hub when the order
## is given - either still waiting for orders or about to set out.
##
## Each turn the escort heads for wherever the escortee is going this turn
## (the end of its path, or where it stands). Escorts set out after every
## other unit (see sets_out_last()), so they see the escortee's fresh route;
## with the same speed and the same start they walk in step, tile by tile,
## and fight alongside it. While the escortee is still at home the escort
## waits at the hub (and can be called off).
##
## Done when the escortee is back at the hub after its trip (the escort comes
## home with it). Fails if the escortee is lost.
##
## Kind: "escort:<unit id>". The target hex is ignored (it's saved as where
## the escort is heading).

var escortee_id: int
## Where we're heading this turn: the escortee's destination.
var _destination: Vector2i
## The escortee has left the hub at least once (so being home means done).
var _escortee_left := false
## For messages once it's gone.
var _escortee_name := ""


func _init(p_escortee_id: int) -> void:
	escortee_id = p_escortee_id


func get_display_name() -> String:
	return "Escort"


func get_kind() -> String:
	return "escort:%d" % escortee_id


func _escortee() -> Unit:
	return unit.player.get_unit(escortee_id) if unit else null


func _who() -> String:
	var e := _escortee()
	if e:
		_escortee_name = e.display_name
	return _escortee_name if _escortee_name != "" else "unit %d" % escortee_id


func get_description() -> String:
	return "Escort %s" % _who()


func get_progress_text() -> String:
	if not _escortee_left:
		return "Waiting at the hub to escort %s when it sets out" % _who()
	var e := _escortee()
	if is_working() or (e and e.hex == unit.hex):
		return "Escorting %s" % _who()
	return "Heading to escort %s (%d turn(s) to catch up)" % [_who(), unit.estimate_turns(unit.get_remaining_path())]


func get_completion_text() -> String:
	return "escorted %s back to the hub" % _who()


func get_target_hex() -> Variant:
	return _destination


func get_invalid_reason(u: Unit) -> String:
	var e := u.player.get_unit(escortee_id)
	if e == null:
		return "no such unit to escort"
	if e == u:
		return "can't escort itself"
	if e.state != Unit.State.IN_HUB and e.state != Unit.State.DEPLOYING:
		return "%s has already left the hub" % e.display_name
	if e.mission is EscortMission:
		return "can't escort an escort"
	if e.flies:
		return "can't escort an aircraft"
	if e.mission and e.mission.get_move_phase() != MovePhase.NORMAL:
		return "can't escort a unit on QRF duty"
	return ""


## Sets out after the colony's other units, so the escortee has planned its
## route this turn before we copy it.
func sets_out_last() -> bool:
	return true


## Whenever the escort is back at the hub (waiting for the escortee to set
## out, or there with it between jobs) it can be called off.
func can_cancel_at_hub() -> bool:
	return true


func begin() -> void:
	_destination = unit.player.hex
	_follow()


func prepare() -> void:
	_follow()


## Heads for wherever the escortee is going this turn.
func _follow() -> void:
	var e := _escortee()
	if e == null:
		fail("%s was lost" % _who())
		return
	_who()  # Remember its name in case it's lost later.
	if e.is_in_world():
		_escortee_left = true
	elif _escortee_left:
		complete()  # Back home (or already off again on a new order): trip over.
		return
	var path := e.get_remaining_path()
	_destination = path.back() if e.is_in_world() and not path.is_empty() else e.hex
	if unit.hex == _destination:
		unit.set_destination(unit.hex)  # Stop here.
		phase = Phase.WORKING
	else:
		phase = Phase.TRAVELLING
		unit.set_destination(_destination)  # If unreachable, try again next turn.


func on_arrived() -> void:
	phase = Phase.WORKING


## Escorting is just staying with the escortee; it never finishes by working.
func work() -> void:
	pass


func to_dict() -> Dictionary:
	var data := super()
	data["escortee_left"] = _escortee_left
	data["escortee_name"] = _escortee_name
	return data


func load_dict(data: Dictionary) -> void:
	super(data)
	_destination = SaveGame.hex_from_data(data["target"])
	_escortee_left = bool(data.get("escortee_left", false))
	_escortee_name = str(data.get("escortee_name", ""))
