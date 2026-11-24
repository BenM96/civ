class_name TechList
extends RefCounted
## Every tech in the game (see Tech), grouped by tier.
##
## RULE: every tier must have exactly TECHS_PER_TIER (6) techs, because each
## game deals them out to TechTrees.TREE_COUNT (3) trees, TECHS_PER_TREE_TIER
## (2) per tree per tier. If you add a tech, add a whole tier's worth (or
## swap one out) so every tier keeps 6. check() warns at startup if not.
##
## Other rules:
##   - A tech's `requires` must be in a LOWER tier (so the trees can never
##     deadlock - see TechTrees).
##   - Workforce techs (+1 Builder limit) are in tiers 1, 4, 5 and 6.
##   - Initiative I, II and III (+1 initiative each) are in tiers 1, 4 and 6.
##   - Default units (Infantry, APC, Chopper) only need their building; every
##     other unit has its own unlock tech.
##
## Removed techs aren't deleted: they're kept in disabled/techs/ (which
## Godot ignores), ready to be put back.
##
## To change what a tech does, change its effect fields here (see Tech for
## what they mean); the rest of the game reads them through Player.

const TECHS_PER_TIER := 6

## Every tech, tier 1 first, made on first use.
static var _all: Array[Tech] = []


static func all() -> Array[Tech]:
	if _all.is_empty():
		_all = _create_all()
	return _all


## A tech by its id, or null.
static func get_tech(tech_id: String) -> Tech:
	for t in all():
		if t.id == tech_id:
			return t
	return null


## How many tiers there are.
static func tier_count() -> int:
	var top := 0
	for t in all():
		top = maxi(top, t.tier)
	return top


## The techs in one tier, in list order.
static func in_tier(tier: int) -> Array[Tech]:
	var result: Array[Tech] = []
	for t in all():
		if t.tier == tier:
			result.append(t)
	return result


## Warns if the list breaks the rules above. Returns whether it's fine.
static func check() -> bool:
	var ok := true
	for tier in range(1, tier_count() + 1):
		var n := in_tier(tier).size()
		if n != TECHS_PER_TIER:
			push_warning("Tier %d has %d techs - every tier needs exactly %d." % [tier, n, TECHS_PER_TIER])
			ok = false
	for t in all():
		if t.requires == "":
			continue
		var before := get_tech(t.requires)
		if before == null or before.tier >= t.tier:
			push_warning("Tech '%s' requires '%s', which must exist and be in a lower tier." % [t.id, t.requires])
			ok = false
	return ok


