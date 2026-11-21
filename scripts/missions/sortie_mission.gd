class_name SortieMission
extends Mission
## An air unit's only mission: fly to any tile (except a hub), whatever lies
## between, and fight whoever is there.
##
## The unit leaves the hub at the end of the turn like anyone else, but
## doesn't walk. In the movement phase it waits until every other unit -
## QRF included - has moved, then jumps straight to the target (see
## Movement), where it starts or joins battles like anyone else. At the
## start of the next turn it flies straight home (Unit.fly_to()), and then
## refits in the Hangar (see AirUnit, QuartersRoom).
##
## If it breaks in battle it flies home at the start of the next turn too.

var target: Vector2i


func _init(p_target: Vector2i) -> void:
	target = p_target


func get_display_name() -> String:
	return "Sortie"


func get_kind() -> String:
	return "sortie"


func get_description() -> String:
	return "Sortie to (%d, %d)" % [target.x, target.y]


func get_progress_text() -> String:
	if is_working():
		return "Over (%d, %d) - flies home next turn" % [target.x, target.y]
	return "Flying to (%d, %d) once everyone else has moved" % [target.x, target.y]


func get_completion_text() -> String:
	return "flew a sortie to (%d, %d)" % [target.x, target.y]


func get_target_hex() -> Variant:
	return target


func get_move_phase() -> MovePhase:
	return MovePhase.AIR


func get_invalid_reason(u: Unit) -> String:
	if not u.flies:
		return "%s can't fly" % u.display_name
	if not u.map.has_tile(target):
		return "off the map"
	if u.map.get_player_at(target) != null:
		return "can't fly a sortie onto a hub"
	return ""


## Leaves the hub, but flies only in the air phase (see fly()).
func begin() -> void:
	pass


## The turn after it flew out: the sortie is over, and it heads home.
func prepare() -> void:
	if is_working():
		complete()


## Called by Movement once every other unit has moved.
func fly() -> void:
	if phase != Phase.TRAVELLING or unit.engaged:
		return
	unit.fly_to(target)
	on_arrived()


## Being there is the job: nothing to do in the work step.
func work() -> void:
	pass
