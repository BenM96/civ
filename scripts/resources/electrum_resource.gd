class_name ElectrumResource
extends ResourceType
## A rare metal, needed for research (see TechTrees) and specialist units
## (Unit.SPECIALIST_COST). Deposits only lie far out - more than 10 tiles from every hub and
## from each other. The Miner can carry it home 1 a trip, or an extractor at
## the end of a long belt line brings in 0.2 a turn.


func _init() -> void:
	type = ResourceDeposit.Type.ELECTRUM
	display_name = "Electrum"
	color = Color(0.15, 0.55, 1.0)
	min_amount = 999
	max_amount = 999
	spawn_chance = 0.0  # Placed by distance instead (below).
	terrains = [Terrain.Type.REGOLITH, Terrain.Type.DUST_PLAINS, Terrain.Type.DUNES, Terrain.Type.HIGHLANDS]
	min_distance_from_hubs = 10
	min_spacing = 10
	harvest_amount = 1
	extractor_output = 0.2


## A glowing bright-blue gem with a halo.
func draw_icon(canvas: CanvasItem, c: Vector2, s: float) -> void:
	canvas.draw_circle(c, 0.36 * s, Color(color, 0.25))
	canvas.draw_circle(c, 0.27 * s, Color(color, 0.35))
	var r := 0.22 * s
	var gem := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.25), c + Vector2(r * 0.5, r * 0.85),
		c + Vector2(-r * 0.5, r * 0.85), c + Vector2(-r * 0.8, -r * 0.25),
	])
	canvas.draw_colored_polygon(gem, color)
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.25), c, c + Vector2(-r * 0.8, -r * 0.25),
	]), color.lightened(0.45))
	canvas.draw_circle(c + Vector2(-0.07, -0.08) * s, 0.04 * s, Color(1, 1, 1, 0.9))
