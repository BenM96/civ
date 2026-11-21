class_name AssaultInfantry
extends Infantry
## Infantry built for fighting other infantry: hits them harder. Otherwise
## the same as Infantry.


func _init() -> void:
	super()
	unit_name = "Assault Infantry"
	short_name = "AS"
	cost = {ResourceDeposit.Type.GOLD: 2, ResourceDeposit.Type.TITANIUM: 1}
	train_turns = 3
	#                    infantry, civilian, armour, air
	damage = damage_vs(6, 10, 5, 5)
	body_color = Color(0.95, 0.5, 0.35)
