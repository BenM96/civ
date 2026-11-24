## Techs taken out of the game (Godot ignores this folder - see .gdignore).
## To put one back, copy its lines into TechList._create_all() in
## scripts/techs/tech_list.gd, in the tier given, and swap another tech out
## of that tier so every tier keeps exactly 6.
##
## Their ids are unchanged, so old saves that researched them still name
## them (a save that lists an unknown tech just ignores it).

# --- Workforce II (was tier 2): +1 Builder limit --------------------------
# Removed: too many Builder techs.
#	techs.append(_workforce(2, "II"))

# --- Workforce III (was tier 3): +1 Builder limit -------------------------
# Removed: too many Builder techs.
#	techs.append(_workforce(3, "III"))
