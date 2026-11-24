class_name HexMap
extends Node2D
## Owns the tile data, generates terrain, draws the map and answers
## pathfinding / coordinate questions for the rest of the game.

signal map_generated
## A tile's terrain changed after generation (e.g. a foundation was laid).
signal tile_changed(h: Vector2i)
## A colony lost a structure to another: `by_faction` demolished it (it's
## gone) or captured it (it's theirs now). Not sent when a colony removes or
## replaces its own.
signal structure_lost(h: Vector2i, type: Structure.Type, owner_faction: int, by_faction: int)

@export var width := 40
@export var height := 26
@export var hex_size := 36.0
## 0 = pick a random seed each time.
@export var map_seed := 0
## Multiplies every resource's spawn chance (per-resource chances live in
## each resource's own file in scripts/resources/).
@export_range(0.0, 5.0) var deposit_density := 1.0

## Vector2i (axial) -> HexTile
var tiles: Dictionary = {}

var _astar := AStar2D.new()
var _point_ids: Dictionary = {}  # Vector2i -> int
var _id_to_hex: Array[Vector2i] = []
var _foundation_anchors: Array[Vector2i] = []
## Faction -> Player, for drawing ownership and supply networks.
var players: Dictionary = {}
## The seed the current map was generated from (pass it back to generate()
## to make the same map again).
var last_seed := 0
## The id the next new unit in this game gets (see take_unit_id()).
var next_unit_id := 1
## The control points (see place_control_points()): a colony that has a
## command point on every one, each linked to its hub, wins.
var control_points: Array[Vector2i] = []
## The map is drawn in blocks (HexMapChunk), each its own node, so a change
## only redraws the blocks it touches (mark_dirty()). Chunk key -> chunk.
var _terrain_chunks: Dictionary = {}
var _feature_chunks: Dictionary = {}
## What draw calls go to while a chunk is drawing (see draw_chunk()).
var _canvas: CanvasItem
## Tiles still drawn as they looked before a change the player hasn't seen
## happen yet (a Bomber's bombs land once its flight there has played - see
## show_as_before()): hex -> a copy of the old HexTile. Drawing only; the
## game itself always uses the real tile.
var _shown_before: Dictionary = {}

## How far from its colony's hub each control point is placed.
const CONTROL_POINT_MIN_DISTANCE := 5
const CONTROL_POINT_MAX_DISTANCE := 10
## Control points are never closer together than this.
const CONTROL_POINT_SPACING := 4
## Chunks are this many tiles across and down (see HexMapChunk).
const CHUNK_TILES := 8


## Whether factions `a` and `b` are on the same team (see Player.team): the
## same faction is its own ally; Faction.NONE (no owner) is nobody's.
func are_allied(a: int, b: int) -> bool:
	if a == Faction.NONE or b == Faction.NONE:
		return false
	if a == b:
		return true
	var pa: Player = players.get(a)
	var pb: Player = players.get(b)
	return pa != null and pa.is_ally(pb)


## Hands out a unit id no other unit in this game has had.
func take_unit_id() -> int:
	next_unit_id += 1
	return next_unit_id - 1


## Builds a new map. Uses `seed_override` if given, else map_seed, else a
## random seed.
func generate(seed_override := 0) -> void:
	tiles.clear()
	_foundation_anchors.clear()
	control_points.clear()
	var seed_value := seed_override if seed_override != 0 else (map_seed if map_seed != 0 else randi())
	if seed_value == 0:
		seed_value = 1  # 0 means "random", so it could never be regenerated.
	last_seed = seed_value

	var elevation := FastNoiseLite.new()
	elevation.seed = seed_value
	elevation.frequency = 0.055
	var dust := FastNoiseLite.new()
	dust.seed = seed_value + 1
	dust.frequency = 0.09

	for row in height:
		for col in width:
			var h := Hex.offset_to_axial(col, row)
			var p := Hex.to_pixel(h, 1.0)
			var e := elevation.get_noise_2d(p.x, p.y)
			var d := dust.get_noise_2d(p.x, p.y)
			tiles[h] = HexTile.new(h, _pick_terrain(e, d))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 2
	_scatter_deposits(rng)

	_rebuild_pathfinding()
	_build_chunks()
	map_generated.emit()


# --- Saving ----------------------------------------------------------------

## The map as plain data (see SaveGame): how it was generated, plus every
## tile's current terrain, structure and deposit (which change in play).
func to_dict() -> Dictionary:
	var tile_data := []
	for h in tiles:
		var tile: HexTile = tiles[h]
		tile_data.append([
			h.x, h.y,
			Terrain.Type.keys()[tile.terrain],
			Structure.Type.keys()[tile.structure],
			tile.structure_owner,
			ResourceDeposit.Type.keys()[tile.deposit.type] if tile.deposit else null,
			tile.deposit.amount if tile.deposit else 0,
		])
	return {
		"control_points": control_points.map(func(h: Vector2i) -> Array: return [h.x, h.y]),
		"seed": last_seed,
		"next_unit_id": next_unit_id,
		"width": width,
		"height": height,
		"deposit_density": deposit_density,
		"tiles": tile_data,
	}


