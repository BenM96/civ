class_name HexMap
extends Node2D
## Owns the tile data, generates terrain, draws the map and answers
## pathfinding / coordinate questions for the rest of the game.

signal map_generated
## A tile's terrain changed after generation (e.g. a road was built).
signal tile_changed(h: Vector2i)

@export var width := 40
@export var height := 26
@export var hex_size := 36.0
## 0 = pick a random seed each time.
@export var map_seed := 0
## Multiplies every resource's spawn chance (per-resource chances live in
## ResourceDeposit.DATA).
@export_range(0.0, 5.0) var deposit_density := 1.0

## Vector2i (axial) -> HexTile
var tiles: Dictionary = {}

var _astar := AStar2D.new()
var _point_ids: Dictionary = {}  # Vector2i -> int
var _id_to_hex: Array[Vector2i] = []
var _road_anchors: Array[Vector2i] = []
## Connected hex -> next hex towards the hub (see set_supply_network).
var supply_network: Dictionary = {}


func generate() -> void:
	tiles.clear()
	_road_anchors.clear()
	var seed_value := map_seed if map_seed != 0 else randi()

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
	queue_redraw()
	map_generated.emit()


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
## preferred terrain (see ResourceDeposit.DATA); at most one per tile.
func _scatter_deposits(rng: RandomNumberGenerator) -> void:
	for h in tiles:
		var tile: HexTile = tiles[h]
		if not tile.is_passable():
			continue
		for type in ResourceDeposit.DATA:
			if not ResourceDeposit.can_spawn_on(type, tile.terrain):
				continue
			if rng.randf() < ResourceDeposit.DATA[type]["spawn_chance"] * deposit_density:
				tile.deposit = ResourceDeposit.create_random(type, h, rng)
				break


func remove_deposit(h: Vector2i) -> void:
	var tile := get_tile(h)
	if tile and tile.deposit:
		tile.deposit = null
		queue_redraw()


## Changes a tile's terrain at runtime (e.g. a road being built) and updates
## pathfinding to match.
func set_terrain(h: Vector2i, terrain: Terrain.Type) -> void:
	var tile := get_tile(h)
	if tile == null:
		return
	tile.terrain = terrain
	var id: int = _point_ids[h]
	_astar.set_point_weight_scale(id, float(tile.get_move_cost()))
	_astar.set_point_disabled(id, not tile.is_passable())
	queue_redraw()
	tile_changed.emit(h)


## Places (or clears, with Structure.Type.NONE) a structure on a tile.
## Structures don't affect movement.
func set_structure(h: Vector2i, type: Structure.Type) -> void:
	var tile := get_tile(h)
	if tile == null or tile.structure == type:
		return
	tile.structure = type
	queue_redraw()
	tile_changed.emit(h)


## The hub's supply network, for drawing: connected hex -> the next hex
## towards the hub (the hub itself maps to itself). Set by CentralHub.
func set_supply_network(network: Dictionary) -> void:
	supply_network = network
	queue_redraw()


## Tiles that roads visually connect to even though they aren't roads
## themselves (e.g. the hub).
func add_road_anchor(h: Vector2i) -> void:
	if h not in _road_anchors:
		_road_anchors.append(h)
		queue_redraw()


func _connects_road(h: Vector2i) -> bool:
	var tile := get_tile(h)
	if h in _road_anchors:
		return true
	return tile != null and (tile.terrain == Terrain.Type.ROAD or tile.terrain == Terrain.Type.BRIDGE)


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

