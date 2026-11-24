class_name RegroupMission
extends QrfMission
## Regroup: the colony gathers its ground army back at the hub (giving any
## unit Regroup starts a regroup for all of them - see Player.start_regroup()).
## A military unit on
## Regroup stands by in the QRF room and defends like the QRF (see
## QrfMission) - hurt ones go off to heal and come back - until every
## military unit that can regroup (Unit.can_take("regroup")) is home and at
## full health. Then the regroup is over and all of them go to Mission
## Briefing together, ready for new orders (see Player.check_regroup()).
##
## Given to one unit in Mission Briefing, or to every military unit that
## comes home while the Central Hub panel's Regroup button is on
## (Player.regroup_active). It has no turn limit; it ends with the regroup.


func get_display_name() -> String:
	return "Regroup"


func get_kind() -> String:
	return "regroup"


func get_description() -> String:
	return "Regroup (stand by until the whole army is home and healed)"


func get_deploying_text() -> String:
	return "Joins the regroup at the end of the turn"


func get_completion_text() -> String:
	if _off_to_heal:
		return "left the regroup to be healed (back afterwards)"
	return "regrouped"


func get_progress_text() -> String:
	var text := super()
	return text.replace("QRF:", "Regroup:")
