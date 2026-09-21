# Pinecraft

Single-player 3D sandbox/tycoon: chop trees, haul logs, process them at machines,
sell, upgrade, build on your plot, then automate the whole thing.

**Engine:** Godot 4.4 with Jolt Physics (`physics/3d/physics_engine = "Jolt Physics"`).
No multiplayer. Primitive shapes only, no third-party assets.

## Status

Step 1 of the roadmap: the physics stress-test scene. The gameplay loop
(sawmill/furnace, money, upgrades), plot building and automation come after the
physics budget has been proven.

## Running

```bash
# playable stress test
godot --path . scenes/stress_test.tscn

# headless benchmark (writes bench_results.json)
godot --headless --path . --fixed-fps 60 scenes/bench.tscn          # full sweep
godot --headless --path . --fixed-fps 60 scenes/bench.tscn -- --quick
```

### Stress-test controls

| Key | Action |
| --- | --- |
| WASD / Shift / Space | move, sprint, jump |
| LMB | chop tree (or throw the carried item) |
| RMB | grab / drop an item (velocity-driven drag) |
| 1 / 2 | rain 100 / 500 logs into the funnel |
| 3 | clear all loose items |
| 4 | cannon: 20 ore at 60 m/s (CCD + velocity clamp test) |
| 5 | feed both conveyors |
| 6 | fell every tree at once |
| 7 | reset the worst-case timer |

## Measured results (step 1)

Headless sweep, `--fixed-fps 60`, Intel Xeon @ 2.80 GHz (4 threads, cloud
container — a desktop CPU should be roughly 2-4x faster). "avg/p95/max" is
wall-clock per simulated frame during the violent part of each scenario;
"rest" is the same pile once asleep. Budget is 16.67 ms.

| scenario | avg ms | p95 | max | rest | % budget |
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

* **No tunnelling.** 60 ore chunks fired at 60 m/s: 0 escaped the plot.
* **No instability under dragging.** 20 velocity-dragged items over a live
  200-log pile: 0 escapes, 0 kill-plane rescues, no solver blow-ups.
* **Sleep works.** A settled pile costs ~0.4 ms regardless of size; the residual
  is this project's own bookkeeping loop, not the solver.
* **Surface conveyors jam, kinematic ones do not.** Fed at the same rate, the
  kinematic belt delivered items continuously while the `constant_linear_velocity`
  belt backed up at the output and stalled completely. Automation will use the
  kinematic path.
* 500 loose items is a comfortable working target on this hardware; 1000 is the
  edge. The per-plot cap of 200 exists so a plot can never reach either.

## Physics design

Everything that decides whether the budget holds is centralised, not sprinkled
across per-object scripts.

* **Primitive shapes only.** Every loose item is a `BoxShape3D`; trees, decks and
  terrain are boxes too. No convex hulls, no trimesh for anything dynamic.
* **`LooseItemManager` owns every loose body.** One GDScript loop per physics
  frame does velocity clamping, CCD review and kill-plane rescue for all items.
  500 items cost one loop, not 500 `_integrate_forces` callbacks.
* **Sleeping is the main lever, with a fix on top.** Jolt sleeps whole
  *islands*, so one twitching log kept a 500-log pile awake for ~20 s after it
  had visually settled (measured). The manager therefore tracks per-plot peak
  motion and, once the entire plot has been still for 0.5 s, sleeps every free
  item in one pass — leaving no active body to re-wake the island. Settling
  dropped from ~20 s to ~4 s and a resting pile from 6.6 ms/frame to 0.4 ms.
  Sleeping bodies are skipped by the maintenance loop entirely.
* **Per-plot cap** (`Tuning.LOOSE_ITEMS_PER_PLOT`, default 200). Going over
  recycles the oldest free item instead of freeing it — pooled nodes are
  detached from the tree, so they leave the physics space completely and cost
  nothing in broadphase.
* **Layers and masks** live in `scripts/core/Layers.gd`
  (`WORLD / PLAYER / LOOSE / MACHINE / TREE / TRIGGER / VEHICLE`). Loose items
  never test against trigger volumes; triggers only test against loose items
  and the player.
* **CCD is dynamic.** `continuous_cd` is switched on above 16 m/s and off below
  10 m/s (hysteresis, reviewed at 10 Hz), so only genuinely fast objects pay.
* **Velocity caps** at 40 m/s linear / 20 rad/s angular, well under Jolt's own
  60 m/s ceiling, which keeps penetration and jitter bounded.
* **Kill plane** at y = -25: anything below is teleported back to its plot
  spawn with velocity zeroed, via `PhysicsServer3D` so Jolt never integrates a
  huge delta.
* **Dragging is velocity-driven, not joint-driven.** The carried body's velocity
  is steered toward a hold point with a clamped P-gain; a joint between the
  camera and an 8 kg log is the classic way to make a solver explode.
* **Machines are kinematic.** `Conveyor` ships in two modes: `SURFACE`
  (`constant_linear_velocity`, items stay simulated) and `KINEMATIC` (an
  `Area3D` captures items, freezes them `FREEZE_MODE_KINEMATIC` and slides them
  along the belt by transform). The kinematic mode does zero solver work and
  cannot jam — it is what the automation layer will be built on.

## Layout

```
scripts/core/      Layers, Tuning, InputSetup
scripts/physics/   LooseItem, LooseItemManager, ItemDef
scripts/world/     ChoppableTree, Conveyor, StressWorld, StressTest
scripts/player/    Player (move, chop, grab/drag, throw)
scripts/ui/        StressHUD
data/              items.json (data-driven item table)
tools/Bench.gd     headless benchmark harness
```

## Roadmap

1. **Physics stress test** *(this step)*
2. MVP loop: chop → carry → sawmill/furnace → sell → upgrade tools
3. Plot building and saving (plot state as JSON)
4. Automation: conveyors, splitters, hoppers, simple logic
5. Ore mining, plot expansion, vehicles, daily-changing prices
