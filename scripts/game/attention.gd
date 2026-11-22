class_name Attention
extends RefCounted
## What the local player could be doing this turn, for the End Turn / Next
## button and auto-skip (see TurnManager):
##   ORDERS   - units are waiting in Mission Briefing for orders;
##   TRAINING - a unit can be trained (allowed, affordable and feedable);
##   RESEARCH - a tech can be researched (affordable).
## While any is open the button says Next, opens the matching panel
## (Mission Briefing, Training, Research - in that order) and auto-skip
## stops. Closing that panel dismisses the issue, even if there's still
## something to do. A dismissed issue comes back only when it newly becomes
## true: each issue is a set of items (unit ids, unit names, tech ids), and
## an item counts again once it has stopped being true and become true
## again - e.g. another unit comes home, or you can afford something new.

enum Issue { NONE, ORDERS, TRAINING, RESEARCH }

## The panel each issue opens, and the one whose closing dismisses it.
const SECTIONS := {
	Issue.ORDERS: Hud.Section.BRIEFING,
	Issue.TRAINING: Hud.Section.TRAINING,
	Issue.RESEARCH: Hud.Section.RESEARCH,
}

var player: Player
## Issue -> {item: true}: items the player has dismissed (by closing the
## panel) that are still true.
var _dismissed := {Issue.ORDERS: {}, Issue.TRAINING: {}, Issue.RESEARCH: {}}


func _init(p_player: Player) -> void:
	player = p_player


## The first open issue (in ORDERS, TRAINING, RESEARCH order), or NONE.
func first_active() -> Issue:
	for issue: Issue in [Issue.ORDERS, Issue.TRAINING, Issue.RESEARCH]:
		if is_active(issue):
			return issue
	return Issue.NONE


## Whether `issue` has anything the player hasn't dismissed. Also forgets
## dismissed items that are no longer true, so they count again if they
## come back.
func is_active(issue: Issue) -> bool:
	var items := _items(issue)
	var dismissed: Dictionary = _dismissed[issue]
	for item: Variant in dismissed.keys():
		if not item in items:
			dismissed.erase(item)
	for item: Variant in items:
		if not dismissed.has(item):
			return true
	return false


## The player closed `section`: dismiss the issue it's for, as it stands now.
func dismiss_section(section: Hud.Section) -> void:
	for issue: Issue in SECTIONS:
		if SECTIONS[issue] == section:
			for item: Variant in _items(issue):
				_dismissed[issue][item] = true


## A short reason for the Next button's tooltip, e.g. "2 unit(s) need orders".
func describe(issue: Issue) -> String:
	match issue:
		Issue.ORDERS:
			return "%d unit(s) in Mission Briefing need orders" % player.get_units_needing_orders().size()
		Issue.TRAINING:
			return "You can train: %s" % ", ".join(_items(Issue.TRAINING))
		Issue.RESEARCH:
			return "You can research: %s" % ", ".join(_items(Issue.RESEARCH).map(
				func(id: String) -> String: return TechList.get_tech(id).display_name))
	return ""


## What makes `issue` true right now: idle unit ids, trainable unit names,
## or affordable tech ids.
func _items(issue: Issue) -> Array:
	var items := []
	if player == null or player.collapsed:
		return items
	match issue:
		Issue.ORDERS:
			for u in player.get_units_needing_orders():
				items.append(u.id)
		Issue.TRAINING:
			for bp in player.blueprints:
				if player.has_unit_tech(bp) and player.has_training_building(bp) \
						and player.get_training_refusal(bp) == "" and player.can_afford(player.get_training_cost(bp)):
					items.append(bp.unit_name)
		Issue.RESEARCH:
			for tech in TechList.all():
				if player.get_research_refusal(tech.id) == "":
					items.append(tech.id)
	return items
