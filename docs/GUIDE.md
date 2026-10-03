# Pinecraft

A single-player 3D sandbox/tycoon in the spirit of Oaklands: fell trees, haul
logs, process them at machines, sell for money, upgrade your tools, build a
factory on your plot and then let conveyors do the walking.

**Engine:** Godot 4.4 with Jolt Physics (`physics/3d/physics_engine = "Jolt Physics"`).
Single-player only. Primitive shapes, no third-party assets.

## Running

```bash
godot --path .                                               # play
godot --headless --path . --fixed-fps 60 scenes/tests.tscn   # integration tests
godot --headless --path . --fixed-fps 60 scenes/bench.tscn   # physics benchmark
godot --headless --path . --fixed-fps 60 scenes/smoke_world.tscn  # boot the real world headless
godot --path . scenes/boot_time.tscn -- --map=ostars         # time the loading screen
godot --path . scenes/stress_test.tscn                       # physics playground
```

If you add a new script with a `class_name`, run
`godot --headless --editor --quit --path .` once so the global class cache picks
it up; headless runs resolve class names from that cache.

### Loading

The world is built behind the loading screen (`scripts/ui/Boot.gd`), in
stages. The slow sums - the land's heights, its plates and their welding, the
forests' stands, the prospecting and the cave plan - run on worker threads
(`scripts/core/Workers.gd`), split over every core but a quarter of them, so
the rest of the computer stays usable; and the loading screen goes on drawing
meanwhile (capped at 60 frames a second), so the window never locks up.

Two things are kept between loads, per map: the land (heights, rivers, roads,
cave mouths) in `user://terrain_cache*.bin`, and the cave plan (every cavern
and tunnel) in `user://cave_plan*.bin`. The first load after the land or the
game changes works them out again, which is the slow load; after that they
are read back. The cave plan is keyed on the land, the game's version and
CaveNetwork's own source, so a new build always plans afresh once. Set
`PROFILE_LOAD=1` to print how long each stage takes; `scenes/boot_time.tscn`
runs the real loading screen and says how long the world took and the longest
the screen went without drawing.

### Controls

