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
- **Lose:** your colony has no units left and none in training.
- A rival with no units left (and none in training) collapses. Outlast every
  rival and you also win.

### Biomass and starvation

Biomass is food, and it isn't stored: it's a rate. Your **biomass
production** is what your Greenhouses (3 a turn each) and Biomass extractors
(1 a turn each) make, less what your units eat (1 each a turn). The top bar
shows it, e.g. "Biomass: +2 a turn".

- You can't train a unit you couldn't feed: Training is blocked while the
  new unit (and any already training) would push production below zero.
- If production does go below zero (say an extractor is captured, demolished
  or runs dry), **one unit starves to death at the end of every turn** until
  it's back to zero or above. The most injured unit goes first (ties at
  random, so healthy ones go at random), and Workers only once nobody else
  is left. A popup tells you each time, with how short you are and how to
  fix it.

### Resources

| Resource | Used for |
|---|---|
| Biomass | Feeding your units (production per turn, not stored - see above) |
| Gold | Training units |
| Titanium | Training units, conveyor belts, extractors, bridges |
| Sediment | Foundations, extractors, bridges |
| Unobtainium | Winning (50 wins the game) |

Every hub has at least one deposit of each resource within 4 tiles (but none
right next to it), except Unobtainium: its deposits are only found more than
10 tiles from every hub and from each other, and it can only be mined with an
extractor connected by belts - Workers can't harvest it by hand.

### Buildings

Buildings live inside your hub rather than on the map. Open **Buildings** on
the bottom bar (or press B) to see what you can build and what your hub
has. A building is paid for when you order it and is ready at the end of
the turn (you can cancel it before then for a full refund). Every building
costs 5 Sediment and 2 Titanium for now.

| Building | Needs | Most | What it does |
|---|---|---|---|
| Greenhouse | - | 3 | Grows 3 Biomass a turn. Every colony starts with one. |
| Barracks | - | 1 | Opens the Barracks room. Needed to train infantry. |
| Garage | - | 1 | Opens the Garage room. Needed to train armour; repairs damaged armour. |
| Hangar | - | 1 | Opens the Hangar room. Needed to train air units. |
| Med Bay | - | 1 | Opens the Med Bay room, which heals infantry and civilians. |
| Surgical Ward | Med Bay | 2 | One more unit heals in the Med Bay at a time. |
| Regen Lab | Med Bay | 2 | Units in the Med Bay heal 1 HP a turn faster. |
| Repair Bay | Garage | 2 | One more vehicle is repaired in the Garage at a time. |
| Machine Shop | Garage | 2 | Vehicles in the Garage are repaired 1 HP a turn faster. |
| Flight Crew Quarters | Hangar | 3 | Aircraft refit 1 turn faster after a sortie. |

### The central hub's rooms

Every unit at home is in one of the hub's rooms. Open **Central Hub** on the
bottom bar (or press H, or click your hub) to see them, and drag a unit onto
another room to move it there. While you drag, rooms the unit can go to
light up green and the rest get a red cross; the card under the mouse says
what dropping it there would do, or why it can't go there.

Mission Briefing, the Airlock, the QRF room and the Break Room are open from
the start. The others show a padlock until you build their building.

| Room | What it's for |
|---|---|
| Mission Briefing | Idle units wait here for orders. Only units in Mission Briefing can be given a mission. Units come here when they get home. |
| Airlock | Units given a mission wait here to leave at the end of the turn. Drag one out to call its mission off. |
| Med Bay | Heals injured infantry and civilians (see Healing). Only injured infantry and civilians are allowed in. |
| Quick Reaction Force | Units on the QRF mission stand by here (see Missions). Drag one out to take it off QRF duty. |
| Break Room | Off-duty civilian units (Workers). Workers in training are shown here. |
| Barracks | The same, for infantry. |
| Hangar | The same, for air units. Aircraft back from a sortie refit here for 10 turns (less with Flight Crew Quarters) and can't leave until they're done. |
| Garage | The same, for armour units. Also repairs damaged armour (see Healing). |

Units only get to the Airlock and the QRF room by being given a mission.
Units in the Break Room, Barracks, Hangar or Garage don't need orders, so
idle turns can be skipped; the **Wait** button in Mission Briefing sends a
unit there.

### Healing

