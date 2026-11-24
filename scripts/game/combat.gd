class_name Combat
extends RefCounted
## Fighting between colonies, resolved once every unit has moved. Combat
## doesn't go looking for fights itself: the movement phase works out where
## battles broke out and passes them in (see Movement).
##
## A battle starts as an array of hexes where enemies met (its "core"), and
## spreads to every hex right next to them: everyone standing anywhere in
## that area takes part, pooled into one fight whichever hex they're on.
## Battles whose areas overlap are fought as one. Nobody changes hex during
## a battle. Units at a hub (garrisoned, or waiting there) are safe unless
## the hub tile itself is in the core.
##
## One round is fought per turn. Everyone takes part, hurt or not - a unit
## only flees when a hit leaves it at or below half its HP (step 3):
##   1. Each colony's units go into a list, in random order - except that
##      aircraft always come first (in random order among themselves). The
##      lists are taken highest initiative first (Player.get_initiative() -
##      from command points and Initiative techs); colonies with the same
##      initiative go in a random order.
##   2. Working through the lists side by side - the first unit of each list
##      in turn, then the second of each, and so on (a list that runs out is
##      skipped) - every unit fires once, at an enemy unit still in the
##      fight, taking that much HP off it: the attacker's damage against
##      the target's unit type (Unit.damage, Unit.unit_type) - never at an
##      ally (a colony on the same team, Player.team). Armour takes
##      two shots one after the other when its turn comes (each picking a
##      target afresh - Unit.shots_per_turn).
##      Targets: each unit prefers the type it does most damage to, and
##      shoots a random enemy of that type if there is one; otherwise the
##      next most damaged type, and so on. Civilians always come last, so
##      fighters shoot civilians only when nothing else is left
##      (Unit.get_target_preference()). Aircraft always shoot enemy aircraft
##      first (AirUnit). Nobody shoots at a type it does no damage to (a
##      Bomber never fires at ground units).
##   3. A unit hit down to 0 HP or below dies on the spot. One hit leaving it at
##      or below half its max HP (even one already there) breaks it and it
##      flees on the spot. Either way it's out of the
##      fight: it doesn't fire if its turn hadn't come yet, and can't be shot.
##   4. Afterwards the dead are removed, and everyone who fled drops their
##      mission and retreats one tile towards their hub (Unit.break_off());
##      aircraft fly home in the air return phase instead.
## Units still sharing a tile next turn fight again (see Movement).
##
## Each battle also comes back as a report - plain data describing who was
## there and every shot, in order - so the game can replay it (BattleView):
##   {"core": [Vector2i] (where enemies met), "hexes": [Vector2i] (the core
##    and every tile around it), "message": String,
##    "units": {unit id: {"name", "type", "short", "silhouette", "unit_type", "faction",
##                        "color", "hex", "home",
##                        "hp", "max_hp"}},   # As they were before the battle.
##    "events": [{"type": "shot", "from": id, "to": id, "damage": int,
##                 "hp": int (target's HP after), "result": "hit",
##                 "broken" or "dead"}]}
##
## The dice are seeded from the map seed, the turn and the battle, so the
## same game always plays out the same way.


## Fights every battle in `battles`: an Array of battles, each an Array of
## hexes as [x, y] (see Movement). Returns a report for each (see above).
static func resolve(map: HexMap, battles: Array, turn: int) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	var areas := _battle_areas(map, battles)
	for i in areas.size():
		var core: Array[Vector2i] = areas[i][0]
		var hexes: Array[Vector2i] = areas[i][1]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([map.last_seed, turn, i])
		var sides := _sides_on(map, hexes, core)
		var report := {"core": core, "hexes": hexes, "units": _describe_units(sides), "events": []}
		var fled := _fight(sides, rng, report["events"])
		var dead: Array[Unit] = []
		for side in sides:
			for u: Unit in sides[side]:
				if u.health <= 0:
					dead.append(u)
		report["message"] = "Battle at %s: %s" % [_describe_hexes(core), _describe_outcome(report["events"], dead, fled)]
		reports.append(report)
		for u in dead:
			u.player.remove_unit(u)
		for u in fled:
			u.break_off()
	return reports


