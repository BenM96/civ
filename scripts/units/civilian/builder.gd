class_name Builder
extends Worker
## Builds structures (foundations, bridges, extractors, conveyor belts,
## command points), paying for them from the hub's stockpile. Colonies start
## without one; how many it may have is Player.get_builder_limit(), raised
## by the Workforce techs.

const NAME := "Builder"


func _init() -> void:
	super()
	unit_name = NAME
	short_name = "BU"
	cost = {ResourceDeposit.Type.GOLD: 1, ResourceDeposit.Type.TITANIUM: 1}
	allowed_missions = ["build"]
