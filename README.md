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
godot --path . scenes/stress_test.tscn                       # physics playground
```

If you add a new script with a `class_name`, run
`godot --headless --editor --quit --path .` once so the global class cache picks
it up; headless runs resolve class names from that cache.

### Controls

The game opens on a title screen over a flyover of the valley: **Continue**
picks up the save (it tells you the day, money and when it was saved), **New
Game** starts over after asking, and Settings and Controls are there before
you play. The full list of keys is on the Controls page and in the journal
(F1), and the few that matter right now are always in the bottom-right corner.

| Key | Action |
| --- | --- |
| WASD / Shift / Space | move, sprint, jump |
| LMB | cut the limb under the crosshair / hammer a chunk / buck felled wood |
| RMB | pick a piece onto the carry rack |
| F | heavy-drag a piece, or heave a chunk out of the ground |
| Q / G | drop one / drop everything |
| E | deposit, open a paid box, talk to the shopkeep, stop or start a belt |
| Shift+E | empty a storage bin back onto the ground |
| B | build mode (freecam: WASD, mouse, Shift/Ctrl for height) |
| Wheel / 1-7 (build) | choose from the build bar |
| Z / X / C (build) | rotate the ghost about each axis, in quarter turns |
| LMB / RMB (build) | place / remove |
| Esc | pause menu (leaves build mode first, closes the journal first) |
| Tab / M / P / U / F1 | journal: orders / map / market / upgrades / controls |
| H / F3 | hide the key hints / debug readout |
| F5 / F9 / F8 | quick save / quick load / new game (asks first) |
| V | get in and out of the hauler (third-person while driving) |
| E / G (driving) | hook and unhook the winch / reel it in |
| F (driving) | crane: take hold of a piece, or let it go |
| WASD / Shift / Ctrl / R / T (crane) | drive the load itself, and turn it |
| X / Z / C (not in build mode) | unload all / drop one / flip the truck upright |

## Interface

- **Title screen** over the live world, with a camera circling the valley.
  New Game rebuilds the scene from nothing rather than scrubbing the old one.
- **Pause menu** (Esc, or alt-tab) over frosted glass: resume, settings,
  controls, save, load, back to the title, quit. Leaving for the title or
  quitting saves; so does closing the window.
- **Settings** (`user://settings.cfg`, kept apart from the save so a new game
  keeps them): mouse sensitivity, invert Y, field of view; fullscreen, v-sync,
  render scale, shadows, ambient occlusion, bloom, view distance, and whether
  the sun moves; interface scale, key hints, compass, checklist, frame rate;
  autosave. Everything applies as you move it.
- **HUD**: money that counts up, with the change floating off it; the day and
  how long until prices move; the carry rack as a bar; a compass with the plot,
  the sell yard, the store, the quarry and your truck on it; the open orders
  with progress bars; the prompt for what you are aiming at, with its keys drawn
  as keycaps; a feed of what just happened (a yard of fifty logs is one line,
  not fifty); and the keys for what you are doing now.
- **Build bar**: in build mode, every building you own with its size and cost
  (red when you cannot afford it), a line on what it is for, and why the ghost
  will not go where you are pointing. The pad's grid brightens so you can see
  what it will snap to.
- **Driving**: speed and cargo gauges.
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
4. **Move it.** You can lift 100 kg and drag 1000 kg; past that you need the
   truck's winch or its crane. A full rack slows you down, which is the reason
   to build belts. The hauler's bed has tall sides, a cab guard and a
   tailgate; what you put in it is a real, loose load, so drive accordingly.
5. **Process.** The sawmill's intake is a real hole - a trunk that will not fit
   through it does not go in, so you buck it first or buy a mill with a bigger
   mouth. Machines conserve volume exactly: what goes in comes back out as
   pieces with the outlet's cross-section, at whatever length that volume needs.