## Rebuilds the map that to_dict() saved. Do this before placing any hubs.
func load_dict(data: Dictionary) -> void:
	width = int(data["width"])
	height = int(data["height"])
	deposit_density = float(data["deposit_density"])
	generate(int(data["seed"]))
	next_unit_id = int(data["next_unit_id"])
	for entry: Array in data["tiles"]:
		var h := Vector2i(int(entry[0]), int(entry[1]))
		var tile: HexTile = tiles[h]
		tile.terrain = Terrain.from_save_name(entry[2])
		tile.structure = Structure.Type[entry[3]]
		tile.structure_owner = int(entry[4])
		tile.deposit = null
		if entry[5] != null:
			tile.deposit = ResourceDeposit.new(ResourceDeposit.Type[entry[5]], h, int(entry[6]))
	for entry: Array in data["control_points"]:
		var h := Vector2i(int(entry[0]), int(entry[1]))
		tiles[h].control_point = true
		control_points.append(h)
	_rebuild_pathfinding()
	redraw_all()


func _pick_terrain(e: float, d: float) -> Terrain.Type:
	if e < -0.33:
		return Terrain.Type.CHASM
	if e > 0.38:
		return Terrain.Type.MESA
	if e > 0.2:
		return Terrain.Type.HIGHLANDS
	if d > 0.18:
		return Terrain.Type.DUNES
	if d < -0.15:
		return Terrain.Type.DUST_PLAINS
	return Terrain.Type.REGOLITH


## Randomly places resource deposits. Each resource only appears on its
## preferred terrain (see scripts/resources/); at most one per tile.
func _scatter_deposits(rng: RandomNumberGenerator) -> void:
	var infos := ResourceDeposit.all_infos()
	for h in tiles:
		var tile: HexTile = tiles[h]
		if not tile.is_passable():
			continue
		for info in infos:
			if info.is_remote() or not info.can_spawn_on(tile.terrain):
				continue
			if rng.randf() < info.spawn_chance * deposit_density:
				tile.deposit = ResourceDeposit.create_random(info.type, h, rng)
				break


