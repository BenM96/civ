class_name Tech
extends RefCounted
## A researchable technology (see TechList for every one, TechTrees for how
## they're laid out each game, and Player.research_tech() for researching).
##
## A tech only unlocks or raises things - it never builds anything itself.
## What it does is set by the effect fields below (most techs use one). The
## rest of the game asks the Player what it has researched (Player.has_tech(),
## get_building_limit(), get_builder_limit(), get_type_damage_bonus()...) rather
## than looking at techs directly.

## Saved in save files - never change one once it's in use.
var id := ""
var display_name := ""
## 1 and up: the tier_N folder its script is in. A tech's prerequisite is
## always in a lower tier.
var tier := 1
## A tech (its id) that must be researched first, on any tree, or "".
var requires := ""

# --- Effects ------------------------------------------------------------------
## A hub building (Building id) this lets the colony build.
var unlocks_building := ""
## A unit (UnitBlueprint.unit_name) this lets the colony train.
var unlocks_unit := ""
## A map structure (Buildable id) this lets Builders build, e.g. command points.
var unlocks_buildable := ""
## Building id -> how much this raises the most the hub may have.
var building_limit_bonus: Dictionary = {}
## How much this raises the Builder limit.
var builder_limit_bonus := 0
## The unit type (Unit.UnitType) that type_damage_bonus applies to, or -1.
var type_damage_attacker := -1
## Target UnitType -> extra damage every type_damage_attacker unit does to
## units of that type (e.g. Civil Defence: civilians +2 vs civilians;
## Infantry Weapons: infantry +1 vs every type).
var type_damage_bonus: Dictionary = {}
## Extra movement points for every land unit.
var movement_bonus := 0
## Extra initiative (see Player.get_initiative()).
var initiative_bonus := 0
## Extra delivered per turn by extractors on these resource types:
## ResourceDeposit.Type -> float.
var extractor_bonus: Dictionary = {}


## Each tech is its own script in scripts/techs/tier_N/ that calls this from
## its _init(). `tier` comes from the folder (set by TechList).
func _init(p_id := "", p_name := "", p_requires := "") -> void:
	id = p_id
	display_name = p_name
	requires = p_requires


## What researching it does, e.g. "Lets you build a Barracks." - for the
## Research panel.
func get_effect_text() -> String:
	var parts: PackedStringArray = []
	if unlocks_building != "":
		parts.append("Lets you build a %s." % Building.get_name_for(unlocks_building))
	if unlocks_unit != "":
		parts.append("Lets you train %s." % unlocks_unit)
	if unlocks_buildable != "":
		parts.append("Lets Builders build %ss." % Structure.get_name_for_id(unlocks_buildable))
	for building_id in building_limit_bonus:
		parts.append("+%d %s limit." % [building_limit_bonus[building_id], Building.get_name_for(building_id)])
	if builder_limit_bonus > 0:
		parts.append("+%d Builder limit." % builder_limit_bonus)
	var bonuses := type_damage_bonus.values()
	if type_damage_attacker >= 0 and type_damage_bonus.size() == Unit.UnitType.size() \
			and bonuses.all(func(b: int) -> bool: return b == bonuses[0]):
		parts.append("%s units do +%d damage to everything." % [
			Unit.get_type_name(type_damage_attacker), bonuses[0]])
	elif type_damage_attacker >= 0:
		for target in type_damage_bonus:
			parts.append("%s units do +%d damage to %s units." % [
				Unit.get_type_name(type_damage_attacker), type_damage_bonus[target],
				Unit.get_type_name(target).to_lower()])
	if movement_bonus > 0:
		parts.append("+%d movement for every land unit." % movement_bonus)
	if initiative_bonus > 0:
		parts.append("+%d initiative (whoever has the most fires first in battle)." % initiative_bonus)
	for type in extractor_bonus:
		parts.append("%s extractors deliver %s more a turn." % [
			ResourceDeposit.get_type_name(type), ResourceDeposit.format_amount(extractor_bonus[type])])
	return " ".join(parts)
