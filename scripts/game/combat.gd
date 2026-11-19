class_name Combat
extends RefCounted
## Fighting between colonies, resolved once every unit has moved (see
## Movement for how fighters get stopped). Only units out on the map take
## part; units garrisoned in a hub are safe.
##
##   1. Border clashes: fighters that tried to swap tiles with each other
##      trade one for one. Survivors stay on their own tiles.
##   2. Tile battles, on every tile holding more than one colony's units:
##      a. Fighters (Infantry) trade one for one - a 4 v 2 leaves 2 standing.
##      b. If any fighters are left, every enemy non-fighter (Worker) on the
##         tile is killed.


## Fights every battle. `clashes` comes from Movement.run(). Returns
## messages for the event log.
static func resolve(map: HexMap, clashes: Array[Dictionary]) -> PackedStringArray:
	var messages: PackedStringArray = []

	for clash in clashes:
		var dead := _trade_fighters(clash["sides"])
		var a: Vector2i = clash["tiles"][0]
		var b: Vector2i = clash["tiles"][1]
		messages.append("Clash between (%d, %d) and (%d, %d): %s"
			% [a.x, a.y, b.x, b.y, _describe_losses(dead)])
		_remove_dead(dead)

	var by_tile := {}
	for u in map.get_units_in_world():
		if not by_tile.has(u.hex):
			by_tile[u.hex] = []
		by_tile[u.hex].append(u)
	for h: Vector2i in by_tile:
		var dead := _tile_battle(by_tile[h])
		if dead.is_empty():
			continue
		messages.append("Battle at (%d, %d): %s" % [h.x, h.y, _describe_losses(dead)])
		_remove_dead(dead)
	return messages


## Works out who dies among the units on one tile.
static func _tile_battle(units: Array) -> Array[Unit]:
	# faction -> that faction's units, split by role.
	var fighters := {}
	var civilians := {}
	for u: Unit in units:
		var group := fighters if u.can_fight else civilians
		if not group.has(u.hub.faction):
			group[u.hub.faction] = []
		group[u.hub.faction].append(u)

	var dead := _trade_fighters(fighters)

	# Surviving fighters wipe out every other side's civilians.
	for side in civilians:
		for fighter_side in fighters:
			if fighter_side != side:
				dead.append_array(civilians[side])
				break
	return dead


## Fighters trade one for one while two or more sides still have some.
## `sides` is {faction: [Unit]}; the dead are removed from it and returned,
## so afterwards it holds only the survivors.
static func _trade_fighters(sides: Dictionary) -> Array[Unit]:
	var dead: Array[Unit] = []
	while sides.size() >= 2:
		var order: Array = sides.keys()
		order.sort_custom(func(a, b) -> bool: return sides[a].size() > sides[b].size())
		for side in [order[0], order[1]]:
			dead.append(sides[side].pop_back())
			if sides[side].is_empty():
				sides.erase(side)
	return dead


static func _remove_dead(dead: Array[Unit]) -> void:
	for u in dead:
		u.hub.remove_unit(u)


## e.g. "Your colony lost 2 Infantry; Rival colony lost 2 Infantry, 1 Worker"
static func _describe_losses(dead: Array[Unit]) -> String:
	# faction -> {unit_name -> count}
	var losses := {}
	for u in dead:
		var faction := u.hub.faction
		if not losses.has(faction):
			losses[faction] = {}
		losses[faction][u.unit_name] = losses[faction].get(u.unit_name, 0) + 1
	var parts: PackedStringArray = []
	for faction in losses:
		var counts: PackedStringArray = []
		for unit_name in losses[faction]:
			counts.append("%d %s" % [losses[faction][unit_name], unit_name])
		parts.append("%s lost %s" % [Faction.get_display_name(faction), ", ".join(counts)])
	return "; ".join(parts)