## Places the "remote" resources (e.g. Electrum - see
## ResourceType.min_distance_from_hubs): as many deposits as fit on tiles
## more than min_distance_from_hubs from every hub and more than min_spacing
## from each other, on their usual terrain, reachable from a hub. Tiles are
## tried in a random order from the map's seed, so the same map always gets
## the same deposits. Returns how many were placed.
func place_remote_deposits(hub_spots: Array[Vector2i]) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = last_seed + 5
	var placed := 0
	for info in ResourceDeposit.all_infos():
		if not info.is_remote():
			continue
		var candidates: Array[Vector2i] = []
		for h in tiles:
			var tile: HexTile = tiles[h]
			if tile.is_passable() and tile.deposit == null and info.can_spawn_on(tile.terrain) \
					and _farther_than(h, hub_spots, info.min_distance_from_hubs):
				candidates.append(h)
		# Fisher-Yates with our own rng (Array.shuffle() would use the global one).
		for i in range(candidates.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = tmp
		var mine: Array[Vector2i] = []
		for h in candidates:
			if not _farther_than(h, mine, info.min_spacing):
				continue
			if not hub_spots.any(func(spot: Vector2i) -> bool: return not find_path(spot, h).is_empty()):
				continue
			tiles[h].deposit = ResourceDeposit.create_random(info.type, h, rng)
			mine.append(h)
		if mine.is_empty():
			push_warning("No room for any %s deposit on this map" % info.display_name)
		placed += mine.size()
	redraw_all()
	return placed


## Places one control point per hub, CONTROL_POINT_MIN_DISTANCE to
## CONTROL_POINT_MAX_DISTANCE tiles from it: on open, passable ground with no
## deposit, nearer that hub than any other (so nobody's is handed to a
## rival), at least CONTROL_POINT_SPACING from the others, and reachable on
## foot. Picked at random from the map's seed, so the same map always gets
## the same points. If a hub has no such tile, the "nearer than any other
## hub" rule is dropped for it.
func place_control_points(hub_spots: Array[Vector2i]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = last_seed + 11
	for spot in hub_spots:
		var h: Variant = _pick_control_point(spot, hub_spots, rng, true)
		if h == null:
			h = _pick_control_point(spot, hub_spots, rng, false)
		if h == null:
			push_warning("No room for a control point near %s" % spot)
			continue
		tiles[h].control_point = true
		control_points.append(h)
	redraw_all()


func _pick_control_point(spot: Vector2i, hub_spots: Array[Vector2i], rng: RandomNumberGenerator,
		nearest_only: bool) -> Variant:
	var candidates: Array[Vector2i] = []
	for h in tiles:
		var tile: HexTile = tiles[h]
		var d := Hex.distance(h, spot)
		if d < CONTROL_POINT_MIN_DISTANCE or d > CONTROL_POINT_MAX_DISTANCE:
			continue
		if not tile.is_passable() or tile.deposit != null or h in hub_spots:
			continue
		if not _farther_than(h, control_points, CONTROL_POINT_SPACING - 1):
			continue
		if nearest_only and hub_spots.any(func(other: Vector2i) -> bool:
				return other != spot and Hex.distance(h, other) <= d):
			continue
		candidates.append(h)
	candidates.sort()  # Dictionary order isn't guaranteed; keep it repeatable.
	while not candidates.is_empty():
		var h: Vector2i = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		if not find_path(spot, h).is_empty():
			return h
	return null


## Whether `h` is more than `distance` tiles from every one of `spots`.
func _farther_than(h: Vector2i, spots: Array[Vector2i], distance: int) -> bool:
	for spot in spots:
		if Hex.distance(h, spot) <= distance:
			return false
	return true


## Makes sure every colony starts with one deposit of every resource type
## within `radius` tiles of its hub. Wherever one is missing, it's added on a
## free tile 2..radius away that the hub can reach - on the resource's usual
## terrain if there is any, otherwise on any open ground. Uses the map's
## seed, so the same map always gets the same deposits.
func guarantee_deposits_near(hub_spots: Array[Vector2i], radius: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = last_seed + 3
	for spot in hub_spots:
		for type in ResourceDeposit.Type.values():
			if ResourceDeposit.get_info(type).is_remote():
				continue  # Only ever far from hubs (see place_remote_deposits()).
			if _has_deposit_near(spot, type, radius):
				continue
			var preferred: Array[Vector2i] = []
			var fallback: Array[Vector2i] = []
			for h in tiles:
				var tile: HexTile = tiles[h]
				var d := Hex.distance(h, spot)
				if d < 2 or d > radius or tile.deposit != null or not tile.is_passable() or h in hub_spots:
					continue
				if find_path(spot, h).is_empty():
					continue
				if ResourceDeposit.can_spawn_on(type, tile.terrain):
					preferred.append(h)
				else:
					fallback.append(h)
			var choices := preferred if not preferred.is_empty() else fallback
			if choices.is_empty():
				push_warning("No room for a %s deposit near %s" % [ResourceDeposit.get_type_name(type), spot])
				continue
			var h: Vector2i = choices[rng.randi_range(0, choices.size() - 1)]
			tiles[h].deposit = ResourceDeposit.create_random(type, h, rng)
	redraw_all()


## Removes every deposit on, or right next to, each hub spot, so no colony
## starts with resources on its doorstep. Do this before
## guarantee_deposits_near(), which then refills anything missing further out.
func clear_deposits_around(hub_spots: Array[Vector2i]) -> void:
	for spot in hub_spots:
		remove_deposit(spot)
		for n in Hex.neighbors(spot):
			remove_deposit(n)


func _has_deposit_near(center: Vector2i, type: ResourceDeposit.Type, radius: int) -> bool:
	for h in tiles:
		var tile: HexTile = tiles[h]
		if tile.deposit and tile.deposit.type == type and h != center and Hex.distance(h, center) <= radius:
			return true
	return false


func remove_deposit(h: Vector2i) -> void:
	var tile := get_tile(h)
	if tile and tile.deposit:
		tile.deposit = null
		mark_dirty(h)


## Changes a tile's terrain at runtime (e.g. a foundation being laid) and updates
## pathfinding to match.
func set_terrain(h: Vector2i, terrain: Terrain.Type) -> void:
	var tile := get_tile(h)
	if tile == null:
		return
	tile.terrain = terrain
	var id: int = _point_ids[h]
	_astar.set_point_weight_scale(id, float(tile.get_move_cost()))
	_astar.set_point_disabled(id, not tile.is_passable())
	mark_dirty(h, true)
	tile_changed.emit(h)


## Places (or clears, with Structure.Type.NONE) a structure on a tile,
## owned by the faction whose hub built it. Structures don't affect movement.
## `by_faction`: who did it, when clearing (demolishing) - defaults to the
## new owner (building or capturing). See structure_lost.
func set_structure(h: Vector2i, type: Structure.Type, owner_faction := Faction.NONE, by_faction := Faction.NONE) -> void:
	var tile := get_tile(h)
	if tile == null:
		return
	var new_owner := Faction.NONE if type == Structure.Type.NONE else owner_faction
	if tile.structure == type and tile.structure_owner == new_owner:
		return
	var old_type := tile.structure
	var old_owner := tile.structure_owner
	var by := by_faction if by_faction != Faction.NONE else new_owner
	tile.structure = type
	tile.structure_owner = new_owner
	mark_dirty(h)
	tile_changed.emit(h)
	if old_owner != Faction.NONE and new_owner != old_owner and by != old_owner:
		structure_lost.emit(h, old_type, old_owner, by)


## Lets the map draw each faction's hub links and supply network.
func register_player(player: Player) -> void:
	players[player.id] = player
	add_foundation_anchor(player.hex)


func get_player_at(h: Vector2i) -> Player:
	for faction in players:
		if players[faction].hex == h:
			return players[faction]
	return null


## Every faction's units that are out on the map (not garrisoned).
func get_units_in_world() -> Array[Unit]:
	var result: Array[Unit] = []
	for faction in players:
		for u: Unit in players[faction].units:
			if u.is_in_world():
				result.append(u)
	return result


## Units out on the map standing on `h`, from any faction.
func get_units_at(h: Vector2i) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in get_units_in_world():
		if u.hex == h:
			result.append(u)
	return result


## Tiles that foundations visually connect to even though they aren't foundations
## themselves (e.g. the hub).
func add_foundation_anchor(h: Vector2i) -> void:
	if h not in _foundation_anchors:
		_foundation_anchors.append(h)
		mark_dirty(h)


func _connects_foundation(h: Vector2i) -> bool:
	var tile := get_tile(h)
	if h in _foundation_anchors:
		return true
	return tile != null and (tile.terrain == Terrain.Type.FOUNDATION or tile.terrain == Terrain.Type.BRIDGE)


# --- Queries ---------------------------------------------------------------

func has_tile(h: Vector2i) -> bool:
	return tiles.has(h)


func get_tile(h: Vector2i) -> HexTile:
	return tiles.get(h)


func is_passable(h: Vector2i) -> bool:
	var tile := get_tile(h)
	return tile != null and tile.is_passable()


func hex_to_world(h: Vector2i) -> Vector2:
	return to_global(Hex.to_pixel(h, hex_size))


func world_to_hex(world_pos: Vector2) -> Vector2i:
	return Hex.from_pixel(to_local(world_pos), hex_size)


func get_world_rect() -> Rect2:
	var rect := Rect2()
	var first := true
	for h in tiles:
		var p := hex_to_world(h)
		if first:
			rect = Rect2(p, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(p)
	return rect.grow(hex_size)


## Returns the path from `from` to `to`, NOT including `from`.
## Empty if unreachable (or if from == to).
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if from == to or not _point_ids.has(from) or not _point_ids.has(to):
		return result
	# A unit can be left standing on a tile that became impassable (a bridge
	# collapsing under it): let it path off, just not back on.
	var from_id: int = _point_ids[from]
	var stranded := _astar.is_point_disabled(from_id)
	if stranded:
		_astar.set_point_disabled(from_id, false)
	var ids := _astar.get_id_path(from_id, _point_ids[to])
	if stranded:
		_astar.set_point_disabled(from_id, true)
	for i in range(1, ids.size()):
		result.append(_id_to_hex[ids[i]])
	return result


func get_path_cost(path: Array[Vector2i]) -> int:
	var cost := 0
	for h in path:
		cost += get_tile(h).get_move_cost()
	return cost


## Number of passable tiles reachable from `start` (flood fill).
func count_reachable(start: Vector2i) -> int:
	if not is_passable(start):
		return 0
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for n in Hex.neighbors(current):
			if not seen.has(n) and is_passable(n):
				seen[n] = true
				frontier.append(n)
	return seen.size()


# --- Pathfinding -----------------------------------------------------------

func _rebuild_pathfinding() -> void:
	_astar.clear()
	_point_ids.clear()
	_id_to_hex.clear()
	var next_id := 0
	for h in tiles:
		var tile: HexTile = tiles[h]
		_point_ids[h] = next_id
		_id_to_hex.append(h)
		# Point positions are in local space; all neighbours are the same
		# distance apart, so weight_scale acts as the cost of entering a tile.
		_astar.add_point(next_id, Hex.to_pixel(h, hex_size), float(tile.get_move_cost()))
		_astar.set_point_disabled(next_id, not tile.is_passable())
		next_id += 1
	for h in tiles:
		for n in Hex.neighbors(h):
			if _point_ids.has(n):
				_astar.connect_points(_point_ids[h], _point_ids[n])



# --- Drawing ---------------------------------------------------------------

## Makes the chunk nodes (see HexMapChunk) for the current tiles: a terrain
## layer under a features layer, each split into CHUNK_TILES blocks.
func _build_chunks() -> void:
	for chunk: HexMapChunk in _terrain_chunks.values() + _feature_chunks.values():
		chunk.queue_free()
	_terrain_chunks.clear()
	_feature_chunks.clear()
	var groups := {}  # Chunk key -> Array[Vector2i].
	for h in tiles:
		var key := _chunk_key(h)
		if not groups.has(key):
			var list: Array[Vector2i] = []
			groups[key] = list
		groups[key].append(h)
	var keys := groups.keys()
	keys.sort()
	# Every terrain chunk first, so all features draw over all terrain.
	for layer in [HexMapChunk.Layer.TERRAIN, HexMapChunk.Layer.FEATURES]:
		for key: Vector2i in keys:
			var chunk := HexMapChunk.new()
			chunk.map = self
			chunk.layer = layer
			chunk.hexes = groups[key]
			add_child(chunk)
			if layer == HexMapChunk.Layer.TERRAIN:
				_terrain_chunks[key] = chunk
			else:
				_feature_chunks[key] = chunk


func _chunk_key(h: Vector2i) -> Vector2i:
	var o := Hex.axial_to_offset(h)
	return Vector2i(floori(o.x / float(CHUNK_TILES)), floori(o.y / float(CHUNK_TILES)))


## Redraws the whole map (after generating or loading it).
func redraw_all() -> void:
	for chunk: HexMapChunk in _terrain_chunks.values() + _feature_chunks.values():
		chunk.queue_redraw()


## Something on `h` changed: redraws the chunks holding it and its
## neighbours (belts, foundations and bridges draw links into the tiles
## around them). `terrain` also redraws the ground there.
func mark_dirty(h: Vector2i, terrain := false) -> void:
	var around := Hex.neighbors(h)
	around.append(h)
	for n in around:
		var key := _chunk_key(n)
		if _feature_chunks.has(key):
			_feature_chunks[key].queue_redraw()
		if terrain and _terrain_chunks.has(key):
			_terrain_chunks[key].queue_redraw()


## Keeps drawing `h` as it looks now, whatever changes on it, until
## show_now(h) - so a change can appear when the player sees it happen.
func show_as_before(h: Vector2i) -> void:
	var tile := get_tile(h)
	if tile == null or _shown_before.has(h):
		return
	var copy := HexTile.new(h, tile.terrain)
	copy.deposit = tile.deposit
	copy.structure = tile.structure
	copy.structure_owner = tile.structure_owner
	copy.control_point = tile.control_point
	_shown_before[h] = copy


## Draws `h` as it really is again (see show_as_before()).
func show_now(h: Vector2i) -> void:
	if _shown_before.erase(h):
		mark_dirty(h, true)


## Draws one chunk's tiles onto it (HexMapChunk._draw() calls this). Tiles
## held by show_as_before() are swapped in just while drawing.
func draw_chunk(chunk: HexMapChunk) -> void:
	_canvas = chunk
	_swap_shown_tiles()
	if chunk.layer == HexMapChunk.Layer.TERRAIN:
		_draw_terrain(chunk.hexes)
	else:
		_draw_features(chunk.hexes)
	_swap_shown_tiles()
	_canvas = null


## Swaps the real tiles and their held looks (see show_as_before()); called
## twice, it puts everything back.
func _swap_shown_tiles() -> void:
	for h: Vector2i in _shown_before:
		var real: HexTile = tiles[h]
		tiles[h] = _shown_before[h]
		_shown_before[h] = real


func _draw_terrain(hexes: Array[Vector2i]) -> void:
	var outline := Color(0.2, 0.08, 0.03, 0.35)
	for h in hexes:
		var tile: HexTile = tiles[h]
		var center := Hex.to_pixel(h, hex_size)
		var points := Hex.corners(center, hex_size)
		_canvas.draw_colored_polygon(points, Terrain.get_color(tile.terrain))
		points.append(points[0])
		_canvas.draw_polyline(points, outline, 1.0)
		_draw_decoration(tile.terrain, center, h)


func _draw_features(hexes: Array[Vector2i]) -> void:
	for h in hexes:
		if tiles[h].terrain == Terrain.Type.BRIDGE:
			_draw_bridge(h)
		elif tiles[h].terrain == Terrain.Type.FOUNDATION:
			_draw_foundation(h)
	for h in hexes:
		var tile: HexTile = tiles[h]
		if tile.has_deposit():
			_draw_deposit(tile.deposit, Hex.to_pixel(h, hex_size))
	# Belt links, then extractor rigs on top of their deposits.
	for h in hexes:
		var owner_faction := _belt_owner(h)
		if owner_faction == Faction.NONE:
			continue
		# Belts and extractors always draw (linking to whatever's next to them,
		# hub included); a hub tile only draws its half of links to belts.
		if Structure.carries_resources(tiles[h].structure) or _has_belt_neighbour(h, owner_faction):
			_draw_belt_links(h, owner_faction)
	for h in hexes:
		if tiles[h].structure == Structure.Type.EXTRACTOR:
			_draw_extractor(h)
	for h in hexes:
		if not tiles[h].control_point:
			continue
		if tiles[h].structure == Structure.Type.COMMAND_POINT:
			_draw_command_point(h)
		else:
			_draw_control_point(h)


## Which faction's supply network this tile could belong to: the owner of
## its conveyor/extractor, or the faction whose hub stands on it.
func _belt_owner(h: Vector2i) -> int:
	var tile := get_tile(h)
	if tile and Structure.carries_resources(tile.structure):
		return tile.structure_owner
	var player := get_player_at(h)
	return player.id if player else Faction.NONE


## Belts only link up with the same faction's belts, extractors and hub.
func _connects_belt(h: Vector2i, owner_faction: int) -> bool:
	return has_tile(h) and _belt_owner(h) == owner_faction


func _has_belt_neighbour(h: Vector2i, owner_faction: int) -> bool:
	for n in Hex.neighbors(h):
		var tile := get_tile(n)
		if tile and Structure.carries_resources(tile.structure) and tile.structure_owner == owner_faction:
			return true
	return false


func _is_supply_connected(h: Vector2i, owner_faction: int) -> bool:
	return players.has(owner_faction) and players[owner_faction].is_supply_connected(h)


## Half a belt from this tile's centre to each linked neighbour; the
## neighbour draws the other half. Connected belts have rails in their
## faction's colour and chevrons pointing the way resources flow (towards
## the hub); disconnected ones are dull.
func _draw_belt_links(h: Vector2i, owner_faction: int) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var tile := get_tile(h)
	var is_belt := tile.structure == Structure.Type.CONVEYOR
	var lit := _is_supply_connected(h, owner_faction)
	var faction_color := Faction.get_color(owner_faction)
	var frame := Color(0.16, 0.16, 0.19)
	var surface := Color(0.36, 0.4, 0.46) if lit else Color(0.33, 0.3, 0.3)
	var rail := Color(faction_color, 0.95) if lit else Color(faction_color.darkened(0.45), 0.7)
	var ends: Array[Vector2] = []
	for n in Hex.neighbors(h):
		if _connects_belt(n, owner_faction):
			ends.append(c + (Hex.to_pixel(n, s) - c) * 0.5)
	if is_belt:
		_canvas.draw_circle(c, 0.17 * s, frame)
	for e in ends:
		_canvas.draw_line(c, e, frame, 0.3 * s)
	if is_belt:
		_canvas.draw_circle(c, 0.12 * s, surface)
	for e in ends:
		_canvas.draw_line(c, e, surface, 0.2 * s)
		var side := (e - c).orthogonal().normalized() * 0.1 * s
		_canvas.draw_line(c + side, e + side, rail, 1.5)
		_canvas.draw_line(c - side, e - side, rail, 1.5)
	# Flow chevrons on the segment towards the hub.
	var next_hex: Vector2i = players[owner_faction].get_network_parent(h) if lit else h
	if lit and next_hex != h:
		var target := c + (Hex.to_pixel(next_hex, s) - c) * 0.5
		var dir := (target - c).normalized()
		var perp := dir.orthogonal()
		for t in [0.3, 0.75]:
			var tip := c.lerp(target, t) + dir * 0.05 * s
			_canvas.draw_polyline(PackedVector2Array([
				tip - dir * 0.08 * s + perp * 0.07 * s, tip, tip - dir * 0.08 * s - perp * 0.07 * s,
			]), faction_color.lightened(0.6), 2.0)


## A small drilling derrick over the deposit, with a status light:
## green = connected and producing, red = not connected, grey = exhausted.
func _draw_extractor(h: Vector2i) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var tile := get_tile(h)
	var metal := Color(0.75, 0.78, 0.82)
	var dark := Color(0.2, 0.21, 0.25)
	var top := c + Vector2(0, -0.42) * s
	var left := c + Vector2(-0.26, 0.24) * s
	var right := c + Vector2(0.26, 0.24) * s
	# Base platform, edged in the owner's colour.
	_canvas.draw_rect(Rect2(c + Vector2(-0.34, 0.2) * s, Vector2(0.68, 0.13) * s), dark)
	_canvas.draw_rect(Rect2(c + Vector2(-0.34, 0.2) * s, Vector2(0.68, 0.13) * s),
		Faction.get_color(tile.structure_owner), false, 2.5)
	# Tower legs and cross braces.
	for leg in [left, right]:
		_canvas.draw_line(leg, top, dark, 4.0)
		_canvas.draw_line(leg, top, metal, 2.0)
	for t in [0.35, 0.65]:
		_canvas.draw_line(left.lerp(top, t), right.lerp(top, t), metal, 1.5)
	# Drill shaft.
	_canvas.draw_line(top, c + Vector2(0, 0.2) * s, Color(0.95, 0.95, 0.95), 1.5)
	# Hopper showing the resource being mined.
	var res_color := tile.deposit.get_color() if tile.has_deposit() else Color(0.5, 0.5, 0.5)
	_canvas.draw_rect(Rect2(c + Vector2(-0.11, 0.0) * s, Vector2(0.22, 0.16) * s), res_color)
	_canvas.draw_rect(Rect2(c + Vector2(-0.11, 0.0) * s, Vector2(0.22, 0.16) * s), dark, false, 1.5)
	# Status light.
	var light := Color(0.55, 0.55, 0.55)
	if tile.has_deposit():
		light = Color(0.35, 1.0, 0.4) if _is_supply_connected(h, tile.structure_owner) else Color(1.0, 0.3, 0.25)
	_canvas.draw_circle(top, 0.09 * s, dark)
	_canvas.draw_circle(top, 0.065 * s, light)


## An unclaimed control point: a gold ring round the tile and a white
## marker flag.
func _draw_control_point(h: Vector2i) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var gold := Color(1.0, 0.82, 0.3)
	var ring := Hex.corners(c, s * 0.8)
	ring.append(ring[0])
	_canvas.draw_polyline(ring, Color(0.15, 0.1, 0.05, 0.6), 5.0, true)
	_canvas.draw_polyline(ring, gold, 2.5, true)
	_draw_flag(c, s, Color(0.95, 0.95, 0.9), gold)


## A command point: a squat bunker with an antenna and a flag in its
## owner's colour, plus a status light - green when linked to its hub by
## belts (it counts towards victory), red when it isn't.
func _draw_command_point(h: Vector2i) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var tile := get_tile(h)
	var owner_color := Faction.get_color(tile.structure_owner)
	var dark := Color(0.2, 0.21, 0.25)
	var ring := Hex.corners(c, s * 0.8)
	ring.append(ring[0])
	_canvas.draw_polyline(ring, Color(0.15, 0.1, 0.05, 0.6), 5.0, true)
	_canvas.draw_polyline(ring, owner_color, 2.5, true)
	# Bunker.
	var bunker := PackedVector2Array([
		c + Vector2(-0.36, 0.3) * s, c + Vector2(-0.26, 0.02) * s,
		c + Vector2(0.26, 0.02) * s, c + Vector2(0.36, 0.3) * s])
	_canvas.draw_colored_polygon(bunker, Color(0.62, 0.64, 0.68))
	bunker.append(bunker[0])
	_canvas.draw_polyline(bunker, dark, 2.0, true)
	_canvas.draw_rect(Rect2(c + Vector2(-0.16, 0.1) * s, Vector2(0.32, 0.07) * s), dark)
	_draw_flag(c, s, owner_color, Color(0.85, 0.85, 0.88))
	var light := Color(0.35, 1.0, 0.4) if _is_supply_connected(h, tile.structure_owner) else Color(1.0, 0.3, 0.25)
	_canvas.draw_circle(c + Vector2(-0.22, -0.05) * s, 0.08 * s, dark)
	_canvas.draw_circle(c + Vector2(-0.22, -0.05) * s, 0.055 * s, light)


## A flagpole rising from the middle of the tile with a pennant.
func _draw_flag(c: Vector2, s: float, flag_color: Color, pole_color: Color) -> void:
	var foot := c + Vector2(0.06, 0.05) * s
	var top := c + Vector2(0.06, -0.55) * s
	_canvas.draw_line(foot, top, Color(0.1, 0.08, 0.06), 3.5)
	_canvas.draw_line(foot, top, pole_color, 1.8)
	var pennant := PackedVector2Array([top, top + Vector2(0.34, 0.1) * s, top + Vector2(0, 0.22) * s])
	_canvas.draw_colored_polygon(pennant, flag_color)
	pennant.append(pennant[0])
	_canvas.draw_polyline(pennant, Color(0.1, 0.08, 0.06), 1.5, true)


func _draw_decoration(terrain: Terrain.Type, c: Vector2, h: Vector2i) -> void:
	var s := hex_size
	# Stable per-tile pseudo-random value so details don't all line up.
	var hash_value := absi(hash(h))
	var jitter := Vector2(((hash_value % 7) - 3) * 0.04, (((hash_value >> 3) % 7) - 3) * 0.04) * s
	match terrain:
		Terrain.Type.REGOLITH:
			if hash_value % 3 == 0:
				# Small impact crater.
				_canvas.draw_circle(c + jitter, 0.2 * s, Color(0.6, 0.28, 0.13, 0.6))
				_canvas.draw_arc(c + jitter, 0.2 * s, 0, TAU, 14, Color(1.0, 0.7, 0.45, 0.45), 1.5)
			else:
				_canvas.draw_circle(c + jitter + Vector2(-0.2, 0.15) * s, 0.05 * s, Color(0.45, 0.2, 0.1, 0.6))
				_canvas.draw_circle(c + jitter + Vector2(0.18, -0.1) * s, 0.04 * s, Color(0.45, 0.2, 0.1, 0.6))
		Terrain.Type.DUST_PLAINS:
			var speck := Color(1.0, 0.8, 0.6, 0.35)
			for offset in [Vector2(-0.3, -0.1), Vector2(0.05, 0.25), Vector2(0.3, -0.2)]:
				_canvas.draw_circle(c + jitter + offset * s, 0.035 * s, speck)
		Terrain.Type.DUNES:
			var ridge := Color(1.0, 0.78, 0.5, 0.7)
			var shade := Color(0.7, 0.38, 0.17, 0.7)
			for y in [-0.25, 0.1]:
				var base := c + Vector2(0, y * s) + jitter * 0.5
				_canvas.draw_arc(base, 0.35 * s, PI * 1.15, PI * 1.85, 10, ridge, 2.0)
				_canvas.draw_arc(base + Vector2(0, 0.06 * s), 0.35 * s, PI * 1.15, PI * 1.85, 10, shade, 1.5)
		Terrain.Type.HIGHLANDS:
			var rock := Color(0.42, 0.2, 0.1)
			for offset in [Vector2(-0.25, 0.15), Vector2(0.22, 0.05), Vector2(-0.02, -0.25)]:
				var b: Vector2 = c + offset * s
				_canvas.draw_colored_polygon(PackedVector2Array([
					b + Vector2(-0.14, 0.08) * s, b + Vector2(-0.05, -0.12) * s,
					b + Vector2(0.08, -0.08) * s, b + Vector2(0.14, 0.08) * s,
				]), rock)
		Terrain.Type.MESA:
			_canvas.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.55, 0.35) * s, c + Vector2(-0.32, -0.25) * s,
				c + Vector2(0.32, -0.25) * s, c + Vector2(0.55, 0.35) * s,
			]), Color(0.4, 0.18, 0.09))
			_canvas.draw_line(c + Vector2(-0.32, -0.25) * s, c + Vector2(0.32, -0.25) * s,
				Color(0.85, 0.5, 0.28), 3.0)
		Terrain.Type.RUBBLE:
			# Broken concrete slabs and twisted metal.
			var slab := Color(0.62, 0.58, 0.55)
			var slab_dark := Color(0.35, 0.3, 0.28)
			for chunk: Vector3 in [Vector3(-0.25, 0.12, 0.13), Vector3(0.2, 0.18, 0.11),
					Vector3(0.05, -0.2, 0.15), Vector3(-0.1, -0.02, 0.08), Vector3(0.3, -0.1, 0.07)]:
				var b := c + jitter * 0.5 + Vector2(chunk.x, chunk.y) * s
				var r := chunk.z * s
				var poly := PackedVector2Array([
					b + Vector2(-r, r * 0.4), b + Vector2(-r * 0.6, -r * 0.7),
					b + Vector2(r * 0.7, -r * 0.5), b + Vector2(r, r * 0.5),
				])
				_canvas.draw_colored_polygon(poly, slab_dark)
				_canvas.draw_colored_polygon(PackedVector2Array([poly[0], poly[1], poly[2]]), slab)
			var rebar := Color(0.25, 0.2, 0.2)
			_canvas.draw_line(c + Vector2(-0.35, -0.15) * s, c + Vector2(-0.15, -0.32) * s, rebar, 1.5)
			_canvas.draw_line(c + Vector2(0.1, 0.32) * s, c + Vector2(0.32, 0.28) * s, rebar, 1.5)
		Terrain.Type.CHASM, Terrain.Type.BRIDGE:
			var crack := Color(0.12, 0.05, 0.03)
			_canvas.draw_polyline(PackedVector2Array([
				c + Vector2(-0.6, -0.1) * s, c + Vector2(-0.2, 0.1) * s,
				c + Vector2(0.1, -0.12) * s, c + Vector2(0.6, 0.08) * s,
			]), crack, 0.18 * s)


