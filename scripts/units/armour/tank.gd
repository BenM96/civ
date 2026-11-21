class_name Tank
extends ArmourUnit
## Main battle tank: strong against infantry. Fires twice a round (see
## ArmourUnit).


func _init() -> void:
	super()
	unit_name = "Tank"
	short_name = "T"
	cost = {ResourceDeposit.Type.GOLD: 3, ResourceDeposit.Type.TITANIUM: 3}
	train_turns = 5
	#                    infantry, civilian, armour, air
	damage = damage_vs(6, 8, 4, 2)
	body_color = Color(0.6, 0.65, 0.45)
