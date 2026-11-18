class_name Infantry
extends Unit
## Military unit. Can demolish man-made structures (roads, bridges,
## extractors, conveyors), leaving rubble behind. Can't harvest or build.


func _init() -> void:
	unit_name = "Infantry"
	max_movement = 4
	max_health = 15
	body_color = Color(0.9, 0.35, 0.3)
	can_demolish = true
