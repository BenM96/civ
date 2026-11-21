class_name Combat
extends RefCounted
## Fighting between colonies, resolved once every unit has moved. Combat
## doesn't go looking for fights itself: the movement phase works out where
## battles broke out and passes them in (see Movement).
##
## A battle is just an array of hexes. Everyone standing on those hexes
## takes part, pooled into one fight whichever hex they're on, and nobody
## changes hex during a battle. Units garrisoned in a hub are safe.
##
## One round is fought per turn:
##   1. Units already below half their max HP (broken in an earlier battle)
##      flee straight away without firing.
##   2. Each colony's other units go into a list, in random order, and the
##      lists are taken in a random order.
##   3. Working through the lists side by side - the first unit of each list
##      in turn, then the second of each, and so on (a list that runs out is
##      skipped) - every unit fires once, at a random enemy unit still in
##      the fight, taking that much HP off it: the attacker's damage against
##      the target's armour type (Unit.damage, Unit.armor_type).
##   4. A unit hit down to 0 HP or below dies on the spot. One hit below half
##      its max HP breaks and flees on the spot. Either way it's out of the
##      fight: it doesn't fire if its turn hadn't come yet, and can't be shot.
##   5. Afterwards the dead are removed, and everyone who fled drops their
##      mission and retreats one tile towards their hub (Unit.break_off()).
## Units still sharing a tile next turn fight again (see Movement).
##
## Each battle also comes back as a report - plain data describing who was
## there and every shot, in order - so the game can replay it (BattleView):
##   {"hexes": [Vector2i], "message": String,
##    "units": {unit id: {"name", "type", "faction", "color", "hex", "home",
##                        "hp", "max_hp"}},   # As they were before the battle.
##    "events": [{"type": "flee", "unit": id}
##               or {"type": "shot", "from": id, "to": id, "damage": int,
##                   "hp": int (target's HP after), "result": "hit",
##                   "broken" or "dead"}]}
##
## The dice are seeded from the map seed, the turn and the battle, so the
## same game always plays out the same way.


## Fights every battle in `battles`: an Array of battles, each an Array of
## hexes as [x, y] (see Movement). Returns a report for each (see above).
static func resolve(map: HexMap, battles: Array, turn: int) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for i in battles.size():
		var hexes: Array[Vector2i] = []
		for data in battles[i]:
			hexes.append(SaveGame.hex_from_data(data))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([map.last_seed, turn, i])
		var sides := _sides_on(map, hexes)
		var report := {"hexes": hexes, "units": _describe_units(sides), "events": []}
		var fled := _fight(sides, rng, report["events"])
		var dead: Array[Unit] = []
		for side in sides:
			for u: Unit in sides[side]:
				if u.health <= 0:
					dead.append(u)
		report["message"] = "Battle at %s: %s" % [_describe_hexes(hexes), _describe_outcome(report["events"], dead, fled)]
		reports.append(report)
		for u in dead:
			u.player.remove_unit(u)
		for u in fled:
			u.break_off()
	return reports


## Everyone out on the map standing on any of `hexes`, as {faction: [Unit]},
## each side in unit id order.
static func _sides_on(map: HexMap, hexes: Array[Vector2i]) -> Dictionary:
	var sides := {}
	for u in map.get_units_in_world():
		if not u.hex in hexes:
			continue
		if not sides.has(u.player.id):
			sides[u.player.id] = []
		sides[u.player.id].append(u)
	for side in sides:
		sides[side].sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
	return sides


## Every unit in the battle as it is before the fight, for the report.
static func _describe_units(sides: Dictionary) -> Dictionary:
	var units := {}
	for side in sides:
		for u: Unit in sides[side]:
			units[u.id] = {
				"name": u.display_name,
				"type": u.unit_name,
				"faction": u.player.id,
				"color": u.body_color,
				"hex": u.hex,
				"home": u.player.hex,
				"hp": u.health,
				"max_hp": u.max_health,
			}
	return units


## One round of fire (see the top of this file), recording each step in
## `events`. Shuffles each side's list in place. Returns the units that fled.
static func _fight(sides: Dictionary, rng: RandomNumberGenerator, events: Array) -> Array[Unit]:
	var fled: Array[Unit] = []
	# Already broken: off before a shot is fired.
	for side in sides:
		for u: Unit in sides[side]:
			if u.is_broken():
				fled.append(u)
				events.append({"type": "flee", "unit": u.id})
	var order: Array = sides.keys()
	order.sort()
	_shuffle(order, rng)
	var longest := 0
	for side in order:
		_shuffle(sides[side], rng)
		longest = maxi(longest, sides[side].size())
	for i in longest:
		for side in order:
			var list: Array = sides[side]
			if i >= list.size():
				continue
			var attacker: Unit = list[i]
			if attacker.health <= 0 or attacker in fled:
				continue  # Killed or fled before its turn came.
			var targets: Array[Unit] = []
			for other in order:
				if other == side:
					continue
				for u: Unit in sides[other]:
					if u.health > 0 and not u in fled:
						targets.append(u)
			if targets.is_empty():
				continue
			var target := targets[rng.randi_range(0, targets.size() - 1)]
			var amount := attacker.get_damage_against(target)
			target.take_damage(amount)
			var result := "hit"
			if target.health <= 0:
				result = "dead"
			elif target.is_broken():
				result = "broken"
				fled.append(target)
			events.append({"type": "shot", "from": attacker.id, "to": target.id,
				"damage": amount, "hp": target.health, "result": result})
	return fled


## Fisher-Yates with our own rng (Array.shuffle() would use the global one).
static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = list[i]
		list[i] = list[j]
		list[j] = swap


## e.g. "(3, 4), (4, 4)"
static func _describe_hexes(hexes: Array[Vector2i]) -> String:
	var parts: PackedStringArray = []
	for h in hexes:
		parts.append("(%d, %d)" % [h.x, h.y])
	return ", ".join(parts)


## e.g. "Your colony lost 1 Infantry; Pink colony lost 1 Worker. Fled:
## Infantry 2 (Pink colony)"
static func _describe_outcome(events: Array, dead: Array[Unit], broken: Array[Unit]) -> String:
	var hits := 0
	for e: Dictionary in events:
		if e["type"] == "shot" and e["damage"] > 0:
			hits += 1
	if dead.is_empty() and broken.is_empty():
		return "nobody fell (%d hit(s) landed)" % hits if hits > 0 else "no damage done"
	var text := _describe_losses(dead) if not dead.is_empty() else "nobody died"
	if not broken.is_empty():
		var fled: PackedStringArray = []
		for u in broken:
			fled.append("%s (%s)" % [u.display_name, u.player.get_display_name()])
		text += ". Broke and fled: " + ", ".join(fled)
	return text


## e.g. "Your colony lost 2 Infantry; Rival colony lost 2 Infantry, 1 Worker"
static func _describe_losses(dead: Array[Unit]) -> String:
	# faction -> {unit_name -> count}
	var losses := {}
	for u in dead:
		var faction := u.player.id
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
