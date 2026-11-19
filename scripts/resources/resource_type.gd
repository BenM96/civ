class_name ResourceType
extends RefCounted
## Everything about one kind of resource, in one file per resource (like
## units and structures): its name and colour, where its deposits appear,
## what it yields to Workers and to Extractors, and how its deposit is drawn.
##
## To add a new resource: add a value to ResourceDeposit.Type, write a
## script extending this class (see biomass_resource.gd), and list it in
## ResourceDeposit._type_scripts().

var type: ResourceDeposit.Type
var display_name := "Resource"
var color := Color.WHITE

# --- Where deposits appear --------------------------------------------------
## Deposit size range, picked at random.
var min_amount := 10
var max_amount := 50
## Chance per eligible tile of a deposit appearing.
var spawn_chance := 0.05
## Terrain types (Terrain.Type) deposits can appear on.
var terrains: Array = []

# --- What it yields ---------------------------------------------------------
## Taken from the deposit per Harvest trip by a Worker (whole units).
var harvest_amount := 1
## Delivered to the hub per turn by a connected Extractor. Can be a fraction:
## stockpiles hold whole units, so the extractor builds up progress and
## delivers whenever a whole unit is ready (0.2 = 1 every 5 turns).
var extractor_output := 1.0


## extractor_output in hundredths of a unit, so progress is counted exactly
## in whole numbers (the same on every computer).
func extractor_output_hundredths() -> int:
	return roundi(extractor_output * 100)


func can_spawn_on(terrain: Terrain.Type) -> bool:
	return terrain in terrains


## Draws the deposit's icon (inside the ring the map draws around it) at `c`
## on `canvas`, for a hex of size `s`.
func draw_icon(_canvas: CanvasItem, _c: Vector2, _s: float) -> void:
	pass
