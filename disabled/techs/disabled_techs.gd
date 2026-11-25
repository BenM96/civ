## Techs taken out of the game (Godot ignores this folder - see .gdignore).
## To put one back, make a file for it in scripts/techs/tier_N/ (copy any
## tech there and set its fields), and swap another tech out of that tier so
## every tier keeps exactly 6.
##
## Their ids are unchanged, so old saves that researched them still name
## them (a save that lists an unknown tech just ignores it).

# --- Workforce II (was tier 2): +1 Builder limit --------------------------
# Removed: too many Builder techs.
#	techs.append(_workforce(2, "II"))

# --- Workforce III (was tier 3): +1 Builder limit -------------------------
# Removed: too many Builder techs.
#	techs.append(_workforce(3, "III"))

# --- Per-unit Weapons techs (were tiers 5-7): one unit +1 damage to everything
# Removed: replaced by Infantry, Armour and Air Weapons (whole unit type, T5).
# They used Tech.damage_bonus_unit, which no longer exists; to bring one back,
# use type_damage_attacker/type_damage_bonus or re-add that field.
#	infantry_weapons (Infantry, T5), apc_weapons (APC, T5),
#	chopper_weapons (Chopper, T5), assault_weapons (Assault Infantry, T6),
#	at_weapons (AT Infantry, T6), stinger_weapons (Stinger Infantry, T6),
#	td_weapons (Tank Destroyer, T6), tank_guns (Tank, T7),
#	flak_guns (Anti-Aircraft Gun, T7), fighter_weapons (Fighter, T7),
#	bomber_weapons (Bomber, T7)
