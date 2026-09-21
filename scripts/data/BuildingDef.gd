class_name BuildingDef
extends Resource

## A placeable building. `size` is in grid cells (x, y, z).

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = &"machine"   ## machine | conveyor | splitter | storage | sell
@export var cost: int = 100
@export var size: Vector3i = Vector3i(2, 2, 2)
@export var machine: StringName = &""
@export var speed: float = 3.0
@export var capacity: int = 60
@export var unlock_cost: int = 0            ## 0 = available from the start

static func from_dict(d: Dictionary) -> BuildingDef:
	var b := BuildingDef.new()
	b.id = StringName(d.get("id", "unknown"))
	b.display_name = String(d.get("display_name", "Building"))
	b.kind = StringName(d.get("kind", "machine"))
	b.cost = int(d.get("cost", 100))
	var s: Array = d.get("size", [2, 2, 2])
	b.size = Vector3i(int(s[0]), int(s[1]), int(s[2]))
	b.machine = StringName(d.get("machine", ""))
	b.speed = float(d.get("speed", 3.0))
	b.capacity = int(d.get("capacity", 60))
	b.unlock_cost = int(d.get("unlock_cost", 0))
	return b

func footprint_world(cell_size: float) -> Vector3:
	return Vector3(float(size.x), float(size.y), float(size.z)) * cell_size