## Wooden-decked span from the centre towards every passable neighbour, with
## a girder underneath and rails along each side.
func _draw_bridge(h: Vector2i) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var ends: Array[Vector2] = []
	for n in Hex.neighbors(h):
		if is_passable(n):
			ends.append(c + (Hex.to_pixel(n, s) - c) * 0.5)
	var girder := Color(0.22, 0.22, 0.26)
	var deck := Color(0.62, 0.45, 0.28)
	var plank := Color(0.42, 0.29, 0.17)
	var rail := Color(0.8, 0.82, 0.86)
	_canvas.draw_circle(c, 0.22 * s, girder)
	for e in ends:
		_canvas.draw_line(c, e, girder, 0.42 * s)
	_canvas.draw_circle(c, 0.17 * s, deck)
	for e in ends:
		_canvas.draw_line(c, e, deck, 0.32 * s)
	for e in ends:
		var dir := (e - c).normalized()
		var side := dir.orthogonal() * 0.16 * s
		var length := c.distance_to(e)
		var step := 0.1 * s
		var d := step
		while d < length:
			var p := c + dir * d
			_canvas.draw_line(p - side, p + side, plank, 1.0)
			d += step
		_canvas.draw_line(c + side, e + side, rail, 2.0)
		_canvas.draw_line(c - side, e - side, rail, 2.0)


