class_name TechList
extends RefCounted
## Every tech in the game (see Tech), grouped by tier.
##
## Each tech is its own script in scripts/techs/tier_N/ (extends Tech). The
## folder it's in IS its tier: to move a tech, move its file. Within a tier
## they're in file-name order. Each file says at the top whether it's
## LOCKED (don't move it without asking) or FLEXIBLE (can be moved or used
## as filler).
##
## RULE: every tier must have exactly TECHS_PER_TIER (6) techs, because each
## game deals them out to TechTrees.TREE_COUNT (3) trees, TECHS_PER_TREE_TIER
## (2) per tree per tier. If you add a tech, add a whole tier's worth (or
## swap one out) so every tier keeps 6. check() warns at startup if not.
##
## Other rules:
##   - A tech's `requires` must be in a LOWER tier (so the trees can never
##     deadlock - see TechTrees).
##   - Buildings: Barracks T1, Garage T2, Hangar T3 (locked).
##   - Counter units come the tier after the unit type they counter arrives:
##     anti-armour (AT Infantry, Tank Destroyer) in T3, after the Garage (T2);
##     anti-air (Stinger Infantry, AA Gun, Fighter) in T4, after the Hangar
##     (T3). The Tank is locked in T3 too.
##   - Default units (Infantry, APC, Chopper) only need their building; every
##     other unit has its own unlock tech.
##
## Removed techs aren't deleted: they're kept in disabled/techs/ (which
## Godot ignores), ready to be put back.
##
## To change what a tech does, change its effect fields in its file (see Tech
## for what they mean); the rest of the game reads them through Player.

const TECHS_PER_TIER := 6
const TECHS_DIR := "res://scripts/techs"

## Every tech, tier 1 first, made on first use.
static var _all: Array[Tech] = []


static func all() -> Array[Tech]:
	if _all.is_empty():
		_all = _load_all()
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


## Loads every tier_N folder in turn, stopping at the first one missing.
## ResourceLoader.list_directory() also works in exported builds (where the
## scripts are remapped).
static func _load_all() -> Array[Tech]:
	var techs: Array[Tech] = []
	var tier := 1
	while DirAccess.dir_exists_absolute("%s/tier_%d" % [TECHS_DIR, tier]):
		var dir := "%s/tier_%d" % [TECHS_DIR, tier]
		var files := Array(ResourceLoader.list_directory(dir)).filter(
			func(f: String) -> bool: return f.ends_with(".gd"))
		files.sort()
		for file: String in files:
			var tech: Tech = load("%s/%s" % [dir, file]).new()
			tech.tier = tier
			techs.append(tech)
		tier += 1
	return techs


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
