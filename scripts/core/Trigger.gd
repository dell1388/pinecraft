class_name Trigger
extends RefCounted

## Geometry guard for trigger volumes.
##
## Area3D.get_overlapping_bodies() (and, in some orders, body_entered) can hand
## back a body that is no longer really inside: pooled items are detached from
## the tree, which removes them from the space without a clean exit event, and
## the same node is later re-used somewhere else entirely. Accepting on trust
## therefore lets a bin or machine swallow an item that is metres away.
## Every sink runs this cheap point-in-box test before it acts.

static func contains_point(shape_node: CollisionShape3D, point: Vector3, margin: float = 0.0) -> bool:
	if shape_node == null:
		return false
	var box := shape_node.shape as BoxShape3D
	if box == null:
		return true          # non-box triggers fall back to the engine's answer
	var local: Vector3 = shape_node.global_transform.affine_inverse() * point
	var half: Vector3 = box.size * 0.5 + Vector3(margin, margin, margin)
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z

## Bodies genuinely inside the volume, in the order the engine reports them.
static func bodies_inside(area: Area3D, shape_node: CollisionShape3D, margin: float = 0.25) -> Array:
	var out: Array = []
	for body in area.get_overlapping_bodies():
		var node := body as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if node.get_parent() == null:
			continue        # pooled: detached from the tree
		if contains_point(shape_node, node.global_position, margin):
			out.append(body)
	return out
