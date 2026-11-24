class_name Attention
extends RefCounted
## What the local player could be doing this turn, for the End Turn / Next
## button and auto-skip (see TurnManager):
##   ORDERS    - units are waiting in Mission Briefing for orders (not ones
##               about to repeat an order). This one is a hard stop: it
##               can't be dismissed, and the turn can't end until every
##               one has an order (see blocks_end_turn());
##   TRAINING  - a unit can be trained (allowed, affordable and feedable);
##   BUILDINGS - research has unlocked a hub building we haven't built yet
##               and haven't looked at in the Buildings panel since;
##   RESEARCH  - a tech can be researched (affordable).
## While any is open the button says Next, opens the matching panel
## (Mission Briefing, Training, Buildings, Research - in that order) and
## auto-skip stops. Closing that panel dismisses the issue for the rest of
## the turn, even if there's still something to do - but every new turn
## starts afresh, so anything still true blocks again (new_turn()). A new
## building only needs seeing once: after the Buildings panel has been
## closed with it on show, it never blocks again. Each issue is a set of
## items (unit ids, unit names, building ids, tech ids), so something new
## that turns up after a dismissal blocks again the same turn.

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
## Issue -> {item: true}: items the player has dismissed this turn (by
## closing the panel).
var _dismissed := {}
## Building id -> true: unlocked buildings the player has already been shown
## (or had from the start).
var _seen_buildings := {}


func _init(p_player: Player) -> void:
	player = p_player
	new_turn()
	for id: Variant in _items(Issue.BUILDINGS):
		_seen_buildings[id] = true


## A new turn: forget this turn's dismissals, so whatever's still true
## blocks End Turn again.
func new_turn() -> void:
	for issue: Issue in ORDER:
		_dismissed[issue] = {}


## The first open issue (in ORDER), or NONE.
func first_active() -> Issue:
	for issue: Issue in ORDER:
		if is_active(issue):
			return issue
	return Issue.NONE


## Whether `issue` has anything the player hasn't dismissed this turn.
func is_active(issue: Issue) -> bool:
	var dismissed: Dictionary = _dismissed[issue]
	for item: Variant in _items(issue):
		if not dismissed.has(item):
			return true
	return false


## Units waiting for orders: the turn can't end until they have some.
func blocks_end_turn() -> bool:
	return not _items(Issue.ORDERS).is_empty()


## The player closed `section`: dismiss the issue it's for, as it stands now.
func dismiss_section(section: Hud.Section) -> void:
	for issue: Issue in SECTIONS:
		if SECTIONS[issue] == section and issue != Issue.ORDERS:
			for item: Variant in _items(issue):
				_dismissed[issue][item] = true
				if issue == Issue.BUILDINGS:
					_seen_buildings[item] = true


## A short reason for the Next button's tooltip, e.g. "2 unit(s) need orders".
func describe(issue: Issue) -> String:
	match issue:
		Issue.ORDERS:
			return "%d unit(s) in Mission Briefing need orders - give each one an order (or Wait) before ending the turn" % _items(Issue.ORDERS).size()
		Issue.TRAINING:
			return "You can train: %s" % ", ".join(_items(Issue.TRAINING))
		Issue.BUILDINGS:
			return "New to build: %s" % ", ".join(_items(Issue.BUILDINGS).map(
				func(id: String) -> String: return player.get_building_type(id).display_name))
		Issue.RESEARCH:
			return "You can research: %s" % ", ".join(_items(Issue.RESEARCH).map(
				func(id: String) -> String: return TechList.get_tech(id).display_name))
	return ""


## What makes `issue` true right now: idle unit ids, trainable unit names,
## newly unlocked building ids, or affordable tech ids.
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
				if player.has_building_tech(type.id) and player.count_planned_buildings(type.id) == 0 \
						and not _seen_buildings.has(type.id):
					items.append(type.id)
		Issue.RESEARCH:
			for tech in TechList.all():
				if player.get_research_refusal(tech.id) == "":
					items.append(tech.id)
	return items
