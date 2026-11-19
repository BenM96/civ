class_name Movement
extends RefCounted
## Moves every unit from every colony at the same time.
##
## Movement is split into ticks, one per movement point (3 for every unit at
## the moment). A step lands on the tick given by Unit.get_next_step_tick():
## road steps land one tick apart, an open-ground step lands on tick 3. All
## units whose step lands on the same tick move together, and a unit counts
## as standing on its old tile until its step lands.
##
## Fighters (Infantry) of opposing colonies stop when they meet:
##   - On a tile: after every tick, any tile holding fighters from more than
##     one colony stops all of them there (walking onto an enemy, or both
##     arriving on the same tile at once).
##   - On a border: if they would swap tiles on the same tick, neither gets
##     across. Both stay on their own tile, stopped, and the attempt is
##     returned as a "clash" for Combat to resolve.


## Runs all movement for the turn. Returns the border clashes, each a
## Dictionary: {"tiles": [Vector2i, Vector2i], "sides": {faction: [Unit]}}.
static func run(map: HexMap) -> Array[Dictionary]:
	var units := map.get_units_in_world()
	var ticks := 0
	for u in units:
		ticks = maxi(ticks, u.max_movement)
	var clashes: Array[Dictionary] = []
	for tick in range(1, ticks + 1):
		var movers: Array[Unit] = []
		for u in units:
			if u.get_next_step_tick() == tick:
				movers.append(u)
		clashes.append_array(_stop_border_crossings(movers))
		for u in movers:
			u.take_step()
		_stop_meetings(map)
	for u in units:
		u.play_movement()
	return clashes


## Finds opposing fighters about to swap tiles. Stops them (removing them
## from `movers`) and returns the clashes.
static func _stop_border_crossings(movers: Array[Unit]) -> Array[Dictionary]:
	# (from, to) -> fighters stepping that way this tick.
	var crossing := {}
	for u in movers:
		if u.can_fight:
			var key := _edge(u.hex, u.get_next_step_hex())
			if not crossing.has(key):
				crossing[key] = []
			crossing[key].append(u)
	var clashes: Array[Dictionary] = []
	var done := {}
	for key: Vector4i in crossing:
		var reverse := Vector4i(key.z, key.w, key.x, key.y)
		if done.has(key) or not crossing.has(reverse):
			continue
		done[key] = true
		done[reverse] = true
		var sides := {}
		for u: Unit in crossing[key] + crossing[reverse]:
			if not sides.has(u.hub.faction):
				sides[u.hub.faction] = []
			sides[u.hub.faction].append(u)
		if sides.size() < 2:
			continue  # Friendly units passing each other.
		for faction in sides:
			for u: Unit in sides[faction]:
				u.engage()
				movers.erase(u)
		clashes.append({"tiles": [Vector2i(key.x, key.y), Vector2i(key.z, key.w)], "sides": sides})
	return clashes


## Stops every fighter on a tile that holds fighters from more than one colony.
static func _stop_meetings(map: HexMap) -> void:
	# hex -> {faction -> true}, and hex -> fighters there.
	var factions_at := {}
	var fighters_at := {}
	for u in map.get_units_in_world():
		if not u.can_fight:
			continue
		if not fighters_at.has(u.hex):
			fighters_at[u.hex] = []
			factions_at[u.hex] = {}
		fighters_at[u.hex].append(u)
		factions_at[u.hex][u.hub.faction] = true
	for h in fighters_at:
		if factions_at[h].size() >= 2:
			for u: Unit in fighters_at[h]:
				u.engage()


static func _edge(from: Vector2i, to: Vector2i) -> Vector4i:
	return Vector4i(from.x, from.y, to.x, to.y)
