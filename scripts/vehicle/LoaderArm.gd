class_name LoaderArm
extends Node3D

## A front loader's lift arms and bucket. The arms pivot on the body behind
## the front wheels and carry the bucket out in front; the bucket keeps its
## own angle to the vehicle whatever the arms do (as a loader's parallel
## linkage does), so it can be held flat, curled back to hold a load, or
## tipped forward to pour it out.
##
## The bucket is a solid kinematic body: dropped flat to the ground it is a
## blade that shoves whatever is in front of it, and whatever ends up in it
## rides there by friction and its walls - so it scoops a pile of small
## pieces, lifts them, and pours them out when it is tipped. It is moved to
## where the arms put it every physics frame, so it is never pushed back.

## Arm angle from level, radians; negative is down.
var lift: float = 0.0
## Bucket angle to the vehicle, radians; positive curls it back, negative
## tips it forward.
var tilt: float = 0.0
var lift_min: float = -0.5
## The carrying pose it starts in and goes back to on [N]: arms a little up,
## bucket curled back a touch.
var home_lift: float = 0.0
const HOME_TILT := 0.25
var homing: bool = false
var lift_max: float = 0.9
const TILT_MIN := -0.95
const TILT_MAX := 0.7
static var LIFT_SPEED: float = Balance.num("loader.lift_speed", 0.45)         ## rad/s
static var TILT_SPEED: float = Balance.num("loader.tilt_speed", 0.9)          ## rad/s

## From the spec: the arm pivot in the vehicle's frame, the arm's length, and
## the bucket's inside width, depth (front to back) and height.
var pivot := Vector3(0, 0.6, -0.4)
var arm_length: float = 2.6
var width: float = 2.6
var depth: float = 1.1
var height: float = 0.8
var arm_x: float = 0.7              ## each arm's distance from the centre line
const PLATE := 0.08

var vehicle: Hauler
var bucket: AnimatableBody3D
var _arms: Array[MeshInstance3D] = []

## Locked: what is in the bucket is clamped in it, part of the bucket exactly
## as it lies, until it is unlocked - driver or no driver. The thumb - a
## clamp hinged on the top of the back plate - swings down over the load.
var locked: bool = false
var _locked: Dictionary = {}          ## LooseItem -> [its shapes on the bucket]
var _thumb: Node3D
var thumb_angle: float = THUMB_OPEN
const THUMB_OPEN := 2.0               ## rad, folded up and back
const THUMB_CLOSED := 0.0             ## flat over the bucket mouth
const THUMB_SPEED := 3.0

func setup(v: Hauler, spec: Dictionary) -> void:
	vehicle = v
	pivot = Hauler._vec(spec.get("pivot", [0, 0.6, -0.4]))
	arm_length = float(spec.get("arm", 2.6))
	width = float(spec.get("width", 2.6))
	depth = float(spec.get("depth", 1.1))
	height = float(spec.get("height", 0.8))
	arm_x = float(spec.get("arm_x", 0.7))
	# Lowest: the bucket floor just off the ground under the vehicle at rest.
	var ground := v._lowest_wheel_y() - v.wheel_radius - Hauler.SAG
	lift_min = asin(clampf((ground + 0.06 - pivot.y) / arm_length, -1.0, 1.0))
	home_lift = lerpf(lift_min, 0.0, 0.3)
	lift = home_lift
	tilt = HOME_TILT

func _ready() -> void:
	bucket = AnimatableBody3D.new()
	bucket.name = "Bucket"
	bucket.top_level = true
	bucket.sync_to_physics = false
	bucket.collision_layer = Layers.VEHICLE
	bucket.collision_mask = Layers.LOOSE
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	bucket.physics_material_override = pm
	# Bucket frame: the hinge at the back of the floor, the mouth toward -Z.
	_plate(Vector3(width + PLATE * 2.0, PLATE, depth), Vector3(0, -PLATE * 0.5, -depth * 0.5))
	_plate(Vector3(width + PLATE * 2.0, height, PLATE), Vector3(0, height * 0.5, PLATE * 0.5))
	for side in [-1.0, 1.0]:
		_plate(Vector3(PLATE, height, depth), Vector3(side * (width + PLATE) * 0.5, height * 0.5, -depth * 0.5))
	bucket.add_child(_dress_bucket())
	_thumb = Node3D.new()
	_thumb.name = "Thumb"
	_thumb.position = Vector3(0, height + PLATE * 0.5, PLATE * 0.5)
	_thumb.add_child(_dress_thumb())
	bucket.add_child(_thumb)
	add_child(bucket)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var g := Greeble.new()
		g.box(Vector3(0.18, 0.26, arm_length), Transform3D(Basis(), Vector3(0, 0, -arm_length * 0.5)), vehicle.paint.darkened(0.1))
		g.box(Vector3(0.24, 0.3, 0.3), Transform3D(), VehicleModel.DARK)
		arm.mesh = g.commit()
		arm.material_override = Greeble.solid_material()
		arm.set_meta("side", side)
		add_child(arm)
		_arms.append(arm)
	vehicle.add_collision_exception_with(bucket)
	_pose(true)