The game opens on a title screen over a flyover of the valley: **Continue**
picks up the newest save (it tells you the slot, day, money and when it was
saved), **Load Game** lists every save slot, **New Game** asks which map
(Pinecraft Isles or Ostars - see [The maps](#the-maps)) and which slot to
start in, and Settings and Controls are there before you play. The full list
of keys is on the Controls page and in the journal (F1), and the few that
matter right now are always in the bottom-right corner.

**Every key can be rebound**: Settings > Controls lists every action - click
one and press the key or mouse button you want (+ adds a second key, x clears
it) - or edit the `[controls]` section of your config file (below). Prompts,
hints and the controls sheet all draw whatever key does the job now. The
defaults:

| Key | Action |
| --- | --- |
| WASD / Shift / Space | move, sprint, jump |
| F2 | first or third person: look out of his eyes or over his shoulder (remembered) |
| 1-9 / Wheel | take a tool off the hotbar (the same number again puts it away) |
| LMB, empty hand | hold to drag what you aim at, by the point you grabbed; heave a chunk out of the ground |
| Wheel (dragging) / RMB (dragging) | pull it closer or push it away / throw it |
| LMB, axe / hammer | cut the limb under the crosshair or buck felled wood / crack a chunk |
| RMB | pick a piece onto the carry rack (the crosshair looks past what is on it) |
| I | inventory: drag tools onto the hotbar |
| Q / G | drop one / drop everything |
| E | deposit, open a paid box, talk to the shopkeep, stop or start a belt |
| R (at a machine) | change the size of what it makes |
| Shift+E | empty a storage bin back onto the ground |
| B | build mode (freecam: WASD, mouse, Shift/Ctrl for height) - you start empty-handed |
| E (build) | the build menu: click what to build |
| MMB (build) | copy the building you aim at - same thing, size, tier and turn |
| Wheel / 1-7 (build) | step through / pick from the build bar |
| Z / X / C (build) | rotate the ghost about each axis, in quarter turns |
| LMB / RMB (build) | place / remove |
| F (build) | select the building you aim at for editing (again to finish) |
| 1 / 2 / 3, drag a handle (editing) | move / scale / rotate it; Del removes |
| Esc | pause menu (closes the build menu, journal or build mode first) |
| Tab / M / P / U / F1 | journal: orders / map / market / upgrades / controls |
| H / F3 | hide the key hints and the crane banner / debug readout |
| F5 / F9 / F8 | quick save / quick load (the slot being played) / new game (asks first) |
| F at a vehicle / F in it | get in (third-person while driving) / get out |
| Shift / Ctrl (driving, manual gearbox) | gear up / down |
| Y | winch: hook the line on whatever you aim at, or unhook it - from the seat or standing by the truck; it snaps to a log, chunk or tree near the crosshair |
| K / L | winch: reel in / let out (G still reels in the seat) |
| O | outriggers out or in - the truck is locked where it stands (seated or standing by it) |
| R (driving) | crane: work it (the truck goes down on its outriggers) or stow it |
| WASD / Shift, Ctrl / Q, E (crane) | move the log away/toward and left/right of the camera, up and down, turn it |
| F (crane) | drop the claw: it goes down until it meets something, grabs and comes back up (again: let go) |
| RMB held (crane) | fine, slow control; without it the crane runs at a brisk pace |
| Shift / Ctrl, Q / E, Space (loader) | arms up / down, tip / curl, lock the load |
| G (loader) | swap the bucket for the log grapple (empty) |
| N | crane or loader back to its starting pose |
| X / Z / C (not in build mode) | unload all (the dump truck tips its tub) / drop one / recover (once a second, not on outriggers) |
| T | hitch a trailer behind the truck, or let it go |

## Interface

- **Title screen** over the live world, with a camera circling the valley.
  New Game rebuilds the scene from nothing rather than scrubbing the old one.
- **Pause menu** (Esc, or alt-tab) over frosted glass: resume, settings,
  controls, save, load, back to the title, quit. Leaving for the title or
  quitting saves; so does closing the window.
- **Settings and controls** live in one **personal config file**,
  `user://config.cfg` (on Windows `%APPDATA%/Godot/app_userdata/Pinecraft/`),
  kept apart from the saves so a new game keeps them. Every line has a comment
  saying what it is, so it can be edited by hand as easily as from the
  Settings screen, which has buttons to open its folder and to read it again.
  In it: mouse sensitivity, invert Y, field of view, manual gearbox; fullscreen,
  v-sync, render scale, shadows, ambient occlusion, bloom, view distance, and
  whether the sun moves; interface scale, key hints, the crane/winch banner,
  compass, checklist, frame rate, name labels over buildings; autosave; and
  every key binding. (An old `settings.cfg` is read once if there is no
  config file yet.)
- **Save slots**: six (`user://saves/slot_N.json`). The game plays in one;
  saves, quick saves and autosaves go to it. The pause menu's Save slots page
  saves into any slot, loads another (saving this one first) or clears one;
  the title screen loads any slot or starts a new game in one. The old single
  save moves into slot 1.
- **Version**: the version number and release date are on the pause menu and
  the title screen, from `application/config/version` and
  `application/config/release_date` in project.godot - bump them there.
- **HUD**: money that counts up, with the change floating off it; the day and
  how long until prices move; the carry rack as a bar; a compass with the plot,
  the sell yard, the store, the quarry and your truck on it; the open orders
  with progress bars; the prompt for what you are aiming at, with its keys drawn
  as keycaps; a feed of what just happened (a yard of fifty logs is one line,
  not fifty); and the keys for what you are doing now.
- **Build menu and bar**: build mode opens empty-handed. The build menu (E)
  shows everything you can put up, in sections - belts, machines, storage,
  pads, plans, doodads - with its size and what it costs or how many copies
  are left; click one to take it in hand. The bar along the bottom is the same
  list a page at a time, with a line on what the thing in hand is for and why
  the ghost will not go where you are pointing. The pad's grid brightens, with
  the quarter-metre snapping grid showing up close.
- **Driving**: speed, cargo and gear; the crane, winch or loader controls sit
  in a banner over the gauges (hidden with H or in Settings > Interface).
- **Journal**: orders, a map of the island (every place you have found, a "?"
  for the rest, your truck and you), today's market with each price's move,
  upgrade tracks and what is still on the shelf, and the controls.
- **Getting started**: a checklist from felling a first tree to filling a first
  order. It watches what you actually do, and a later step ticks off the ones
  before it, so a loaded game with a sawmill is not asked to chop a tree.

The look is one theme built in code (`UITheme`): Rubik for text and Lilita One
for the logo and big numbers (both SIL OFL, in `assets/fonts/`), dark glass
panels, amber for focus and selection. The world got the same pass: a blue
procedural sky, filmic tone mapping, haze the colour of the horizon, a sun
that crosses the sky over a market day (it never sets), and a concrete pad with
its cell grid and a hazard-striped edge.

## The loop

1. **Cut** a tree apart cylinder by cylinder. There is no tree health bar: every
   branch and the trunk has its own collider and its own accumulated axe work,
   and a swing lands on whichever limb is under the crosshair. Take a branch and
   the tree keeps standing; cut the trunk and it parts *at the height of the
   cut*, so what is above falls with the branches that were on it and what is
   below is a shorter tree you can cut again.
2. **Buck** the felled length down. Each cut halves a piece, and the work scales
   with the cross-section at the cut, so a fat trunk is several swings and a
   branch is one. You are cutting it down to something that will go through a
   machine's mouth, or that you can lift.
3. **Work ore out of the ground.** A chunk is part buried, and the pull to take
   it whole is its own weight plus the buried share of that weight again - small
   ones come out on a heave, big ones will not come at all. The other way is the
   hammer: every blow opens a crack somewhere random or drives a nearby one
   deeper, and when a crack goes through, the piece on its near side breaks off
   while the rest settles further in. A heavier head cracks deeper. A crusher
   does the same job to whole chunks, much faster.
4. **Move it.** With nothing in your hand, hold the left button on a piece and
   it comes with you *by the point you grabbed* - a log taken by one end swings
   from that end. You can drag and lift up to a tonne; past that you need a
   truck's winch or its crane. A full rack slows you down, which is the reason
   to build belts. The hauler's bed has tall sides, a cab guard and a
   tailgate; what you put in it is a real, loose load, so drive accordingly.
5. **Process.** Machines are tunnels on a belt, like a curing oven on a line:
   a piece rides in one mouth, is changed in the middle behind strip curtains
   and its own sawdust, steam or sparks, and rides out of the other mouth on
   the same belt. Wood: fell > buck to size > **Sander** > **Planker**, which
   makes *one* plank from a log - as long as the log, 1.8 radii wide, 0.8
   thick. Ore: **Crusher** > **Smelter** (one bar per lump) > **Refiner**.
   Stone (quartz, jade, emerald, diamond...): **Sander** (polished) > **Gem
   Cutter**, which facets a rough stone into one jewel. Every material has a
   raw, a first-step and a final value, and most gain along the way - but not
   all, and not evenly (see *Materials*). The finish is kept through cutting,
   planking and saving. A tunnel mouth is a real opening: a trunk too
   big for it jams on the bulkhead until you buck it or buy a higher tier
   (T2 and T3 widen the mouth and speed the belt). Chained on belts, the
   machines keep up with each other: tunnel belts run at belt speed (3 m/s),
   yellow guide wings on each in-feed steer an off-centre piece into the
   mouth, the walls are slick steel, the crusher lays its lumps out one deep
   in two staggered lanes, and the smelter lays its bars flat down the belt.

   **Demo lines** (Settings > Game > Debug) put an automated ore line
   (hopper > Crusher > Smelter > Refiner) and stone line (hopper > Sander >
   Gem Cutter) on a slab about 190 m south of home, on the compass as "Demo
   Lines". Hoppers drop a mix from tin to starmetal and quartz to diamond; a
   sign over each machine shows the last piece it made and its price, and a
   board at the end of each line keeps running totals of value in and out.
   Finished pieces stay on show for 25 s, then clear. Nothing is saved.
6. **Sell** at the yard - there is no selling from the plot, so the wood has to
   make the trip. Drop material inside the fence, walk up to the shopkeep
   and ask; everything of yours in the yard is bought at once at the day's rate,
   with whatever is still in your arms going over the counter with it. Standing
   orders pay a bonus on top for a volume of a named material.
7. **Buy** at the store, which is a shop you walk into, laid out in sections -
   Tools, Vehicles, Conveyors, Machinery, Gear and Doodads - each a bay with a
   big sign and a stepped shelf. Every box has a picture of what is inside
   printed on it (the real model, rendered in white on the section colour),
   its name and price, and machine tiers wear T1 / T2 / T3 in orange, grey and
   blue. Drag what you want to the counter and the till charges for it; an
   unpaid box carried out of the door goes back on its shelf. A paid box is
   yours to open wherever you like: a tool goes into your inventory and onto
   the hotbar, and a machine, vehicle pad, belt or doodad box is **one copy**
   of it to build, free, at the tier on the box. Want two sanders? Buy two
   boxes. A T2 box is a T2 machine only - it does not bring a T1 with it -
   and taking a building down puts the copy back. Tiers can be bought in any
   order. Land is sold at the desk. **Summit Outfitters**, a long drive
   up into the high country, sells the pro tools, the heavy trucks, the top
   machine tiers, the refiner and the fancier doodads.
8. **Build.** Machines and belts go on the plot grid, which snaps to a
   quarter of a metre (sixteen steps to each square; buildings are still sized
   in whole metres). Build mode starts with nothing in hand: choose from the
   build menu, or aim at something already built and copy it (MMB) - same
   thing, size, tier and turn. Plain belts, splitters, bins and the first
   sawmill are paid for as you place them; store-bought things use up the
   copies you bought. Structures are free plans built out of *material*: place
   a translucent plan, touch material to it, and it fills. A plan takes a tenth
   of its own volume in material (`build.material_share`) - it is framed and
   faced, not cast solid. The first piece decides what the shape is made of and
   nothing else will go in after that; full, it turns solid and takes the
   material's colour. The models speak for themselves now: floating name
   labels over buildings are off unless you turn them on (Settings > Interface).
9. **Automate**: belts run into and out of the machine tunnels, ramps climb,
   long and wide belts come in the store, splitters fan output three ways,
   filters sort by type, belts can be stopped and storage buffers the surplus.
   Borderless belts run right to the edge of their grid square with no steel
   channel down the sides, so several laid side by side make one wide deck.
   Aim at a tunnel machine and press **R** to change the size of what it makes:
   one wide plank, 2 or 4 boards; one bar, 2 or 4; whole, halved or quartered
   refined bars; 1, 2 or 4 jewels; coarse, medium or fine crusher lumps. The
   volume is the same whichever; only the pieces change.
   In build mode, **F** selects a placed building and gives it handles: move
   it (blue diamonds; up and down in quarter metres), scale it (belts stretch
   up to 16 m and widen, plans and doodads grow) or rotate it (a ring round
   each axis). Doodads - fences, lamps, benches, planters, flags, a gnome, and
   up the mountain a golden statue, a fountain and a crystal beacon - are just
   for looks.

## The maps

There are two, picked on the New Game page; each save slot remembers its own,
and a co-op guest builds whichever the host is playing.

- **Pinecraft Isles** - the home island and five more, with the town, the
  sell yard, the quarry, outposts, roads and bridges. Everything below
  [Ostars](#ostars) describes this one.
- **Ostars, the Known Continent** - drawn after the owner's map, with its own
  forests, ore by how hard the country is, and three traders instead of one
  sell yard.

### Ostars

One big continent in the same 4.8 km square of sea (`scripts/world/Ostars.gd`
is the terrain's *shaper*: it gives the biome and height at any point, and
Terrain carves the rivers, the crater and the caves into that as usual). Home
- the plot - is in the Silverflow Meadows in the middle, where it always is.

| Where | What |
|---|---|
| North | The **Frostpeak Wilds** (snow crags, the Frostpeak range) and the **Frostpeak Tundra**: flat snowfields with frozen lakes (the new ICE biome - flat, nothing grows) |
| Across the north | The **Avalanche Mountains**, snow-capped, over 200 m, with two passes through |
| West | **Sylvenwood** (thick woods), the **Silverflow River** past home down to **Halyon Port**, **Mt. Orodruin** on the coast - a 250 m cone of ash (the new ASH biome) with a lava lake smoking in its crater - and over the **Aethel Sea** the **Great Sky Arch**, a rock causeway humped up out of the sea to the **Whispering Woods** on their island |
| Middle | The **Shattered Desert** - plates of rock lifted in steps with cracks down to the sand between - the **Al-Khalid Sands** (dunes), and the **Emperor's Spine**, a sandstone ridge 38 m high with a flat top you can drive along, ramping down at both ends (the near end is a short walk north-east of home) |
| South | The **Sunscorched Badlands** (mesas and gullies) and the **Meteor Crater of Kael** - starmetal lies in it |
| South-west | The **Gulf of Krakens** |
| East | The other **Whispering Woods**, the **Ostar River** past **Ostaros City** to the **Bay of the Wyrm**, **Sylvanwood** (maples and cherries, a little mahogany), the two **Mor'uk Bogs**, and the **Veiled Archipelago** off the coast |
| South-east | The **Dragon's Teeth** - fangs of rock over 200 m - running out to their own island (black opal) |

**Roads** (`World.ostars_roads`): the plot's drive runs down to a main street
south of the town, with a lane up between the dealer and the works to the
hardware store; the street runs west to Old Bjorn's yard and on to the sea at
Granny Opal's, and east out of town, then north up through the foothills to
Dusty's and over the pass to Summit Outfitters. The long roads are routed over
the land - round the hills, switching back up the slopes - and each ends on
the home side of its yard. Roads are quicker to drive, and nothing grows on
them.

**What is built** (`Ostars.SITES`, each levelled and facing home; no outposts
or quarry): the town by home - the hardware store, the
vehicle dealer and the machine works - Summit Outfitters up on the tundra past
the Avalanche pass, and the three traders (see [Traders](#traders)): Old
Bjorn's lumber yard at the edge of the meadows 270 m from home, Dusty's assay
office up in the Avalanche foothills, and Granny Opal's by the sea at Halyon
Port. The compass and the map always show the traders; every other named
place is a "?" until you go there. Ostaros City's site is still empty.

**Ore and gems by how hard the country is** (`scripts/world/Prospector.gd`).
Every spot's hardness is its region's (meadows 0, forests 0.5, dunes 1,
shattered desert 1.3, bogs 1.5, badlands 1.9, tundra 2.2, Orodruin 2.4, the
Wilds and the Dragon's Teeth 2.6) plus one for every 70 m of height (up to
2.5) plus a little for steepness. Each ore has its country and a band of
hardness, and is thickest at the hard end of it:

| Where | What |
|---|---|
| Round home (easy) | tin, quartz, limestone, iron |
| The desert, the foothills, the bogs | zinc, copper, sandstone, slate, magnetite, amethyst, jade, cobalt |
| Up the mountains and far out | silver, nickel, granite, obsidian, basalt, bismuth, marble, turquoise |
| Only the hardest country | emerald, tungsten, gold, ruby, sunstone, platinum, lapis |

Starmetal lies in the Meteor Crater of Kael, black opal on the Dragon's Tooth
Isle, and the caves (a big network under the continent with a cave biome
under each kind of country, and a small one under the Whispering Woods) have
their own. The map caches to `user://terrain_cache_ostars.bin`, and the cave
plan to `user://cave_plan_ostars.bin` (see Loading, below).

**The forests are grown, not scattered** (`scripts/world/Forester.gd`):

1. *How wooded the land is*, everywhere: each region has its own (Sylvenwood
   and the Whispering Woods thick, the meadows light, the desert all but bare),
   broken up by glades and patchiness, thicker along the rivers, thinning to
   nothing at the treeline (120 m, 165 m in the snow), and nothing on ice, the
   ridges, the beach or the plot.
2. *Stands*: spots tried all over on a jittered grid, each kept by how wooded
   it is there, sized by the same, with a leading and a second kind of tree
   from the region's mix (willows and birches on a river bank, palms at a
   desert river, pine, ironwood and spruce on any mountain).
3. *Trees*: the budget shared between the stands by how much wood each holds,
   and each stand's trees dropped in a clump round its middle - 70% its
   leading kind, 20% its second, the rest anything in the mix. A rare tree
   (ebony, mahogany, spirit trees) never leads a stand, so it turns up one
   here and there rather than as a grove. Too wet for a kind, and something in
   the mix that likes the wet takes the spot instead.
   No two trees closer than 3.6 m.
4. *Strays*: a few lone trees anywhere wooded enough.
5. *The home wood*: 70 pine, birch and oak in the best patch 95-175 m from the
   plot (the compass calls it the Home Woods).

Each kind of tree then gets a field that keeps 85% of its spots stood and
regrows on the rest. Ostars has three trees of its own, each cutting into a
wood the game already has: **Whisperbark** (tall, pale, a blue-green head;
birch), **Bog Cypress** (a fat trunk standing in the bog water; willow) and
**Charred Snag** (burnt black on Orodruin; pine).

### Traders

Each place you sell at has its own trader, built in Blender like the
lumberjack (`source/npc_build.py`, `assets/models/npc_*.glb`) and posed in code
(`NpcFigure`). Talk to them wherever they are to sell what is in their yard;
each buys only its own goods and leaves the rest on your rack.

| Trader | Buys | What they do all day |
|---|---|---|
| **Old Bjorn** (lumber yard) | wood, lumber, goods | Chops at his own pine beside the yard, paces about, leans on his axe for a breather and wipes his brow. Fell his tree and he stamps and shakes his fists ("Oi! I didn't need your help!"), sulks with his arms folded, and is back at it when it grows again (45 s). You keep the log. |
| **Dusty McGrath** (assay office) | ore, metal, stone, glass | Swings his pick at his great lump of ore (sparks fly), paces, leans on the pick. |
| **Granny Opal** (gems) | gems, cut jewels | Rocks in her rocking chair on the porch all day, knitting; nods off now and then ("Zzz..."), looks up and says hello when you come by. |

The lumber yard and the assay office also **sell** - Bjorn lumber, Dusty
refined metal - at a shop counter beside the yard. [E] at the counter opens
the order sheet: a price a piece for each (half as much again as it sells
for), and 1, 5, 10 or 25 at a time, paid on the spot. Their helper (Pip at
Bjorn's, Nugget at Dusty's - short, hi-vis vest, cap) carries the order out
in armfuls to the **loading bay**: park your truck in the bay and it goes in
the back, rows along the bed; no truck, and it is stacked on the bay floor.

On the islands the Sell Yard's hand (the helper's model) waves you in and
cheers a sale, and the trading posts have traders too: Granny Pearl at the
Mire Gem Exchange, Stoney Pete (a miner) at the Frostline Post and Old Hal (a
lumberman) at the Dune Trading Post - leaning on their tools at the counter.

## The isles

> **Current world (latest):** 4.8 km across. A home island 2.4 km wide, split
> into big single-biome regions (the Greenwood round home, the Spine Mountains
> with peaks over 250 m, the Redsand Desert with dunes and mesas, the Mudflat
> Swamp, the Northpine Taiga), and five more islands: Frostreach (snow),
> Sunscar (desert mesas), Mirewood (swamp and hills), Crater Isle (Star Crater,
> starmetal) and Hollow Isle (the Hidden Valley and its mahogany), which only
> the deep tunnel under the sea reaches. Roads are routed on the land with a
> 1-in-9 grade limit, so they wind and switch back, and are drawn as asphalt
> with lines, verges and posts (dirt tracks to outposts). Under every island
> is a cave network - about 100 caverns and 15-18 km of tunnel, three quarters
> below sea level, all joined up - in seven cave biomes: river, desert,
> crystal, ice (sapphires), fungal (glowcap mushrooms to fell), magma and the
> abyss (diamonds). Generation is threaded and cached in
> `user://terrain_cache.bin` (the cave plan in `user://cave_plan.bin`); far
> trees and rocks stay dormant until you come
> near, and decor streams in round you. Some of the detail below describes the
> earlier, smaller map.

The map is **2.5 km across**, and it is mostly islands: a big home island in
the middle with the plot, the yard, the store and the quarry, and four more
out across the water - **Frostreach** to the north (snow and mountains, the
Summit store), **Sunscar** to the east (desert and mesa), **Mirewood** to the
west (wet woods and swamp) and little **Crater Isle** to the south-east. The
trunk roads run out from home and **bridge** whatever water is in the way -
four bridges in all, the longest over 250 m, plank decks on girders with an
arch, rails you cannot drive through and piers down to the sea bed. Crater
Isle has no bridge: its road is a **causeway** through the shallows, wading
depth all the way. Each island has its own climate nudge (the north colder,
the east drier, the west wetter), so they look like different places. Height and biome come from two low-frequency fields,
elevation and moisture, the way a real biome table works - so it is procedural
but legible, and the same seed gives the same country every time. Woodland,
swamp, desert, mountains, taiga and snowland all appear.

**The look is big flat panels and hard edges.** Height is one continuous
surface banded into terraces - flat tops, short steep risers - with each
biome banding it at its own step (two metres in the woods, four in the
mountains, none in the swamp). Every triangle is coloured by its own slope:
flat faces are the biome's ground, steep ones are rock, terraces alternate a
shade so the bands read at a distance like contour lines, and there is sand
only where there is water beside it. Height used to come from a base per biome,
which stood the mountains on sheer plinths thirty metres high wherever two
biomes met; now the worst step between neighbouring ground points is a riser,
and every mountain can be walked up.

**It is dressed.** About 9,000 pieces of set dressing are scattered by biome -
grass and flowers in the woods, ferns and toadstools in the taiga, reeds and
lily pads in the swamp, cacti and scrub in the desert, scree on the hills,
drifts and ice in the snow - as MultiMeshes in 75 m tiles that fade out past
150 m, so the whole map costs a few dozen draw calls in view. About 800
boulders, big enough to walk round, have colliders.

**It is built in chunks.** The ground is 32 x 32-cell chunks, each its own mesh
and collision shape, so the renderer culls what is behind you and no single
shape holds the whole country. The open sea floor is one flat sheet rather
than 100,000 drowned triangles. The whole world builds in about six seconds.

Everything else is carved into that afterwards, in order:

* **Build sites are levelled** - the plot, the yard, the store and the quarry -
  so a factory floor is never on a slope.
* **Rivers are cut down through** whatever the land was doing, with banks that
  fall away over a few metres. Each has stretches left shallow enough to drive
  through; everywhere else wants a bridge. Water deeper than a metre is swum
  rather than waded, slowly, and a hauler whose driver seat goes under can no
  longer be driven.
* **Roads are graded across** it, and never steeper than 1 in 10: where the
  land climbs faster the road goes through it in a cutting. A bridged road
  leaves the water alone and asks for a bridge over every wet stretch; a ford
  road builds its bed up to wading depth instead.
* **Roads are flat across** - the whole carriageway to one height, which
  follows the land lengthwise off a smoothed profile but does not tilt sideways.
  Blending in from the centre-line instead leaves a camber, and a cambered road
  is one you slide off. The carriageway has to be comfortably wider than a
  terrain cell or it is narrower than the grid representing it, which is why it
  is 18 m across on a 6 m grid, with a 20 m shoulder blending back into the
  land. Where a road meets a river it crosses at a ford rather than filling the
  river in, and driving one is slightly quicker.
* **Roads hold their line on bends.** The carriageway (RoadSurface) is laid at
  the road's own profile height, level across, bends and all, with a shoulder
  down to the land each side; the land under it is laid a little lower
  (`ROAD_SINK`), and where the road comes back past itself - a hairpin, a
  switchback, a tight bend on a hillside - the ground between the legs is taken
  down to the lower leg, so nothing pokes up through a road on a turn. Its
  cross-sections take their direction over a few metres, and the inside edge of
  a tight bend is held rather than folded back over itself.
* **The plot is kept clear.** Its square, at its biggest expansion and a
  margin round it, is levelled just under the pad (before the roads are graded
  and again at the end), so the land never shows through at the corners, and
  no road is laid across it: the roads come down to the ground and stop at its
  edge.

Resource fields sample the ground, so trees and rocks stand on it and avoid the
water, the roads and the levelled build sites.

**Fields churn.** A field fills to its quota and used to stop there for good,
so once you had cleared the woods near home every tree left was a long walk
away. Now a full field every half-minute or so retires one *untouched* tree or
chunk at least 90 m from you, and the refill that follows can land anywhere -
including near you. Nothing you have started on is ever taken, nothing vanishes
in view, and nothing new appears within 30 m of you.

**The further out, the better it is.** Every tree species and every ore has a
band of distance from home it grows in, on top of its biome. Tin, quartz, iron
and pine are on the doorstep; magnetite, silver and amethyst are at the edge of
the home island; jade, obsidian and cobalt on the near shores of the others;
tungsten, platinum, ruby, bismuth and the glowing woods only on the far
islands. The smoke run checks it: the dear ore averages ~950 m out, the cheap
~410 m. And the best of all is **hidden**, with no road to it:

* **The Hidden Valley** on Mirewood: a flat green floor walled in by a 45 m
  ridge with one narrow gorge in, and the only **mahogany** on the map - tall,
  straight, dark-crowned and worth $900 a cubic metre as sanded planks.
* **Star Crater** on Crater Isle: a scorched black bowl with a raised rim, and
  the only **starmetal**, glowing blue, where it came down.
* **Starless Deep**, whichever cave is farthest from home: the only
  **diamonds**.

### Caves

Nine caves, spread over the islands, placed where the hill is high enough over the whole footprint that
nothing pokes out, the mouth faces open ground, and the chamber floor stays
above the sea. The heightfield leaves out the two cells a cave's trench runs
through; everything below is built: a timber-shored trench down to a portal, a
sloping tunnel with rails and lamps, and a chamber under the hill with pillars,
a ledge, stalagmites, glowing crystals and a mine cart. Each has a field of
ore on the floor, stocked by how far out it is: the nearest have copper, iron,
tin, zinc, quartz and amethyst; the middle ones silver, magnetite, nickel,
jade, cobalt and gold; the far ones gold, emerald, ruby, platinum, tungsten
and sunstone; and the farthest, diamonds. Going underground
dims the sky light to the cave's own, turns on a lamp on your hat, and hides
the landmark labels that would otherwise show through the rock.

### Places

Found for their own country by the terrain rather than put at fixed spots, so
each sits on a level patch of the right ground:

| Place | Where | What for |
| --- | --- | --- |
| Dune Trading Post | desert, on Sunscar | pays +45% for lumber, +30% for goods, +25% for jewels |
| Frostline Post | snow or taiga, on Frostreach | pays +45% for metal, +35% for ore |
| Mire Gem Exchange | wet woods, on Mirewood | pays +50% for jewels, +30% for rough stone |
| Far Camp | the far north | a camp at the end of the road |
| Ranger Lookout | woods or hills | a tower you can climb, and the view |
| Old Logging Camp | taiga or woods | tents, a fire, a log pile |
| Stilt Shack | swamp | a cabin on stilts with a jetty |
| Sunken Ruins | desert or woods | broken walls and fallen columns |
| Miner's camps | at each cave mouth | |

Traders buy the same way the home yard does - drop it inside the fence and
ask - and pay the day's price plus their premium, which is what makes the long
haul pay. Every place has a **supply cache** that pays out once a market day,
more the further it is from home. Walking within 40 m of a place **discovers**
it: until then the compass and the map show a "?" when you are near, and after
that its name for good.

Roads that meet a river cross at a ford rather than filling it in. Anything
that punches through the ground (the land is a surface with no thickness, and
a log landing hard on a steep face can go through it) is put back on top where
it went in, rather than sent home by the kill plane.

**The forest belongs to the biomes.** A species is offered a pool of ground the
terrain has already vetted - right biome, dry, off the roads, outside the build
sites - rather than a ring drawn round the origin, so the look of the land tells
you what you will be cutting, and the hard woods are out in the hard country.
Within its country each species grows in **groves of its own** (about one per
36 vetted spots, `world.grove_radius` across), thicker toward the middle, with
a few strays between (`world.grove_share`). And there is always a wood a short
walk from the plot - the **Home Woods**, pine, birch and oak, on the compass -
so the first tree is not a trek. A tree comes down bare: its leaves stay behind.

| Tree | Grows in | Cuts into |
| --- | --- | --- |
| Mahogany | the Hidden Valley only - tall, dark, buttressed | mahogany |
| Pine | woodland, taiga | pine |
| Spruce | snowland | spruce |
| Oak | woodland | oak |
| Willow | swamp (standing in shallow water) | willow |
| Ironwood | mountains | ironwood |
| Desert Ironwood | desert | ironwood |
| Birch | woodland, taiga - white bark, round light crown | birch |
| Maple | woodland - autumn red and orange, all year | maple |
| Cherry Blossom | woodland, swamp - low and wide, a cloud of pink | cherry |
| Redwood | taiga - a giant: 14-19 m, a metre-plus thick | redwood |
| Palm | desert - fronds from the top of a thin trunk | palm |
| Baobab | desert - a barrel of a trunk, a tuft on top | baobab |
| Frostbark | snow - ice-blue needles that catch the light | frostbark |
| Spirit Tree | swamp - ghost-white, glowing teal leaves (rare) | spiritwood |
| Emberbark | mountains - charcoal black with smouldering knots (rare) | emberbark |
| Dead Snag | mountains, desert, swamp - grey and bare | pine |

About 1,350 trees stand at once, across all seventeen; maple, cherry, redwood
and baobab start a couple of hundred metres out, the ironwoods at 350 m, and
frostbark, spirit trees and emberbark only on the far islands. About 380 rocks
stand at once, in twenty-one kinds, each in its own host rock:

| Metal ore | | Stone | |
| --- | --- | --- | --- |
| Tin | near home | Quartz | near home |
| Zinc | home island | Amethyst | 400 m+, hills and desert |
| Iron | everywhere | Jade | 600 m+, wet woods |
| Copper | desert, hills | Obsidian | 600 m+, desert and hills |
| Magnetite | 300 m+, hills | Emerald | 800 m+, wet woods, far caves |
| Nickel | 450 m+, the cold | Ruby | 850 m+, desert, far caves |
| Silver | 380 m+, the cold | Diamond | Starless Deep only |
| Cobalt | 550 m+ | | |
| Bismuth | 700 m+, desert (glows) | | |
| Tungsten (wolframite) | 750 m+, mountains | | |
| Gold | 750 m+, snow; caves | | |
| Platinum | 850 m+, snow | | |
| Sunstone | 850 m+, desert | | |
| Starmetal | Star Crater only | | |

Stones grow as bigger, glassier crystals than the metal ores do.

Tree and wood are still separate ideas - the two ironwoods are different trees
cutting the same wood - but each biome that is worth a trip pays for it. Willow
is the odd one: poor value by the cubic metre and very light, so it pays well
for what it weighs and is worth carrying by hand where oak is worth a truck.

Quotas follow how much country each species actually has, so a seed that grows
little swamp gets a few willows rather than an empty field grinding away at a
region that is not there.

## Mayhem

* **TNT** is sold by the stick at the hardware store (EXPLOSIVES, $50 each,
  always back on the shelf). Open the box, **[E]** on the stick lights a
  four-second fuse, then pick it up and throw it. A blast (`scripts/world/Blast.gd`)
  throws players a long way (38 m/s at its heart), blows loose things about,
  sets off every other stick or box of TNT within 8 m a split second later -
  lying about, on someone's rack or in their hand, so a pile goes up in a
  ripple - and cracks ore apart: easy ores (tier 1) come to pieces, tier 2 ores take 30%
  of it, and the top ores and finest gems (tier 3) only 3% - barely a mark.
  Loose ore chunks in the blast crack in two the same way. The knobs are in the
  `explosives` section of `balance.json`.
* **Getting knocked flying.** A long drop (landing faster than 16 m/s, about
  twelve metres), a truck driving into you (faster than 5 m/s under its own
  speed - running into a parked one, or one creeping along, just stops you
  against it) or a blast turns you into a ragdoll
  (`scripts/player/Ragdoll.gd`): body, head, upper arms, forearms, thighs and
  shins are each a physics body, jointed at the neck, shoulders, elbows, hips
  and knees within a person's range, so every limb flails and flops on its
  own. The camera stands off and follows (the mouse swings it round, it pulls
  back the faster you go and shakes as you hit things), each hit on the ground
  is a thud and a puff of dust, and a big knock sends your beanie flying. Once you have
  lain still a second or two you pick yourself up where you are, hat back on.
  Whatever was on the rack goes everywhere.
* **Cranes pick up players.** Close the grapple (or drop the claw) on someone
  and they come too, held by the body with arms and legs dangling. Hold **jump** for a second to
  wriggle free; otherwise they drop when the crane lets go.
* **The crusher crushes players.** Fall (or be dropped) into its hopper and you
  go through: the camera watches the machine for a few seconds while ten Meat
  Bits come out of the far end (worth $2 each at the yard), then you are back
  at base.
* In co-op the host works out who gets hit and the guest's own game acts it
  out (`knock` and `crush` messages).

## Co-op

One player hosts their own game; friends join it. Everything is shared: one
world, one purse, one set of unlocks and upgrades, the host's save.

- **Host:** Main menu (Esc > Main menu) > Co-op > *Host this game*. It opens
  UDP port 24565; friends outside your network need it forwarded. The page
  shows your local IP addresses.
- **Join:** Co-op > type the host's IP > *Join*. Your own world is saved and
  put aside; the host's is built on your machine and joined. Esc > *Leave
  co-op* (or the host quitting) brings you back to your own.

How it works: the host runs the whole game - physics, machines, trees, money.
Each guest is a real `Player` in the host's world, driven by the keys and
mouse the guest presses (`PlayerInput`), so every action - chopping,
dragging, the crane, the loader, driving, buying - is the same code as single
player. The guest's machine builds the same static world from the same seeds
and draws everything that changes from what the host sends (`NetHost` ->
`NetClient`): loose pieces, trees and their cuts, rocks and their cracks,
buildings, vehicles (wheels, crane, bucket, tub), other players, money,
unlocks and orders. Looking about is instant on the guest; moving goes
through the host, so it lags by the round trip.

Not yet in co-op: building from a guest's machine (the host builds), the
guest's inventory screen (hotbar changes), and on-screen aids that live only
on the host (drag line, crane ghost, winch reticle). Tested end to end by
`scenes/net_probe.tscn`: a headless host and guest on localhost that join,
walk, share money, pick up a log and drive a truck.

## Materials are volumes

Nothing in the game is counted in "items". Every piece is a solid with real
dimensions:

* A piece is a box or a tapered cylinder whose long axis is local +Y. Its
  **mass is density x volume** and its **price is rate x volume**, both from
  `data/items.json`. A 4 m trunk weighs what a 4 m trunk should.
* **The planker** turns a log into one plank the log's length, 1.8 radii wide
  and 0.8 thick - the slabs and sawdust are the waste, and the plank is still
  worth about half as much again as the log. **The smelter** turns a lump of ore
  into one bar holding 60% of its volume. **The crusher** breaks a chunk into
  lumps and conserves ore exactly. **The sander** and **refiner** add a finish
  that stays with the piece through cutting and saving; what it is worth
  depends on the material (below). Each is a change to the same physics body as it passes the middle of
  the tunnel, so it keeps its place and speed on the belt.
* **The gem cutter** facets a rough stone into one jewel, a squat eight-sided
  crown holding half its volume. **The sander** polishes stone rather than
  sanding it. Jewels glitter.
* **Every material has three values**, set in one table (`materials` in
  `data/items.json`) as dollars per cubic metre of the *raw* material: raw, as
  found; after the first step (sanded log, smelted bar, polished stone); and
  final, after the whole path (sanded plank, refined bar, cut jewel). The item
  rates and each material's own finish bonuses are worked back from it at
  load, allowing for what each machine keeps of the volume, so the table is
  exactly what the yard pays. Most things gain; some do not:

  | Material | Raw | First step | Final | |
  | --- | --- | --- | --- | --- |
  | Pine | 22 | 28 | 48 | steady |
  | Baobab | 40 | 64 | 52 | spongy - sell it sanded |
  | Redwood | 50 | 56 | 140 | sanding does little, planks are the prize |
  | Spiritwood | 230 | 180 | 620 | sanding scuffs the glow |
  | Mahogany | 260 | 380 | 900 | |
  | Copper | 820 | 1,300 | 1,350 | refining adds almost nothing |
  | Magnetite | 700 | 650 | 1,500 | smelting kills the magnetism |
  | Tungsten | 1,400 | 1,500 | 5,200 | barely worth smelting - until refined |
  | Bismuth | 2,200 | 1,300 | 1,700 | the crystals are worth more than the metal |
  | Starmetal | 6,000 | 11,000 | 16,000 | |
  | Obsidian | 600 | 1,100 | 800 | brittle - sell it polished |
  | Jade | 900 | 2,400 | 2,500 | all the value is in the polish |
  | Diamond | 5,000 | 5,000 | 22,000 | polish does nothing, the cut is everything |

  The whole table - 36 materials - is in the journal's **Market** tab as a
  price guide, with the change at each step in green or red.
* **The workbench** works the other way round - it consumes *volume by
  category* (0.12 m3 of any lumber plus a little metal makes a crate), so any
  offcut length is usable.
* Because value is per cubic metre, a machine's worth is exactly what it adds,
  and the week's market moves every rate.
* **The market moves by material.** Every form of a material - mahogany logs,
  sanded mahogany, mahogany lumber - shares the week's rise or fall, so a good
  week for mahogany is good whatever state you sell it in; the market board
  has one row per material. How far a material swings depends on what it is
  worth: cheap woods are all over the place (up to about +/-60% by default),
  the dear metals and stones hardly move (a few percent). The two ends and
  where they fall are in balance.json (`economy.*`).
* Bucking, splitting, storing, loading and unloading all conserve volume too,
  and the test suite asserts it to four decimal places at every step. Branches
  still on a trunk count: they are paid for with it at the yard, go into a bin
  with it (and come out as pieces of their own), and go into a machine with it.

## Vehicles

Seven, each sold at the store as a crated pad of its own. Place the pad and it
spawns that vehicle; use it again to recall and respawn it. They are all one
class driven by `data/vehicles.json` - hull, wheels, springs, engine, bed and
rig - so a new one is a row of data.

| vehicle | unlock | top speed | load | rig |
| --- | --- | --- | --- | --- |
| Quad Bike | $1,200 | 20 m/s | 0.6 m³ rack | - |
| Pickup | $2,500 | 27 m/s | 2.5 m³ | winch 2.5 t |
| Dune Buggy | $3,500 | 32 m/s | none | winch 1 t |
| Flatbed Hauler | $5,000 | 22 m/s | 8 m³ | winch 4 t, crane 1.2 t |
| Log Truck | $12,000 | 19 m/s | 18 m³ stake bed, open back | winch 8 t, crane 2.5 t |
| Dump Truck | $15,000 | 18 m/s | 14 m³ tub that tips | winch 6 t |
| Crane Truck | $20,000 | 18 m/s | 10 m³ | winch 12 t, crane 6 t, 22 m reach |

The big three run tandem rear axles, and their rearmost axle steers a little
the other way (`rear_steer`), which with the trucks' wider steering lock
tightens their turn considerably. Springs and dampers scale with weight, so
every vehicle rides like the original truck. The dump truck's tub is a set of
colliders swung about a rear hinge, so the load really slides out under
gravity. The front loader's bucket swaps for a **log grapple** (G, while it is
empty): four fork tines, a toothed back rack and a heavy clamp that Space
closes over whatever lies across the tines. Settings > Game > Debug has an
unlimited-money switch for trying them all.

**Gears.** Every vehicle has a gearbox (`gears` in vehicles.json: each gear's
top speed as a share of the vehicle's). The low gears pull harder - the torque
at the wheels goes up as the gear comes down (`vehicles.gear_torque_exponent`)
- which is what gets a loaded truck up a steep hill: a loaded log truck that
stalled a few metres up a 38-degree slope now climbs it. The automatic shifts
for the speed being asked for and only brings the extra pull to bear uphill,
so it pulls away on the flat as gently as it always did. Trucks can be driven
with a **manual gearbox** instead (Settings > Controls): Shift and Ctrl change
gear, and the gauge shows the gear.

**Engine and tyres** are upgrades for every vehicle at once, sold in the
store's Gear bay: a tuned engine, a turbo diesel and a big block (more pull,
a little more top speed), and all-terrain, mud-terrain and lugged tyres with
chains (more grip).

**Towing.** Trucks with a hitch pull trailers [T] (and trailers with a hitch
of their own make a train). The pickup has a `tow_limit` in vehicles.json:
it pulls the utility trailer and anything lighter (the lawnmower trailer),
counted by each trailer's empty weight, anywhere in its train; the logging and
dump trailers and the low-loader are too heavy for it, and it says so. The
hauler, log truck, dump truck and crane truck pull anything.

**Recovering** a vehicle (C) sets it back on its wheels, at most once a second
and not while it is down on its outriggers.

**Cranes** run briskly unless you hold fine control (RMB); the joints and the
target speed are `crane.joint_speed` and `crane.move_speed`. A crane working
from a truck that is towing a trailer lets the trailer's load loose too, so it
can lift logs out of the trailer as well as its own bed.

**The winch** hooks whatever the crosshair is on - or, if that is only the
ground, the log, chunk or tree nearest the line of sight within a metre and a
half, so it does not take pixel-perfect aim. The ring showing where it will
catch is drawn only from the driver's seat.

## The look: grass, flowers, leaves and birds

All of it is only the look - nothing collides with it or can be picked - and
all of it is set in Settings > Video (and by the presets: Low has shaders off
and short grass, Medium shaders on and short grass, High shaders on and far
grass).

* **Grass and flowers** (`scripts/world/GrassField.gd`, the *Grass* setting:
  off, short range 32 m, far 60 m). The ground round the camera is cut into
  16 m chunks. Every chunk draws the same 1,936 tufts of five blades and 169
  flowers (one MultiMesh each, made once and shared) and has its own 9 x 9
  lattice of the ground under it - height, how grassy, how flowery, and the
  colour of the plate there - which the vertex shader reads to stand each
  tuft on the ground in the ground's own colour, or fold it away where
  nothing grows: roads, water, rock and sand (anything not green), snow and
  desert, the plot's concrete (kept clear however big the plot grows - the
  levelled lawn round it is grassed), the shops' and traders' yards, cave
  mouths. Flowers (red, yellow, white, purple, blue) come in patches, most in
  the woodland meadows. Further off a chunk draws a half, then a quarter of
  its tufts (the shader thins smoothly in between, so nothing pops), and at
  the edge of the range they shrink into the ground. Blades are single
  triangles with their normals up, cast no shadow, sway in gusts of wind
  (with shaders on) and bend away from your legs. A chunk's lattice is made
  a few rows a frame, a millisecond or so at most.
* **The ground** with shaders on: grassy plates (green and facing up) get
  drifts of lighter and darker, yellower and bluer green at a few sizes, a
  fine speckle up close and a soft sheen instead of the plates' shine; rock,
  sand and snow are as before (`Terrain.LAND_SHADER`).
* **Leaves** with shaders on (`ChoppableTree.FOLIAGE_SHADER`): the whole tree
  leans with the wind, more the higher up and each at its own pace, the
  leaves flutter, are dappled with small clusters of light and shade, and
  glow a little with the sun behind them. Bark is left as it is (leaves are
  told from bark by vertex alpha: 0 on the leaf pieces, 1 on wood).
* **Far trees** (`ChoppableTree.stand_in`) are no longer two stacked prisms
  (the "buns"): a broadleaf is a cluster of leaf lumps round a middle one, a
  conifer its stacked tiers, a palm its fronds, about 120 triangles, in the
  same colours as a built tree (they used to come out brighter). The middle
  distance's leaf clumps are five lumps, not three.
* **Birds** (`scripts/world/Birds.gd`, the *Birds* setting): three flocks of
  small dark birds wheeling over the country round you, a pair of gulls that
  keep to the water, and a hawk circling high up; flapping in bursts and
  gliding (in the shader), all one draw, gone to roost at night.

The perf harness (`scenes/perf.tscn`) prints the grass's and the birds' time a
frame.

## Models

Nearly every mesh is built in code from primitives. The one exception is you.

* **The traders** (`assets/models/npc_lumberman.glb`, `npc_miner.glb`,
  `npc_granny.glb`, `npc_helper.glb`) are built by `source/npc_build.py` the
  same way and with the same pivots, so `NpcFigure` poses them as the player
  is posed. Each file has its props beside the person: the miner's pickaxe
  and the lumberman's felling axe (put in the right hand in code, or stood on
  their heads to lean on), Granny's rocking chair (she rocks with it).
