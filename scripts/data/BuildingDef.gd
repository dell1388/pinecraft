class_name BuildingDef
extends Resource

## A placeable building. `size` is in grid cells (x, y, z).

@export var id: StringName = &""
@export var display_name: String = ""
## One line saying what it is for, shown on the build bar.
@export var blurb: String = ""
@export var kind: StringName = &"machine"   ## machine | conveyor | splitter | storage | sell
@export var cost: int = 100
@export var size: Vector3i = Vector3i(2, 2, 2)
@export var machine: StringName = &""
@export var speed: float = 3.0
@export var capacity: float = 6.0
## Conveyor options. `rise` makes the belt a ramp; `railed` false makes it a
## borderless deck that things can be pushed on and off sideways.
@export var rise: float = 0.0
@export var railed: bool = true
## What kind of belt: straight (the default; a ramp when it rises), bend,
## merge or align. `turn` is a bend's way round: -1 left, +1 right.
@export var belt: StringName = &"straight"
@export var turn: float = -1.0
## Pads: which vehicle (an id in vehicles.json) this pad spawns.
@export var vehicle: StringName = &""
## Which tier this copy is. Every copy of a machine is bought on its own, at
## its own tier, and keeps it.
@export var tier: int = 1
## Taken out of the game for now: not sold, not in the build bar.
@export var hidden: bool = false

static func from_dict(d: Dictionary) -> BuildingDef:
	var b := BuildingDef.new()
	b.id = StringName(d.get("id", "unknown"))
	b.display_name = String(d.get("display_name", "Building"))
	b.blurb = String(d.get("blurb", ""))
	b.kind = StringName(d.get("kind", "machine"))
	b.cost = int(d.get("cost", 100))
	var s: Array = d.get("size", [2, 2, 2])
	b.size = Vector3i(int(s[0]), int(s[1]), int(s[2]))
	b.machine = StringName(d.get("machine", ""))
	b.speed = float(d.get("speed", 3.0))
	b.capacity = float(d.get("capacity", 6.0))
	b.rise = float(d.get("rise", 0.0))
	b.railed = bool(d.get("railed", true))
	b.belt = StringName(d.get("belt", "straight"))
	b.turn = float(d.get("turn", -1.0))
	b.hidden = bool(d.get("hidden", false))
	b.vehicle = StringName(d.get("vehicle", "hauler" if b.kind == &"pad" else ""))
	return b

func footprint_world(cell_size: float) -> Vector3:
	return Vector3(float(size.x), float(size.y), float(size.z)) * cell_size
