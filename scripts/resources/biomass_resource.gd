class_name BiomassResource
extends ResourceType
## Food. It isn't stored: what the hub's Greenhouses and Biomass extractors
## make each turn is the colony's biomass production, set against what its
## units eat (see Player.get_biomass_production()). While production is
## below zero, one unit starves each turn (see Player.starve()). Only
## extractors can mine it - there's nowhere to keep a hand-harvested load.


func _init() -> void:
	type = ResourceDeposit.Type.BIOMASS
	display_name = "Biomass"
	color = Color(0.45, 0.95, 0.4)
	min_amount = 999
	max_amount = 999
	spawn_chance = 0.07
	terrains = [Terrain.Type.REGOLITH, Terrain.Type.DUST_PLAINS, Terrain.Type.DUNES, Terrain.Type.HIGHLANDS]
	stored = false
	can_harvest = false
	extractor_output = 1.0


## A cluster of glowing green growths.
func draw_icon(canvas: CanvasItem, c: Vector2, s: float) -> void:
	for blob: Vector3 in [Vector3(-0.15, 0.08, 0.14), Vector3(0.14, 0.1, 0.12), Vector3(0.0, -0.13, 0.15)]:
		var p := c + Vector2(blob.x, blob.y) * s
		canvas.draw_circle(p, blob.z * s, color.darkened(0.35))
		canvas.draw_circle(p + Vector2(-0.03, -0.03) * s, blob.z * s * 0.6, color)
