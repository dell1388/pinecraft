class_name Ragdoll
extends Node3D

## The lumberjack gone limp: his body, head, upper arms, forearms, thighs and
## shins each a physics body, hung together at the neck, shoulders, elbows,
## hips and knees, so a truck, a blast or a long drop sends him cartwheeling
## with every limb flopping on its own. PlayerAvatar puts the model's pivots
## where the bodies are each frame; his hands, feet and fingers ride along.
##
## Built from the model as it stands at that moment, so he goes limp from
## whatever pose he was in, without a jump. The body (`torso`) is the one the
## rest of the game deals with: the camera watches it, a crane holds him by
## it, and he gets up where it comes to rest.

## Each bone: the model pivot it moves, its parent bone, its shape in the
## pivot's frame (capsules hang down from the pivot), its mass, and how its
## joint to the parent may bend.
##   shape: [kind, radius, length, centre]
##   limits: [flex lo, flex hi, twist, side]  (radians; flex is about x,
##           forward for arms and hips, back for knees)
const BONES := {
	&"torso": {"part": &"Torso", "parent": &"", "shape": ["capsule", 0.33, 0.8, Vector3(0, 0.36, 0)], "mass": 40.0},
	&"head": {"part": &"Head", "parent": &"torso", "shape": ["capsule", 0.2, 0.52, Vector3(0, 0.16, -0.06)], "mass": 6.0,
		"limits": [-0.6, 0.8, 0.9, 0.5]},
	&"arm_l": {"part": &"Arm_L", "parent": &"torso", "shape": ["capsule", 0.11, 0.32, Vector3(0, -0.12, 0)], "mass": 4.0,
		"limits": [-1.3, 2.8, 0.9, 1.6]},
	&"arm_r": {"part": &"Arm_R", "parent": &"torso", "shape": ["capsule", 0.11, 0.32, Vector3(0, -0.12, 0)], "mass": 4.0,
		"limits": [-1.3, 2.8, 0.9, 1.6]},
	&"fore_l": {"part": &"Elbow_L", "parent": &"arm_l", "shape": ["capsule", 0.1, 0.44, Vector3(0, -0.2, 0)], "mass": 3.0,
		"limits": [0.0, 2.4, 0.0, 0.0]},
	&"fore_r": {"part": &"Elbow_R", "parent": &"arm_r", "shape": ["capsule", 0.1, 0.44, Vector3(0, -0.2, 0)], "mass": 3.0,
		"limits": [0.0, 2.4, 0.0, 0.0]},
	&"thigh_l": {"part": &"Leg_L", "parent": &"torso", "shape": ["capsule", 0.13, 0.36, Vector3(0, -0.14, 0)], "mass": 8.0,
		"limits": [-0.7, 2.2, 0.5, 0.8]},
	&"thigh_r": {"part": &"Leg_R", "parent": &"torso", "shape": ["capsule", 0.13, 0.36, Vector3(0, -0.14, 0)], "mass": 8.0,
		"limits": [-0.7, 2.2, 0.5, 0.8]},
	&"shin_l": {"part": &"Knee_L", "parent": &"thigh_l", "shape": ["capsule", 0.12, 0.4, Vector3(0, -0.17, 0)], "mass": 5.0,
		"limits": [-2.4, 0.0, 0.0, 0.0], "foot": true},
	&"shin_r": {"part": &"Knee_R", "parent": &"thigh_r", "shape": ["capsule", 0.12, 0.4, Vector3(0, -0.17, 0)], "mass": 5.0,
		"limits": [-2.4, 0.0, 0.0, 0.0], "foot": true},
}
const ORDER: Array[StringName] = [&"torso", &"head", &"arm_l", &"arm_r", &"fore_l", &"fore_r",
	&"thigh_l", &"thigh_r", &"shin_l", &"shin_r"]

## bone -> RigidBody3D
var bodies: Dictionary = {}
## bone -> the model pivot it moves
var parts: Dictionary = {}
var torso: RigidBody3D

