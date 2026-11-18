class_name Structure
extends RefCounted
## Kinds of structure that can stand on a tile (on top of its terrain).
## Roads are terrain, not structures; these are industrial buildings that
## form the hub's supply network.

enum Type {
	NONE,
	## Mines the deposit it sits on: 1 resource per turn while connected.
	EXTRACTOR,
	## Carries resources between extractors and the hub.
	CONVEYOR,
}

const NAMES := {
	Type.NONE: "",
	Type.EXTRACTOR: "Extractor",
	Type.CONVEYOR: "Conveyor Belt",
}


static func get_display_name(type: Type) -> String:
	return NAMES[type]


## Whether resources can travel through a tile with this structure.
static func carries_resources(type: Type) -> bool:
	return type == Type.EXTRACTOR or type == Type.CONVEYOR
