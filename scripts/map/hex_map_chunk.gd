class_name HexMapChunk
extends Node2D
## Draws one block of the map's tiles (see HexMap.CHUNK_TILES), on one of
## two layers: TERRAIN (ground colour, outlines, rocks and dunes - changes
## only when terrain does) or FEATURES (foundations, bridges, deposits,
## belts, extractors, control points). Splitting the map up means a change
## redraws only the chunks it touches (HexMap.mark_dirty()) instead of all
## 1,000+ tiles, which used to stall the game for a quarter of a second
## every turn.

enum Layer { TERRAIN, FEATURES }

var map: HexMap
var layer: Layer
## The tiles this chunk draws.
var hexes: Array[Vector2i] = []


func _draw() -> void:
	map.draw_chunk(self)