## Builds the ragdoll from the model's pivots as they are now, moving with
## `velocity`. `parts_of` answers a pivot name with its Node3D. Returns false
## if the model is not there to build from.
func build(parts_of: Callable, velocity: Vector3, owner_player: Node) -> bool:
	name = "Ragdoll"
	for b in ORDER:
		var part := parts_of.call(BONES[b].part) as Node3D
		if part == null:
			return false
		parts[b] = part
	for b in ORDER:
		var spec: Dictionary = BONES[b]
		var part: Node3D = parts[b]
		var body := RigidBody3D.new()
		body.name = String(b)
		body.mass = spec.mass
		body.collision_layer = Layers.PLAYER
		body.collision_mask = Layers.MASK_PLAYER | Layers.KERB
		body.continuous_cd = b == &"torso" or b == &"head"
		body.angular_damp = 0.6
		body.linear_damp = 0.02
		var pm := PhysicsMaterial.new()
		pm.friction = 0.85
		pm.bounce = 0.12
		body.physics_material_override = pm
		var shape: Array = spec.shape
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = shape[1]
		cap.height = maxf(shape[2], shape[1] * 2.0 + 0.01)
		cs.shape = cap
		cs.position = shape[3]
		body.add_child(cs)
		if spec.get("foot", false):
			# The boot, out in front of the shin.
			var fs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.27, 0.14, 0.44)
			fs.shape = box
			fs.position = Vector3(0, -0.34, -0.06)
			body.add_child(fs)
		body.set_meta("player", owner_player)
		add_child(body)
		body.global_transform = Transform3D(part.global_transform.basis.orthonormalized(), part.global_position)
		body.linear_velocity = velocity
		bodies[b] = body
	torso = bodies[&"torso"]
	# No part of him collides with any other part of him: the joints keep
	# him together, and his arm starting inside his shoulder must not fly off.
	for i in ORDER.size():
		for j in range(i + 1, ORDER.size()):
			(bodies[ORDER[i]] as RigidBody3D).add_collision_exception_with(bodies[ORDER[j]])
	for b in ORDER:
		var spec: Dictionary = BONES[b]
		if spec.parent == &"":
			continue
		_joint(bodies[spec.parent], bodies[b], spec.limits)
	return true

func _joint(a: RigidBody3D, b: RigidBody3D, limits: Array) -> void:
	var j := Generic6DOFJoint3D.new()
	j.name = "Joint_%s" % b.name
	add_child(j)
	# At the child's pivot, turned with it: x flexes, y twists, z swings.
	j.global_transform = b.global_transform
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	for axis in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % axis, true)
		j.set("linear_limit_%s/upper_distance" % axis, 0.0)
		j.set("linear_limit_%s/lower_distance" % axis, 0.0)
		j.set("angular_limit_%s/enabled" % axis, true)
	j.set("angular_limit_x/lower_angle", float(limits[0]))
	j.set("angular_limit_x/upper_angle", float(limits[1]))
	j.set("angular_limit_y/lower_angle", -float(limits[2]))
	j.set("angular_limit_y/upper_angle", float(limits[2]))
	j.set("angular_limit_z/lower_angle", -float(limits[3]))
	j.set("angular_limit_z/upper_angle", float(limits[3]))

## Adds to how every part of him is moving: a shove, plus a random fling of
## the arms and legs, harder the harder he was hit.
func shove(push: Vector3, spin: Vector3) -> void:
	var flail := clampf(push.length() * 0.5, 2.0, 14.0)
	for b in ORDER:
		var body: RigidBody3D = bodies[b]
		body.linear_velocity += push
		if b == &"torso":
			body.angular_velocity += spin
		else:
			body.angular_velocity += spin + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * flail
		body.sleeping = false

## Puts the model's pivots where the bodies are, top of the tree down.
func pose_model() -> void:
	for b in ORDER:
		var body: RigidBody3D = bodies[b]
		var part: Node3D = parts[b]
		if is_instance_valid(body) and is_instance_valid(part):
			part.global_transform = Transform3D(body.global_transform.basis.orthonormalized(), body.global_position)

## How fast the fastest part of him is going.
func speed() -> float:
	var most := 0.0
	for b in ORDER:
		most = maxf(most, (bodies[b] as RigidBody3D).linear_velocity.length())
	return most

func spin() -> float:
	return torso.angular_velocity.length()

func rids() -> Array[RID]:
	var out: Array[RID] = []
	for b in ORDER:
		out.append((bodies[b] as RigidBody3D).get_rid())
	return out

## Held by the body (a crane's grapple) or let go.
func set_held(on: bool) -> void:
	torso.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	torso.freeze = on
	for b in ORDER:
		(bodies[b] as RigidBody3D).sleeping = false
