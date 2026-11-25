class_name Apc
extends ArmourUnit
## Armoured personnel carrier: the default armour vehicle. Fires twice a
## round, like all armour (see ArmourUnit).


func _init() -> void:
	super()
	unit_name = "APC"
	short_name = "APC"
	train_turns = 4
	#                    civilian, infantry, armour, air
	damage = damage_vs(6, 3, 3, 2)
	body_color = Color(0.6, 0.68, 0.5)
