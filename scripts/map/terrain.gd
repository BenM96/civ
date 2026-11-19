class_name Terrain
extends RefCounted
## Martian terrain types and their static properties. Every tile is a shade of
## orange; the type mainly changes movement cost and surface detail.
##
## Move costs are in movement points. Units have 3 MP and can only enter a
## tile they have enough MP left for: all open ground costs 3 (one tile per
## turn), while roads and bridges cost 1 (up to three tiles per turn).

enum Type { REGOLITH, DUST_PLAINS, DUNES, HIGHLANDS, MESA, CHASM, ROAD, BRIDGE, RUBBLE }

const IMPASSABLE_COST := 99

const DATA := {
	Type.REGOLITH: {"name": "Regolith", "color": Color(0.82, 0.42, 0.2), "move_cost": 3, "passable": true},
	Type.DUST_PLAINS: {"name": "Dust Plains", "color": Color(0.9, 0.55, 0.3), "move_cost": 3, "passable": true},
	Type.DUNES: {"name": "Dunes", "color": Color(0.93, 0.62, 0.32), "move_cost": 3, "passable": true},
	Type.HIGHLANDS: {"name": "Rocky Highlands", "color": Color(0.68, 0.33, 0.17), "move_cost": 3, "passable": true},
	Type.MESA: {"name": "Mesa", "color": Color(0.55, 0.26, 0.14), "move_cost": IMPASSABLE_COST, "passable": false},
	Type.CHASM: {"name": "Chasm", "color": Color(0.36, 0.16, 0.09), "move_cost": IMPASSABLE_COST, "passable": false},
	Type.ROAD: {"name": "Road", "color": Color(0.74, 0.52, 0.38), "move_cost": 1, "passable": true},
	## A chasm that a Worker has spanned with a bridge.
	Type.BRIDGE: {"name": "Bridge", "color": Color(0.36, 0.16, 0.09), "move_cost": 1, "passable": true},
	## Left behind when Infantry demolish anything man-made.
	Type.RUBBLE: {"name": "Rubble", "color": Color(0.5, 0.37, 0.3), "move_cost": 3, "passable": true},
}


static func get_display_name(type: Type) -> String:
	return DATA[type]["name"]


static func get_color(type: Type) -> Color:
	return DATA[type]["color"]


static func get_move_cost(type: Type) -> int:
	return DATA[type]["move_cost"]


static func is_passable(type: Type) -> bool:
	return DATA[type]["passable"]
