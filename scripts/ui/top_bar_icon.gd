class_name TopBarIcon
extends Control
## A small icon for the top bar, in place of a word: a resource (drawn by
## the resource's own draw_icon(), as on the map), a command point (gold
## ring and flag) or initiative (a lightning bolt). Hover text says what it
## is (set by the HUD).

enum Kind { RESOURCE, COMMAND_POINT, INITIATIVE }

const SIZE := 26.0

var kind := Kind.RESOURCE
var resource_type := ResourceDeposit.Type.TITANIUM


func _init(p_kind := Kind.RESOURCE, p_type := ResourceDeposit.Type.TITANIUM) -> void:
	kind = p_kind
	resource_type = p_type
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_PASS  # So the tooltip shows.


func _draw() -> void:
	var c := size / 2.0
	var r := SIZE * 0.48
	match kind:
		Kind.RESOURCE:
			var color := ResourceDeposit.get_type_color(resource_type)
			draw_circle(c, r, Color(0.15, 0.06, 0.03, 0.8))
			draw_arc(c, r, 0, TAU, 20, Color(color, 0.9), 1.5, true)
			ResourceDeposit.get_info(resource_type).draw_icon(self, c, r / 0.44)
		Kind.COMMAND_POINT:
			var gold := Color(1.0, 0.82, 0.3)
			draw_circle(c, r, Color(0.15, 0.06, 0.03, 0.8))
			draw_arc(c, r, 0, TAU, 20, gold, 1.5, true)
			var foot := c + Vector2(-0.15, 0.55) * r
			var top := c + Vector2(-0.15, -0.6) * r
			draw_line(foot, top, gold, 2.0)
			draw_colored_polygon(PackedVector2Array([top, top + Vector2(0.65, 0.2) * r, top + Vector2(0, 0.42) * r]), gold)
		Kind.INITIATIVE:
			var blue := Color(0.55, 0.85, 1.0)
			draw_circle(c, r, Color(0.15, 0.06, 0.03, 0.8))
			draw_arc(c, r, 0, TAU, 20, blue, 1.5, true)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.15, -0.7) * r, c + Vector2(-0.35, 0.1) * r, c + Vector2(0.0, 0.1) * r,
				c + Vector2(-0.15, 0.7) * r, c + Vector2(0.35, -0.1) * r, c + Vector2(0.0, -0.1) * r,
			]), blue)
