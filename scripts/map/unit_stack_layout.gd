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


## Lays out every unit out on the map. Call after units move or die.
static func arrange(map: HexMap) -> void:
	var by_tile := {}
	for u in map.get_units_in_world():
		if not by_tile.has(u.hex):
			by_tile[u.hex] = []
		by_tile[u.hex].append(u)
	for h in by_tile:
		var units: Array = by_tile[h]
		# Keep each colony's units together, in a stable order.
		units.sort_custom(func(a: Unit, b: Unit) -> bool:
			if a.hub.faction != b.hub.faction:
				return a.hub.faction < b.hub.faction
			return a.display_name < b.display_name)
		var layout: Array = LAYOUTS[mini(units.size(), MAX_SHOWN)]
		var slots: Array = layout[1]
		for i in units.size():
			var slot: Vector2 = slots[mini(i, slots.size() - 1)]
			units[i].set_icon_layout(slot * map.hex_size, layout[0])
