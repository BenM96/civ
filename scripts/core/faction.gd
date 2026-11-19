class_name Faction
extends RefCounted
## Who owns a hub, its units and the structures they build.
##
## Factions are just numbers, 0 and up, one per colony. Which one is played
## from this computer is `local_faction` (set by the game); everything else
## treats all factions the same. There's no limit on how many - each gets a
## name and colour from PALETTE, and once that runs out, a generated colour.

const NONE := -1
## The colony the human at this computer plays, unless the game says otherwise.
const PLAYER := 0

## The colony played from this computer: shown as "Your colony", followed by
## the camera and HUD. Set by the game when it starts or loads.
static var local_faction := PLAYER

## [name, colour] for each faction in turn. Colours are chosen to stand out
## against the orange terrain and from each other.
const PALETTE := [
	["Cyan colony", Color(0.4, 0.85, 1.0)],
	["Pink colony", Color(1.0, 0.45, 0.85)],
	["Violet colony", Color(0.62, 0.45, 1.0)],
	["Lime colony", Color(0.6, 1.0, 0.3)],
	["White colony", Color(0.97, 0.97, 0.97)],
]


## "Your colony" for the local faction, otherwise e.g. "Pink colony".
static func get_display_name(faction: int) -> String:
	if faction == local_faction:
		return "Your colony"
	return get_colony_name(faction)


## The colony's own name, the same on every computer, e.g. "Cyan colony".
static func get_colony_name(faction: int) -> String:
	if faction < 0:
		return "Nobody"
	if faction < PALETTE.size():
		return PALETTE[faction][0]
	return "Colony %d" % (faction + 1)


static func get_color(faction: int) -> Color:
	if faction < 0:
		return Color(0.6, 0.6, 0.6)
	if faction < PALETTE.size():
		return PALETTE[faction][1]
	# Spread extra colours around the colour wheel (golden-angle steps), but
	# skip the oranges and reds the terrain is made of.
	var hue := fposmod(0.15 + faction * 0.618034, 1.0)
	hue = lerpf(0.13, 0.95, hue)
	return Color.from_hsv(hue, 0.55, 1.0)