Injured infantry and civilians heal in the **Med Bay**, and damaged armour is
repaired in the **Garage**. Units that come home hurt go straight there (if
you've built it), and move on to Mission Briefing once fully healed. If you
haven't built one, they go to Mission Briefing and stay hurt.

Only one unit heals at a time, 1 HP a turn; the rest wait their turn. The
ones waiting are listed at the top of the room in healing order. Drag a unit
onto another one in the queue to put it in that place. Surgical Wards
and Repair Bays heal more units at once; Regen Labs and Machine Shops heal
faster. Aircraft are repaired by refitting in the Hangar.

### Units

Train units from **Training** on the bottom bar. Each Worker you build
doubles the price of the next; every other unit adds 1 of each resource to
the price of the next of its kind (Infantry: 1 Gold + 1 Titanium, then
2 + 2, 3 + 3...). Every unit you have ever built counts. Losing units
doesn't make the next one cheaper. Infantry need a Barracks, armour a Garage
and air units a Hangar before you can train them (see Buildings).

Each unit has a type, which decides its icon's shape, how much damage it
takes, how it moves and fights, and which room it waits in:

| Type | Icon | Special |
|---|---|---|
| Civilian | Circle | - |
| Infantry | Pentagon | - |
| Armour | Square | Fires **twice** each time its turn comes in a battle. Can't capture or demolish. |
| Air | Triangle | Only flies **sorties** (see Missions), then refits in the Hangar for 10 turns. |

Each icon shows the unit's short name, e.g. W, I, AA.

| Unit | Type | Label | Cost (first one) | Turns | Missions |
|---|---|---|---|---|---|
| Worker | Civilian | W | 1 Gold, 1 Titanium | 2 | Harvest, build |
| Guard | Civilian | G | 1 Gold, 1 Titanium | 2 | Move, guard, QRF |
| Infantry | Infantry | I | 1 Gold, 1 Titanium | 3 | Move, guard, escort, capture, demolish, QRF |
| Assault Infantry | Infantry | AS | 2 Gold, 1 Titanium | 3 | As Infantry |
| AT Infantry | Infantry | AT | 2 Gold, 1 Titanium | 3 | As Infantry |
| Stinger Infantry | Infantry | ST | 2 Gold, 1 Titanium | 3 | As Infantry |
| APC | Armour | APC | 2 Gold, 2 Titanium | 4 | Move, guard, escort, QRF |
| Tank Destroyer | Armour | TD | 3 Gold, 3 Titanium | 5 | As APC |
| Tank | Armour | T | 3 Gold, 3 Titanium | 5 | As APC |
| Anti-Aircraft Gun | Armour | AA | 3 Gold, 3 Titanium | 5 | As APC |
| Chopper | Air | CH | 2 Gold, 3 Titanium | 4 | Sortie |
| Fighter | Air | F | 3 Gold, 3 Titanium | 5 | Sortie |
| Bomber | Air | B | 3 Gold, 4 Titanium | 5 | Sortie |

The computer colonies only train Workers and Infantry for now. Once they
have 3 Workers they build a Barracks, then a Med Bay; when they're short of
biomass to grow they build more Greenhouses.

### Combat

Every unit has 10 HP. Damage per shot depends on the attacker and the
target's type (hover over a unit in Training to see its numbers):

| Attacker | vs Infantry | vs Civilian | vs Armour | vs Air |
|---|---|---|---|---|
| Worker | 1 | 3 | 0 | 0 |
| Guard | 3 | 4 | 0 | 0 |
| Infantry | 4 | 5 | 2 | 2 |
| Assault Infantry | 6 | 10 | 5 | 5 |
| AT Infantry | 5 | 7 | 10 | 3 |
| Stinger Infantry | 4 | 5 | 6 | 4 |
| APC (x2 shots) | 4 | 6 | 4 | 2 |
| Tank Destroyer (x2) | 2 | 4 | 8 | 1 |
| Tank (x2) | 6 | 8 | 4 | 2 |
| Anti-Aircraft Gun (x2) | 4 | 6 | 4 | 8 |
| Chopper | 4 | 4 | 4 | 4 |
| Fighter | 2 | 3 | 2 | 8 |
| Bomber | 7 | 7 | 7 | 1 |

**Preferred targets.** Each unit would rather shoot the type it does the
most damage to: if any enemy of that type is in the fight it shoots one of
them at random, otherwise the type it does the next most damage to, and so
on. Types it does equal damage to are equally preferred. Civilians always
come last, whatever the damage, so fighting units only shoot civilians when
nothing else is left. The Training tooltips show each unit's order
("Shoots first: ...").

A battle starts when units of different colonies end up on the same tile,
try to walk past each other, or start a turn on the same tile. The battle
takes in those tiles and every tile around them: every unit standing in that
area joins in (units at their own hub stay safe), and battles whose areas
overlap become one. Everyone in it stops for the turn, and one round is
fought:

1. Units already below half their HP (under 5) flee straight away.
2. Each colony's other units are put in a list in random order, and the
   lists take turns in a random order: the first unit of each list fires,
   then the second of each, and so on.
3. Every unit fires once (armour twice in a row), at an enemy still in the
   fight, picked at random from its preferred targets (see above). A unit hit to 0 HP dies at once; one hit below half its
   HP breaks and flees at once. Either way it's out of the fight and
   doesn't get to fire.
4. Units that fled abandon their mission, retreat a tile towards their
   hub, then walk home. Aircraft fly home at the start of the next turn.

Units still sharing a tile next turn fight another round. Damaged units
show a health bar, and heal in the hub once they get home (see Healing).

After each turn the camera moves to every battle and replays it shot by
shot. **Skip** jumps to the end of one battle; **Skip all battles** skips
the rest for that turn.

### Missions

Open **Mission Briefing** on the bottom bar, pick a mission from a unit's
dropdown, press **Select Target** and click a tile. (Escort and QRF need no
tile: the button says **Give Order**.)

| Mission | Who | What it does |
|---|---|---|
| Move | Guard, infantry, armour | Walk to a tile, then come home |
| Harvest | Worker | Bring back 1 resource from a deposit |
| Build | Worker | Foundation, bridge, conveyor belt or extractor |
| Guard | Guard, infantry, armour | Hold a tile for 20 turns |
| Escort | Infantry, armour | Follow a unit from the hub wherever it goes, fighting beside it, and come home with it (not aircraft) |
| Capture | Infantry | Take over an enemy extractor or conveyor belt |
| Demolish | Infantry | Tear down foundations, bridges, belts or extractors |
| QRF | Guard, infantry, armour | Stand by in the Quick Reaction Force room and defend your extractors and belts (see below) |
| Sortie | Air | Fly straight to any tile but a hub and fight there (see below) |

**Sortie.** Aircraft don't walk. Once every other unit has moved (the QRF
included), each aircraft on a sortie jumps straight to its target, over
anything in between, and starts or joins battles there like anyone else.
At the start of the next turn it flies straight home, and refits in the
Hangar for 10 turns, which also repairs it. It then goes to Mission
Briefing, ready for another sortie.

