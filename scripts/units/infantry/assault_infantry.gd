class_name AssaultInfantry
extends Infantry
## Infantry built for fighting other infantry: hits them harder. Otherwise
## the same as Infantry.


func _init() -> void:
	super()
	unit_name = "Assault Infantry"
	short_name = "AS"
	add_specialist_cost()
	train_turns = 3
	#                    civilian, infantry, armour, air
	damage = damage_vs(10, 6, 3, 2)
	body_color = Color(0.95, 0.5, 0.35)