6. **Sell** at the yard. Drop material inside the fence, walk up to the shopkeep
   and ask; everything of yours in the yard is bought at once at the day's rate,
   with whatever is still in your arms going over the counter with it. Standing
   orders pay a bonus on top for a volume of a named material.
7. **Buy** at the store, which is a shop you walk into. Stock sits in labelled
   boxes on shelves; carry what you want to the counter and the till charges for
   it. Taking a box off a shelf is not owning it, and carrying an unpaid one out
   of the door puts it back. A paid box is yours to open wherever you like. Land
   is sold at the desk.
8. **Build.** Machines and belts go on the plot grid. Structures are built out of
   *material*: place a translucent plan, touch material to it, and it fills by
   exactly that piece's volume. The first piece decides what the shape is made
   of and nothing else will go in after that; full, it turns solid and takes the
   material's colour.
9. **Automate**: belts hand items straight into machines, ramps climb, splitters
   fan output three ways, filters sort by type, belts can be stopped, storage
   buffers the surplus, and a sell chute closes the loop.

## The map

The land is an island, 600 m across, running down to beaches and a sea that
goes to the horizon. Height and biome come from two low-frequency fields,
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
150 m, so the whole island costs a few dozen draw calls in view. About 130
boulders, big enough to walk round, have colliders.

Everything else is carved into that afterwards, in order:

* **Build sites are levelled** - the plot, the yard, the store and the quarry -
  so a factory floor is never on a slope.
* **Rivers are cut down through** whatever the land was doing, with banks that
  fall away over a few metres. Each has stretches left shallow enough to drive
  through; everywhere else wants a bridge. Water deeper than a metre is swum
  rather than waded, slowly, and a hauler whose driver seat goes under can no
  longer be driven.
* **Roads are graded across** it - the whole carriageway to one height, which
  follows the land lengthwise off a smoothed profile but does not tilt sideways.
  Blending in from the centre-line instead leaves a camber, and a cambered road
  is one you slide off. The carriageway has to be comfortably wider than a
  terrain cell or it is narrower than the grid representing it, which is why it
  is 18 m across on a 6 m grid, with a 20 m shoulder blending back into the
  land. Where a road meets a river it crosses at a ford rather than filling the
  river in, and driving one is slightly quicker.

Resource fields sample the ground, so trees and rocks stand on it and avoid the
water, the roads and the levelled build sites.

**Fields churn.** A field fills to its quota and used to stop there for good,
so once you had cleared the woods near home every tree left was a long walk
away. Now a full field every half-minute or so retires one *untouched* tree or
chunk at least 90 m from you, and the refill that follows can land anywhere -
including near you. Nothing you have started on is ever taken, nothing vanishes
in view, and nothing new appears within 30 m of you.

**Ore is all over the map**, not only in the quarry: iron in the hills and
woods, copper in the desert and mountains, a little gold up in the snow. The
quarry is still where there is most of everything, close to home. Most of the
gold is underground.

### Caves

Three caves, placed where the hill is high enough over the whole footprint that
nothing pokes out, the mouth faces open ground, and the chamber floor stays
above the sea. The heightfield leaves out the two cells a cave's trench runs
through; everything below is built: a timber-shored trench down to a portal, a
sloping tunnel with rails and lamps, and a chamber under the hill with pillars,
a ledge, stalagmites, glowing crystals and a mine cart. Each has a field of
ore on the floor - richer than the surface, mostly gold. Going underground
dims the sky light to the cave's own, turns on a lamp on your hat, and hides
the landmark labels that would otherwise show through the rock.

### Places

Found for their own country by the terrain rather than put at fixed spots, so
each sits on a level patch of the right ground:

| Place | Where | What for |
| --- | --- | --- |
| Dune Trading Post | desert | pays +45% for lumber, +30% for goods |
| Frostline Post | snow or taiga | pays +45% for metal, +35% for ore |
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
you what you will be cutting, and the hard woods are out in the hard country:

| Tree | Grows in | Cuts into |
| --- | --- | --- |
| Pine | woodland, taiga | pine |
| Spruce | snowland | spruce |
| Oak | woodland | oak |
| Willow | swamp (standing in shallow water) | willow |
| Ironwood | mountains | ironwood |
| Desert Ironwood | desert | ironwood |

Tree and wood are still separate ideas - the two ironwoods are different trees
cutting the same wood - but each biome that is worth a trip pays for it. Willow
is the odd one: poor value by the cubic metre and very light, so it pays well
for what it weighs and is worth carrying by hand where oak is worth a truck.

Quotas follow how much country each species actually has, so a seed that grows
little swamp gets a few willows rather than an empty field grinding away at a
region that is not there.

## Materials are volumes

Nothing in the game is counted in "items". Every piece is a solid with real
dimensions, and machines conserve volume rather than swapping one item id for
another:

* A piece is a box or a tapered cylinder whose long axis is local +Y. Its
  **mass is density x volume** and its **price is rate x volume**, both from
  `data/items.json`. A 4 m trunk weighs what a 4 m trunk should.
* **The sawmill** measures what it is fed, mills at a fixed cubic metres per
  second, and pushes out boards with the outlet hole's cross-section, cut to
  whatever length that volume needs and never longer than it can cut in one
  piece. Feed it a fat 2 m log and you get long boards; feed it a branch and you
  get a short one. In, out and on the ground always add up.
* **The furnace** does the same through a roof hatch and a side vent, with
  billets instead of boards: the bar's length is what carries the volume.
* **The workbench** works the other way round - it consumes *volume by
  category* (0.12 m3 of any lumber plus a little metal makes a crate), so any
  offcut length is usable.
* Because value is per cubic metre, milling never creates or destroys money.
  What changes is the **rate**: lumber is worth more per cubic metre than the
  wood it came from, and the day's market decides by how much.
* Bucking, splitting, storing, loading and unloading all conserve volume too,
  and the test suite asserts it to four decimal places at every step.

## Models

Still no asset files: every mesh is built in code from primitives, just more of
them than before.

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
* **Ore chunks** are slabs of rock with the ore breaking out of them as
  crystals, so iron, copper and gold read differently at a glance and gold
  catches the light - sunk into the ground by however much is buried, and
  drawn from the ore left in them, so hammering a piece off visibly shrinks the
  rock. Open cracks are dark seams that lengthen as they deepen.
* **Machines** are shells, not blocks: each wall is built as up to four boxes
  around a rectangular opening, so the intake and outlet are real holes you can
  see material go into and come out of - and they *are* real holes, since a
  piece has to fit through one to go in. Upgrading a machine rebuilds its shell
  around the new mouth. Every machine is framed on its edges, plated and vented
  on its solid faces, stripes under its holes, and has a control box with a
  **status light**: green working, amber waiting, red stopped with its outlet
  full. Then each is its machine - the sawmill a toothed blade through the roof,
  a finned motor, in-feed rollers and a sawdust chute; the furnace brick
  courses, a banded chimney and a glowing mouth that lights the ground; the
  crusher a hopper, a spoked flywheel and a drive belt; the workbench a vise,
  a pegboard of tools and a lamp.
* **Belts** are a rubber belt between steel channels, with rollers at the ends,
  legs down to the pad on ramps, visible rails where they have them, and
  **chevrons painted on the belt pointing the way it runs** (cyan on the fast
  belt). Splitters and filters have a turntable and an arrow to each output.
* **The hauler** has a cab with glass and mirrors, a light bar, a grille,
  bumper, headlights and tail lights, an exhaust stack, mudguards, stake posts
  round the bed, and wheels with a tread, rims and lug nuts that spin with
  ground speed and steer with the front axle. Its winch cable and crane boom
  are drawn last, from the hook to wherever the load ended up.
* **Nameplates.** Primitives can only say so much, and a plot is a field of
  similar boxes, so every placed building, the build ghost and the two landmarks
  carry a billboarded label. It is a stopgap until the models speak for
  themselves, and it is the difference between a factory and a guessing game.
