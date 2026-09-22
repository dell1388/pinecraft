class_name Nameplate
extends RefCounted

## A billboarded label floating over a thing.
##
## The models are primitives, and a grey box three metres on a side could be a
## furnace, a crusher or a storage bin. Until the models say which, the label
## does - and in build mode, where a plot is a field of similar boxes, it is the
## difference between a factory and a guessing game.

## Distance past which a plate stops drawing. Close things are worth naming;
## the whole map shouting at once is not.
const NEAR := 48.0
const FAR := 140.0

static func attach(parent: Node3D, text: String, height: float,
		tint: Color = Color(0.96, 0.95, 0.90), reach: float = NEAR) -> Label3D:
	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.0045
	label.outline_size = 14
	label.modulate = tint
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	# Drawn over whatever it names: a plate hidden inside its own machine is no
	# use to anyone.
	label.no_depth_test = true
	label.position = Vector3(0, height, 0)
	label.visibility_range_end = reach
	label.visibility_range_end_margin = reach * 0.2
	parent.add_child(label)
	return label

## Landmarks are read from across the map, so they get a bigger plate that
## carries much further.
static func landmark(parent: Node3D, text: String, height: float,
		tint: Color = Color(0.98, 0.90, 0.55)) -> Label3D:
	var label := attach(parent, text, height, tint, FAR)
	label.pixel_size = 0.012
	return label