func _plate(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	bucket.add_child(cs)

func _dress_bucket() -> MeshInstance3D:
	var g := Greeble.new()
	g.layer_step = VehicleModel.LAYER
	var steel := Color(0.36, 0.37, 0.40)
	var paint := vehicle.paint
	g.box(Vector3(width + PLATE * 2.0, PLATE, depth), Transform3D(Basis(), Vector3(0, -PLATE * 0.5, -depth * 0.5)), steel)
	g.box(Vector3(width + PLATE * 2.0, height, PLATE), Transform3D(Basis(), Vector3(0, height * 0.5, PLATE * 0.5)), paint)
	for side in [-1.0, 1.0]:
		g.box(Vector3(PLATE, height, depth), Transform3D(Basis(), Vector3(side * (width + PLATE) * 0.5, height * 0.5, -depth * 0.5)), paint)
	# The cutting edge along the front of the floor.
	g.box(Vector3(width + PLATE * 2.0, 0.05, 0.14), Transform3D(Basis(), Vector3(0, -PLATE * 0.5, -depth - 0.05)), VehicleModel.STEEL)
	return g.instance("BucketMesh")

## The thumb, drawn in its closed pose: tines out along the top of the
## bucket, hooked down at their tips, on a cross tube at the hinge.
func _dress_thumb() -> MeshInstance3D:
	var g := Greeble.new()
	g.layer_step = VehicleModel.LAYER
	var steel := VehicleModel.DARK
	g.box(Vector3(width * 0.9, 0.12, 0.12), Transform3D(), steel)
	var tines := 4
	for i in tines:
		var x := lerpf(-width * 0.38, width * 0.38, float(i) / float(tines - 1))
		g.box(Vector3(0.1, 0.1, depth * 0.95), Transform3D(Basis(), Vector3(x, 0, -depth * 0.475)), vehicle.paint.darkened(0.2))
		g.box(Vector3(0.1, 0.28, 0.1), Transform3D(Basis(), Vector3(x, -0.12, -depth * 0.95)), steel)
	return g.instance("ThumbMesh")

## Clamps what is in the bucket, or lets it go. Returns what happened.
func set_locked(on: bool) -> String:
	if on == locked:
		return ""
	locked = on
	if on:
		for item in held():
			_lock(item)
		return "bucket locked - %d piece%s clamped in" % [_locked.size(), "" if _locked.size() == 1 else "s"]
	var n := _locked.size()
	_release()
	return "bucket unlocked - %d piece%s loose" % [n, "" if n == 1 else "s"]

func _lock(item: LooseItem) -> void:
	if item.state != LooseItem.State.FREE or _locked.has(item):
		return
	item.set_state(LooseItem.State.CAPTURED)
	item.collision_layer = 0
	item.collision_mask = 0
	item.reparent(bucket, true)
	item.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
	item.process_mode = Node.PROCESS_MODE_DISABLED
	# Saved with the vehicle, not as a piece lying about.
	item.carrier = vehicle
	var shapes: Array[CollisionShape3D] = []
	for c in item.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var copy := CollisionShape3D.new()
		copy.shape = cs.shape
		copy.transform = item.transform * cs.transform
		bucket.add_child(copy)
		shapes.append(copy)
	_locked[item] = shapes

func _release() -> void:
	for item: LooseItem in _locked.keys():
		for cs: CollisionShape3D in _locked[item]:
			if is_instance_valid(cs):
				cs.queue_free()
		if not is_instance_valid(item) or item.state != LooseItem.State.CAPTURED:
			continue
		var at := item.global_transform
		if vehicle.manager != null:
			item.reparent(vehicle.manager, true)
		item.process_mode = Node.PROCESS_MODE_INHERIT
		item.collision_layer = Layers.LOOSE
		item.collision_mask = Layers.MASK_LOOSE
		item.carrier = null
		item.set_state(LooseItem.State.FREE)
		item.teleport(at)
		item.linear_velocity = vehicle.linear_velocity + vehicle.angular_velocity.cross(at.origin - vehicle.global_position)
	_locked.clear()

func locked_items() -> Array[LooseItem]:
	var out: Array[LooseItem] = []
	for item: LooseItem in _locked.keys():
		if is_instance_valid(item):
			out.append(item)
	return out

## Works the arms and bucket: `raise` and `curl` in -1..1.
func drive(raise: float, curl: float, delta: float) -> void:
	if raise == 0.0 and curl == 0.0:
		return
	homing = false
	lift = clampf(lift + raise * LIFT_SPEED * delta, lift_min, lift_max)
	tilt = clampf(tilt + curl * TILT_SPEED * delta, TILT_MIN, TILT_MAX)

## The hinge at the arm tips, in the vehicle's frame.
func tip() -> Vector3:
	return pivot + Vector3(0, sin(lift), -cos(lift)) * arm_length

## The bucket's frame in the vehicle's frame.
func bucket_local() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, tilt), tip())

