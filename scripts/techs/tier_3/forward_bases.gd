extends Tech
## LOCKED: do not move to another tier or change without asking first.
## Lets Builders build FOBs: forts on the belt network where QRF units can be based instead of the hub, while linked to it by belts.


func _init() -> void:
	super("forward_bases", "Forward Bases")
	unlocks_buildable = FobBuildable.ID
