class_name AntiAircraftGun
extends ArmourUnit
## Mobile anti-aircraft gun: strong against air units. Fires twice a round
## (see ArmourUnit).


func _init() -> void:
	super()
	unit_name = "Anti-Aircraft Gun"
	short_name = "AA"
	add_specialist_cost()
	train_turns = 5
	#                    civilian, infantry, armour, air
	damage = damage_vs(6, 3, 3, 10)
	body_color = Color(0.7, 0.72, 0.55)
