class_name MachineDef
extends Resource

## How a machine eats and what it produces.
##
## `mill` and `smelt` conserve volume: whatever goes in comes back out as
## pieces with the outlet's cross-section, cut to whatever length that volume
## needs. `assemble` consumes volume by category and emits a fixed-size good.

const MODE_MILL := &"mill"
const MODE_SMELT := &"smelt"
const MODE_ASSEMBLE := &"assemble"
## Inline (tunnel-on-a-belt) machines. Each piece is changed as it passes the
## middle of the tunnel: planked, sanded, crushed, smelted or refined.
const MODE_PLANK := &"plank"
const MODE_SAND := &"sand"
const MODE_CRUSH := &"crush"
const MODE_REFINE := &"refine"
## Rough stone to a faceted jewel, keeping `yield_share` of the volume.
const MODE_CUT := &"cut"
const INLINE_MODES := [&"plank", &"sand", &"crush", &"smelt", &"refine", &"cut"]

@export var id: StringName = &""
@export var display_name: String = ""
@export var mode: StringName = MODE_MILL
@export var accepts: Array[StringName] = []
@export var cross_section: Vector2 = Vector2(0.3, 0.3)
@export var max_piece_length: float = 2.4
@export var m3_per_second: float = 0.05
@export var buffer_m3: float = 2.0
@export var conversion: Dictionary = {}        ## input item id -> output item id
@export var color: Color = Color(0.4, 0.4, 0.4)

## Where the openings are: face, hole size and the height of the hole's centre.
@export var intake_face: StringName = &"front"
@export var intake_hole: Vector2 = Vector2(0.7, 0.7)
@export var intake_height: float = 0.9
@export var outlet_face: StringName = &"back"
@export var outlet_hole: Vector2 = Vector2(0.4, 0.4)
@export var outlet_height: float = 0.6
## Inline machines: the tunnel mouth (width, height) at tier 1, the belt speed
## through it, the effect that hides the change, the largest lump a crusher
## leaves and the share of ore volume a smelter keeps.
@export var tunnel: Vector2 = Vector2(1.0, 0.8)
@export var belt_speed: float = 1.5
@export var effect: StringName = &"steam"
@export var max_piece: float = 0.4
@export var yield_share: float = 1.0

func is_inline() -> bool:
	return INLINE_MODES.has(mode)

func accepts_category(category: StringName) -> bool:
	return accepts.has(category)

func output_for(item_id: StringName) -> StringName:
	return StringName(conversion.get(item_id, &""))

static func from_dict(d: Dictionary) -> MachineDef:
	var m := MachineDef.new()
	m.id = StringName(d.get("id", "unknown"))
	m.display_name = String(d.get("display_name", "Machine"))
	m.mode = StringName(d.get("mode", "mill"))
	for c in d.get("accepts", []):
		m.accepts.append(StringName(c))
	if d.has("cross_section"):
		var cs: Array = d["cross_section"]
		m.cross_section = Vector2(cs[0], cs[1])
	m.max_piece_length = float(d.get("max_piece_length", 2.4))
	m.m3_per_second = float(d.get("m3_per_second", 0.05))
	m.buffer_m3 = float(d.get("buffer_m3", 2.0))
	for k in d.get("conversion", {}):
		m.conversion[StringName(k)] = StringName(d["conversion"][k])
	var c: Array = d.get("color", [0.4, 0.4, 0.4])
	m.color = Color(c[0], c[1], c[2])
	var intake: Dictionary = d.get("intake", {})
	m.intake_face = StringName(intake.get("face", "front"))
	var ih: Array = intake.get("hole", [0.7, 0.7])
	m.intake_hole = Vector2(ih[0], ih[1])
	m.intake_height = float(intake.get("height", 0.9))
	var outlet: Dictionary = d.get("outlet", {})
	m.outlet_face = StringName(outlet.get("face", "back"))
	var oh: Array = outlet.get("hole", [0.4, 0.4])
	m.outlet_hole = Vector2(oh[0], oh[1])
	m.outlet_height = float(outlet.get("height", 0.6))
	var tn: Array = d.get("tunnel", [1.0, 0.8])
	m.tunnel = Vector2(tn[0], tn[1])
	m.belt_speed = float(d.get("belt_speed", 1.5))
	m.effect = StringName(d.get("effect", "steam"))
	m.max_piece = float(d.get("max_piece", 0.4))
	m.yield_share = float(d.get("yield", 1.0))
	return m
