class_name Schematic
extends Node3D

## A shape you plan first and pay for in material.
##
## Placing one costs almost nothing: it is a drawing, a translucent block with
## no collision. Touching material to it fills it - the piece is consumed and
## the shape fills by exactly that much volume. The first thing fed to a shape
## decides what it is made of, and after that it will only take more of the
## same. Once it is full it turns solid, takes the colour of whatever filled it,
## and starts colliding like any other structure.
##
## Volume is conserved on the way in and on the way out: a piece too big for the
## room left is trimmed rather than swallowed, and pulling a finished shape down
## hands the material back.

signal filled_changed(schematic: Schematic)
signal completed(schematic: Schematic)

@export var building_id: StringName = &"schematic_block"

var def: BuildingDef
var manager: LooseItemManager
var plot_id: int = 0

## What has gone in so far, and what it was. `material` is empty until the
## first piece arrives and fixed from then on.
var filled_m3: float = 0.0
var material: StringName = &""
var solid: bool = false

var _size: Vector3 = Vector3.ONE
var _body: StaticBody3D
var _shape: CollisionShape3D
var _ghost: MeshInstance3D
var _fill: MeshInstance3D
var _area: Area3D
var _area_shape: CollisionShape3D
var _poll: float = 0.0

func setup(p_manager: LooseItemManager, p_def: BuildingDef, p_plot_id: int = 0) -> void:
	manager = p_manager
	def = p_def
	building_id = p_def.id
	plot_id = p_plot_id

func _ready() -> void:
	if def == null:
		def = GameData.building(building_id)
	_size = def.footprint_world(Plot.CELL)
	_build()
	set_physics_process(true)

## How much material this shape takes to finish.
func capacity_m3() -> float:
	return _size.x * _size.y * _size.z

func remaining_m3() -> float:
	return maxf(0.0, capacity_m3() - filled_m3)

func fill_fraction() -> float:
	return clampf(filled_m3 / maxf(0.0001, capacity_m3()), 0.0, 1.0)

# --- Filling ---------------------------------------------------------------

## Spec: only the material that started the shape can finish it.
func can_accept(item_id: StringName) -> bool:
	if solid or remaining_m3() <= 0.0001:
		return false
	if material != &"" and item_id != material:
		return false
	return GameData.item(item_id) != null

func accept_item(item: LooseItem) -> bool:
	if not can_accept(item.item_id):
		return false
	if material == &"":
		material = item.item_id
	var room := remaining_m3()
	var supplied := item.volume()
	var taken: float = minf(room, supplied)
	# A piece bigger than the room left is trimmed, not swallowed whole: the
	# offcut comes back rather than disappearing into the wall.
	if supplied - taken > 0.0001:
		_return_offcut(item, supplied - taken)
	manager.despawn(item)
	filled_m3 += taken
	_refresh()
	filled_changed.emit(self)
	if remaining_m3() <= 0.0001:
		_solidify()
	return true

func _return_offcut(item: LooseItem, offcut: float) -> void:
	var dims := item.dims
	var scaled: Dictionary
	if dims.get("shape", Solid.BOX) == Solid.CYLINDER:
		# Keep the round stock round: shorten it to the offcut's volume.
		var ratio: float = offcut / maxf(0.0001, item.volume())
		scaled = Solid.cylinder(float(dims.r0), float(dims.r1), float(dims.length) * ratio)
	else:
		scaled = Solid.cube(offcut)
	var spot := global_position + Vector3(0, _size.y + 0.4, 0)
	var back := manager.spawn(item.item_id, Transform3D(Basis(), spot), plot_id,
		Vector3.UP * 0.4, scaled, item.owned)
	if back != null:
		back.owned = true

## Material dropped against the shape is taken, so a belt or an armful both work.
func _on_body(body: Node) -> void:
	var item := body as LooseItem
	if item == null or item.state != LooseItem.State.FREE:
		return
	if not can_accept(item.item_id):
		return
	if not Trigger.contains_point(_area_shape, item.global_position, 0.3):
		return
	accept_item(item)

