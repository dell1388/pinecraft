# Pinecraft

**Fell it, haul it, mill it, sell it - then build the machines that do it for you.**

Pinecraft is a physics-first logging and mining sandbox. Every log is a real,
loose, rolling solid with its own weight; every rock is part-buried and has to be
heaved out or hammered apart. Cut trees limb by limb, strap the load down (or
don't) and drive it over the bridges between islands, feed it down conveyors
through tunnel machines that plank, sand, crush, smelt, refine and cut gems, and
sell it at the yard for whatever the market pays today.

- A big island world with other islands beyond it - snowfields, desert, mountains,
  wet woods and a crater where something fell from the sky - joined by winding
  roads, bridges and a causeway.
- Cave networks under it all, well below sea level: big chambers and tight
  tunnels running back and forth, ice caves, desert caves, river caves, crystal
  and fungal caves, each with its own resources - and one tunnel that goes
  under the sea to an island you cannot reach any other way.
- Seventeen kinds of tree, twenty-odd ores and gemstones, and materials that do
  not always behave: some are worth more raw, some only pay once they are
  fully refined.
- Seven vehicles, from a quad to a log truck and a crane truck; two stores; a
  build mode with handles for moving, scaling and rotating what you place.

No asset files: everything you see is built in code from primitives.

## Install and play

1. Download **Godot 4.4.1** (standard build, not .NET) from
   <https://godotengine.org/download/archive/4.4.1-stable/>.
2. Get the game:
   ```bash
   git clone https://github.com/dell1388/pinecraft.git
   ```
3. Run it - either open the Godot project manager, **Import** the `pinecraft`
   folder and press **Play**, or from a terminal:
   ```bash
   godot --path pinecraft
   ```
   The first launch builds the world and caches it, so it takes a little longer
   than later ones.

Controls are on the title screen's Controls page and in the in-game journal
(**F1**). The essentials: **WASD** to move, **left mouse** on something with an
empty hand to drag it, **1-9** for your tools, **E** to use things and get into
vehicles, **B** for build mode, **Tab** for the journal.

## For developers

```bash
godot --headless --path . --fixed-fps 60 scenes/tests.tscn        # integration tests
godot --headless --path . --fixed-fps 60 scenes/smoke_world.tscn  # boot the whole world headless
```

After adding a script with a new `class_name`, run
`godot --headless --editor --quit --path .` once to refresh the class cache.

Design notes, systems and measurements live in [docs/GUIDE.md](docs/GUIDE.md)
for now.
