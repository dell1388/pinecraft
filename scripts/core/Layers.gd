class_name Layers
extends RefCounted

## Central definition of physics layers/masks.
## Layer numbers are 1-indexed in the editor; the constants below are bitmasks.

const WORLD    := 1 << 0   # terrain, plot floors, static props
const PLAYER   := 1 << 1   # player character body
const LOOSE    := 1 << 2   # loose physics items: logs, ore, crates
const MACHINE  := 1 << 3   # kinematic machines & conveyor bodies
const TREE     := 1 << 4   # choppable trees (static until felled)
const TRIGGER  := 1 << 5   # area volumes: conveyor capture, hoppers, sell zones
const VEHICLE  := 1 << 6   # vehicles (later)

# --- Composite masks -------------------------------------------------------

const MASK_LOOSE := WORLD | LOOSE | MACHINE | TREE | PLAYER | VEHICLE
const MASK_PLAYER := WORLD | LOOSE | MACHINE | TREE | VEHICLE
const MASK_MACHINE := LOOSE | PLAYER | VEHICLE
const MASK_TRIGGER := LOOSE | PLAYER
const MASK_RAY_INTERACT := WORLD | LOOSE | TREE | MACHINE
