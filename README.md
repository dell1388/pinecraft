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

| Key | Action |
| --- | --- |
| WASD / Shift / Space | move, sprint, jump |
| LMB | chop tree / buck felled wood / mine rock (place, in build mode) |
| RMB | pick item onto the carry rack (remove building, in build mode) |
| F | heavy-drag a single item / release |
| Q / G | drop one / drop everything |
| E | deposit into a machine, bin or sell zone |
| Shift+E | empty a storage bin back onto the ground |
| B / R / wheel | build mode / rotate / cycle building |
| M / U / F1 | market board / shop & upgrades / help |
| F5 / F9 / F8 | save / load / new game |
| V / X / Z / C | enter-exit hauler / unload all / drop one / flip it upright |

## The loop

1. **Fell** pine, oak and ironwood in the forest ring. A felled tree does not
   turn into tidy logs: the trunk drops as one piece with exactly the shape it
   grew to - a 7 m tapered pole weighing a quarter of a tonne - and its branches
   come off as their own pieces.
2. **Buck** that trunk down with the axe. Each cut halves a piece, and the work
   a cut takes scales with the cross-section at the cut, so a fat trunk is
   several swings and a branch is one. Cut until the pieces are small enough to
   carry (or drag them, or load them on the hauler whole).
3. **Mine** iron, copper and gold in the quarry to the west.
4. **Haul** with the carry rack (a volume, not a slot count), the heavy drag, or
   the flatbed hauler. A full rack slows you down. Anything in the hauler's bed
   becomes part of the truck and cannot fall out; `X` unloads the lot, `Z` drops
   one.
5. **Process**: the sawmill takes wood in one end and pushes square lumber out
   the other; the furnace is fed through the roof and pours billets out of its
   side; the workbench assembles lumber and metal into crates and toolkits.
6. **Sell** at the gold depot pad or, once built, a sell chute on your own plot.
   Prices are redrawn every in-game day, so stockpile in bins when a price is low.
7. **Upgrade** axe, pickaxe, carry rack and boots; **expand** the plot through
   four tiers; **unlock** the furnace, workbench and fast conveyors.
8. **Automate**: belts hand items straight into machines, splitters fan output
   out three ways, filters sort by item type (invert them with Shift+E), storage
   buffers the surplus, and a sell chute closes the loop without you walking a
   step.

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

* **Trees** are a flared stump, a tapered trunk, four to seven angled branch
  cylinders and a cone of foliage on each branch end. The trunk mesh and the
  piece that falls are the same frustum, which is what makes "it keeps the shape
  it grew" true rather than approximate.
* **Machines** are shells, not blocks: each wall is built as up to four boxes
  around a rectangular opening, so the intake and outlet are real holes you can
  see material go into and come out of. The sawmill carries a blade through a
  slot in its roof and infeed/outfeed lips; the furnace has a chimney and a
  glowing vent; the workbench has a top and a tool rack.
* **The hauler** has a cab, deck boards, headlights, and four wheels with hubs
  that spin with ground speed and steer with the front axle. The wheels are
  decoration over the same four suspension raycasts as before.
* **Ore rocks** are a cluster of tilted boxes with bright ore seams, tinted from
  whatever they drop.
* Collision stays primitive throughout: one cylinder or box per loose piece, a
  handful of boxes per machine shell, one box per tree.

## Architecture

```
scripts/core/      Layers, Tuning, InputSetup, Trigger (trigger-volume guard)
scripts/systems/   GameData (autoload), Economy (autoload), PlayerState (autoload), SaveSystem
scripts/data/      RecipeDef, MachineDef, BuildingDef
scripts/physics/   LooseItem, LooseItemManager, ItemDef
scripts/world/     ChoppableTree, OreRock, Machine, StorageBin, SellZone,
                   Conveyor, Splitter, Filter, World, StressWorld, StressTest
scripts/build/     Plot (grid, placement, persistence), BuildSystem (ghost)
scripts/player/    Player
scripts/vehicle/   Hauler
scripts/ui/        GameHUD, StressHUD
scripts/core/      ... plus Solid (volume and cutting maths)
data/              items, recipes, buildings, upgrades, prices  (all JSON)
tools/             Bench, Tests, SmokeWorld, Probe
```

Everything numeric lives in `data/*.json`: items and their mass, size, colour,
base value and volatility; recipes; building costs, footprints and unlocks;
upgrade tracks; plot expansion tiers. `GameData` cross-validates every reference
at load, so a typo in a data file fails loudly instead of silently doing nothing.

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
* **Machines, belts, splitters and vehicle cargo are kinematic.** Items entering
  a machine become counters in a buffer and leave the physics world entirely;
  belts own captured items outright and slide them by transform. Nothing in the
  automation layer depends on friction or luck.