func _physics_process(delta: float) -> void:
	if homing:
		lift = move_toward(lift, home_lift, LIFT_SPEED * delta)
		tilt = move_toward(tilt, HOME_TILT, TILT_SPEED * delta)
		homing = not (is_equal_approx(lift, home_lift) and is_equal_approx(tilt, HOME_TILT))
	thumb_angle = move_toward(thumb_angle, THUMB_CLOSED if locked else THUMB_OPEN, THUMB_SPEED * delta)
	if _thumb != null:
		_thumb.rotation = Vector3(thumb_angle, 0, 0)
	_pose(false, delta)

## Puts the bucket where the arms hold it. The vehicle moves in the step that
## follows this, so the bucket goes where the vehicle is about to be.
func _pose(snap: bool, delta: float = 0.0) -> void:
	if vehicle == null or bucket == null:
		return
	var at := vehicle.global_transform
	if not snap:
		var w := vehicle.angular_velocity
		if w.length() > 0.0001:
			at.basis = Basis(w.normalized(), w.length() * delta) * at.basis
		at.origin += vehicle.linear_velocity * delta
	var xform := at * bucket_local()
	if snap:
		PhysicsServer3D.body_set_state(bucket.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	bucket.global_transform = xform
	for arm in _arms:
		var side: float = arm.get_meta("side")
		var x := side * arm_x
		arm.transform = Transform3D(Basis(Vector3.RIGHT, lift), Vector3(x, pivot.y, pivot.z))

## Back to the carrying pose, at the arms' own pace.
func home() -> void:
	homing = true

## Clamps the bucket once the pieces put back in it by a load have settled
## into the physics world.
func relock_after_load() -> void:
	for i in 3:
		await get_tree().physics_frame
	set_locked(true)

## After the vehicle has been moved to a new place.
func snap() -> void:
	_pose(true)

## Loose pieces in the bucket now.
func held() -> Array[LooseItem]:
	var out: Array[LooseItem] = []
	if bucket == null:
		return out
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, depth)
	q.shape = box
	q.transform = bucket.global_transform * Transform3D(Basis(), Vector3(0, height * 0.5, -depth * 0.5))
	q.collision_mask = Layers.LOOSE
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 64):
		var item := hit.collider as LooseItem
		if item != null and not out.has(item):
			out.append(item)
	for item in locked_items():
		if not out.has(item):
			out.append(item)
	return out

func status_line() -> String:
	return "loader: arms %d%%, bucket %s%s  [Shift/Ctrl] raise/lower  [Q/E] tip/curl  [Space] %s  [N] reset" % [
		roundi(100.0 * (lift - lift_min) / (lift_max - lift_min)),
		"curled" if tilt > 0.15 else ("tipped" if tilt < -0.15 else "flat"),
		", locked" if locked else "", "unlock" if locked else "lock"]