## Paved strips from the tile centre towards every connected neighbour.
func _draw_foundation(h: Vector2i) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var edge := Color(0.3, 0.24, 0.22)
	var surface := Color(0.52, 0.47, 0.44)
	var stripe := Color(0.95, 0.85, 0.5, 0.8)
	var ends: Array[Vector2] = []
	for n in Hex.neighbors(h):
		if _connects_foundation(n):
			ends.append(c + (Hex.to_pixel(n, s) - c) * 0.5)
	_canvas.draw_circle(c, 0.17 * s, edge)
	for e in ends:
		_canvas.draw_line(c, e, edge, 0.34 * s)
	_canvas.draw_circle(c, 0.13 * s, surface)
	for e in ends:
		_canvas.draw_line(c, e, surface, 0.24 * s)
	for e in ends:
		_canvas.draw_dashed_line(c, e, stripe, 1.5, 0.12 * s)


func _draw_deposit(deposit: ResourceDeposit, c: Vector2) -> void:
	var s := hex_size
	var color := deposit.get_color()
	# Dark backing disc + coloured ring so every deposit stands out from the
	# terrain, whatever shade of orange it sits on.
	_canvas.draw_circle(c, 0.44 * s, Color(0.15, 0.06, 0.03, 0.55))
	_canvas.draw_circle(c, 0.44 * s, Color(color, 0.12))
	_canvas.draw_arc(c, 0.44 * s, 0, TAU, 24, Color(color, 0.9), 2.0, true)
	# The icon itself is drawn by the resource's own file (scripts/resources/).
	ResourceDeposit.get_info(deposit.type).draw_icon(_canvas, c, s)
