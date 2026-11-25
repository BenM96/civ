extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Unlocks the Repair Bay (Garage upgrade): one more vehicle is repaired in the Garage at a time.


func _init() -> void:
	super("vehicle_repair", "Vehicle Repair", "garage")
	unlocks_building = RepairBay.ID