* **The player** is a barrel-shaped lumberjack with a huge ginger beard lying on
  his belly (its strands carved into it), a red plaid shirt, braces, green work
  gloves, domed work boots with laces and brass eyelets, and a yellow knit
  beanie: `assets/models/player.glb`, built in Blender by a script kept in the
  file (`source/player.blend`, text `player_build`: flat colours, faceted,
  lightly rounded blocks). The model is pivots - hips (the body), head,
  shoulders, elbows, wrists, each finger at the knuckle and halfway, thumbs,
  hips, knees and ankles - and `PlayerAvatar` poses them in code every frame;
  nothing is keyframed in the file. Knees bend as each leg comes through a
  step and on landing, and fold to sit; elbows pump when sprinting, bend to
  carry and wind up a swing; fingers close round a tool, the wheel or the
  levers and hang loose otherwise; stood still, he shifts his weight from leg
  to leg. Its base pose follows what you are doing: standing
  (breathing), walking and sprinting (short quick steps, arms swinging), in the
  air (arms out, windmilling on a long drop, a squash on landing), swimming (a
  doggy paddle), wading (hands held up out of the wet), carrying a load
  (across the chest, leaning back), dragging (reaching for the grabbed point,
  both hands on anything heavy), holding a tool (over the shoulder), at the
  wheel (hands on it, turning it as you steer), working a crane or loader
  (hands on the levers, watching the log) and in build mode (hand on hip,
  pointing where you look, foot tapping). Over that go one-off gestures: the
  chop and the hammer blow (up over the head, down hard), pick up, throw, drop,
  use, grab, a lever pull for anything done from the cab, a fist pump when a
  building goes down and a shake of the head when one comes off, drawing a
  tool, and, stood about long enough, a fidget - stroking the beard, a look
  round, a stretch, a scratch under the hat. In first person only his shadow
  is drawn; in third person (F2), at the wheel and in build mode, all of him.
  A closed cab is a solid box, so in a truck he sits hidden inside it; on the
  quad and the buggy he is out in the open.
  In co-op everyone is the lumberjack, each in a shirt of their own colour
  with their name over him (`scripts/net/Avatar.gd` stands in for a player
  whose game is on another machine). The host sends what each one is
  carrying, dragging and building and every gesture they make, so all
  machines draw the same chop at the same moment.