static func _create_all() -> Array[Tech]:
	var techs: Array[Tech] = []

	# --- Tier 1 ----------------------------------------------------------
	techs.append(_workforce(1, "I"))
	techs.append(_building("barracks", "Barracks", 1, BarracksBuilding.ID))
	techs.append(_building("field_medicine", "Field Medicine", 1, MedBayBuilding.ID))
	techs.append(_greenhouses("hydroponics_1", "Hydroponics I", 1))
	var defence := Tech.new("civil_defence", "Civil Defence", 1)
	defence.type_damage_bonus = [Unit.UnitType.CIVILIAN, Unit.UnitType.CIVILIAN]
	techs.append(defence)
	techs.append(_initiative("initiative_1", "Initiative I", 1))

	# --- Tier 2 ----------------------------------------------------------
	techs.append(_building("garage", "Garage", 2, GarageBuilding.ID))
	var doctrine := Tech.new("command_doctrine", "Command Doctrine", 2)
	doctrine.unlocks_buildable = CommandPointBuildable.ID
	techs.append(doctrine)
	var fob := Tech.new("forward_bases", "Forward Bases", 2)
	fob.unlocks_buildable = FobBuildable.ID
	techs.append(fob)
	techs.append(_building("surgery", "Surgery", 2, SurgicalWard.ID, "field_medicine"))
	techs.append(_unit("assault_infantry", "Assault Infantry", 2, "barracks"))
	techs.append(_unit("at_infantry", "AT Infantry", 2, "barracks"))

	# --- Tier 3 ----------------------------------------------------------
	techs.append(_building("hangar", "Hangar", 3, HangarBuilding.ID))
	techs.append(_building("vehicle_repair", "Vehicle Repair", 3, RepairBay.ID, "garage"))
	techs.append(_building("regeneration", "Regeneration", 3, RegenLab.ID, "field_medicine"))
	techs.append(_building("machine_tools", "Machine Tools", 3, MachineShop.ID, "garage"))
	techs.append(_unit("stinger_infantry", "Stinger Infantry", 3, "barracks"))
	techs.append(_unit("tank_destroyer", "Tank Destroyer", 3, "garage"))

	# --- Tier 4 ----------------------------------------------------------
	techs.append(_workforce(4, "II"))
	techs.append(_unit("tank", "Tank", 4, "garage"))
	techs.append(_unit("aa_gun", "Anti-Aircraft Gun", 4, "garage"))
	techs.append(_unit("fighter", "Fighter", 4, "hangar"))
	techs.append(_unit("fighter_bomber", "Fighter Bomber", 4, "hangar"))
	techs.append(_initiative("initiative_2", "Initiative II", 4, "initiative_1"))

	# --- Tier 5 ----------------------------------------------------------
	techs.append(_workforce(5, "III"))
	techs.append(_unit("bomber", "Bomber", 5, "hangar"))
	var drilling := Tech.new("advanced_drilling", "Advanced Drilling", 5)
	for type in [ResourceDeposit.Type.TITANIUM, ResourceDeposit.Type.SEDIMENT, ResourceDeposit.Type.GOLD]:
		drilling.extractor_bonus[type] = 0.1
	techs.append(drilling)
	techs.append(_weapons("infantry_weapons", "Infantry Weapons", 5, "Infantry", "barracks"))
	techs.append(_weapons("apc_weapons", "APC Weapons", 5, "APC", "garage"))
	techs.append(_weapons("chopper_weapons", "Chopper Weapons", 5, "Chopper", "hangar"))

	# --- Tier 6 ----------------------------------------------------------
	techs.append(_workforce(6, "IV"))
	techs.append(_initiative("initiative_3", "Initiative III", 6, "initiative_2"))
	techs.append(_weapons("assault_weapons", "Assault Weapons", 6, "Assault Infantry", "assault_infantry"))
	techs.append(_weapons("at_weapons", "AT Weapons", 6, "AT Infantry", "at_infantry"))
	techs.append(_weapons("stinger_weapons", "Stinger Weapons", 6, "Stinger Infantry", "stinger_infantry"))
	techs.append(_weapons("td_weapons", "TD Weapons", 6, "Tank Destroyer", "tank_destroyer"))

	# --- Tier 7 ----------------------------------------------------------
	techs.append(_building("flight_crews", "Flight Crews", 7, FlightCrewQuarters.ID, "hangar"))
	techs.append(_weapons("tank_guns", "Tank Guns", 7, "Tank", "tank"))
	techs.append(_weapons("flak_guns", "Flak Guns", 7, "Anti-Aircraft Gun", "aa_gun"))
	techs.append(_weapons("fighter_weapons", "Fighter Weapons", 7, "Fighter", "fighter"))
	techs.append(_weapons("bomber_weapons", "Bomber Weapons", 7, "Bomber", "bomber"))
	techs.append(_movement("all_terrain_drives_2", "All-Terrain Drives", 7))
	return techs


# --- Helpers for the common kinds ----------------------------------------------

## "Workforce III": +1 Builder limit. Its id keeps the tier it was first in
## (saved games use it); `numeral` is its number in the series now.
static func _workforce(tier: int, numeral: String) -> Tech:
	var t := Tech.new("workforce_%d" % tier, "Workforce %s" % numeral, tier)
	t.builder_limit_bonus = 1
	return t


static func _building(id: String, name: String, tier: int, building_id: String, requires := "") -> Tech:
	var t := Tech.new(id, name, tier, requires)
	t.unlocks_building = building_id
	return t


static func _unit(id: String, unit_name: String, tier: int, requires: String) -> Tech:
	var t := Tech.new(id, unit_name, tier, requires)
	t.unlocks_unit = unit_name
	return t


static func _greenhouses(id: String, name: String, tier: int, requires := "") -> Tech:
	var t := Tech.new(id, name, tier, requires)
	t.building_limit_bonus = {Greenhouse.ID: 1}
	return t


static func _weapons(id: String, name: String, tier: int, unit_name: String, requires := "") -> Tech:
	var t := Tech.new(id, name, tier, requires)
	t.damage_bonus_unit = unit_name
	return t


static func _movement(id: String, name: String, tier: int, requires := "") -> Tech:
	var t := Tech.new(id, name, tier, requires)
	t.movement_bonus = 1
	return t


## "Initiative II": +1 initiative. In tiers 2, 4 and 6, each needing the last.
static func _initiative(id: String, name: String, tier: int, requires := "") -> Tech:
	var t := Tech.new(id, name, tier, requires)
	t.initiative_bonus = 1
	return t


# --- What unlocks what ---------------------------------------------------------

## The tech that lets a colony build hub building `building_id`, or null if
## it needs none.
static func unlocking_building(building_id: String) -> Tech:
	for t in all():
		if t.unlocks_building == building_id:
			return t
	return null


## The tech that lets a colony train `unit_name`, or null if it needs none
## (the default unit of each type only needs its building).
static func unlocking_unit(unit_name: String) -> Tech:
	for t in all():
		if t.unlocks_unit == unit_name:
			return t
	return null


## The tech that lets Builders build map structure `buildable_id`, or null.
static func unlocking_buildable(buildable_id: String) -> Tech:
	for t in all():
		if t.unlocks_buildable == buildable_id:
			return t
	return null
