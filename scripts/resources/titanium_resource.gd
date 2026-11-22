class_name TitaniumResource
extends ResourceType
## Metal for training units, conveyor belts, extractors and bridges.


func _init() -> void:
	type = ResourceDeposit.Type.TITANIUM
	display_name = "Titanium"
	color = Color(0.62, 0.78, 1.0)
	min_amount = 999
	max_amount = 999
	spawn_chance = 0.14
	terrains = [Terrain.Type.HIGHLANDS]
	harvest_amount = 1
	extractor_output = 0.2


## Metallic crystal shards.
func draw_icon(canvas: CanvasItem, c: Vector2, s: float) -> void:
	for shard: Vector3 in [Vector3(-0.14, 0.12, 0.8), Vector3(0.13, 0.14, 0.7), Vector3(0.0, 0.08, 1.0)]:
		var base := c + Vector2(shard.x, shard.y) * s
		var hgt := 0.32 * shard.z * s
		var w := 0.08 * s
		var crystal := PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(-w, -hgt * 0.7),
			base + Vector2(0, -hgt), base + Vector2(w, -hgt * 0.7), base + Vector2(w, 0),
		])
		canvas.draw_colored_polygon(crystal, color.darkened(0.25))
		canvas.draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(-w, -hgt * 0.7), base + Vector2(0, -hgt), base,
		]), color.lightened(0.3))