func _physics_process(delta: float) -> void:
	if solid:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	for body in Trigger.bodies_inside(_area, _area_shape):
		_on_body(body)

## Full: the drawing becomes a thing.
func _solidify() -> void:
	if solid:
		return
	solid = true
	_shape.disabled = false
	_ghost.visible = false
	_fill.visible = true
	_apply_material(_fill, 1.0)
	if _area != null:
		_area.queue_free()
		_area = null
	completed.emit(self)

## Taking a shape down gives the material back rather than refunding cash, since
## cash never went into it.
func reclaim() -> float:
	var given := filled_m3
	if manager != null and material != &"" and given > 0.0001:
		var def_out := GameData.item(material)
		# Handed back in pieces small enough to pick up again.
		var piece: float = 0.35 if def_out == null else maxf(0.08, minf(0.35, given))
		var left := given
		var i := 0
		while left > 0.0001 and i < 64:
			var take: float = minf(piece, left)
			var spot := global_position + Vector3(
				randf_range(-0.4, 0.4), _size.y + 0.5 + float(i) * 0.12, randf_range(-0.4, 0.4))
			var back := manager.spawn(material, Transform3D(Basis(), spot), plot_id,
				Vector3.ZERO, Solid.cube(take), true)
			if back == null:
				break
			left -= take
			i += 1
	filled_m3 = 0.0
	material = &""
	return given

# --- Geometry --------------------------------------------------------------

func _build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.MACHINE
	_body.collision_mask = Layers.MASK_MACHINE
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _size
	_shape.shape = box
	_shape.position = Vector3(0, _size.y * 0.5, 0)
	_shape.disabled = true        # a plan does not collide
	_body.add_child(_shape)
	add_child(_body)

	# The outline of what is planned.
	_ghost = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = _size
	_ghost.mesh = gm
	_ghost.position = Vector3(0, _size.y * 0.5, 0)
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.55, 0.75, 1.0, 0.22)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost.material_override = gmat
	add_child(_ghost)

	# How full it is, drawn as the material rising inside the outline.
	_fill = MeshInstance3D.new()
	_fill.mesh = BoxMesh.new()
	_fill.visible = false
	add_child(_fill)

	_area = Area3D.new()
	_area.collision_layer = Layers.TRIGGER
	_area.collision_mask = Layers.LOOSE
	_area_shape = CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = _size + Vector3(0.7, 0.7, 0.7)
	_area_shape.shape = ab
	_area_shape.position = Vector3(0, _size.y * 0.5, 0)
	_area.add_child(_area_shape)
	_area.body_entered.connect(_on_body)
	add_child(_area)

func _refresh() -> void:
	var fraction := fill_fraction()
	if fraction <= 0.0001:
		_fill.visible = false
		return
	_fill.visible = true
	var height: float = _size.y * fraction
	(_fill.mesh as BoxMesh).size = Vector3(_size.x, height, _size.z)
	_fill.position = Vector3(0, height * 0.5, 0)
	_apply_material(_fill, fraction)

func _apply_material(mesh: MeshInstance3D, fraction: float) -> void:
	var def_mat := GameData.item(material)
	var color: Color = def_mat.color if def_mat != null else Color(0.6, 0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if fraction < 1.0:
		# Still a plan being filled, so it reads as loose material inside an
		# outline rather than as a finished wall.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 0.75)
	mesh.material_override = mat

func status_line() -> String:
	if solid:
		return "%s of %s" % [def.display_name, GameData.item_name(material)]
	if material == &"":
		return "%s: empty plan, needs %.2f m3 of anything" % [def.display_name, capacity_m3()]
	return "%s: %.2f / %.2f m3 of %s" % [
		def.display_name, filled_m3, capacity_m3(), GameData.item_name(material)]

func to_dict() -> Dictionary:
	return {"filled_m3": filled_m3, "material": String(material)}

func from_dict(d: Dictionary) -> void:
	filled_m3 = float(d.get("filled_m3", 0.0))
	material = StringName(d.get("material", ""))
	_refresh()
	if remaining_m3() <= 0.0001 and filled_m3 > 0.0:
		_solidify()
