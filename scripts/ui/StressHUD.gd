class_name StressHUD
extends CanvasLayer

## Live readout of the numbers that decide whether the physics budget holds.

var manager: LooseItemManager
var conveyors: Array[Conveyor] = []

var _label: Label
var _help: Label
var _accum: float = 0.0
var _worst_physics_ms: float = 0.0
var _frame_ms_avg: float = 0.0

const HELP_TEXT := """[1] rain 100 logs   [2] rain 500 logs   [3] clear
[4] cannon (fast, CCD)   [5] feed conveyors   [6] fell all trees
[7] reset worst-case     WASD move, Shift sprint, Space jump
LMB chop / throw   RMB grab-drag   Esc release mouse"""

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.modulate = Color(1, 1, 1, 0.92)
	var vb := VBoxContainer.new()
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	vb.add_child(_label)
	panel.add_child(vb)
	add_child(panel)

	var help_panel := PanelContainer.new()
	help_panel.anchor_top = 1.0
	help_panel.anchor_bottom = 1.0
	help_panel.offset_top = -110
	help_panel.offset_left = 12
	help_panel.offset_bottom = -12
	_help = Label.new()
	_help.text = HELP_TEXT
	_help.add_theme_font_size_override("font_size", 13)
	help_panel.add_child(_help)
	add_child(help_panel)

func reset_worst() -> void:
	_worst_physics_ms = 0.0

func _process(delta: float) -> void:
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_worst_physics_ms = maxf(_worst_physics_ms, physics_ms)
	_frame_ms_avg = lerpf(_frame_ms_avg, delta * 1000.0, 0.1)
	_accum += delta
	if _accum < 0.1:
		return
	_accum = 0.0
	var captured := 0
	for c in conveyors:
		captured += c.captured_count()
	var lines := [
		"FPS %d   frame %.2f ms   physics %.2f ms (worst %.2f)" % [
			Engine.get_frames_per_second(), _frame_ms_avg, physics_ms, _worst_physics_ms],
		"active bodies %d   pairs %d   islands %d" % [
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)],
	]
	if manager != null:
		lines.append("loose live %d / cap %d   pooled %d   awake %d" % [
			manager.active_count(), manager.per_plot_cap, manager.pooled_count(),
			manager.awake_count()])
		lines.append("ccd active %d   recycled %d   kill-plane saves %d   bulk-slept %d" % [
			manager.stat_ccd_on, manager.stat_recycled, manager.stat_killplane,
			manager.stat_forced_sleeps])
	lines.append("conveyor captured %d" % captured)
	lines.append("objects %d   mem %.1f MB" % [
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	_label.text = "\n".join(lines)
