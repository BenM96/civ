extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## +1 movement for every land unit.


func _init() -> void:
	super("all_terrain_drives_2", "All-Terrain Drives")
	movement_bonus = 1