* **The land** is one `ArrayMesh` with a triangle per facet - each triangle
  carries its own vertices and its own normal, which is what makes hills read as
  facets rather than as a blurry blanket, and vertex colours carry the biome. Its
  collider is the same triangles.
* **Round stock is octagonal.** Trunks, branches and felled logs are drawn with
  eight sides, matching the faceted land; the collision cylinder stays at the
  full radius, so the mesh always sits inside its own collider. One constant,
  `Tuning.ROUND_SIDES`, drives all of it.
* **Trees** are a flared stump, a tapered trunk, four to nine angled branch
  cylinders and a cone of foliage on each branch end. Every limb has its own
  collider, which is how the aim ray knows which one you are standing under. The
  trunk mesh and the piece that falls are the same frustum, which is what makes
  "it keeps the shape it grew" true rather than approximate. Six species differ
  in silhouette rather than in colour alone: where branches start up the trunk,
  how far they are swept up or out, how long they are, how wide the foliage
  clumps are, and whether there is a crown on top at all.
  The leaves, palm fronds and root flare are made in Blender
  (`assets/models/trees.glb`, source in `source/trees.blend`): low-poly pieces
  with light and shade painted into their vertex colours and tinted per tree -
  a conifer's drooping tiers, round lumpy clumps (birch, maple), broad flatter
  canopies (oak, ironwood, willow, mahogany), blossom clouds, arching fronds,
  and buttress roots at every trunk's foot; a birch has black marks up its
  bark. Leaves carry no collider, so cutting is unchanged. An untouched tree is
  one merged mesh, in two versions: every clump in full within 35 m, and past
  that the same outline in a fraction of the triangles.
