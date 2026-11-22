class_name Tech
extends RefCounted
## A researchable technology (see TechList for every one, TechTrees for how
## they're laid out each game, and Player.research_tech() for researching).
##
## A tech only unlocks or raises things - it never builds anything itself.
## What it does is set by the effect fields below (most techs use one). The
## rest of the game asks the Player what it has researched (Player.has_tech(),
## get_building_limit(), get_builder_limit(), get_damage_bonus()...) rather
## than looking at techs directly.

## Saved in save files - never change one once it's in use.
var id := ""
var display_name := ""
## 1 and up. A tech's prerequisite is always in a lower tier.
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
## A unit (unit_name) whose damage against every type this raises by 1.
var damage_bonus_unit := ""
## Extra movement points for every land unit.
var movement_bonus := 0
## Extra initiative (see Player.get_initiative()).
var initiative_bonus := 0
## Extra delivered per turn by extractors on these resource types:
## ResourceDeposit.Type -> float.
var extractor_bonus: Dictionary = {}


func _init(p_id: String, p_name: String, p_tier: int, p_requires := "") -> void:
	id = p_id
	display_name = p_name
	tier = p_tier
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
	if damage_bonus_unit != "":
		parts.append("%s does +1 damage to everything." % damage_bonus_unit)
	if movement_bonus > 0:
		parts.append("+%d movement for every land unit." % movement_bonus)
	if initiative_bonus > 0:
		parts.append("+%d initiative (whoever has the most fires first in battle)." % initiative_bonus)
	for type in extractor_bonus:
		parts.append("%s extractors deliver %s more a turn." % [
			ResourceDeposit.get_type_name(type), ResourceDeposit.format_amount(extractor_bonus[type])])
	return " ".join(parts)
