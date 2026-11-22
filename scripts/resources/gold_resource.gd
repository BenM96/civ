class_name GoldResource
extends ResourceType
## Rare and valuable: every unit costs it.


func _init() -> void:
	type = ResourceDeposit.Type.GOLD
	display_name = "Gold"
	color = Color(1.0, 0.82, 0.2)
	min_amount = 999
	max_amount = 999
	spawn_chance = 0.03
	terrains = [Terrain.Type.HIGHLANDS, Terrain.Type.REGOLITH]
	harvest_amount = 1
	extractor_output = 0.2


## Glinting nuggets with a sparkle.
func draw_icon(canvas: CanvasItem, c: Vector2, s: float) -> void:
	for nugget: Vector3 in [Vector3(-0.13, 0.1, 0.11), Vector3(0.12, 0.08, 0.09), Vector3(0.0, -0.08, 0.13)]:
		var p := c + Vector2(nugget.x, nugget.y) * s
		var r := nugget.z * s
		canvas.draw_colored_polygon(PackedVector2Array([
			p + Vector2(-r, 0.2 * r), p + Vector2(-0.5 * r, -0.8 * r), p + Vector2(0.6 * r, -0.7 * r),
			p + Vector2(r, 0.1 * r), p + Vector2(0.4 * r, 0.8 * r), p + Vector2(-0.6 * r, 0.7 * r),
		]), color.darkened(0.3))
		canvas.draw_circle(p + Vector2(-0.2, -0.25) * r, 0.45 * r, color)
	var spark := c + Vector2(0.17, -0.2) * s
	var k := 0.09 * s
	canvas.draw_line(spark + Vector2(-k, 0), spark + Vector2(k, 0), Color.WHITE, 1.5, true)
	canvas.draw_line(spark + Vector2(0, -k), spark + Vector2(0, k), Color.WHITE, 1.5, true)
