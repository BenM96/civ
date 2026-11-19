class_name BiomassResource
extends ResourceType
## Food. Every unit eats it each turn and a colony whose stock falls below
## zero loses. The hub grows some; the rest comes from extractors (Workers
## can harvest it, but the AI never does).


func _init() -> void:
	type = ResourceDeposit.Type.BIOMASS
	display_name = "Biomass"
	color = Color(0.45, 0.95, 0.4)
	min_amount = 40
	max_amount = 120
	spawn_chance = 0.07
	terrains = [Terrain.Type.REGOLITH, Terrain.Type.DUST_PLAINS, Terrain.Type.DUNES, Terrain.Type.HIGHLANDS]
	harvest_amount = 1
	extractor_output = 1.0


## A cluster of glowing green growths.
func draw_icon(canvas: CanvasItem, c: Vector2, s: float) -> void:
	for blob: Vector3 in [Vector3(-0.15, 0.08, 0.14), Vector3(0.14, 0.1, 0.12), Vector3(0.0, -0.13, 0.15)]:
		var p := c + Vector2(blob.x, blob.y) * s
		canvas.draw_circle(p, blob.z * s, color.darkened(0.35))
		canvas.draw_circle(p + Vector2(-0.03, -0.03) * s, blob.z * s * 0.6, color)
