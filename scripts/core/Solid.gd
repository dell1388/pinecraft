class_name Solid
extends RefCounted

## Dimensions of a physical piece, and the volume maths that goes with them.
##
## Every loose object in the game is either a box or a (possibly tapered)
## cylinder, and its long axis is local +Y. Machines conserve volume rather than
## item counts, so this is where that arithmetic lives.

const BOX := &"box"
const CYLINDER := &"cylinder"

static func box(size: Vector3) -> Dictionary:
	return {"shape": BOX, "size": size}

## A frustum: bottom radius, top radius, length along Y. r0 == r1 is a cylinder.
static func cylinder(r0: float, r1: float, length: float) -> Dictionary:
	return {"shape": CYLINDER, "r0": maxf(0.01, r0), "r1": maxf(0.01, r1), "length": maxf(0.02, length)}

## A cube of a given volume. Ore comes off a chunk as lumps, and a lump's only
## real property is how much of it there is.
static func cube(volume_m3: float) -> Dictionary:
	var side: float = pow(maxf(0.000001, volume_m3), 1.0 / 3.0)
	return box(Vector3(side, side, side))

static func volume(d: Dictionary) -> float:
	if d.get("shape", BOX) == CYLINDER:
		var r0: float = d.r0
		var r1: float = d.r1
		return PI * float(d.length) / 3.0 * (r0 * r0 + r0 * r1 + r1 * r1)
	var s: Vector3 = d.size
	return s.x * s.y * s.z

## Long-axis extent, which is what "how long is this piece" means everywhere.
static func length_of(d: Dictionary) -> float:
	if d.get("shape", BOX) == CYLINDER:
		return float(d.length)
	return (d.size as Vector3).y

static func bounds(d: Dictionary) -> Vector3:
	if d.get("shape", BOX) == CYLINDER:
		var r: float = maxf(float(d.r0), float(d.r1))
		return Vector3(r * 2.0, float(d.length), r * 2.0)
	return d.size

## Whether a piece will go through a rectangular opening. The long axis goes
## through first, so it is the two smaller extents that have to fit, and the
## piece may be turned to suit the hole.
static func fits_through(d: Dictionary, hole: Vector2) -> bool:
	var b := bounds(d)
	var extents := [b.x, b.y, b.z]
	extents.sort()
	return extents[0] <= minf(hole.x, hole.y) + 0.001 \
		and extents[1] <= maxf(hole.x, hole.y) + 0.001

static func max_radius(d: Dictionary) -> float:
	if d.get("shape", BOX) == CYLINDER:
		return maxf(float(d.r0), float(d.r1))
	var s: Vector3 = d.size
	return maxf(s.x, s.z) * 0.5

## Splits a piece across its long axis at `t` (0..1 of its length), conserving
## total volume exactly: the cut radius is the taper interpolated at the cut.
static func split(d: Dictionary, t: float = 0.5) -> Array[Dictionary]:
	t = clampf(t, 0.05, 0.95)
	if d.get("shape", BOX) == CYLINDER:
		var length: float = d.length
		var r_cut: float = lerpf(float(d.r0), float(d.r1), t)
		return [
			cylinder(float(d.r0), r_cut, length * t),
			cylinder(r_cut, float(d.r1), length * (1.0 - t)),
		]
	var s: Vector3 = d.size
	return [
		box(Vector3(s.x, s.y * t, s.z)),
		box(Vector3(s.x, s.y * (1.0 - t), s.z)),
	]

## Cuts `total_volume` into equal pieces of the given cross-section, none longer
## than max_length. The piece lengths always multiply back to the input volume.
static func cut_to_pieces(total_volume: float, cross_section: Vector2,
		max_length: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var area: float = maxf(0.0001, cross_section.x * cross_section.y)
	var total_length: float = total_volume / area
	if total_length <= 0.001:
		return out
	var count: int = maxi(1, int(ceil(total_length / maxf(0.05, max_length))))
	var piece_length: float = total_length / float(count)
	for i in count:
		out.append(box(Vector3(cross_section.x, piece_length, cross_section.y)))
	return out

static func to_dict(d: Dictionary) -> Dictionary:
	if d.get("shape", BOX) == CYLINDER:
		return {"shape": "cylinder", "r0": float(d.r0), "r1": float(d.r1), "length": float(d.length)}
	var s: Vector3 = d.size
	return {"shape": "box", "size": [s.x, s.y, s.z]}

static func from_dict(d: Dictionary) -> Dictionary:
	if String(d.get("shape", "box")) == "cylinder":
		return cylinder(float(d.get("r0", 0.2)), float(d.get("r1", 0.2)), float(d.get("length", 1.0)))
	var s: Array = d.get("size", [0.3, 0.3, 0.3])
	return box(Vector3(s[0], s[1], s[2]))
