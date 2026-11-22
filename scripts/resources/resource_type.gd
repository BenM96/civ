class_name ResourceType
extends RefCounted
## Everything about one kind of resource, in one file per resource (like
## units and structures): its name and colour, where its deposits appear,
## what it yields to the Miner and to Extractors, and how its deposit is drawn.
##
## To add a new resource: add a value to ResourceDeposit.Type, write a
## script extending this class (see biomass_resource.gd), and list it in
## ResourceDeposit._type_scripts().

var type: ResourceDeposit.Type
var display_name := "Resource"
var color := Color.WHITE

# --- Where deposits appear --------------------------------------------------
## Deposit size range, picked at random.
var min_amount := 999
var max_amount := 999
## Chance per eligible tile of a deposit appearing.
var spawn_chance := 0.05
## Terrain types (Terrain.Type) deposits can appear on.
var terrains: Array = []
## If above 0, deposits aren't scattered at random: they're placed only on
## tiles MORE than this many tiles from every hub, and more than
## min_spacing from each other (see HexMap.place_remote_deposits()). Nor
## does every hub get one nearby.
var min_distance_from_hubs := 0
var min_spacing := 0

# --- What it yields ---------------------------------------------------------
## Whether the hub keeps a stockpile of it. If not (Biomass), it isn't
## stored at all: what buildings and extractors make of it each turn is just
## a rate, set against what the units eat (see Player.get_biomass_production()).
var stored := true
## Whether the Miner can harvest it by hand. If not, only extractors get it.
var can_harvest := true
## Taken from the deposit per Harvest trip by the Miner (whole units).
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


## Placed by distance rules rather than scattered (see min_distance_from_hubs).
func is_remote() -> bool:
	return min_distance_from_hubs > 0


## Draws the deposit's icon (inside the ring the map draws around it) at `c`
## on `canvas`, for a hex of size `s`.
func draw_icon(_canvas: CanvasItem, _c: Vector2, _s: float) -> void:
	pass