func _draw() -> void:
	var outline := Color(0.2, 0.08, 0.03, 0.35)
	for h in tiles:
		var tile: HexTile = tiles[h]
		var center := Hex.to_pixel(h, hex_size)
		var points := Hex.corners(center, hex_size)
		draw_colored_polygon(points, Terrain.get_color(tile.terrain))
		points.append(points[0])
		draw_polyline(points, outline, 1.0)
		_draw_decoration(tile.terrain, center, h)
	for h in tiles:
		if tiles[h].terrain == Terrain.Type.BRIDGE:
			_draw_bridge(h)
		elif tiles[h].terrain == Terrain.Type.ROAD:
			_draw_road(h)
	for h in tiles:
		var tile: HexTile = tiles[h]
		if tile.has_deposit():
			_draw_deposit(tile.deposit, Hex.to_pixel(h, hex_size))
	# Belt links, then extractor rigs on top of their deposits.
	for h in tiles:
		if Structure.carries_resources(tiles[h].structure) or (h in _road_anchors and _has_belt_neighbour(h)):
			_draw_belt_links(h)
	for h in tiles:
		if tiles[h].structure == Structure.Type.EXTRACTOR:
			_draw_extractor(h)


func _connects_belt(h: Vector2i) -> bool:
	var tile := get_tile(h)
	return (tile != null and Structure.carries_resources(tile.structure)) or h in _road_anchors


func _has_belt_neighbour(h: Vector2i) -> bool:
	for n in Hex.neighbors(h):
		var tile := get_tile(n)
		if tile and Structure.carries_resources(tile.structure):
			return true
	return false


## Half a belt from this tile's centre to each linked neighbour; the
## neighbour draws the other half. Connected belts are lit and show
## chevrons pointing the way resources flow (towards the hub).
func _draw_belt_links(h: Vector2i) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var tile := get_tile(h)
	var is_belt := tile.structure == Structure.Type.CONVEYOR
	var lit := supply_network.has(h)
	var frame := Color(0.16, 0.16, 0.19)
	var surface := Color(0.36, 0.4, 0.46) if lit else Color(0.36, 0.3, 0.3)
	var rail := Color(0.4, 0.9, 1.0, 0.9) if lit else Color(0.9, 0.35, 0.25, 0.7)
	var ends: Array[Vector2] = []
	for n in Hex.neighbors(h):
		if _connects_belt(n):
			ends.append(c + (Hex.to_pixel(n, s) - c) * 0.5)
	if is_belt:
		draw_circle(c, 0.17 * s, frame)
	for e in ends:
		draw_line(c, e, frame, 0.3 * s)
	if is_belt:
		draw_circle(c, 0.12 * s, surface)
	for e in ends:
		draw_line(c, e, surface, 0.2 * s)
		var side := (e - c).orthogonal().normalized() * 0.1 * s
		draw_line(c + side, e + side, rail, 1.5)
		draw_line(c - side, e - side, rail, 1.5)
	# Flow chevrons on the segment towards the hub.
	if lit and supply_network[h] != h:
		var target := c + (Hex.to_pixel(supply_network[h], s) - c) * 0.5
		var dir := (target - c).normalized()
		var perp := dir.orthogonal()
		for t in [0.3, 0.75]:
			var tip := c.lerp(target, t) + dir * 0.05 * s
			draw_polyline(PackedVector2Array([
				tip - dir * 0.08 * s + perp * 0.07 * s, tip, tip - dir * 0.08 * s - perp * 0.07 * s,
			]), Color(0.85, 1.0, 1.0), 2.0)


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
	# Base platform.
	draw_rect(Rect2(c + Vector2(-0.34, 0.2) * s, Vector2(0.68, 0.13) * s), dark)
	draw_rect(Rect2(c + Vector2(-0.34, 0.2) * s, Vector2(0.68, 0.13) * s), metal, false, 1.5)
	# Tower legs and cross braces.
	for leg in [left, right]:
		draw_line(leg, top, dark, 4.0)
		draw_line(leg, top, metal, 2.0)
	for t in [0.35, 0.65]:
		draw_line(left.lerp(top, t), right.lerp(top, t), metal, 1.5)
	# Drill shaft.
	draw_line(top, c + Vector2(0, 0.2) * s, Color(0.95, 0.95, 0.95), 1.5)
	# Hopper showing the resource being mined.
	var res_color := tile.deposit.get_color() if tile.has_deposit() else Color(0.5, 0.5, 0.5)
	draw_rect(Rect2(c + Vector2(-0.11, 0.0) * s, Vector2(0.22, 0.16) * s), res_color)
	draw_rect(Rect2(c + Vector2(-0.11, 0.0) * s, Vector2(0.22, 0.16) * s), dark, false, 1.5)
	# Status light.
	var light := Color(0.55, 0.55, 0.55)
	if tile.has_deposit():
		light = Color(0.35, 1.0, 0.4) if supply_network.has(h) else Color(1.0, 0.3, 0.25)
	draw_circle(top, 0.09 * s, dark)
	draw_circle(top, 0.065 * s, light)


