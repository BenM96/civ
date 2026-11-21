class_name Apc
extends ArmourUnit
## Armoured personnel carrier: the default armour vehicle. Fires twice a
## round, like all armour (see ArmourUnit).


func _init() -> void:
	super()
	unit_name = "APC"
	short_name = "APC"
	cost = {ResourceDeposit.Type.GOLD: 2, ResourceDeposit.Type.TITANIUM: 2}
	train_turns = 4
	#                    infantry, civilian, armour, air
	damage = damage_vs(4, 6, 4, 2)
	body_color = Color(0.6, 0.68, 0.5)
