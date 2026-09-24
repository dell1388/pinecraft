class_name BoxArt
extends Node

## Prints a picture of what is inside on the front of every box in the store:
## the real model - the truck, the machine, the axe - rendered in white on the
## section's colour, like the line art on a shop carton.
##
## One small off-screen viewport renders the pictures one at a time, a frame
## or two apart, and each finished picture is kept for the rest of the game,
## so restocking a shelf costs nothing. Without a renderer (headless), the
## boxes are simply plain.

const SIZE := 192

static var _cache: Dictionary = {}          ## box id -> Texture2D

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _queue: Array = []                      ## [product, callback]
var _busy: bool = false
var _white: StandardMaterial3D

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.environment.ambient_light_energy = 0.9
	_viewport.add_child(env)
	_white = StandardMaterial3D.new()
	_white.albedo_color = Color(0.97, 0.97, 0.99)
	_white.roughness = 1.0

static func cached(box_id: StringName) -> Texture2D:
	return _cache.get(box_id)

## Asks for a product's picture; `done` is called with the texture when it is
## ready (at once, if it was made before).
func request(product: Dictionary, done: Callable) -> void:
	var have := cached(product.box)
	if have != null:
		done.call(have)
		return
	if DisplayServer.get_name() == "headless":
		return
	_queue.append([product, done])
	if not _busy:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var job: Array = _queue.pop_front()
	var product: Dictionary = job[0]
	var have := cached(product.box)
	if have != null:
		job[1].call(have)
		_next.call_deferred()
		return
	var model := _model_for(product)
	if model == null:
		_next.call_deferred()
		return
	_stage.add_child(model)
	await get_tree().process_frame
	_whiten(model)
	_frame(model)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	model.queue_free()
	if image != null and not image.is_empty():
		var tex := ImageTexture.create_from_image(_compose(image, _color(product.color)))
		_cache[product.box] = tex
		job[1].call(tex)
	_next.call_deferred()

## The picture: the white render on the section colour, with a border and
## a couple of printed panel marks like a real carton.
static func _compose(render: Image, color: Color) -> Image:
	render.convert(Image.FORMAT_RGBA8)
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.fill(color)
	var edge := color.lightened(0.55)
	for i in 5:
		out.fill_rect(Rect2i(i, 0, 1, SIZE), edge)
		out.fill_rect(Rect2i(SIZE - 1 - i, 0, 1, SIZE), edge)
		out.fill_rect(Rect2i(0, i, SIZE, 1), edge)
		out.fill_rect(Rect2i(0, SIZE - 1 - i, SIZE, 1), edge)
	out.fill_rect(Rect2i(14, 14, 46, 12), edge)
	out.fill_rect(Rect2i(SIZE - 70, SIZE - 26, 56, 10), edge)
	out.blend_rect(render, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	return out

static func _color(a: Variant) -> Color:
	if a is Color:
		return a
	var arr: Array = a
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))

func _whiten(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = _white
	if node is Label3D:
		(node as Label3D).visible = false
	for c in node.get_children():
		_whiten(c)

## Fits the ortho camera to the model, seen from the front and a little above
## and to the side, the way a carton picture is drawn.
func _frame(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi in _meshes(model):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var centre := box.get_center()
	var radius := box.size.length() * 0.5
	var dir := Vector3(0.75, 0.55, 1.0).normalized()
	_camera.look_at_from_position(centre + dir * (radius * 4.0 + 1.0), centre)
	_camera.size = radius * 2.05
	_camera.near = 0.05
	_camera.far = radius * 10.0 + 10.0

func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).visible and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out

## The thing in the box, built the same way the game builds it.
func _model_for(product: Dictionary) -> Node3D:
	var target := StringName(product.get("target", ""))
	match String(product.get("kind", "")):
		"tool":
			var mi := MeshInstance3D.new()
			mi.mesh = ToolModel.mesh(GameData.tool(target))
			mi.rotation = Vector3(0, 0, -0.6)
			return mi
		"upgrade":
			var g := Greeble.new()
			if target == &"boots":
				for x in [-0.18, 0.18]:
					g.block(Vector3(0.22, 0.4, 0.28), Vector3(x, 0.2, 0), Color.WHITE)
					g.block(Vector3(0.24, 0.12, 0.5), Vector3(x, 0.06, 0.12), Color.WHITE)
			else:
				g.frame(Vector3(0.6, 0.9, 0.2), Transform3D(Basis(), Vector3(0, 0.45, 0)), 0.06, Color.WHITE)
				for y in [0.25, 0.55]:
					g.block(Vector3(0.6, 0.05, 0.3), Vector3(0, y, 0.12), Color.WHITE)
			return g.instance("Upgrade")
	var def := GameData.building(target)
	if def == null:
		return null
	match def.kind:
		&"pad":
			var truck := Hauler.new()
			truck.vehicle_id = def.vehicle
			truck.freeze = true
			return truck
		&"inline":
			var m := InlineMachine.new()
			m.setup_machine(null, def, 0)
			m.set_physics_process(false)
			return m
		&"conveyor":
			var c := Conveyor.new()
			c.length = float(def.size.z)
			c.width = float(def.size.x) * 0.9
			c.rise = def.rise
			c.railed = def.railed
			return c
		&"filter":
			var f := Filter.new()
			f.setup(def)
			return f
		&"splitter":
			var s := Splitter.new()
			s.setup(def)
			return s
		&"doodad":
			var d := Doodad.new()
			d.setup(def)
			return d
		&"machine":
			var mc := Machine.new()
			mc.setup(null, def, 0)
			return mc
	return null
