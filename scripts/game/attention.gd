class_name Attention
extends RefCounted
## What the local player could be doing this turn, for the End Turn / Next
## button, auto-skip (see TurnManager) and the blockers list down the right
## of the screen (see Hud):
##   ORDERS    - units are waiting in Mission Briefing for orders (not ones
##               about to repeat an order). This one is a hard stop: it
##               can't be dismissed, and the turn can't end until every
##               one has an order (see blocks_end_turn());
##   TRAINING  - a unit can be trained (allowed, affordable and feedable);
##   BUILDINGS - a hub building can be ordered right now (unlocked, room
##               under its limit, and affordable) - not just unlocked;
##   RESEARCH  - a tech can be researched (affordable).
## While any is open the button says Next, opens the matching panel
## (Mission Briefing, Training, Buildings, Research - in that order) and
## auto-skip stops. Closing that panel dismisses the issue as it stands -
## and the dismissal lasts, turn after turn: it only comes back when
## something NEW turns up (a unit, building or tech that wasn't on offer
## when the panel was closed). Each issue is a set of items (unit ids, unit
## names, building ids, tech ids); an item stops counting as dismissed once
## it's no longer on offer, so if it comes back later (say it became
## affordable again) it's new again.

enum Issue { NONE, ORDERS, TRAINING, BUILDINGS, RESEARCH }

const ORDER := [Issue.ORDERS, Issue.TRAINING, Issue.BUILDINGS, Issue.RESEARCH]

## The panel each issue opens, and the one whose closing dismisses it.
const SECTIONS := {
	Issue.ORDERS: Hud.Section.BRIEFING,
	Issue.TRAINING: Hud.Section.TRAINING,
	Issue.BUILDINGS: Hud.Section.BUILDINGS,
	Issue.RESEARCH: Hud.Section.RESEARCH,
}

var player: Player
## Issue -> {item: true}: items the player has dismissed (by closing the
## panel) and that are still on offer.
var _dismissed := {}


func _init(p_player: Player) -> void:
	player = p_player
	for issue: Issue in ORDER:
		_dismissed[issue] = {}


## A new turn: forget dismissals of anything no longer on offer, so it
## counts as new if it comes back.
func new_turn() -> void:
	for issue: Issue in ORDER:
		var now := {}
		for item: Variant in _items(issue):
			now[item] = true
		var dismissed: Dictionary = _dismissed[issue]
		for item: Variant in dismissed.keys():
			if not now.has(item):
				dismissed.erase(item)


## The first open issue (in ORDER), or NONE.
func first_active() -> Issue:
	for issue: Issue in ORDER:
		if is_active(issue):
			return issue
	return Issue.NONE


## Every open issue, in ORDER.
func all_active() -> Array[Issue]:
	var result: Array[Issue] = []
	for issue: Issue in ORDER:
		if is_active(issue):
			result.append(issue)
	return result


## Whether `issue` has anything the player hasn't dismissed.
func is_active(issue: Issue) -> bool:
	return not _new_items(issue).is_empty()


## Units waiting for orders: the turn can't end until they have some.
func blocks_end_turn() -> bool:
	return not _items(Issue.ORDERS).is_empty()


## The player closed `section`: dismiss the issue it's for, as it stands now.
func dismiss_section(section: Hud.Section) -> void:
	for issue: Issue in SECTIONS:
		if SECTIONS[issue] == section and issue != Issue.ORDERS:
			for item: Variant in _items(issue):
				_dismissed[issue][item] = true


## A short reason, e.g. "2 unit(s) need orders" - for the Next button's
## tooltip and the blockers list. Names only what's new.
func describe(issue: Issue) -> String:
	if issue == Issue.NONE:
		return ""
	var items := _new_items(issue)
	match issue:
		Issue.ORDERS:
			return "%d unit(s) in Mission Briefing need orders - give each one an order (or Wait) before ending the turn" % items.size()
		Issue.TRAINING:
			return "You can train: %s" % ", ".join(items)
		Issue.BUILDINGS:
			return "You can build: %s" % ", ".join(items.map(
				func(id: String) -> String: return player.get_building_type(id).display_name))
		Issue.RESEARCH:
			return "You can research: %s" % ", ".join(items.map(
				func(id: String) -> String: return TechList.get_tech(id).display_name))
	return ""


## What makes `issue` true right now, less what's been dismissed.
func _new_items(issue: Issue) -> Array:
	var dismissed: Dictionary = _dismissed[issue]
	return _items(issue).filter(func(item: Variant) -> bool: return not dismissed.has(item))


## What makes `issue` true right now: idle unit ids, trainable unit names,
## orderable building ids, or affordable tech ids.
func _items(issue: Issue) -> Array:
	var items := []
	if player == null or player.collapsed:
		return items
	match issue:
		Issue.ORDERS:
			for u in player.get_units_needing_orders():
				if u.repeats_left == 0:
					items.append(u.id)
		Issue.TRAINING:
			for bp in player.blueprints:
				if player.has_unit_tech(bp) and player.has_training_building(bp) \
						and player.get_training_refusal(bp) == "" and player.can_afford(player.get_training_cost(bp)):
					items.append(bp.unit_name)
		Issue.BUILDINGS:
			for type in player.building_types:
				if player.get_building_refusal(type.id) == "":
					items.append(type.id)
		Issue.RESEARCH:
			for tech in TechList.all():
				if player.get_research_refusal(tech.id) == "":
					items.append(tech.id)
	return items
