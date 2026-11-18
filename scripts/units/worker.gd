class_name Worker
extends Unit
## Basic civilian unit. For now it only takes Move missions; later it will
## build tile improvements, gather resources, etc.


func _init() -> void:
	unit_name = "Worker"
	max_movement = 4
	max_health = 8
	body_color = Color(0.85, 0.93, 1.0)
	can_harvest = true
