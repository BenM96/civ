# Civ (working title)

A turn-based colony strategy game on Mars, played on a hex map. You run one
colony against four computer-controlled rivals: gather resources, build a
supply network, grow your workforce and race to be the first to stockpile
**50 Unobtainium**.

Made with [Godot 4.7](https://godotengine.org/).

## How to play

Each colony starts with a hub and a single Worker. During a turn you give
orders to units waiting at your hub; when you press **End Turn**, every
colony's orders play out at the same time. Units walk out, do their job and
come home on their own.

### Winning and losing

- **Win:** be the first colony to hold 50 Unobtainium at the end of a turn.
  You can keep playing afterwards.
- **Lose:** your Biomass drops below zero. Every unit eats 1 Biomass a turn and
  your hub grows 3, so more units need more food.
- A rival that starves collapses. Outlast every rival and you also win.

### Resources

| Resource | Used for |
|---|---|
| Biomass | Feeding your units |
| Gold | Training units |
| Titanium | Training units, conveyor belts, extractors, bridges |
| Sediment | Foundations, extractors, bridges |
| Unobtainium | Winning (50 wins the game) |

Every hub has at least one deposit of each resource within 4 tiles (but none
right next to it), except Unobtainium: its deposits are only found more than
10 tiles from every hub and from each other, and it can only be mined with an
extractor connected by belts - Workers can't harvest it by hand.

### Units

Unit costs start at 1 Gold + 1 Titanium and double for each one of that type
you have ever built. Losing units doesn't make the next one cheaper.

- **Worker:** harvests resources by hand and builds structures.
- **Infantry:** moves, guards, captures and demolishes. Fights every enemy
  unit on its tile 1-for-1, Infantry or Worker, and each side loses its
  Infantry before its Workers. Workers never fight each other.

### Missions

Open **Units** on the bottom bar, pick a mission from a unit's dropdown,
press **Select Target** and click a tile.

| Mission | Who | What it does |
|---|---|---|
| Move | Infantry | Walk to a tile, then come home |
| Harvest | Worker | Bring back 1 resource from a deposit |
| Build | Worker | Foundation, bridge, conveyor belt or extractor |
| Guard | Infantry | Hold a tile for 20 turns |
| Escort | Infantry | Follow a unit from the hub wherever it goes, fighting beside it, and come home with it |
| Capture | Infantry | Take over an enemy extractor or conveyor belt |
| Demolish | Infantry | Tear down foundations, bridges, belts or extractors |

### Building an economy

Harvesting by hand brings back 1 resource per trip. For a steady income:

1. Lay **foundations** from your hub out to a deposit, and on the deposit.
2. Build **conveyor belts** on the foundations, including on the deposit.
3. Build an **extractor** on top of the belt on the deposit. A Biomass
   or Unobtainium extractor delivers 1 per turn; Titanium, Sediment and Gold
   extractors deliver 0.2 per turn (1 every 5 turns).

Each resource's numbers (deposit sizes, where it appears, what a Worker
harvests per trip, what an extractor delivers) and its map icon live in its
own file in `scripts/resources/`.

Belts can only go on foundations (or bridges), and extractors only on belts.
Ordering a Build Extractor does all three steps for you.

### Movement

Units have 3 movement points. Open ground costs 3 (one tile a turn);
foundations and bridges cost 1, so foundations triple your speed. Bridges span
chasms.

## Controls

| Key / mouse | Action |
|---|---|
| WASD / arrow keys | Pan the map |
| Mouse wheel | Zoom |
| Left click | Select a target; click your hub to open it |
| Right click / Esc | Cancel targeting |
| U / F / T | Units, In the Field, Training panels |
| Enter | End turn |
| F5 / F9 | Save / load |

**Skip idle turns** (top bar) moves straight on when every unit is already
busy.

## Running the game

Open the project folder in Godot 4.7 and press Play (F5 in the editor).

## For developers

- `scripts/game/turn_manager.gd` lists everything that happens in a turn, in
  order.
- Every action, human or AI, is an order sent through
  `scripts/game/orders.gd`.
- Each unit and structure keeps all of its data in its own file under
  `scripts/units/` and `scripts/structures/`.
- Saves are JSON in Godot's user folder; each part of the game saves itself
  with `to_dict()` / `load_dict()`.
- The **+50 all (test)** button is for testing only. Search for
  `TESTING ONLY` to find and remove it before release.
