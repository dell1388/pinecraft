class_name ConveyorAlign
extends Conveyor

## An aligning belt: every piece that comes aboard is set square on it - moved
## to the middle of the belt and turned to lie along the way it runs, broad
## face up - then carried on like any belt. Worth putting in front of a
## machine: a piece that arrives crooked goes into the mouth straight.
##
## It waits for room: a piece is only set straight when the place it would go
## is clear, so two arriving together are done one after the other.

var total_aligned: int = 0
var _done: Dictionary = {}           ## LooseItem -> true, already set straight

func _aboard(inside: Dictionary) -> void:
	for item in _done.keys():
		if not inside.has(item):
			_done.erase(item)
	if not running:
		return
	for item: LooseItem in inside:
		if _done.has(item) or item.state != LooseItem.State.FREE:
			continue
		var at := aligned_transform(item)
		if not _clear(item, at):
			continue
		item.teleport(at)
		item.linear_velocity = belt_velocity()
		_done[item] = true
		total_aligned += 1

## Where a piece goes: on the belt's centre line, where it already is along
## the belt, lying along the run with its broad face up, resting on the deck.
func aligned_transform(item: LooseItem) -> Transform3D:
	var local := _local(item)
	var along := Vector3.FORWARD
	var basis := Basis(along.cross(Vector3.UP).normalized(), along, Vector3.UP)
	var b := Solid.bounds(item.dims)
	var z := clampf(local.z, -length * 0.5 + 0.2, length * 0.5 - 0.2)
	var at := Vector3(0.0, DECK_THICKNESS + b.z * 0.5 + 0.02, z)
	return global_transform * Transform3D(basis, at)

func _clear(item: LooseItem, at: Transform3D) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Solid.bounds(item.dims)
	q.shape = box
	q.transform = at
	q.collision_mask = Layers.LOOSE
	q.exclude = [item.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func status_line() -> String:
	return "aligning belt: %s, %d set straight  [E] %s" % [
		"running" if running else "stopped", total_aligned, "stop" if running else "start"]