* **Only what can be seen is drawn.** Besides the usual culling of what is
  outside the camera's view, the ground is an occluder (a coarse copy of the
  land a few metres under it): woods and buildings behind a hill are not drawn.
  Near cave mouths and underground it is switched off, since there the ground is
  not solid.
* **Ore chunks** are slabs of rock with the ore breaking out of them as
  crystals, so iron, copper and gold read differently at a glance and gold
  catches the light - sunk into the ground by however much is buried, and
  drawn from the ore left in them, so hammering a piece off visibly shrinks the
  rock. Open cracks are dark seams that lengthen as they deepen.
  Each ore's chunk is a block of its rock built out of cubes, Minecraft-style,
  with the ore sticking out of its faces as cubes that glow, each in its own
  colour. The block is built in the game (`scripts/world/OreLook.gd`) for the
  exact box it fills - any size and aspect ratio, a long slab just gets more
  cubes along its length - for the chunk in the ground and every piece mined
  from it. Every ore has its own pattern: banded iron, copper in green patina,
  a gold-in-quartz vein, silver, cobalt in pink bloom, sunstone, tin, zinc,
  magnetite, nickel, rainbow bismuth, tungsten blades, platinum in olivine,
  and a starmetal meteorite with glowing cracks. The design was worked out in
  Blender (`assets/models/source/ores.blend`).
