class_name Hex
extends RefCounted
## Static helpers for pointy-top hexagons using axial coordinates.
##
## A hex coordinate is stored as a Vector2i where x = q (column-ish axis)
## and y = r (row axis). The implied third cube coordinate is s = -q - r.
## Reference: https://www.redblobgames.com/grids/hexagons/

const SQRT3 := 1.7320508075688772

## The six neighbour offsets, starting east and going counter-clockwise.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbor(h: Vector2i, direction: int) -> Vector2i:
	return h + DIRECTIONS[posmod(direction, 6)]


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		result.append(h + d)
	return result


## Number of steps between two hexes, ignoring terrain.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) >> 1


## Centre of a hex in pixels, relative to the map origin.
static func to_pixel(h: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (h.x + h.y * 0.5), size * 1.5 * h.y)


## The hex containing a pixel position (relative to the map origin).
static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return axial_round(q, r)


static func axial_round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


## The six corner points of a hex, for drawing.
static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * size)
	return points


## Converts "odd-r" offset coordinates (col, row) to axial. Rectangular maps
## are easiest to describe in offset coordinates.
static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - ((row - (row & 1)) >> 1), row)


static func axial_to_offset(h: Vector2i) -> Vector2i:
	return Vector2i(h.x + ((h.y - (h.y & 1)) >> 1), h.y)
