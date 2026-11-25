extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Electrum and Biomass extractors deliver 0.1 more a turn.


func _init() -> void:
	super("electrum_drilling", "Electrum Drilling")
	extractor_bonus = {ResourceDeposit.Type.ELECTRUM: 0.1, ResourceDeposit.Type.BIOMASS: 0.1}