* **Machines** are tunnels over a belt, dressed like a curing oven: steel side
  panels with ribs and a bolted access panel, a dark inside the belt vanishes
  into, a bulkhead at each end with the mouth cut out of it, hazard stripes
  round the mouth and strip curtains hanging over it, and a status light. The
  planker and sander carry a motor and a drive guard on the roof, the smelter a
  chimney and a fire glow inside, the refiner three glowing cells, the crusher
  a hopper and a flywheel. Each throws its own sawdust, steam, dust, sparks or
  flame from its mouths while it works, with a burst as each piece changes.
  The workbench is still the old kind of machine: a shell with an intake and an
  outlet.
* **Belts** are a rubber belt between steel channels, with rollers at the ends,
  legs down to the pad on ramps, visible rails where they have them, and
  **chevrons painted on the belt pointing the way it runs** (cyan on the fast
  belt). Splitters and filters have a turntable and an arrow to each output.
* **The hauler** has a cab with glass and mirrors, a light bar, a grille,
  bumper, headlights and tail lights, an exhaust stack, mudguards, stake posts
  round the bed, and wheels with a tread, rims and lug nuts. The wheels are
  real: each is its own body on a sprung joint, driven by a motor on its axle
  and steered by turning the joint, so the truck goes where its tyres take it.
  The winch line and crane rope are real lines too - slack until drawn tight,
  then pulling as hard as the machine on them is rated for and no harder.
  Hook either one on to ore still in the ground and reel or hoist: if the
  machine is rated for the pull the chunk needs, it comes out on the line.
  The hook's swing is damped hard, so a load settles under the boom.
* **Nameplates.** Back when a plot was a field of similar grey boxes, every
  building carried a floating label. The models say what they are now, so the
  labels over buildings, the build ghost and the yard and stores are off by
  default (Settings > Interface turns them back on); the yard has a painted
  sign over its hatch, and places out on the map keep their names.
* **The yard** is a fenced pad with a weighbridge, a plank hut with a tin roof,
  a serving hatch and a sign, and a shopkeep in an apron and a hat. **The
  store** has a parapet, a striped awning over the door, a sign, lit windows,
  lamps, a bench and crates outside, and shelving, a counter and a land desk
  inside; a shallow ramp across the doorway takes you in without a lip to
  stub a toe (or a dragged box) on.
* **Greeble.** All of this detail is built by `Greeble` into one merged,
  flat-shaded, vertex-coloured mesh per model with one shared material (plus a
  glow surface for lamps and crystals), so a busy model is still one draw call.
  Faces are wound by an outward hint rather than by bookkeeping, and a test
  checks every triangle faces out.
