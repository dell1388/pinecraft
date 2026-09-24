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
@export var unlock_cost: int = 0            ## 0 = available from the start
## Conveyor options. `rise` makes the belt a ramp; `railed` false makes it a
## borderless deck that things can be pushed on and off sideways.
@export var rise: float = 0.0
@export var railed: bool = true
## Pads: which vehicle (an id in vehicles.json) this pad spawns.
@export var vehicle: StringName = &""
## Which tier this copy is. Every copy of a machine is bought on its own, at
## its own tier, and keeps it.
@export var tier: int = 1

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
	b.unlock_cost = int(d.get("unlock_cost", 0))
	b.rise = float(d.get("rise", 0.0))
	b.railed = bool(d.get("railed", true))
	b.vehicle = StringName(d.get("vehicle", "hauler" if b.kind == &"pad" else ""))
	return b

func footprint_world(cell_size: float) -> Vector3:
	return Vector3(float(size.x), float(size.y), float(size.z)) * cell_size
