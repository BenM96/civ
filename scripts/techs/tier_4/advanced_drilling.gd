extends Tech
## FLEXIBLE: can be moved to another tier or used as filler without asking.
## Titanium, Sediment and Gold extractors deliver 0.1 more a turn.


func _init() -> void:
	super("advanced_drilling", "Advanced Drilling")
	for type in [ResourceDeposit.Type.TITANIUM, ResourceDeposit.Type.SEDIMENT, ResourceDeposit.Type.GOLD]:
		extractor_bonus[type] = 0.1
