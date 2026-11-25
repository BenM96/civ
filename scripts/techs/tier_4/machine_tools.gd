extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Unlocks the Machine Shop (Garage upgrade): vehicles in the Garage are repaired 1 HP a turn faster.


func _init() -> void:
	super("machine_tools", "Machine Tools", "garage")
	unlocks_building = MachineShop.ID
