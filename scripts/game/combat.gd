class_name Combat
extends RefCounted
## Fighting between colonies, resolved once every unit has moved. Combat
## doesn't go looking for fights itself: the movement phase works out where
## battles broke out and passes them in (see Movement).
##
## A battle is just an array of hexes. Everyone standing on those hexes
## takes part, pooled into one fight whichever hex they're on, and nobody
## changes hex during a battle. Units garrisoned in a hub are safe.


## Fights every battle in `battles`: an Array of battles, each an Array of
## hexes as [x, y] (see Movement). Returns messages for the event log.
static func resolve(map: HexMap, battles: Array) -> PackedStringArray:
	var messages: PackedStringArray = []
	for battle: Array in battles:
		var hexes: Array[Vector2i] = []
		for data in battle:
			hexes.append(SaveGame.hex_from_data(data))
		var dead := _fight(_sides_on(map, hexes))
		if dead.is_empty():
			continue
		messages.append("Battle at %s: %s" % [_describe_hexes(hexes), _describe_losses(dead)])
		_remove_dead(dead)
	return messages


## Everyone out on the map standing on any of `hexes`, as {faction: [Unit]}.
static func _sides_on(map: HexMap, hexes: Array[Vector2i]) -> Dictionary:
	var sides := {}
	for u in map.get_units_in_world():
		if not u.hex in hexes:
			continue
		if not sides.has(u.hub.faction):
			sides[u.hub.faction] = []
		sides[u.hub.faction].append(u)
	return sides


## Works out who dies in one battle; `sides` is {faction: [Unit]}. Every
## unit counts, one for one, but only while Infantry are involved: two
## sides trade a unit each while at least one of them still has Infantry
## (Workers alone stand off without anyone dying). Each side loses its
## Infantry first, then its Workers - so 1 Infantry v 2 Workers leaves 1
## Worker standing.
static func _fight(sides: Dictionary) -> Array[Unit]:
	# Workers first in each side, so Infantry pop off first.
	for side in sides:
		sides[side].sort_custom(func(a: Unit, b: Unit) -> bool: return not a.can_fight and b.can_fight)

	var dead: Array[Unit] = []
	while true:
		var pair := _next_fight(sides)
		if pair.is_empty():
			break
		for side in pair:
			dead.append(sides[side].pop_back())
			if sides[side].is_empty():
				sides.erase(side)
	return dead


## The two sides that fight next: the largest pair where at least one side
## has Infantry left. Empty when no fight is left on the tile.
static func _next_fight(sides: Dictionary) -> Array:
	var order: Array = sides.keys()
	order.sort_custom(func(a, b) -> bool:
		if sides[a].size() != sides[b].size():
			return sides[a].size() > sides[b].size()
		return a < b)
	for i in order.size():
		for j in range(i + 1, order.size()):
			if _has_fighter(sides[order[i]]) or _has_fighter(sides[order[j]]):
				return [order[i], order[j]]
	return []


static func _has_fighter(units: Array) -> bool:
	return not units.is_empty() and (units.back() as Unit).can_fight


static func _remove_dead(dead: Array[Unit]) -> void:
	for u in dead:
		u.hub.remove_unit(u)


## e.g. "(3, 4), (4, 4)"
static func _describe_hexes(hexes: Array[Vector2i]) -> String:
	var parts: PackedStringArray = []
	for h in hexes:
		parts.append("(%d, %d)" % [h.x, h.y])
	return ", ".join(parts)


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
