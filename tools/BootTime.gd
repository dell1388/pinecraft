extends Node
## Load-time harness (not part of the game): runs the real loading screen and
## reports how long the world took to build and the longest the screen went
## without drawing a frame - the longest the window was locked up. Run with:
##   PROFILE_LOAD=1 godot --path . scenes/boot_time.tscn -- [--map=ostars|isles]
## (PROFILE_LOAD adds each stage's time.) Delete user://terrain_cache*.bin and
## user://cave_plan*.bin first to time a first load.

var boot: Node
var start := 0
var last := 0
var frames := 0
var worst := 0
var worst_at := 0.0
var done := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--map="):
			WorldMap.forced = WorldMap.valid(String(a).trim_prefix("--map="))
	start = Time.get_ticks_msec()
	last = start
	boot = load("res://scenes/boot.tscn").instantiate()
	get_tree().root.add_child.call_deferred(boot)

func _process(_d: float) -> void:
	if done:
		return
	var now := Time.get_ticks_msec()
	frames += 1
	if now - last > worst:
		worst = now - last
		worst_at = float(now - start) / 1000.0
	last = now
	for n in get_tree().root.get_children():
		if n is World and (n as World).player != null and not is_instance_valid(boot):
			done = true
			print("boot: world up in %.1f s, %d frames drawn, longest without one %d ms (at %.1f s), %d threads, %d used for big jobs" % [
				float(now - start) / 1000.0, frames, worst, worst_at, OS.get_processor_count(),
				preload("res://scripts/core/Workers.gd").tasks()])
			var win := get_window()
			print("boot: window %s at %s, %s; screen %d is %s at %s" % [
				["windowed", "minimized", "maximized", "fullscreen", "exclusive fullscreen"][win.mode],
				win.position, win.size, win.current_screen,
				DisplayServer.screen_get_size(win.current_screen), DisplayServer.screen_get_position(win.current_screen)])
			get_tree().quit()