## Each battle's area: [core, hexes] - the core hexes where enemies met, and
## those plus every tile next to them. Battles whose areas overlap are
## merged, so no unit fights twice in a turn. Sorted, so every computer
## fights them in the same order.
static func _battle_areas(map: HexMap, battles: Array) -> Array:
	var areas: Array = []
	for battle: Array in battles:
		var core := {}
		var area := {}
		for data in battle:
			var h := SaveGame.hex_from_data(data)
			core[h] = true
			area[h] = true
			for n in Hex.neighbors(h):
				if map.has_tile(n):
					area[n] = true
		areas.append([core, area])
	# Merge overlapping areas until none overlap.
	var merged := true
	while merged:
		merged = false
		for i in areas.size():
			for j in range(i + 1, areas.size()):
				var a: Dictionary = areas[i][1]
				var b: Dictionary = areas[j][1]
				if a.keys().any(func(h: Vector2i) -> bool: return b.has(h)):
					areas[i][0].merge(areas[j][0])
					a.merge(b)
					areas.remove_at(j)
					merged = true
					break
			if merged:
				break
	var result: Array = []
	for entry: Array in areas:
		result.append([_sorted_hexes(entry[0]), _sorted_hexes(entry[1])])
	result.sort_custom(func(x: Array, y: Array) -> bool: return _hex_less(x[0][0], y[0][0]))
	return result


static func _sorted_hexes(hex_set: Dictionary) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	hexes.assign(hex_set.keys())
	hexes.sort_custom(_hex_less)
	return hexes


static func _hex_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## Everyone out on the map standing on any of `hexes`, as {faction: [Unit]},
## each side in unit id order. Units on a hub tile outside the `core` are
## left out (safe at home).
static func _sides_on(map: HexMap, hexes: Array[Vector2i], core: Array[Vector2i]) -> Dictionary:
	var sides := {}
	for u in map.get_units_in_world():
		if not u.hex in hexes:
			continue
		if not u.hex in core and map.get_player_at(u.hex) != null:
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
				"short": u.get_short_label(),
				"silhouette": u.silhouette,
				"unit_type": u.unit_type,
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
	var order := _side_order(sides, rng)
	var longest := 0
	for side in order:
		_shuffle(sides[side], rng)
		_air_first(sides[side])
		longest = maxi(longest, sides[side].size())
	for i in longest:
		for side in order:
			var list: Array = sides[side]
			if i >= list.size():
				continue
			var attacker: Unit = list[i]
			if attacker.health <= 0 or attacker in fled:
				continue  # Killed or fled before its turn came.
			# Armour fires twice in a row (Unit.shots_per_turn).
			for shot in attacker.shots_per_turn:
				if not _fire(attacker, sides, order, side, rng, fled, events):
					break
	return fled


## `attacker` fires one shot at a random enemy still in the fight, of the
## type it most prefers to shoot (see Unit.pick_preferred_targets()).
## Returns false if there was nobody left to shoot.
static func _fire(attacker: Unit, sides: Dictionary, order: Array, side: Variant,
		rng: RandomNumberGenerator, fled: Array[Unit], events: Array) -> bool:
	var targets: Array[Unit] = []
	for other in order:
		if attacker.player.is_ally(sides[other][0].player):  # Ourselves, or an ally.
			continue
		for u: Unit in sides[other]:
			if u.health > 0 and not u in fled:
				targets.append(u)
	# Only at enemies it can hurt (a Bomber's guns can't touch ground units).
	var hurtable: Array[Unit] = []
	for u in targets:
		if attacker.get_damage_against(u) > 0:
			hurtable.append(u)
	targets = hurtable
	if targets.is_empty():
		return false
	targets = attacker.pick_preferred_targets(targets)
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
	return true


## The colonies (side ids) in the order they fire: highest initiative first,
## ties in a random order.
static func _side_order(sides: Dictionary, rng: RandomNumberGenerator) -> Array:
	var order: Array = sides.keys()
	order.sort()
	_shuffle(order, rng)
	var initiative := {}
	for side in order:
		var unit: Unit = sides[side][0]
		initiative[side] = unit.player.get_initiative()
	# Stable insertion sort, so ties keep their shuffled order.
	for i in range(1, order.size()):
		var j := i
		while j > 0 and initiative[order[j]] > initiative[order[j - 1]]:
			var swap: Variant = order[j]
			order[j] = order[j - 1]
			order[j - 1] = swap
			j -= 1
	return order


## Moves the aircraft in `list` to the front, keeping the order otherwise.
static func _air_first(list: Array) -> void:
	var air := list.filter(func(u: Unit) -> bool: return u.flies)
	var ground := list.filter(func(u: Unit) -> bool: return not u.flies)
	list.assign(air + ground)


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


## e.g. "Your colony lost 1 Infantry; Pink colony lost 1 Builder. Fled:
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


## e.g. "Your colony lost 2 Infantry; Rival colony lost 2 Infantry, 1 Miner"
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
