class_name Builder
extends Unit
## Construction unit. Takes Build missions (roads for now) but can't harvest.


func _init() -> void:
	unit_name = "Builder"
	max_movement = 4
	max_health = 10
	body_color = Color(1.0, 0.78, 0.25)
	can_build = true
	can_harvest = false
