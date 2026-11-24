class_name Movement
extends RefCounted
## The movement phase: moves every unit from every colony at the same time,
## working out where battles break out, then passes those battles to Combat.
##
## Movement is split into ticks, one per movement point (3 for every unit at
## the moment). A step lands on the tick given by Unit.get_next_step_tick():
## foundation steps land one tick apart, an open-ground step lands on tick 3. All
## units whose step lands on the same tick move together, and a unit counts
## as standing on its old tile until its step lands.
##
## A battle breaks out when units of opposing colonies (Miners, Builders and Infantry
## alike) either:
##   - start the turn on the same tile (e.g. survivors of last turn's
##     battle, or a guard and the enemy it caught): that tile is a battle
##     hex before anyone moves, so they fight again rather than walk away, or
##   - end up on the same tile (one walks onto the other, or both arrive at
##     once): that tile becomes a battle hex, or
##   - try to pass through each other, swapping tiles on the same tick:
##     neither gets across, and both tiles become battle hexes.
## Friendly units never start a battle.
##
## Every unit on a battle hex stops there for the rest of the turn, and so
## does any unit that steps onto one later in the turn (it joins the
## battle). Everyone else carries on moving.
##
## Quick reaction forces (QrfMission) don't move with everyone else: once
## all other units have finished, they choose where to go from where the
## enemies ended up and get a movement phase of their own (same ticks, same
## battle rules). Their move is also shown after everyone else's.
##
## Aircraft on a sortie (SortieMission) go first, before anyone else moves:
## each jumps straight to its target tile, so it catches whoever is there
## at the start of the turn. Enemies on the tile it lands on make it a
## battle hex (and they stay to fight), and the battle takes in the tiles
## around it as usual. Enemies walking onto it later in the turn join in.
## Their flight is also shown first.
##
## Battles that share a hex (e.g. several border clashes around one tile)
## are merged into one. What's passed to Combat is the list of battles, each
## an array of hexes - plain JSON-safe data:
##
##   [ [[3, 4], [4, 4]],   # a battle across two hexes
##     [[9, 2]] ]          # a battle on one hex
##
## Hexes within a battle, and the battles themselves, are sorted so every
## computer resolves them in the same order.


## Runs the movement phase: moves every unit, then has Combat fight the
## battles that broke out. Returns a report of each battle (see Combat).
static func run(map: HexMap, turn: int) -> Array[Dictionary]:
	return Combat.resolve(map, _move_units(map), turn)


## Moves every unit, in three phases (see Mission.get_move_phase()): first
## aircraft fly straight to their targets; then everyone else moves
## together, tick by tick; then the QRF picks where to go from where
## everyone ended up, and moves the same way. Returns the battles, as described above.
static func _move_units(map: HexMap) -> Array:
	var units := map.get_units_in_world()
	var normal: Array[Unit] = []
	var late: Array[Unit] = []
	var air: Array[Unit] = []
	for u in units:
		var phase := u.mission.get_move_phase() if u.mission else Mission.MovePhase.NORMAL
		match phase:
			Mission.MovePhase.REACTION:
				late.append(u)
			Mission.MovePhase.AIR:
				air.append(u)
			_:
				normal.append(u)
	# Each battle as it broke out: an Array of Vector2i. Merged at the end.
	var outbreaks: Array = []
	# Every hex in any battle -> true.
	var battle_hexes := {}
	# Units that start the turn on a tile with enemies fight there.
	for h in _find_meetings(map):
		_add_battle([h], outbreaks, battle_hexes)
	for u in units:
		if battle_hexes.has(u.hex):
			u.engage()
	_fly(map, air, outbreaks, battle_hexes)
	var normal_delay := 0.0
	for u in air:
		normal_delay = maxf(normal_delay, u.get_movement_anim_time())
	_run_ticks(map, normal, outbreaks, battle_hexes)
	var late_delay := normal_delay
	for u in normal:
		late_delay = maxf(late_delay, normal_delay + u.get_movement_anim_time())
	for u in late:
		u.mission.react()
	_run_ticks(map, late, outbreaks, battle_hexes)
	for u in air:
		u.play_movement()  # Aircraft are shown first.
	for u in normal:
		u.play_movement(normal_delay)
	for u in late:
		u.play_movement(late_delay)  # Shown moving after everyone else.
	return _merge(outbreaks)