* **The yard** is a fenced pad with a weighbridge, a plank hut with a tin roof
  and a serving hatch, and a shopkeep in an apron and a hat. **The store** has
  a parapet, a striped awning over the door, a sign, lit windows, lamps, a
  bench and crates outside, and shelving, a counter and a land desk inside.
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
                   StorageBin, SellZone, SellYard, Store, VehiclePad,
                   Conveyor, Splitter, Filter, World, StressWorld, StressTest
scripts/build/     Plot (grid, placement, persistence), BuildSystem (freecam
                   ghost), Schematic (shapes filled with material)
scripts/player/    Player
scripts/vehicle/   Hauler, VehicleRig (winch and crane)
scripts/ui/        UITheme, UIKit, GameHUD, Compass, Journal, MapView, KeyGuide,
                   MainMenu, PauseMenu, SettingsPanel, StressHUD
assets/fonts/      Rubik, Lilita One (SIL OFL)
data/              items, recipes, buildings, upgrades, prices, quests, store
tools/             Bench, Tests, SmokeWorld, Probe
```

Everything numeric lives in `data/*.json`: items and their mass, size, colour,
base value and volatility; recipes; building costs, footprints and unlocks;
upgrade tracks; plot expansion tiers; standing orders; what the store stocks.
`GameData` cross-validates every reference at load, so a typo in a data file
fails loudly instead of silently doing nothing. Prices are never written twice:
a boxed axe on a shelf costs whatever the next level of the axe track costs, and
a crated machine costs that building's unlock price until you own one and its
next level afterwards.

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
* **Carrying is kinematic, dragging is velocity-driven.** Rack items are frozen
  (`FREEZE_MODE_KINEMATIC`) and snapped to slots: no solver cost, no jitter. The
  single-item heavy drag steers the body's velocity toward a hold point, which is
  stable at any mass where a camera-to-log joint is the classic way to make a
  solver explode.
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

906 checks across 55 tests, all passing. Every test has to say it reached its
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
belt-to-machine hand-off; belt ramps, borderless decks and stopping a belt;
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

The assembled world - a 600 m biome map with rivers and roads, 90 trees and 33
ore chunks kept stocked by their fields, the plot, machines, belts, the sell
yard, the store, the hauler, the HUD and ~130 loose pieces - plus three caves,
nine outposts, ~9,000 pieces of dressing and ~130 boulders - runs at **about
1.5 ms/frame average**, with trees felling, chunks breaking, machines milling
and the sell chute paying out. Building the world and the interface costs one
frame of about 75 ms at startup; opening a journal page costs 15-25 ms of UI
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
Lifting to 100 kg and moving to 1000 kg. A loose load in a walled truck bed. Third-person driving, winches that hook to any solid
surface, a crane that hands the player the *object* rather than the boom, and a
power rating on both past which nothing happens at all. A square of property to
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
occupancy grid exact. Outriggers, and vehicles beyond the one hauler - the
non-linear vehicle progression the doc describes (fast and small, slow and
strong, crane and no bed) needs more than one chassis to be a progression.
Belt curves and tees as distinct pieces, though filters and splitters already
cover the sorting the doc lists beside them.

## Status and next steps

Done: physics foundation, the full loop from standing tree to sold material,
volume-conserving materials and machines, limb-by-limb felling and bucking,
embedded ore and hammer-cracking, quota-stocked resource fields, a biome map
with rivers and roads, plot building with JSON save/load, schematic shapes,
automation (belts, ramps, splitters, filters, storage, sell chutes), the
physical store, the sell yard and standing orders, vehicle pads, the winch and
crane, ownership and persistence, and daily-changing prices.

Natural next steps, in the order they would pay off: caves and the terrain
representation they need; the build-mode gizmo and multi-select; a second and
third vehicle so the vehicle upgrade path is a real choice; belt curves; and
performance work on the manager's per-frame loop (the ~0.4 ms floor at rest is
that loop, not the solver).
