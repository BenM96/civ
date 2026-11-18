class_name HexOverlay
extends Node2D
## Draws transient highlights on top of the map: hovered tile, mission path
## previews and markers for where units in the field are heading.

var map: HexMap

var _hover := Vector2i.ZERO
var _has_hover := false
var _preview_path: Array[Vector2i] = []
var _preview_valid := true
var _preview_label := ""
var _markers: Array[Vector2i] = []


func set_hover(h: Vector2i, has_hover: bool) -> void:
	_hover = h
	_has_hover = has_hover
	queue_redraw()


## `path` should include the starting hex as its first element.
func set_preview(path: Array[Vector2i], valid: bool, label: String) -> void:
	_preview_path = path
	_preview_valid = valid
	_preview_label = label
	queue_redraw()


func clear_preview() -> void:
	_preview_path = []
	_preview_label = ""
	queue_redraw()


func set_markers(markers: Array[Vector2i]) -> void:
	_markers = markers
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	var size := map.hex_size

	for m in _markers:
		_draw_hex_outline(m, size * 0.85, Color(1.0, 0.9, 0.3, 0.8), 2.0)

	if _preview_path.size() > 0:
		var color := Color(0.4, 1.0, 0.5) if _preview_valid else Color(1.0, 0.35, 0.3)
		var target: Vector2i = _preview_path[-1]
		draw_colored_polygon(Hex.corners(map.to_local(map.hex_to_world(target)), size),
			Color(color, 0.25))
		var points := PackedVector2Array()
		for h in _preview_path:
			points.append(to_local(map.hex_to_world(h)))
		if points.size() > 1:
			draw_polyline(points, Color(color, 0.9), 3.0, true)
			for i in range(1, points.size()):
				draw_circle(points[i], 4.0, color)
		if _preview_label != "":
			_draw_label(to_local(map.hex_to_world(target)) + Vector2(0, -size * 1.1), _preview_label)

	if _has_hover:
		_draw_hex_outline(_hover, size, Color(1, 1, 1, 0.9), 2.0)


func _draw_hex_outline(h: Vector2i, radius: float, color: Color, line_width: float) -> void:
	var points := Hex.corners(to_local(map.hex_to_world(h)), radius)
	points.append(points[0])
	draw_polyline(points, color, line_width, true)


func _draw_label(pos: Vector2, text: String) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 16
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := pos - Vector2(text_size.x / 2.0, 0)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
