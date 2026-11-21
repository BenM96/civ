class_name QrfRoom
extends Room
## The quick reaction force's standby room. Units come here by being given
## the QRF mission (see QrfMission) and wait here between call-outs; dragging
## one out takes it off QRF duty.

const ID := "qrf"


func _init() -> void:
	id = ID
	display_name = "Quick Reaction Force"
	description = "Units on QRF duty stand by here. After everyone else has moved each turn, they head for the nearest enemy standing on one of your extractors or belts, and come back here once none are left.\nGive a unit the QRF mission in Mission Briefing to send it here; drag it out to take it off QRF duty."


func get_refusal(_unit: Unit) -> String:
	return "give a unit the QRF mission in Mission Briefing to put it on QRF duty"
