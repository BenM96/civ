class_name SedimentResource
extends ResourceType
## Building material for foundations, extractors and bridges.


func _init() -> void:
	type = ResourceDeposit.Type.SEDIMENT
	display_name = "Sediment"
	color = Color(0.97, 0.93, 0.8)
	min_amount = 60
	max_amount = 160
	spawn_chance = 0.08
	terrains = [Terrain.Type.DUST_PLAINS, Terrain.Type.DUNES]
	harvest_amount = 1
	extractor_output = 0.2


## Layered strata in a low mound.
func draw_icon(canvas: CanvasItem, c: Vector2, s: float) -> void:
	var layers: Array[Color] = [color.darkened(0.3), color.darkened(0.1), color]
	for i in layers.size():
		var y := (0.18 - i * 0.1) * s
		var half := (0.3 - i * 0.07) * s
		canvas.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-half, y), c + Vector2(-half * 0.8, y - 0.1 * s),
			c + Vector2(half * 0.8, y - 0.1 * s), c + Vector2(half, y),
		]), layers[i])
