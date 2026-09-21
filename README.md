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
| LMB | chop tree / mine rock (place, in build mode) |
| RMB | pick item onto the carry rack (remove building, in build mode) |
| F | heavy-drag a single item / release |
| Q / G | drop one / drop everything |
| E | deposit into a machine, bin or sell zone |
| Shift+E | empty a storage bin back onto the ground |
| B / R / wheel | build mode / rotate / cycle building |
| M / U / F1 | market board / shop & upgrades / help |
| F5 / F9 / F8 | save / load / new game |
| V / X / C | enter-exit hauler / unload it / flip it back upright |

## The loop

1. **Chop** pine, oak and ironwood in the forest ring; **mine** iron, copper and
   gold in the quarry to the west.
2. **Haul** with the carry rack (capacity is an upgrade), the heavy drag, or the
   flatbed hauler once you can afford it. A full rack slows you down.
3. **Process**: sawmill turns logs into planks, furnace smelts ore into ingots,
   workbench combines planks and ingots into crates and toolkits.
4. **Sell** at the gold depot pad or, once built, a sell chute on your own plot.
   Prices are redrawn every in-game day, so stockpile in bins when a price is low.
5. **Upgrade** axe, pickaxe, carry rack and boots; **expand** the plot through
   four tiers; **unlock** the furnace, workbench and fast conveyors.
6. **Automate**: belts hand items straight into machines, splitters fan output
   out three ways, storage buffers the surplus, and a sell chute closes the loop
   without you walking a step.

## Architecture

```
scripts/core/      Layers, Tuning, InputSetup, Trigger (trigger-volume guard)
scripts/systems/   GameData (autoload), Economy (autoload), PlayerState (autoload), SaveSystem
scripts/data/      RecipeDef, MachineDef, BuildingDef
scripts/physics/   LooseItem, LooseItemManager, ItemDef
scripts/world/     ChoppableTree, OreRock, Machine, StorageBin, SellZone,
                   Conveyor, Splitter, World, StressWorld, StressTest
scripts/build/     Plot (grid, placement, persistence), BuildSystem (ghost)
scripts/player/    Player
scripts/vehicle/   Hauler
scripts/ui/        GameHUD, StressHUD
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

* **Primitive shapes only.** Every loose item is a `BoxShape3D`; trees, rocks,
  decks, machines and terrain are boxes too. No convex hulls or trimesh anywhere
  in the dynamic path.
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
* **Vehicle cargo has collisions disabled while aboard.** A kinematic crate
  clipping its carrier's own hull fights the solver every frame; with collisions
  left on, the loaded hauler crawled 5 m in 2.5 s instead of 30 m.

## Measured results

Headless, `--fixed-fps 60`, Intel Xeon @ 2.80 GHz (4 threads, cloud container —
a desktop CPU is roughly 2-4x faster). Times are wall-clock per simulated frame.
Budget is 16.67 ms.

### Integration tests (`scenes/tests.tscn`)

193 checks across 19 tests, all passing: data integrity, deterministic daily
prices, chopping, mining, machine processing and rejection, sell pricing, storage
store/dispense, belt-to-machine hand-off, splitter round-robin, building
placement/cost/refund/bounds, save-load round-trip, plot expansion, upgrades,
carry rack limits and deposits, hauler driving/cargo/stability, kill plane,
item cap, and a full automated base under load.

### Physics benchmark (`scenes/bench.tscn`)

| scenario | avg ms | p95 | max | at rest | % budget |
| --- | --- | --- | --- | --- | --- |
| 100 logs dropped | 0.71 | 1.35 | 1.71 | 0.42 | 4% |
| 250 logs dropped | 2.31 | 3.58 | 6.41 | 0.42 | 14% |
| **500 logs dropped** | **6.51** | **9.20** | **17.23** | **0.39** | **39%** |
| 1000 logs dropped | 18.24 | 26.02 | 32.64 | 0.72 | 109% |
| 2000 logs dropped | 51.26 | 76.49 | 122.53 | 1.02 | 308% |
| conveyor, kinematic, fed 5/s | 0.64 | 1.03 | 1.37 | - | 4% |
| conveyor, surface velocity, fed 5/s | 0.76 | 1.20 | 1.79 | - | 5% |
| 20 dragged items over a 200 pile | 1.88 | 2.88 | 3.66 | - | 11% |
| 60 ore fired at 60 m/s (CCD) | 0.79 | 1.85 | 2.94 | - | 5% |
| continuous spawn/despawn churn | 2.32 | 3.23 | 4.16 | - | 14% |
| 1500 items into a 200 cap | 3.83 | 4.82 | 6.57 | 0.41 | 23% |

* No tunnelling: 60 ore chunks at 60 m/s, 0 escaped the plot.
* No instability while dragging 20 items over a live 200-log pile: 0 escapes.
* Surface-velocity belts jam at the output; kinematic belts do not. Automation
  uses the kinematic path.
* A settled pile costs ~0.4 ms whatever its size.

### Whole game, headless (`scenes/smoke_world.tscn`)

The assembled world (90 trees, 34 rocks, plot, machines, belts, sell chute,
hauler, ~110 loose items) runs at **0.78 ms/frame average, 4.99 ms worst**, with
machines producing and the sell chute paying out.

## Status and next steps

Done: physics foundation, full MVP loop, plot building with JSON save/load,
automation (belts, splitters, storage, sell chutes), ore mining, plot expansion,
upgrades, the hauler, and daily-changing prices.

Natural next steps: logic gates and filters on the belt network, more machine
tiers, a proper art pass, quests or contracts to steer progression, and
performance work on the manager's per-frame loop (the ~0.4 ms floor at rest is
that loop, not the solver).