* Collision stays primitive throughout: one cylinder or box per loose piece, a
  handful of boxes per machine shell, one cylinder per tree limb, one box per
  chunk. The land is the only trimesh, and nothing dynamic uses one.

## Architecture

```
scripts/core/      Layers, Tuning, InputSetup, Trigger (trigger-volume guard),
                   Solid (volume, fitting and cutting maths), Greeble (merged
                   detail meshes), Nameplate
scripts/systems/   GameData (autoload), Economy (autoload), PlayerState (autoload),
                   Settings (autoload), SaveSystem, QuestLog, Tutorial
scripts/data/      RecipeDef, MachineDef, BuildingDef
scripts/physics/   LooseItem, LooseItemManager, ItemDef
scripts/world/     Terrain, Decor, Cave, Outpost, SupplyCache, ResourceField,
                   ChoppableTree, OreRock, Machine,
                   StorageBin, SellYard, Store, VehiclePad, Bridge,
                   Conveyor, Splitter, Filter, World, StressWorld, StressTest
scripts/build/     Plot (grid, placement, persistence), BuildSystem (freecam
                   ghost), Schematic (shapes filled with material)
scripts/player/    Player
scripts/vehicle/   Hauler (every vehicle), VehicleModel (dressing), VehicleRig (winch and crane)
scripts/ui/        UITheme, UIKit, GameHUD, Compass, Journal, MapView, KeyGuide,
                   MainMenu, PauseMenu, SettingsPanel, StressHUD
assets/fonts/      Rubik, Lilita One (SIL OFL)
data/              items, recipes, buildings, upgrades, prices, quests, store, balance
scripts/net/       Net (autoload), NetHost, NetClient, PlayerInput, Avatar
tools/             Bench, Tests, SmokeWorld, Probe, NetProbe
```

Everything numeric lives in `data/*.json`: items and their mass, size, colour,
base value and volatility; recipes; building costs, footprints and unlocks;
upgrade tracks; plot expansion tiers; standing orders; what the store stocks.
`GameData` cross-validates every reference at load, so a typo in a data file
fails loudly instead of silently doing nothing. Prices are never written twice:
a boxed axe on a shelf costs whatever the next level of the axe track costs, a
T1 machine crate costs that building's unlock price, and a higher tier crate
that level of its track - every time, since each crate is one machine.

`data/balance.json` is the constants file: the game-feel knobs that are not a
row in one of those tables, and multipliers over the ones that are - walking
speed, reach and drag strength, how many swings a tree or a cut takes, hammer
cracking; every vehicle's engine, top speed, grip and steering, the gears'
pull, road and bridge speed bonuses, winch pull and speed, the recovery
cooldown, how still a parked vehicle is held; crane speed, fine control and
lifting power; loader speeds; machine speed; the build grid and how much
material a plan takes; sale prices, the market week and how far cheap and dear
materials swing; grove size and the home woods; spawn clearance round vehicles
and the kill plane. Each section has an `_about` line saying what its numbers
mean. Change a value and restart; anything missing falls back to the tuned
default, and a test fails if the file names a value nothing reads. (Your own
settings and keys are not in it: they are in your personal config file.)

`tools/Shot.gd` (scenes/shot.tscn) boots the real world and saves screenshots
of a named scenario (`-- --shot=roads`, `build`, `plot`, `store`, ...) to
`user://shots`; run it with a display (or under xvfb-run with
`--rendering-driver opengl3`). `tools/Climb.gd` (scenes/climb.tscn) drives
every vehicle up ramps of rising steepness and prints how high each got.

## Physics design

The physics budget was proven before any gameplay was built on it, and every
rule below is enforced in one place rather than per object.

* **Primitive shapes only.** Every loose piece is one `BoxShape3D` or
  `CylinderShape3D`; trees, rocks, decks, machine shells and terrain are boxes.
  No convex hulls or trimesh anywhere, however detailed the mesh on top gets.
  Round stock rolls, which costs about 60% more solver time than the old
  all-boxes world and is worth it: logs that roll are the reason a plot needs
  kerbs and belts.
* **`LooseItemManager` owns every loose body.** One GDScript loop per physics
  frame does velocity clamping, CCD review, quiet-tracking and kill-plane rescue
  for all items, instead of 500 `_integrate_forces` callbacks.
* **Sleeping, with a fix on top.** Jolt sleeps whole *islands*, so one twitching
  log kept a 500-log pile awake for ~20 s after it had visually settled
  (measured). The manager tracks per-plot peak motion and, once a plot has been
  still for 0.5 s, sleeps every free item in one pass, leaving nothing active to
  re-wake the island: settling dropped to ~4 s and a resting pile from
  6.6 ms/frame to 0.4 ms. Sleeping bodies are then skipped entirely.
* **Per-plot cap** (200 at tier 0, rising to 400 with expansion). Going over
  recycles the oldest free item; pooled nodes are *detached from the tree*, so
  they leave the physics space completely and cost nothing in broadphase.
* **Layers and masks** in `scripts/core/Layers.gd`:
  `WORLD / PLAYER / LOOSE / MACHINE / TREE / TRIGGER / VEHICLE / KERB`. Plot
  kerbing is its own layer so items cannot roll off the plot while the player
  and vehicles drive straight over it.
* **Dynamic CCD**: `continuous_cd` switches on above 16 m/s and off below 10 m/s
  (hysteresis, reviewed at 10 Hz), so only genuinely fast objects pay for it. The
  hauler keeps it on permanently — 900 kg at 22 m/s must never tunnel.
* **Velocity caps** at 40 m/s linear / 20 rad/s angular, under Jolt's own
  ceiling, which keeps penetration and jitter bounded.
* **Kill plane** at y = -25: anything below is teleported back to its plot spawn
  through `PhysicsServer3D`, so Jolt never integrates a huge delta.
* **Felling pivots about the stump.** A trunk handed angular velocity about its
  own centre does nothing at all: one edge of its base drives into the ground
  and the contact constraint cancels the spin. The tree instead gets a rotation
  about its base plus the matching centre-of-mass velocity and two degrees of
  lean, so it swings over like a felled tree instead of sinking straight down.
* **Dragging pulls the point you grabbed.** Each physics step the hand works
  out the impulse that would bring the grabbed point toward the hold point,
  using the body's real mass and inertia *as seen from that point* (the 3x3
  effective-mass matrix `1/m - [r] I^-1 [r]`), caps it at a tonne of strength,
  and applies it there. A log held by one end swings from that end; a light
  billet comes at once and a heavy trunk comes slowly. No joint, so nothing to
  explode. The carry rack is still kinematic slots, for now.
* **Belts, splitters and truck beds are physical.** Nothing is locked down.
  A belt deck is a static body with a surface velocity, so the engine itself
  drags whatever rests on it along by friction: pieces ride at belt speed,
  climb ramps if they grip, tip over if they are stood on end, jam against
  anything in the way and clear when it goes, and fall off the end if nothing
  is there. A belt wakes whatever is on it while it runs; a stopped belt is a
  still deck and what is on it goes to sleep. The one convenience is at the far
  lip, where a piece that has reached a machine, bin or chute is dropped into
  it. Splitters are powered-roller plates: each piece gets an output when it
  lands and a friction-limited push toward it, so heavy pieces turn slowly.
  The **3-Way Splitter** is in build mode with the belts ($510): a 3 x 3 plate
  level with a belt's deck, one belt in at the back and belts off its left,
  front and right, dealing pieces out to each in turn. Aim at a side and press
  [R] to lock that way (a red-and-white gate comes down across it, and pieces
  go out the open ways only); [R] again opens it. Locks are kept in the save.
  Items entering a machine still become counters in its buffer.
* **Trigger volumes are geometry-checked.** `Area3D.get_overlapping_bodies()` can
  report a body that is no longer really inside — pooled items are detached
  without a clean exit event and the same node is re-used elsewhere. Sinks ran
  a point-in-box test (`Trigger`) before acting; without it a storage bin
  re-swallowed items it had just poured out, metres away.
* **The hauler has tyres, not a yaw torque.** It used to be steered by dropping
  a torque on the chassis and driven by a force through its centre of mass,
  which is why it handled like a trolley on ice: the body turned and the
  velocity carried straight on. Every wheel now works at its own contact patch -
  the front pair points where it is steered, the truck corners because those
  tyres bite, and what any tyre can do is bounded by the load that wheel is
  carrying, so a wheel in the air grips nothing. With nobody aboard the wheels
  lock and the truck sleeps, so a parked truck stays where it was left.
* **The truck's load is loose.** Whatever lies in the bed is an ordinary body
  held in by thick sides, a headboard over the cab and a tailgate. It adds its
  weight to the springs, surges forward under hard braking and fetches up on
  the headboard, and falls out if the truck goes over. The truck only keeps
  track of it: it counts what is in the bed, keeps it awake while moving, turns
  on continuous collision above 5 m/s so a piece thrown at a wall meets it,
  parks up only once the load has settled (and then puts truck and load to
  sleep in the same step), and saves the load relative to the bed. Unloading
  drops the tailgate and walks the load out the back on a slick floor.
* **Logs collide as octagons.** Jolt lets a true cylinder lying on its side
  sink about 10 cm into a moving body - a truck bed, a belt - where it rests
  fine on static ground. Round stock therefore uses the same eight-sided prism
  it is drawn as.
* **Forces are not pushed at a sleeping truck.** Jolt keeps forces added to a
  sleeping body and applies them all when it wakes, so a parked truck that was
  fed suspension forces every frame leapt ten metres the moment it was driven.

## Measured results