func _draw_decoration(terrain: Terrain.Type, c: Vector2, h: Vector2i) -> void:
	var s := hex_size
	# Stable per-tile pseudo-random value so details don't all line up.
	var hash_value := absi(hash(h))
	var jitter := Vector2(((hash_value % 7) - 3) * 0.04, (((hash_value >> 3) % 7) - 3) * 0.04) * s
	match terrain:
		Terrain.Type.REGOLITH:
			if hash_value % 3 == 0:
				# Small impact crater.
				draw_circle(c + jitter, 0.2 * s, Color(0.6, 0.28, 0.13, 0.6))
				draw_arc(c + jitter, 0.2 * s, 0, TAU, 14, Color(1.0, 0.7, 0.45, 0.45), 1.5)
			else:
				draw_circle(c + jitter + Vector2(-0.2, 0.15) * s, 0.05 * s, Color(0.45, 0.2, 0.1, 0.6))
				draw_circle(c + jitter + Vector2(0.18, -0.1) * s, 0.04 * s, Color(0.45, 0.2, 0.1, 0.6))
		Terrain.Type.DUST_PLAINS:
			var speck := Color(1.0, 0.8, 0.6, 0.35)
			for offset in [Vector2(-0.3, -0.1), Vector2(0.05, 0.25), Vector2(0.3, -0.2)]:
				draw_circle(c + jitter + offset * s, 0.035 * s, speck)
		Terrain.Type.DUNES:
			var ridge := Color(1.0, 0.78, 0.5, 0.7)
			var shade := Color(0.7, 0.38, 0.17, 0.7)
			for y in [-0.25, 0.1]:
				var base := c + Vector2(0, y * s) + jitter * 0.5
				draw_arc(base, 0.35 * s, PI * 1.15, PI * 1.85, 10, ridge, 2.0)
				draw_arc(base + Vector2(0, 0.06 * s), 0.35 * s, PI * 1.15, PI * 1.85, 10, shade, 1.5)
		Terrain.Type.HIGHLANDS:
			var rock := Color(0.42, 0.2, 0.1)
			for offset in [Vector2(-0.25, 0.15), Vector2(0.22, 0.05), Vector2(-0.02, -0.25)]:
				var b: Vector2 = c + offset * s
				draw_colored_polygon(PackedVector2Array([
					b + Vector2(-0.14, 0.08) * s, b + Vector2(-0.05, -0.12) * s,
					b + Vector2(0.08, -0.08) * s, b + Vector2(0.14, 0.08) * s,
				]), rock)
		Terrain.Type.MESA:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.55, 0.35) * s, c + Vector2(-0.32, -0.25) * s,
				c + Vector2(0.32, -0.25) * s, c + Vector2(0.55, 0.35) * s,
			]), Color(0.4, 0.18, 0.09))
			draw_line(c + Vector2(-0.32, -0.25) * s, c + Vector2(0.32, -0.25) * s,
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
				draw_colored_polygon(poly, slab_dark)
				draw_colored_polygon(PackedVector2Array([poly[0], poly[1], poly[2]]), slab)
			var rebar := Color(0.25, 0.2, 0.2)
			draw_line(c + Vector2(-0.35, -0.15) * s, c + Vector2(-0.15, -0.32) * s, rebar, 1.5)
			draw_line(c + Vector2(0.1, 0.32) * s, c + Vector2(0.32, 0.28) * s, rebar, 1.5)
		Terrain.Type.CHASM, Terrain.Type.BRIDGE:
			var crack := Color(0.12, 0.05, 0.03)
			draw_polyline(PackedVector2Array([
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
	draw_circle(c, 0.22 * s, girder)
	for e in ends:
		draw_line(c, e, girder, 0.42 * s)
	draw_circle(c, 0.17 * s, deck)
	for e in ends:
		draw_line(c, e, deck, 0.32 * s)
	for e in ends:
		var dir := (e - c).normalized()
		var side := dir.orthogonal() * 0.16 * s
		var length := c.distance_to(e)
		var step := 0.1 * s
		var d := step
		while d < length:
			var p := c + dir * d
			draw_line(p - side, p + side, plank, 1.0)
			d += step
		draw_line(c + side, e + side, rail, 2.0)
		draw_line(c - side, e - side, rail, 2.0)


## Paved strips from the tile centre towards every connected neighbour.
func _draw_road(h: Vector2i) -> void:
	var s := hex_size
	var c := Hex.to_pixel(h, s)
	var edge := Color(0.3, 0.24, 0.22)
	var surface := Color(0.52, 0.47, 0.44)
	var stripe := Color(0.95, 0.85, 0.5, 0.8)
	var ends: Array[Vector2] = []
	for n in Hex.neighbors(h):
		if _connects_road(n):
			ends.append(c + (Hex.to_pixel(n, s) - c) * 0.5)
	draw_circle(c, 0.17 * s, edge)
	for e in ends:
		draw_line(c, e, edge, 0.34 * s)
	draw_circle(c, 0.13 * s, surface)
	for e in ends:
		draw_line(c, e, surface, 0.24 * s)
	for e in ends:
		draw_dashed_line(c, e, stripe, 1.5, 0.12 * s)


func _draw_deposit(deposit: ResourceDeposit, c: Vector2) -> void:
	var s := hex_size
	var color := deposit.get_color()
	# Dark backing disc + coloured ring so every deposit stands out from the
	# terrain, whatever shade of orange it sits on.
	draw_circle(c, 0.44 * s, Color(0.15, 0.06, 0.03, 0.55))
	draw_circle(c, 0.44 * s, Color(color, 0.12))
	draw_arc(c, 0.44 * s, 0, TAU, 24, Color(color, 0.9), 2.0, true)
	match deposit.type:
		ResourceDeposit.Type.BIOMASS:
			# A cluster of glowing green growths.
			for blob: Vector3 in [Vector3(-0.15, 0.08, 0.14), Vector3(0.14, 0.1, 0.12), Vector3(0.0, -0.13, 0.15)]:
				var p := c + Vector2(blob.x, blob.y) * s
				draw_circle(p, blob.z * s, color.darkened(0.35))
				draw_circle(p + Vector2(-0.03, -0.03) * s, blob.z * s * 0.6, color)
		ResourceDeposit.Type.TITANIUM:
			# Metallic crystal shards.
			for shard: Vector3 in [Vector3(-0.14, 0.12, 0.8), Vector3(0.13, 0.14, 0.7), Vector3(0.0, 0.08, 1.0)]:
				var base := c + Vector2(shard.x, shard.y) * s
				var hgt := 0.32 * shard.z * s
				var w := 0.08 * s
				var crystal := PackedVector2Array([
					base + Vector2(-w, 0), base + Vector2(-w, -hgt * 0.7),
					base + Vector2(0, -hgt), base + Vector2(w, -hgt * 0.7), base + Vector2(w, 0),
				])
				draw_colored_polygon(crystal, color.darkened(0.25))
				draw_colored_polygon(PackedVector2Array([
					base + Vector2(-w, 0), base + Vector2(-w, -hgt * 0.7), base + Vector2(0, -hgt), base,
				]), color.lightened(0.3))
		ResourceDeposit.Type.SEDIMENT:
			# Layered strata in a low mound.
			var layers: Array[Color] = [color.darkened(0.3), color.darkened(0.1), color]
			for i in layers.size():
				var y := (0.18 - i * 0.1) * s
				var half := (0.3 - i * 0.07) * s
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-half, y), c + Vector2(-half * 0.8, y - 0.1 * s),
					c + Vector2(half * 0.8, y - 0.1 * s), c + Vector2(half, y),
				]), layers[i])
