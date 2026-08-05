## Phase 0.7 perf harness (PLAN.md 7.7 layer 5, 3.1) -- the one test layer
## that needs a real scene and must be judged on a physical device, not the
## desktop or headless CI. Spawns UNIT_COUNT villagers through the real
## host_solo() -> SimHost -> SnapshotSystem -> Net -> GameView path (the same
## one a real match uses) and reports sim tick cost and frame rate against
## the budgets in PLAN.md 3.1.
##
## Placeholder dots stand in for sprites -- those don't exist until phase
## 0.2b/0.9 -- drawn directly here rather than in GameView, which stays
## production code with no test-only rendering in it.
extends Control

const UNIT_COUNT := 200                    # PLAN.md 3.1 "Live units (MVP)"
## No CameraRig or viewport clamping exists yet (that's a later phase, once
## real gameplay scenes need it) -- kept small enough that the 1404x648
## design viewport (PLAN.md 3.0) can show the whole spread without one.
const MAP_HALF_EXTENT_TILES := 8
const RETARGET_INTERVAL_SECONDS := 4.0
const FPS_WARMUP_SECONDS := 1.5
const FPS_SAMPLE_SECONDS := 3.0

var _game_view: GameView
var _dots: Node2D
var _report: RichTextLabel
var _unit_ids: Array[int] = []

var _uptime := 0.0
var _retarget_timer := 0.0

var _fps_min := 9999.0
var _fps_max := 0.0
var _fps_accum := 0.0
var _fps_frames := 0
var _fps_window := 0.0
var _fps_avg := 0.0

var _step_min_usec := 9999999
var _step_max_usec := 0
var _step_accum_usec := 0
var _step_samples := 0
var _step_avg_usec := 0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#2B1D14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_game_view = GameView.new()
	_game_view.position = Vector2(702, 324)          # centre of the 1404x648 design viewport
	add_child(_game_view)

	_dots = Node2D.new()
	_dots.draw.connect(_draw_dots)
	_game_view.add_child(_dots)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.scroll_active = false
	_report.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report.set_anchors_preset(Control.PRESET_FULL_RECT)
	_report.offset_left = 24
	_report.offset_top = 24
	_report.offset_right = -24
	_report.offset_bottom = -24
	_report.add_theme_font_size_override("normal_font_size", 15)
	_report.add_theme_font_size_override("bold_font_size", 17)
	add_child(_report)

	Net.snapshot_received.connect(_on_snapshot)
	Net.host_solo()
	_spawn_units()

	_report.text = _build_report()


func _spawn_units() -> void:
	var world: SimWorld = Net.host().world
	for i in UNIT_COUNT:
		var pos := Vector2i(
				randi_range(-MAP_HALF_EXTENT_TILES, MAP_HALF_EXTENT_TILES),
				randi_range(-MAP_HALF_EXTENT_TILES, MAP_HALF_EXTENT_TILES))
		var unit := world.spawn_unit(&"unit.villager", 1, pos)
		_unit_ids.append(unit.id)
	_retarget_all()


## One command per unit, each with its own target -- a single shared target
## for every unit_id would converge all of them onto the same tile instead of
## spreading out, which is a much weaker stress/visual case.
func _retarget_all() -> void:
	for id in _unit_ids:
		var target := Vector2i(
				randi_range(-MAP_HALF_EXTENT_TILES, MAP_HALF_EXTENT_TILES),
				randi_range(-MAP_HALF_EXTENT_TILES, MAP_HALF_EXTENT_TILES))
		Net.submit_command(MoveCommand.new(1, [id], target))


func _on_snapshot(snap: Dictionary) -> void:
	_game_view.apply_snapshot(snap)

	var host: SimHost = Net.host()
	if host != null:
		_step_min_usec = mini(_step_min_usec, host.last_step_usec)
		_step_max_usec = maxi(_step_max_usec, host.last_step_usec)
		_step_accum_usec += host.last_step_usec
		_step_samples += 1


func _process(delta: float) -> void:
	_uptime += delta
	_retarget_timer += delta
	if _retarget_timer >= RETARGET_INTERVAL_SECONDS:
		_retarget_timer = 0.0
		_retarget_all()

	var fps := Engine.get_frames_per_second()
	if fps > 0.0 and _uptime >= FPS_WARMUP_SECONDS:
		_fps_min = minf(_fps_min, fps)
		_fps_max = maxf(_fps_max, fps)
		_fps_accum += fps
		_fps_frames += 1
		_fps_window += delta
		if _fps_window >= FPS_SAMPLE_SECONDS:
			_fps_avg = _fps_accum / float(_fps_frames)
			_fps_accum = 0.0
			_fps_frames = 0
			_fps_window = 0.0

	if _step_samples > 0:
		_step_avg_usec = _step_accum_usec / _step_samples
		_step_accum_usec = 0
		_step_samples = 0

	_dots.queue_redraw()
	_report.text = _build_report()


func _draw_dots() -> void:
	for view in _game_view.pool.active_views():
		_dots.draw_circle(view.position, 6.0, Color("#D8C08A"))


func _build_report() -> String:
	var lines := PackedStringArray()
	lines.append("[b]AOD -- phase 0.7 stress test[/b]")
	lines.append("")
	lines.append("[b]units[/b]  %d  (budget: 50 MVP / 200 full scope, PLAN.md 3.1)" % _unit_ids.size())
	lines.append("")
	lines.append("[b]sim tick cost[/b]  (budget: < 5 ms per 100 ms tick)")
	if _step_samples == 0 and _step_avg_usec == 0:
		lines.append("  warming up...")
	else:
		lines.append("  avg / min / max   %.2f / %.2f / %.2f ms" % [
				_step_avg_usec / 1000.0, _step_min_usec / 1000.0, _step_max_usec / 1000.0])
	lines.append("")
	lines.append("[b]frame rate[/b]  (budget: 60 fps, floor 30)")
	if _uptime < FPS_WARMUP_SECONDS:
		lines.append("  warming up...")
	else:
		lines.append("  avg / min / max   %s / %s / %s" % [
				("%.0f" % _fps_avg) if _fps_avg > 0.0 else "--",
				("%.0f" % _fps_min) if _fps_min < 9999.0 else "--",
				("%.0f" % _fps_max) if _fps_max > 0.0 else "--"])
	lines.append("")
	lines.append("[b]draw calls[/b]  %d  (budget: < 200)" %
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return "\n".join(lines)
