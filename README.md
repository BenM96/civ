# Civ (working title)

A turn-based colony strategy game on Mars, played on a hex map. You run one
colony against four computer-controlled rivals: gather resources, build a
supply network, grow your workforce and race to be the first to hold a
**command point on every control point** on the map.

Made with [Godot 4.7](https://godotengine.org/).

## How to play

Each colony starts with a hub and a single Miner. During a turn you give
orders to units waiting at your hub; when you press **End Turn**, every
colony's orders play out at the same time. Units walk out, do their job and
come home on their own.

The top bar shows each resource as its icon and amount, e.g. the Titanium
icon then "5 (+1)" (hover over one for its name), then your command points
(flag) and initiative (lightning bolt).

### Winning and losing

- **Win:** be the first colony with a command point on every control point
  at the end of a turn, each one linked to your hub by conveyor belts (see
  Control points). You can keep playing afterwards.
- **Lose:** your colony has no units left and none in training, or your
  hub is knocked out (see Hub health).
- A rival that loses all its units (with none in training) or its hub
  collapses. Outlast every rival and you also win.

### Teams

Colonies on the same team are allies. You play alone; every computer
colony is on one team against you. Allies never fight each other: their
units share tiles and pass each other without starting a battle, and in a
battle they never shoot each other. They can't capture, demolish or carpet
bomb each other's structures or hubs, and their QRF and interceptors only go
after enemies. A team wins together: the control-point win counts command
points held by any colony on the team (each linked to its own hub).

### Hub health

Every hub has **10 health**. Enemy Infantry can **demolish** a hub: they
stand on a tile next to it (as for a bridge) and each finished demolish (3
turns) knocks 1 health off. At 0 the colony is knocked out and collapses.
A damaged hub shows a health bar on the map; you can repair it in the
Central Hub panel for 10 Titanium and 10 Sediment per health, once a turn.
A banner warns you whenever your hub is hit (and cheers when your Infantry
hit someone else's), and knocking out a rival gets its own popup. QRF units
also go after enemies standing next to your hub.

### Control points

Every map has one **control point** per colony, 5 to 10 tiles from its hub
(and nearer that hub than any other): a gold-ringed tile with a white flag.
To win you need a **Command Point** on all of them - yours and every
rival's.

- Once you've researched **Command Doctrine** (see Research), a Builder
  builds one with **Build Command Point** in Mission Briefing: pick
  a control point and, like an extractor, it lays foundations and conveyor
  belts from the hub out to it, then builds the command point on the end.
  It costs 20 Titanium, 20 Sediment and 20 Gold.
- A command point only counts while it's linked to your hub by belts. Its
  light shows green when it is and red when it isn't. Cutting or capturing
  a belt on the way stops it counting until the link is restored.
- Infantry can **capture** another colony's command point (it then needs
  your belts to count) or **demolish** it, freeing the control point.
- Each linked command point also gives you **+1 initiative**. Initiative
  isn't stored - like biomass, it's worked out each turn from your linked
  command points plus your Initiative techs. In a battle, the colony with
  the most initiative fires first (see Combat).
- The top bar shows how many you hold by the flag icon (e.g. "2/5") and
  your initiative by the lightning bolt.

The computer colonies go for control points once they reach their last phase
(see Units).

### Biomass and starvation

Biomass is food, and it isn't stored: it's a rate. Your **biomass
production** is what your Greenhouses (3 a turn each) and Biomass extractors
(2 a turn each) make, less what your units eat (1 each a turn). The top bar
shows it by the Biomass icon, e.g. "+2/turn".

- You can't train a unit you couldn't feed: Training is blocked while the
  new unit (and any already training) would push production below zero.
- If production does go below zero (say an extractor is captured, demolished
  or runs dry), **one unit starves to death at the end of every turn** until
  it's back to zero or above. The most injured unit goes first (ties at
  random, so healthy ones go at random), and the Miner and Builders only once
  nobody else is left. A popup tells you each time, with how short you are and how to
  fix it.

### Resources

| Resource | Used for |
|---|---|
| Biomass | Feeding your units (production per turn, not stored - see above) |
| Gold | Training units (rising with each military unit), command points |
| Titanium | Training units, conveyor belts, extractors, bridges, hub buildings, command points |
| Sediment | Foundations, extractors, bridges, hub buildings, command points |
| Electrum | Research, specialist units, aircraft |

