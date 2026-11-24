class_name Notices
extends RefCounted
## Every event that gets a banner at the top of the screen and stops
## "Skip idle turns" - all in one place. To add one: give it a Kind and an
## entry in LIST, then have the game call notify() when it happens (see
## Game._notify()).
##
## Each entry:
##   "good":  true for good news (gold banner with a flash and punch-in),
##            false for a warning (red banner that shakes, red screen edges);
##   "title": the banner's headline;
##   "body":  the text under it, with {placeholders} filled from the values
##            the game passes (String.format()).
## Several of the same kind in one turn are shown as one banner (the game
## gathers them up first - e.g. "3 enemy units...").

enum Kind { HUB_BREACHED, HUB_ATTACKED, ENEMY_IN_TERRITORY, STRUCTURE_LOST }

const LIST := {
	# Our Infantry knocked health off a rival's hub.
	# {other}: their colony, {left}: "4/10 health left", {cheer}: a closing line.
	Kind.HUB_BREACHED: {
		"good": true,
		"title": "HUB BREACHED!",
		"body": "Our Infantry tore into the {other}'s hub - {left}.\n{cheer}",
	},
	# Enemy Infantry knocked health off our hub.
	# {other}: their colony, {left}: "4/10 health left".
	Kind.HUB_ATTACKED: {
		"good": false,
		"title": "YOUR HUB IS UNDER ATTACK!",
		"body": "The {other}'s Infantry are demolishing your hub - {left}.\nAt 0 your colony is lost. Drive them off and repair the hub (Central Hub).",
	},
	# Enemy units stepped onto one of our structures (our territory) - once
	# when they arrive, not every turn they stay.
	# {who}: e.g. "Pink colony Infantry", {where}: e.g. "a conveyor belt".
	Kind.ENEMY_IN_TERRITORY: {
		"good": false,
		"title": "ENEMY IN YOUR TERRITORY!",
		"body": "{who} moved onto {where}.\nSend a force (or put units on QRF duty) to drive them off.",
	},
	# An enemy demolished or captured one of our structures.
	# {what}: e.g. "An extractor was demolished by the Pink colony".
	Kind.STRUCTURE_LOST: {
		"good": false,
		"title": "STRUCTURE LOST!",
		"body": "{what}.",
	},
}


## The banner for `kind`, filled in: {"good": bool, "title", "body", "at"}.
## `at`: the tile it happened on (the camera moves there when the banner
## shows), or null.
static func make(kind: Kind, values: Dictionary, at: Variant = null) -> Dictionary:
	var entry: Dictionary = LIST[kind]
	return {"good": entry["good"], "title": entry["title"], "body": String(entry["body"]).format(values), "at": at}
