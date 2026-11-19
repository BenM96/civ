class_name Structure
extends RefCounted
## Kinds of structure that can stand on a tile (on top of its terrain).
## Foundations and bridges are terrain, not structures.
##
## This file is only the list of kinds a tile can hold. Everything about each
## one (name, cost, behaviour) lives in its own *_buildable.gd file; the
## functions below just look it up there.

enum Type {
	NONE,
	EXTRACTOR,  ## See extractor_buildable.gd
	CONVEYOR,   ## See conveyor_buildable.gd
}

## Every structure kind that can stand on a tile. Add new ones here.
static func _create_all() -> Array[Buildable]:
	return [ExtractorBuildable.new(), ConveyorBuildable.new()]


## Type -> Buildable, filled on first use.
static var _by_type: Dictionary = {}


## The data for a structure kind, or null for NONE.
static func get_buildable(type: Type) -> Buildable:
	if _by_type.is_empty():
		for b in _create_all():
			_by_type[b.structure_type] = b
	return _by_type.get(type)


static func get_display_name(type: Type) -> String:
	var b := get_buildable(type)
	return b.display_name if b else ""


## Whether resources can travel through a tile with this structure.
static func carries_resources(type: Type) -> bool:
	var b := get_buildable(type)
	return b != null and b.carries_resources
