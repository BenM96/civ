class_name SortieMission
extends Mission
## An air unit flies to any tile (except a hub), whatever lies between, and
## fights whoever is there.
##
## The unit leaves the hub at the end of the turn like anyone else, but
## doesn't walk. Before anyone on the ground moves, it jumps straight to
## the target (see Movement) - so it catches whoever is there at the start
## of the turn, and they stay to fight - and starts or joins battles like
## anyone else (enemies who walk onto it that turn join in). After combat, in
## the air return phase of the same turn, it flies home (see
## Unit.return_from_air()) and refits in the Hangar (see AirUnit).

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
	return "Over (%d, %d) - flies home at the end of the turn" % [target.x, target.y]


func get_deploying_text() -> String:
	return "Flies a sortie to (%d, %d) at the end of the turn, before anyone on the ground moves" % [target.x, target.y]


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


func prepare() -> void:
	pass


## Called by Movement before anyone on the ground moves.
func fly() -> void:
	if phase != Phase.TRAVELLING or unit.engaged:
		return
	unit.fly_to(target)
	on_arrived()


## Being there is the job: nothing to do in the work step.
func work() -> void:
	pass