Headless, `--fixed-fps 60`, Intel Xeon @ 2.80 GHz (4 threads, cloud container —
a desktop CPU is roughly 2-4x faster). Times are wall-clock per simulated frame.
Budget is 16.67 ms.

### Integration tests (`scenes/tests.tscn`)

About 1,810 checks across 74 tests, all passing. Every test has to say it reached its
own end, so one that dies part way through - a parse error in what it exercises,
say - is reported as a failure instead of quietly contributing fewer checks.

Covered: data integrity across every cross-reference in the JSON tables;
deterministic daily prices; felling (the trunk arrives at the height, base
radius and taper the tree grew to, and topples); limb-by-limb cutting (a branch
comes off alone, the trunk parts at the height of the cut, the stump keeps
standing, and wood is conserved through every cut); resource fields filling to a
quota and stopping; terrain biomes, relief, levelled build sites, river depth,
fords and road marking; bucking; chunk pulling (the required pull is mass plus
the embedded share of it, and an under-strength pull does nothing); hammer
cracking (a heavier head takes fewer blows, and the ore adds up); the crusher;
milling, smelting and assembly with volume in equal to volume out; intake holes
gating what fits and machine levels widening them; the sell yard buying only
what the player owns inside it; orders paying out and surviving a save; storage;
every material's raw, first-step and final value checked through the shapes the
machines make (and that at least five break the pattern); the gem line (sander
polishes, gem cutter facets); islands with a sea between, a bridged road that
gets a bridge, a crate that stays on the deck, and a walled valley with one way
in; belt-to-machine hand-off; belt ramps, borderless decks and stopping a belt;
splitter round-robin; belt-logic filtering; building placement, cost and refund;
plans filling with one material and turning solid, with offcuts returned and
material reclaimed; save-load round-trip; plot expansion; upgrades; the store
(shelf pricing off the track, taking a box not being owning it, paying at the
till, opening a paid box, unpaid stock going back on the shelf, land at the
desk); carry limits by length and lift limits by weight; ownership and its
persistence; hauler driving with a loose load that stays in when pulling away
and braking, weighs the truck down, surges forward and spills when inverted,
saves with the truck and tips out the back; belts carrying by friction, jamming
against a wall and clearing; vehicle pads spawning one truck and replacing it; winch and
crane power ratings; kill plane; item cap; a full automated base under load;
the tunnel machines (one plank per log, sanding and refining adding value and
surviving a save, crushing, smelting to bars, an oversized trunk jamming on the
mouth until a higher tier widens it, a belt running into a machine); the tool
hotbar and inventory; dragging by the grabbed point; the build-mode editor
(move, stretch, turn, lift, refuse an overlap, save the result); the sectioned
stores with tiers and the summit store; every vehicle; debug money;
and the interface's logic - settings coercing, persisting and resetting, the
title screen reading a save without loading it, prompt keys told apart from
counts in brackets (`[E]` is a key, `[2/5]` is not), compass bearings through
north, and the getting-started checklist catching up with a loaded game but not
counting a starting float as a sale; and the world - terraces with no sheer
plinths and a sea round the edge, caves with rock over every part of them and a
floor you land on, greeble meshes that all face outward, fields that retire only
far, untouched nodes, pieces that fell through the ground coming back up, and
traders' premiums and once-a-day caches (including across a save).

### Physics benchmark (`scenes/bench.tscn`)

| scenario | avg ms | p95 | max | at rest | % budget |
| --- | --- | --- | --- | --- | --- |
| 100 logs dropped | 0.92 | 2.45 | 2.95 | 0.18 | 6% |
| 250 logs dropped | 6.27 | 9.73 | 20.65 | 0.21 | 38% |
| **500 logs dropped** | **12.59** | **17.75** | **37.12** | **0.50** | **76%** |
| 1000 logs dropped | 40.58 | 60.12 | 97.23 | 16.23 | 243% |
| 2000 logs dropped | 67.22 | 99.82 | 120.78 | 91.65 | 403% |
| conveyor, surface velocity, fed 5/s | 0.68 | 1.08 | 1.90 | - | 4% |
| 20 dragged items over a 200 pile | 2.43 | 3.81 | 4.76 | - | 15% |
| 60 ore fired at 60 m/s (CCD) | 0.78 | 1.53 | 1.82 | - | 5% |
| continuous spawn/despawn churn | 2.69 | 3.64 | 5.55 | - | 16% |
| 1500 items into a 200 cap | 3.60 | 4.13 | 7.18 | 0.28 | 22% |

These figures were taken with cylinder colliders on round stock, which is now an
octagonal prism; they have not been re-measured. Round logs cost roughly 60%
more solver time than box stock and take longer to settle, because they roll. The last two
rows are deliberately past the point of no return and are there to show where it
is: the per-plot cap of 200 at tier 0, rising to 400, keeps real play in the top
third of the table, at a fifth to a quarter of budget.

* No tunnelling: 60 ore chunks at 60 m/s, 0 escaped the plot.
* No instability while dragging 20 items over a live 200-log pile: 0 escapes.
* Belts are surface-velocity belts, so they can jam. A piece at the far lip is
  handed to whatever machine is there, which keeps a straight line flowing.
* A settled pile still costs ~0.5 ms whatever its size.

### Whole game, headless (`scenes/smoke_world.tscn`)

The assembled world - a 2.5 km island map with rivers, roads and four bridges,
~1,350 trees of seventeen species and ~380 rocks of twenty-one kinds kept
stocked by their fields, the plot, tunnel machines, belts, the sell yard, both
stores, the hauler, the HUD and ~200 loose pieces - plus nine caves, sixteen
outposts, ~47,000 pieces of dressing and ~800 boulders - runs at **about 2.5
ms/frame average** headless, with trees felling, chunks breaking and machines
working. Building it takes about six seconds (terrain 2 s, dressing 2 s, forest
1.3 s; `PROFILE_LOAD=1` prints the breakdown). It also checks the spread: the
map is 2.5 km, the bridges end on dry road, dear ore is on average well over
twice as far out as cheap ore, the diamonds are all in the farthest cave, the
starmetal in the crater and the mahogany in the valley. A pickup and a log
truck have been driven over every bridge and down the causeway. Opening a journal page costs 15-25 ms of UI
the first time, and pages are only rebuilt when what they show changes.

The smoke run asserts the world's *contents* as well as its frame cost, which is
what makes it worth having: it was an empty forest that caught a broken species
table, and a missing signal handler that caught a world scene which compiled in
the test suite but not in the game. It also opens every journal tab, pauses and
resumes, and sells forty logs at once to check the feed folds them into one line.

## Against the design doc

The design document drives what is here. Line by line:

**Built and tested.** Trees as cut-able cylinder groups with leaves that go with
the wood they hang on; felled wood with real mass and collision that can be cut
smaller and fed to a sawmill that returns the same volume in handier shapes.
Irregular ore chunks with ore-coloured seams; chunks taken whole by a pull equal
to their mass plus the embedded fraction of it, or hammered apart by randomly
generated cracks that deepen faster under a heavier head; a crusher that does it
wholesale; ore smelted to higher value density. Value as density times volume,
periodic price swings, and orders that reward delivering quantities of named
materials. A yard where the shopkeep buys everything of yours standing in it.
Lifting to 100 kg and moving to 1000 kg. A loose load in a walled truck bed. Third-person driving on real wheels, a winch that hooks
anything and drags the lighter end, a crane with a boom you swing, luff and
run out and a hook that hoists and swings its load, and a rating on both at
which the drum stalls. A square of property to
build on, freecam build mode, quarter-turn rotation on three axes, and schematic
shapes that solidify when filled with their own volume of one material. Machines
that must be placed and fed, and vehicle spawn pads that deliver one copy and
recall the old one. A store you walk into, with stock in labelled boxes that
vanish if carried out unpaid, and land sold at the desk. A large simplistic
polygonal map with six biomes, rivers to ford or bridge, water that slows you
and drowns a driver's seat, and roads that are quicker to drive. Ownership that
follows picking up, buying and machines on your own plot, and that decides what
a save remembers. Three to five levels per tool and machine, with machine levels
widening real intake holes, and belts as ramps, borderless decks and
retractables.

**Not built yet.** Caves - the doc wants large extensive ones with rocks and ore
inside, and a heightfield cannot express an overhang, so that needs a different
representation of the land than the one here. Build-mode gizmo handles and
multi-select: the doc asks for cardinal handles on a selected object for finer
translation, rotation and scale, and for selecting several objects and moving
them as one; placement here is still grid-snapped, which is what keeps the
occupancy grid exact. Trailers.
Belt curves and tees as distinct pieces, though filters and splitters already
cover the sorting the doc lists beside them.

## Status and next steps

Done: physics foundation, the full loop from standing tree to sold material,
volume-conserving materials and machines, limb-by-limb felling and bucking,
embedded ore and hammer-cracking, quota-stocked resource fields, a 2.5 km
island map with rivers, roads, bridges and hidden places, 36 materials each
with raw / first-step / final values, plot building with JSON save/load, schematic shapes,
automation (belts, ramps, splitters, filters, storage, tunnel machines), two
physical stores in sections, seven vehicles, a tool hotbar and inventory, a
build-mode editor with move, scale and rotate handles, the sell yard and standing orders, vehicle pads, the winch and
crane, ownership and persistence, and daily-changing prices.

Natural next steps, in the order they would pay off: carry working like drag
(lift off the ground; drag stays on it); multi-select in build mode; belt
curves and tees; trailers; streaming the dressing and far forests in by
distance to cut load time; and
performance work on the manager's per-frame loop (the ~0.4 ms floor at rest is
that loop, not the solver).
