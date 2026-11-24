class_name QrfRoom
extends Room
## The quick reaction force's standby room. Units come here by being given
## the QRF mission (see QrfMission) - in Mission Briefing, or by dragging
## them in here - and wait here between call-outs; dragging one out takes it
## off QRF duty.

const ID := "qrf"


func _init() -> void:
	id = ID
	display_name = "Quick Reaction Force"
	description = "Units on QRF duty stand by here. After everyone else has moved each turn, they head for the nearest enemy standing on one of your extractors or belts, and come back here once none are left.\nDrag a unit in to put it on QRF duty for %d turns (or give it the QRF mission in Mission Briefing to pick how long); drag it out to take it off. Units on Regroup wait here too." % QrfMission.DRAG_TURNS


func get_refusal(unit: Unit) -> String:
	if not unit.can_take("qrf"):
		return "%s can't do QRF duty" % unit.display_name
	return ""
