class_name InputSetup
extends RefCounted

## Actions are registered in code so the project file stays free of hand-rolled
## InputEvent serialisation.

const BINDINGS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
}

static func ensure() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			var already := false
			for existing in InputMap.action_get_events(action):
				if existing is InputEventKey and existing.physical_keycode == key:
					already = true
					break
			if not already:
				InputMap.action_add_event(action, ev)
