class_name UnitStackLayout
extends RefCounted
## Arranges unit icons that share a tile so they're all visible: the more
## units on a tile, the smaller their icons, set out in a pattern that fits
## inside the hex. Supports up to MAX_SHOWN units per tile; any beyond that
## are drawn on top of the last slot.

const MAX_SHOWN := 6

## Units on a tile -> [icon scale, slot offsets in fractions of hex_size].
const LAYOUTS := {
	1: [1.0, [Vector2(0, 0)]],
	2: [0.7, [Vector2(-0.33, 0), Vector2(0.33, 0)]],
	3: [0.6, [Vector2(0, -0.33), Vector2(0.286, 0.165), Vector2(-0.286, 0.165)]],
	4: [0.52, [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25)]],
	5: [0.46, [Vector2(0, -0.44), Vector2(0.418, -0.136), Vector2(0.259, 0.356),
		Vector2(-0.259, 0.356), Vector2(-0.418, -0.136)]],
	6: [0.46, [Vector2(-0.22, -0.381), Vector2(0.22, -0.381), Vector2(0.44, 0),
		Vector2(0.22, 0.381), Vector2(-0.22, 0.381), Vector2(-0.44, 0)]],
}


## Aircraft fly above the ground units on their tile: in a row this far up
## (in hex sizes), spread across at most AIR_ROW_WIDTH, no bigger than
## AIR_SCALE.
const AIR_ROW_Y := -0.62
const AIR_ROW_WIDTH := 1.6
const AIR_SCALE := 0.75


## Lays out every unit out on the map. Call after units move or die.
## Aircraft get a row of their own above the tile (see AIR_ROW_Y); the
## ground units share the tile as above.
static func arrange(map: HexMap) -> void:
	var by_tile := {}
	var air_by_tile := {}
	for u in map.get_units_in_world():
		var group := air_by_tile if u.flies else by_tile
		if not group.has(u.hex):
			group[u.hex] = []
		group[u.hex].append(u)
	for h in by_tile:
		var units: Array = by_tile[h]
		_sort(units)
		var layout: Array = LAYOUTS[mini(units.size(), MAX_SHOWN)]
		var slots: Array = layout[1]
		for i in units.size():
			var slot: Vector2 = slots[mini(i, slots.size() - 1)]
			units[i].set_icon_layout(slot * map.hex_size, layout[0])
	for h in air_by_tile:
		var aircraft: Array = air_by_tile[h]
		_sort(aircraft)
		var shown := mini(aircraft.size(), MAX_SHOWN)
		var spacing := minf(0.8, AIR_ROW_WIDTH / shown)
		# Sized so neighbours' wings (about 3 icon radii across) don't touch.
		var icon_scale := minf(AIR_SCALE, spacing * map.hex_size / (Unit.RADIUS * 3.2))
		for i in aircraft.size():
			var x := (mini(i, shown - 1) - (shown - 1) / 2.0) * spacing
			aircraft[i].set_icon_layout(Vector2(x, AIR_ROW_Y) * map.hex_size, icon_scale)


## Keeps each colony's units together, in a stable order.
static func _sort(units: Array) -> void:
	units.sort_custom(func(a: Unit, b: Unit) -> bool:
		if a.player.id != b.player.id:
			return a.player.id < b.player.id
		return a.display_name < b.display_name)
