# Disabled content

Things taken out of the game but kept so they can be put back. Godot ignores
this whole folder (`.gdignore`), so nothing here is loaded.

- `techs/disabled_techs.gd` - removed techs (Workforce II and III), with how
  to restore them.
- `units/guard_unit.gd` - the Guard (civilian security unit). To restore it,
  move it back to `scripts/units/civilian/` and add `GuardUnit` to the
  blueprint list in `Player._init()`.
- `units/worker.gd` - the old shared base class of the Builder and Miner.
  They now extend `Unit` directly, each with its own stats.
