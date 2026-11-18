class_name Faction
extends RefCounted
## Who owns a hub, its units and the structures they build.

const NONE := -1
## The human player.
const PLAYER := 0
## The computer-controlled opponent (see AiController).
const RIVAL := 1

const NAMES := {PLAYER: "Your colony", RIVAL: "Rival colony"}
const COLORS := {PLAYER: Color(0.4, 0.85, 1.0), RIVAL: Color(1.0, 0.45, 0.85)}


static func get_display_name(faction: int) -> String:
	return NAMES.get(faction, "Nobody")


static func get_color(faction: int) -> Color:
	return COLORS.get(faction, Color(0.6, 0.6, 0.6))
