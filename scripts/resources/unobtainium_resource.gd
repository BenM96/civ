class_name UnobtainiumResource
extends ResourceType
## The prize: the first colony to stockpile TurnManager.AMOUNT_TO_WIN of it
## wins. Deposits only lie far out - more than 10 tiles from every hub and
## from each other - and it can't be harvested by hand: a colony has to run
## belts all the way out and build an extractor on it.


func _init() -> void:
	type = ResourceDeposit.Type.UNOBTAINIUM
	display_name = "Unobtainium"
	color = Color(0.15, 0.55, 1.0)
	min_amount = 100
	max_amount = 120
	spawn_chance = 0.0  # Placed by distance instead (below).
	terrains = [Terrain.Type.REGOLITH, Terrain.Type.DUST_PLAINS, Terrain.Type.DUNES, Terrain.Type.HIGHLANDS]
	min_distance_from_hubs = 10
	min_spacing = 10
	can_harvest = false
	harvest_amount = 0
	extractor_output = 1.0


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