Every hub has at least one deposit of each resource within 4 tiles (but none
right next to it), except Electrum: its deposits are only found more than
10 tiles from every hub and from each other. The Miner can carry it home 1
a trip, or an extractor at the end of a belt line brings in 0.1 a turn.
Every deposit holds 999, so in practice none ever runs out.

### Research

Open **Research** on the bottom bar (or press R). Every game deals the 42
techs out into **3 tech trees**, shuffled fresh each game but the same for
every colony. Each tree has 2 tier-1 techs, then 2 tier-2, and so on up to
tier 7.

- A tree is researched in order: each tech needs the one before it. The 1st
  tech on a tree costs 1 Electrum, the 2nd costs 2, and so on.
- Some techs also need another tech, on any tree, always from a lower tier
  (e.g. Surgery needs Field Medicine). The panel says what's missing.
- You pay when you start it and it's done at the end of the turn (cancel
  before then for a refund). You can research on all three trees in the same
  turn, but only one tech per tree.
- The panel shows the tech you can research next on each tree, the one after
  it (greyed out), and what you've researched.
- Techs only unlock things - researching Barracks lets you build a Barracks;
  it doesn't build one.

Every tech, tier by tier, with what it does and what it needs, is listed in
[TECHS.md](TECHS.md). That file is generated from the game's tech list -
after changing techs, run:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/generate_tech_doc.gd
```

Each **Workforce** tech raises your Builder limit by 1 (you start limited to
1 Builder, counting any in training). Each **Weapons** tech gives one unit
+1 damage against every type; **Civil Defence** gives every civilian +1
damage against civilians. Each **Initiative** tech (tiers 1, 4 and 6)
adds 1 initiative (see Combat). Techs taken out of the game are kept in
`disabled/` (which Godot ignores) so they can be put back. The computer colonies follow the same rules
and research techs too (see Units).

### Buildings

Buildings live inside your hub rather than on the map. Open **Buildings** on
the bottom bar (or press B) to see what you can build and what your hub
has. Each needs its tech first (see Research). A building is paid for when
you order it and is ready at the end of the turn (you can cancel it before
then for a full refund). Every building costs 5 Sediment and 2 Titanium for
now.

| Building | Tech | Needs | Most | What it does |
|---|---|---|---|---|
| Greenhouse | - | - | 1 (2 with Hydroponics I) | Grows 3 Biomass a turn. Every colony starts with one. |
| Barracks | Barracks | - | 1 | Opens the Barracks room. Needed to train infantry. |
| Garage | Garage | - | 1 | Opens the Garage room. Needed to train armour; repairs damaged armour. |
| Hangar | Hangar | - | 1 | Opens the Hangar room. Needed to train air units. |
| Med Bay | Field Medicine | - | 1 | Opens the Med Bay room, which heals infantry and civilians. |
| Surgical Ward | Surgery | Med Bay | 2 | One more unit heals in the Med Bay at a time. |
| Regen Lab | Regeneration | Med Bay | 2 | Units in the Med Bay heal 1 HP a turn faster. |
| Repair Bay | Vehicle Repair | Garage | 2 | One more vehicle is repaired in the Garage at a time. |
| Machine Shop | Machine Tools | Garage | 2 | Vehicles in the Garage are repaired 1 HP a turn faster. |
| Flight Crew Quarters | Flight Crews | Hangar | 3 | Aircraft refit 1 turn faster after every flight. |

### The central hub's rooms

Every unit at home is in one of the hub's rooms. Open **Central Hub** on the
bottom bar (or press H, or click your hub) to see them, and drag a unit onto
another room to move it there. While you drag, rooms the unit can go to
light up green and the rest get a red cross; the card under the mouse says
what dropping it there would do, or why it can't go there.

The big red **RTB** (return to base) button at the top of the panel calls
everyone home: every unit drops its mission and repeats. Units still waiting
to set out, the QRF and Builders waiting at the hub for resources are stood
down at once (getting back what they were given for the job); units out on
the map turn for home with whatever they carry. Units off duty stay put.

Next to it, **Regroup** gathers the army: every military unit (infantry
and armour) waiting in Mission Briefing, and every one that comes home
afterwards, goes on Regroup - standing by in the QRF room, defending like
the QRF and going off to heal when hurt - until all of them are home and at
full health (hurt units the hub has nowhere to heal count as healed). Units
out on missions finish them first. Then the regroup ends and the whole army
comes to Mission Briefing together. While it runs the button shows how
many are home.

Mission Briefing, the Airlock, the QRF room and the Break Room are open from
the start. The others show a padlock until you build their building.

| Room | What it's for |
|---|---|
| Mission Briefing | Idle units wait here for orders. Only units in Mission Briefing can be given a mission. Units come here when they get home. |
| Airlock | Units given a mission wait here to leave at the end of the turn. Drag one out to call its mission off. |
| Med Bay | Heals injured infantry and civilians (see Healing). Only injured infantry and civilians are allowed in. |
| Quick Reaction Force | Units on QRF duty (or Regroup) stand by here (see Missions). Drag a unit in to put it on QRF duty for 20 turns; drag one out to take it off. |
| Break Room | Off-duty civilian units (Miner, Builders). Civilians in training are shown here. |
| Barracks | The same, for infantry. |
| Hangar | The same, for air units. Aircraft back from any flight refit here for 10 turns (1 less per Flight Crew Quarters) and can't leave until they're done; refitting repairs them fully. Interceptors stand by here too (drag one out to take it off duty). |
| Garage | The same, for armour units. Also repairs damaged armour (see Healing). |

Units only get to the Airlock by being given a mission, and to the QRF
room by being given QRF or Regroup (or dragged in).
Units in the Break Room, Barracks, Hangar or Garage don't need orders, so
idle turns can be skipped. The **Wait** order in Mission Briefing (in a
unit's mission dropdown) sends a unit there for the number of turns picked
in the next dropdown (1, 5, 10 or 20), after which it comes back to Mission
Briefing by itself; INF keeps it there until you drag it out. An injured
unit also gets a **Heal** order, which sends it to the Med Bay (or, for
armour, the Garage) - greyed out, saying why, if that isn't built yet.

### Healing

Injured infantry and civilians heal in the **Med Bay**, and damaged armour is
repaired in the **Garage**. Units that come home hurt go straight there (if
you've built it), and move on to Mission Briefing once fully healed. If you
haven't built one, they go to Mission Briefing and stay hurt.

Only one unit heals at a time, 1 HP a turn; the rest wait their turn. The
ones waiting are listed at the top of the room in healing order. Drag a unit
onto another one in the queue to put it in that place. Surgical Wards
and Repair Bays heal more units at once; Regen Labs and Machine Shops heal
faster. Aircraft are repaired by refitting in the **Hangar** after every
flight (see Missions): they come out of it at full HP.

### Units

Train units from **Training** on the bottom bar. Every unit always costs the
same. Your work is split between two civilians:

- The **Miner** harvests deposits. You start with one and can never have
  more. If it dies, a new one costs no resources (only its biomass), so you
  can never be left with no way to gather anything.
- **Builders** build foundations, bridges, conveyor belts, extractors and
  command points, paying from your stockpile. You start with none and may
  have 1 (raised by the Workforce techs); each costs 1 Gold + 1 Titanium.

Give the Miner a repeating harvest order (see Missions) and it gathers on
its own while your Builders build.

Other units: Infantry cost 1 Gold + 2 Titanium,
armour 1 Gold + 3 Titanium + 2 Sediment and air units 1 Gold + 2 Titanium +
2 Electrum. Specialist units (every infantry, armour or air unit except
Infantry, APC and Chopper) cost 1 Electrum on top. Every military unit
(anything but Miners and Builders) also costs 1 more Gold for each
military unit you've trained before: the 1st Infantry costs 1 Gold, the
2nd 2 Gold, and so on.

Infantry need a Barracks, armour a Garage and air units a Hangar before you
can train them (see Buildings). Infantry, APC and Chopper need only their
building; every other infantry, armour and air unit also needs its own tech
(see Research).

Each unit has a type, which decides its icon's shape, how much damage it
takes, how it moves and fights, and which room it waits in:

| Type | Icon | Special |
|---|---|---|
| Civilian | Circle | - |
| Infantry | Pentagon | - |
| Armour | Square | Fires **twice** each time its turn comes in a battle. Can't capture or demolish. |
| Air | Top-down outline of the aircraft | Flies straight to its target and home again in one turn (see Missions), then refits in the Hangar for 10 turns. Drawn above the ground units on its tile, pointing the way it flies. |

Each ground unit's icon shows its short name, e.g. W, I, AA. Aircraft show no label: each has its own outline - Chopper a helicopter, Fighter a Spitfire, Fighter Bomber a Eurofighter, Bomber a Lancaster.

| Unit | Type | Label | Cost | Turns | Missions |
|---|---|---|---|---|---|
| Miner | Civilian | MI | Free (only 1) | 2 | Harvest |
| Builder | Civilian | BU | 1 Gold, 1 Titanium | 2 | Build |
| Infantry | Infantry | I | 1 Gold, 2 Titanium | 3 | Move, guard, escort, capture, demolish, QRF |
| Assault Infantry | Infantry | AS | 1 Gold, 2 Titanium, 1 Electrum | 3 | As Infantry |
| AT Infantry | Infantry | AT | 1 Gold, 2 Titanium, 1 Electrum | 3 | As Infantry |
| Stinger Infantry | Infantry | ST | 1 Gold, 2 Titanium, 1 Electrum | 3 | As Infantry |
| APC | Armour | APC | 1 Gold, 3 Titanium, 2 Sediment | 4 | Move, guard, escort, QRF |
| Tank Destroyer | Armour | TD | 1 Gold, 3 Titanium, 2 Sediment, 1 Electrum | 5 | As APC |
| Tank | Armour | T | 1 Gold, 3 Titanium, 2 Sediment, 1 Electrum | 5 | As APC |
| Anti-Aircraft Gun | Armour | AA | 1 Gold, 3 Titanium, 2 Sediment, 1 Electrum | 5 | As APC |
| Chopper | Air | CH | 1 Gold, 2 Titanium, 2 Electrum | 4 | Sortie, intercept |
| Fighter | Air | F | 1 Gold, 2 Titanium, 3 Electrum | 5 | Sortie, intercept |
| Fighter Bomber | Air | FB | 1 Gold, 2 Titanium, 3 Electrum | 5 | Sortie, intercept |
| Bomber | Air | B | 1 Gold, 2 Titanium, 3 Electrum | 5 | Carpet bomb |

The computer colonies (`scripts/ai/ai_controller.gd`) build up in phases,
each ending at a milestone, and drop back a phase if they lose what got them
there: first a Miner (if they've lost theirs) and Builders up to their
limit, then a Titanium and a Sediment extractor, then a Gold one, then one
on every deposit within 5 tiles (local production first, as foundations
further out are dear), then an Electrum one - started only once they can
pay for the whole line, the Miner fetching Electrum by hand until then -
then any deposit nearest first. If a rival holds a deposit nearer than the
one they'd build on next, they send Infantry to capture it and then connect
it. In that last phase they research Command Doctrine first and
build a command point on every control point they can reach (and relink
ones they've captured) before going back to extractors. All their
Builders work on one job at a time and the Miner fetches what it's short
of - and once that's covered, Electrum (from the 5-tile phase on).
They only build Biomass extractors while biomass production is below +3,
and Gold extractors only while they hold less than twice what their next
military unit costs in Gold. Alongside, they
train an army to use up their biomass, build what hub buildings they can and research what they can
afford. A third of their army stays home on QRF; the
rest attack together, with armour as escorts: Infantry raid the nearest
rival, demolishing its structures - and sometimes its hub (always once
nothing else is left). They repair their own hub whenever it's damaged.
In the last phase each wave picks at
random between a raid and going for command points - capturing rivals'
command points, or guarding their own when there are none to take.
Half their aircraft (that can intercept) stand by on Intercept; Bombers carpet bomb the nearest rival's structures (or its hub); the rest fly sorties at enemy units.

### Combat

Every unit has 10 HP. Damage per shot depends on the attacker and the
target's type (hover over a unit in Training to see its numbers):

| Attacker | vs Infantry | vs Civilian | vs Armour | vs Air |
|---|---|---|---|---|
| Miner, Builder | 1 | 2 (3 with Civil Defence) | 0 | 0 |
| Infantry | 4 | 6 | 2 | 2 |
| Assault Infantry | 6 | 10 | 5 | 2 |
| AT Infantry | 5 | 7 | 10 | 2 |
| Stinger Infantry | 4 | 5 | 6 | 10 |
| APC (x2 shots) | 4 | 6 | 4 | 2 |
| Tank Destroyer (x2) | 2 | 4 | 8 | 2 |
| Tank (x2) | 6 | 8 | 4 | 2 |
| Anti-Aircraft Gun (x2) | 4 | 6 | 4 | 10 |
| Chopper | 6 | 6 | 6 | 6 |
| Fighter | 6 | 6 | 2 | 10 |
| Fighter Bomber | 6 | 6 | 10 | 6 |
| Bomber | 0 | 0 | 0 | 2 |

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

1. Each colony's units are put in a list in random order - hurt ones too.
   The lists take turns highest **initiative** first (colonies with the same
   initiative go in a random order): the first unit of each list fires,
   then the second of each, and so on.
2. Every unit fires once (armour twice in a row), at an enemy still in the
   fight, picked at random from its preferred targets (see above). A unit hit to 0 HP dies at once; one hit leaving it at or below
   half its HP (5 or less) breaks and flees at once - even one that was
   already there, so a hurt unit fights on until it's hit again. Either way it's out of
   the fight and doesn't get to fire.
3. Units that fled abandon their mission, retreat a tile towards their
   hub, then walk home. Aircraft fly home in the air return phase that turn.

Units still sharing a tile next turn fight another round. Damaged units
show a health bar, and heal in the hub once they get home (see Healing).

After each turn the camera moves to every battle and replays it shot by
shot. **Skip** jumps to the end of one battle; **Skip all battles** skips
the rest for that turn.

### Missions

Open **Mission Briefing** on the bottom bar, pick a mission from a unit's
dropdown, press **Select Target** and click a tile. (Escort, QRF, Intercept, Regroup,
Wait and Heal need no tile: the button says **Give Order**.)

The second dropdown says how many times to do it: 1 (the default), 5, 10,
20 or INF for forever (Guard can't be INF; for QRF, Intercept and Wait it's the
number of turns). Each time the unit is back in Mission Briefing (hurt units
once healed, aircraft once refitted) it's given the same order again at the
end of the turn, and sets out the turn after. If the hub can't pay for it
yet, the unit waits until it can. If the order can't be given any more (e.g.
the deposit is gone), it stops repeating. To stop a unit repeating, press
**Cancel** next to it in **Field** while it's waiting to set out, or use
**RTB** (see The central hub's rooms).

Builders work as a team: when you give one Builder a line job
(foundations, belts, an extractor or a command point), every Builder
waiting in Mission Briefing joins it, and so does any Builder that gets
home or finishes training before it's done - they split the tiles between
them. A bridge order goes to just the Builder you picked.

| Mission | Who | What it does |
|---|---|---|
| Move | Infantry, armour | Walk to a tile, then come home |
| Harvest | Miner | Bring back 1 resource from a deposit |
| Build | Builder | Foundation, bridge, conveyor belt or extractor |
| Guard | Infantry, armour | Hold a tile for 20 turns |
| Escort | Infantry, armour | Follow a unit from the hub wherever it goes, fighting beside it, and come home with it (not aircraft) |
| Capture | Infantry | Take over an enemy extractor, conveyor belt or command point (3 turns on the spot) |
| Demolish | Infantry | Tear down foundations, bridges, belts, extractors or command points (3 turns on the spot), or knock 1 health off an enemy hub from next to it (see Hub health) |
| QRF | Infantry, armour | Stand by in the Quick Reaction Force room and defend your extractors, belts and hub (see below) |
| Regroup | Infantry, armour | Stand by like the QRF until every military unit is home and healed, then the whole army goes to Mission Briefing (see The central hub's rooms) |
| Sortie | Chopper, Fighter, Fighter Bomber | Fly straight to any tile but a hub and fight there (see below) |
| Intercept | Chopper, Fighter, Fighter Bomber | Stand by in the Hangar and fly at enemy aircraft that come into your territory (see below) |
| Carpet Bomb | Bomber | Fly to a tile and flatten everything man-made on it, or knock 1 health off an enemy hub, in one turn (see below) |

**Aircraft.** Aircraft don't walk, and every flight takes one turn. Before
anyone on the ground moves, each aircraft on a sortie or carpet bombing
jumps straight to its target, over anything in between - so it catches
whoever is on that tile at the start of the turn, and they stay to fight. It
starts or joins battles there like anyone else, and enemies that walk onto
it that turn join in. Then interceptors fly (see Intercept), and only then
does everyone on the ground move. After combat comes
the **air return** phase: every aircraft still out flies straight home and
refits in the Hangar for 10 turns (1 less per Flight Crew Quarters), which
repairs it fully. It then goes to Mission Briefing - or, on Intercept duty,
straight back on standby.

In battle, aircraft fire before any ground unit and always shoot enemy
aircraft first. Most ground units do only 2 damage to aircraft; the
Anti-Aircraft Gun and Stinger Infantry do 10. In the battle replay aircraft
fly above their hexes, and ones shot down crash and burn.

**Sortie.** Fly to any tile but a hub and fight whoever is there.

**Intercept.** The air force's QRF: the aircraft stands by in the Hangar for
the turns picked in the second dropdown (INF: until you drag it out). When
enemy aircraft land in your territory (on one of your structures, or on or next to
your hub), interceptors fly at them the same turn: the enemy nearest your
hub first, sending interceptors until you have 2 aircraft there for each of
theirs (counting any of yours already there), then the next. Interceptors
not needed stay on standby.

**Carpet Bomb.** The Bomber's only mission. Pick something man-made or an
enemy hub; if the Bomber comes through the battle there, it flattens
everything man-made on the tile (leaving Rubble, or the Chasm for a bridge)
or knocks 1 health off the hub, in the same turn. Its guns can't hurt ground
units at all, and do only 2 to aircraft.

**QRF (quick reaction force).** QRF units don't move with everyone else.
Once every other unit has finished moving, each QRF unit heads for the
nearest enemy standing on one of your structures (extractors and conveyor
belts; foundations and bridges can't be owned) or right next to your hub,
hoping to start a battle. It picks again every turn, and walks back to the
QRF room once no enemies are left there. It stays on duty for the number
of turns picked in the second dropdown (20 when dragged into the QRF room;
INF until you drag it out), then goes to Mission Briefing - at once if it's
standing by, or once it's back if it's out chasing. A hurt QRF unit
standing by goes to the Med Bay or Garage and comes back on duty once
healed, with the turns it had left; one that breaks in battle does the
same once it's home.

### Building an economy

Harvesting by hand brings back 1 resource per trip (not Biomass - only
extractors get that). For a steady income:

1. Lay **foundations** from your hub out to a deposit, and on the deposit.
   Each costs Sediment by its distance from your hub: 1 within 5 tiles, 5
   within 10, 20 within 20 and 50 beyond - so far-off lines (like the ones
   to Electrum) are a big investment.
2. Build **conveyor belts** on the foundations, including on the deposit.
3. Build an **extractor** on top of the belt on the deposit. A Biomass
   extractor adds 2 to your biomass production while its deposit lasts;
   Titanium, Sediment and Gold extractors deliver 0.2 per turn (1 every 5
   turns) and Electrum ones 0.1 (1 every 10).

Each resource's numbers (deposit sizes, where it appears, what the Miner
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
| H / M / F / T / B / R | Central Hub, Mission Briefing, In the Field, Training, Buildings, Research panels |
| E | Show or hide the event log (also the log button at the right end of the bottom bar) |
| Drag a unit card | Move a unit between the hub's rooms (Central Hub panel) |
| Space | End turn (or Next) |
| Enter | End turn (skips Next) |
| F5 / F9 | Save / load |

**Skip idle turns** (top bar) moves straight on to the next turn while
nothing needs you, and nobody is in enemy territory (your units on a
rival's structures or hub, or theirs on yours). Something needs you when
units are waiting for orders,
when you can train a unit (you can afford it and feed it), when research
has unlocked a new hub building, or when you can afford a research. Then
the End Turn button says **Next**: clicking it (or pressing Space) opens
Mission Briefing, Training, Buildings or Research, in that order. Closing
that panel counts it as dealt with for the rest of the turn (unless
something new turns up), but next turn anything still waiting stops you
again - even if you ended the turn with Enter. A new building only needs
seeing once.

Units waiting in Mission Briefing are a **hard stop**: the turn can't end
(not even with Enter) until each has an order - or Wait, to park it off
duty. Units about to repeat an order don't count.

Some events also stop Skip idle turns and show a banner at the top of the
screen (the full list is in `scripts/game/notices.gd`): your hub being
damaged (or you damaging a rival's), an enemy unit stepping onto one of
your structures (your territory), and an enemy demolishing or capturing
one of your structures. Each banner, and each popup, moves the camera to
where it happened.

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
- Techs are all listed in `scripts/techs/tech_list.gd` (each tier must have
  exactly 6 - see the note at the top); `Player` answers what they unlock
  and raise (`has_tech()`, `get_building_limit()`, `get_builder_limit()`...).
- The hub's rooms each have a file in `scripts/rooms/`, holding what
  happens to the units in them; register new ones in `Room.create_all()`.
- The HUD (`scripts/ui/hud.gd`) is the frame; each bottom-bar panel
  (Central Hub, Mission Briefing, Field, Training, Buildings, Research) has its own
  `*_panel.gd` file, and shared button/box styles live in `ui_style.gd`.
- Saves are JSON in Godot's user folder; each part of the game saves itself
  with `to_dict()` / `load_dict()`.
- The **+50 all (test)** button is for testing only. Search for
  `TESTING ONLY` to find and remove it before release.