* **Trigger volumes are geometry-checked.** `Area3D.get_overlapping_bodies()` can
  report a body that is no longer really inside — pooled items are detached
  without a clean exit event and the same node is re-used elsewhere. Sinks ran
  a point-in-box test (`Trigger`) before acting; without it a storage bin
  re-swallowed items it had just poured out, metres away.
* **Vehicle cargo is part of the vehicle, not a passenger.** Loading removes the
  item from the physics world and parents a plain mesh to the hull: no collider,
  no body, no velocity of its own. Nothing can shake, push, grab or sell a load
  in transit, collisions and rollovers included, and cargo costs zero per frame.
  Anything resting in the bed is absorbed on a 10 Hz sweep (and in full the
  moment a driver climbs in), so there is never a loose item aboard waiting to
  be flung off. Unloading spawns the real items back behind the truck.

## Measured results

Headless, `--fixed-fps 60`, Intel Xeon @ 2.80 GHz (4 threads, cloud container —
a desktop CPU is roughly 2-4x faster). Times are wall-clock per simulated frame.
Budget is 16.67 ms.

### Integration tests (`scenes/tests.tscn`)

297 checks across 23 tests, all passing: data integrity, deterministic daily
prices, felling (the trunk arrives at the height, base radius and taper the tree
grew to, and topples), bucking (splits halve, volume is conserved, stubs cannot
be split forever), mining, milling, smelting and assembly (volume in equals
volume out, boards match the outlet cross-section, nothing exceeds the maximum
cut length), machine rejection, volume pricing at the sell zone, storage
store/dispense, belt-to-machine hand-off, splitter round-robin, belt-logic
filtering, building placement/cost/refund/bounds, save-load round-trip, plot
expansion, upgrades, carry limits by volume (including refusing a whole trunk),
hauler driving and cargo retention through a full-speed collision, a rollover,
a recovery and a save/load, kill plane, item cap, and a full automated base
under load.

### Physics benchmark (`scenes/bench.tscn`)

| scenario | avg ms | p95 | max | at rest | % budget |
| --- | --- | --- | --- | --- | --- |
| 100 logs dropped | 1.08 | 2.04 | 2.59 | 0.46 | 6% |
| 250 logs dropped | 4.24 | 5.86 | 7.33 | 0.43 | 25% |
| **500 logs dropped** | **10.81** | **14.46** | **18.30** | **0.57** | **65%** |
| conveyor, kinematic, fed 5/s | 0.70 | 1.18 | 1.61 | - | 4% |
| conveyor, surface velocity, fed 5/s | 0.89 | 1.39 | 1.88 | - | 5% |
| 20 dragged items over a 200 pile | 2.57 | 4.41 | 6.12 | - | 15% |
| 60 ore fired at 60 m/s (CCD) | 0.64 | 1.50 | 2.04 | - | 4% |
| continuous spawn/despawn churn | 2.61 | 3.58 | 5.37 | - | 16% |
| 1500 items into a 200 cap | 4.25 | 4.95 | 8.72 | 0.43 | 25% |

These are cylinders now, not boxes. Round logs cost roughly 60% more solver
time than the old box stock and take longer to settle, because they roll -
500 of them went from 6.6 ms to 10.8 ms a frame. Still inside budget, and the
per-plot cap of 200 keeps real play at about a fifth of it.

* No tunnelling: 60 ore chunks at 60 m/s, 0 escaped the plot.
* No instability while dragging 20 items over a live 200-log pile: 0 escapes.
* Surface-velocity belts jam at the output; kinematic belts do not. Automation
  uses the kinematic path.
* A settled pile still costs ~0.5 ms whatever its size.

### Whole game, headless (`scenes/smoke_world.tscn`)

The assembled world (90 trees, 34 rocks, plot, machines, belts, sell chute,
hauler, ~100 loose pieces) runs at **0.97 ms/frame average, 11.5 ms worst**,
with trees felling, rocks breaking, machines milling and the sell chute paying
out. The smoke run asserts the world's contents as well as its frame cost - it
was a silently empty forest that caught a broken species table here.

## Status and next steps

Done: physics foundation, full MVP loop, volume-conserving materials, felling
and bucking, plot building with JSON save/load, automation (belts, splitters,
filters, storage, sell chutes), ore mining, plot expansion, upgrades, the
hauler, and daily-changing prices.

Natural next steps: logic gates and filters on the belt network, more machine
tiers, a proper art pass, quests or contracts to steer progression, and
performance work on the manager's per-frame loop (the ~0.4 ms floor at rest is
that loop, not the solver).