## Aircraft jump to their sortie targets; enemies where they land start
## battles.
static func _fly(map: HexMap, air: Array[Unit], outbreaks: Array, battle_hexes: Dictionary) -> void:
	if air.is_empty():
		return
	for u in air:
		u.mission.fly()
	for h in _find_meetings(map):
		if not battle_hexes.has(h):
			_add_battle([h], outbreaks, battle_hexes)
	for u in map.get_units_in_world():
		if battle_hexes.has(u.hex):
			u.engage()


## Moves `units`, tick by tick, adding any battles that break out.
static func _run_ticks(map: HexMap, units: Array[Unit], outbreaks: Array, battle_hexes: Dictionary) -> void:
	var ticks := 0
	for u in units:
		ticks = maxi(ticks, u.get_max_movement())
	for tick in range(1, ticks + 1):
		var movers: Array[Unit] = []
		for u in units:
			if u.get_next_step_tick() == tick:
				movers.append(u)
		for crossing in _find_crossings(movers):
			_add_battle(crossing, outbreaks, battle_hexes)
		for u in movers:
			if not battle_hexes.has(u.hex):  # Caught in a battle: stays put.
				u.take_step()
		for h in _find_meetings(map):
			if not battle_hexes.has(h):
				_add_battle([h], outbreaks, battle_hexes)
		# Everyone on a battle hex - there from the start, just arrived or
		# just walked in - stops there.
		for u in map.get_units_in_world():
			if battle_hexes.has(u.hex):
				u.engage()


static func _add_battle(hexes: Array, outbreaks: Array, battle_hexes: Dictionary) -> void:
	outbreaks.append(hexes)
	for h in hexes:
		battle_hexes[h] = true


## Pairs of tiles that opposing units are about to swap this tick, each as
## [Vector2i, Vector2i].
static func _find_crossings(movers: Array[Unit]) -> Array:
	# (from, to) -> {faction -> true} of the units stepping that way.
	var crossing := {}
	for u in movers:
		var key := _edge(u.hex, u.get_next_step_hex())
		if not crossing.has(key):
			crossing[key] = {}
		crossing[key][u.player.id] = true
	var result := []
	var done := {}
	for key: Vector4i in crossing:
		var reverse := Vector4i(key.z, key.w, key.x, key.y)
		if done.has(key) or not crossing.has(reverse):
			continue
		done[key] = true
		done[reverse] = true
		if _opposed(crossing[key], crossing[reverse]):
			result.append([Vector2i(key.x, key.y), Vector2i(key.z, key.w)])
	return result


## True if some faction in `a` is different from some faction in `b`
## (friendly units passing each other don't fight).
static func _opposed(a: Dictionary, b: Dictionary) -> bool:
	for fa in a:
		for fb in b:
			if fa != fb:
				return true
	return false


## Tiles holding units of more than one colony.
static func _find_meetings(map: HexMap) -> Array[Vector2i]:
	# hex -> {faction -> true}
	var factions_at := {}
	for u in map.get_units_in_world():
		if not factions_at.has(u.hex):
			factions_at[u.hex] = {}
		factions_at[u.hex][u.player.id] = true
	var result: Array[Vector2i] = []
	for h: Vector2i in factions_at:
		if factions_at[h].size() >= 2:
			result.append(h)
	return result


## Merges battles that share a hex into one, and converts them to sorted,
## JSON-safe data: [[[x, y], ...], ...].
static func _merge(outbreaks: Array) -> Array:
	# Union-find over hexes: hex -> the hex it's joined to.
	var parent := {}
	for battle: Array in outbreaks:
		for h: Vector2i in battle:
			if not parent.has(h):
				parent[h] = h
		for i in range(1, battle.size()):
			var a := _root(parent, battle[0])
			var b := _root(parent, battle[i])
			if a != b:
				parent[b] = a
	# root -> the hexes in that battle.
	var groups := {}
	for h: Vector2i in parent:
		var r := _root(parent, h)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(h)
	var battles: Array = []
	for r in groups:
		var hexes: Array = groups[r]
		hexes.sort_custom(_hex_less)
		battles.append(hexes)
	battles.sort_custom(func(a: Array, b: Array) -> bool: return _hex_less(a[0], b[0]))
	var result := []
	for hexes: Array in battles:
		var data := []
		for h: Vector2i in hexes:
			data.append(SaveGame.hex_to_data(h))
		result.append(data)
	return result


static func _root(parent: Dictionary, h: Vector2i) -> Vector2i:
	while parent[h] != h:
		h = parent[h]
	return h


static func _hex_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


static func _edge(from: Vector2i, to: Vector2i) -> Vector4i:
	return Vector4i(from.x, from.y, to.x, to.y)