**QRF (quick reaction force).** QRF units don't move with everyone else.
Once every other unit has finished moving, each QRF unit heads for the
nearest enemy standing on one of your structures (extractors and conveyor
belts; foundations and bridges can't be owned), hoping to start a battle.
It picks again every turn, and walks back to the QRF room once no enemies
are left on your structures. It stays on duty until you drag it out of the
QRF room. If it breaks in battle, it drops QRF duty and comes home.

### Building an economy

Harvesting by hand brings back 1 resource per trip (not Biomass or
Unobtainium - only extractors get those). For a steady income:

1. Lay **foundations** from your hub out to a deposit, and on the deposit.
2. Build **conveyor belts** on the foundations, including on the deposit.
3. Build an **extractor** on top of the belt on the deposit. A Biomass
   extractor adds 1 to your biomass production while its deposit lasts; an
   Unobtainium extractor delivers 1 per turn; Titanium, Sediment and Gold
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
| H / M / F / T / B | Central Hub, Mission Briefing, In the Field, Training, Buildings panels |
| Drag a unit card | Move a unit between the hub's rooms (Central Hub panel) |
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
- Each player (human or AI) is a `Player` (`scripts/core/player.gd`): its
  hub, stockpile, units, training and buildings all live there.
- Each unit and structure keeps all of its data in its own file under
  `scripts/units/` and `scripts/structures/`. Units are in a folder per
  type (`scripts/units/civilian/`, `infantry/`, `armour/`, `air/`); the
  shared `Unit` base is `scripts/units/unit.gd`, and armour and air units
  also share `armour/armour_unit.gd` / `air/air_unit.gd`. Register new
  units in the list in `Player._init()`.
- Buildings inside the hub (e.g. the Greenhouse) each have a file in
  `scripts/buildings/`; register new ones in `Building.create_all()`.
- The hub's rooms each have a file in `scripts/rooms/`, holding what
  happens to the units in them; register new ones in `Room.create_all()`.
- The HUD (`scripts/ui/hud.gd`) is the frame; each bottom-bar panel
  (Central Hub, Mission Briefing, Field, Training, Buildings) has its own
  `*_panel.gd` file, and shared button/box styles live in `ui_style.gd`.
- Saves are JSON in Godot's user folder; each part of the game saves itself
  with `to_dict()` / `load_dict()`.
- The **+50 all (test)** button is for testing only. Search for
  `TESTING ONLY` to find and remove it before release.
