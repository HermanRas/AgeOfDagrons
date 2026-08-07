## Phase 0.7 perf harness (PLAN.md 7.7 layer 5, 3.1) -- the one test layer
## that needs a real scene and must be judged on a physical device, not on the
## desktop and not headless. Spawns UNIT_COUNT villagers through the real
## host_solo() -> SimHost -> SnapshotSystem -> Net -> GameView path (the same
## one a real match uses) and reports sim tick cost and frame rate against
## the budgets in PLAN.md 3.1.
##
## Up to 0.2b this drew its own stand-in dots, because EntityView rendered
## nothing. It no longer does: EntityView draws through the asset seam, so the dots
## were removed rather than left to double-render on top of them. The harness now
## measures the production render path, which is what it should have been measuring
## all along -- so the 0.7 device figures in PLAN.md still need re-measuring on the
## reference device.
##
## Draw calls move a long way, and NOT in the direction predicted at 0.2b. Measured
## on desktop at 200 units with the settlement:
##
##   procedural placeholders   681 draw calls   (budget < 200 -- over)
##   real baked atlases         14 draw calls
##
## The placeholders are the expensive path, not the cheap one: each is a filled
## polygon plus an outline plus a facing marker, and none of it batches. Real
## sprites all sample one atlas page and collapse into a handful of calls. So the
## budget risk lives with the **placeholder fallback** on a device with no art pack
## mounted, which is the opposite of the earlier assumption and worth knowing before
## anyone optimises the wrong path.
extends Control

const UNIT_COUNT := 200                    # PLAN.md 3.1 "Live units (MVP)"
## How far from the town centre the stress units spread, in tiles. No CameraRig or
## viewport clamping exists yet (3.3), so this stays small enough that the 1404x648
## design viewport (PLAN.md 3.0) shows the whole spread without one.
##
## Was previously used as a half-extent about tile (0, 0), which spawned most of
## the 200 units on NEGATIVE tiles. That was harmless while no map existed; from
## 2.1 it means three quarters of the stress load standing off the grid, on tiles
## no pathfinder will accept at 4.2. Now measured from the town centre and clamped
## into bounds.
const SPREAD_TILES := 8
const RETARGET_INTERVAL_SECONDS := 4.0
const FPS_WARMUP_SECONDS := 1.5
const FPS_SAMPLE_SECONDS := 3.0

var _game_view: GameView
var _camera: CameraRig
var _report: RichTextLabel
var _start_tile: Vector2i = Vector2i.ZERO
var _unit_ids: Array[int] = []
var _host_error: String = ""

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
	# This scene's root is a full-rect Control, and a Control defaults to
	# MOUSE_FILTER_STOP -- it would swallow every mouse button and motion event
	# before _unhandled_input, so the camera would pan under a finger on the phone
	# and do nothing at all under a mouse on the desktop. Touch is unaffected
	# either way: emulate_mouse_from_touch is off, so touch never enters the GUI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_game_view = GameView.new()
	add_child(_game_view)

	_camera = CameraRig.new()
	add_child(_camera)
	_camera.make_current()

	# Backdrop and readout go on CanvasLayers, which the camera transform does not
	# touch -- left in the world canvas they would pan away with the ground the
	# moment 3.3's drag was used. Two layers, not one: the backdrop has to sit
	# UNDER the world (negative layer) or it paints over everything, and the
	# readout has to sit over it.
	var backdrop := CanvasLayer.new()
	backdrop.layer = -1
	add_child(backdrop)

	var bg := ColorRect.new()
	bg.color = Color("#2B1D14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(bg)

	var hud := CanvasLayer.new()
	add_child(hud)

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
	hud.add_child(_report)

	Net.snapshot_received.connect(_on_snapshot)
	var err := Net.host_solo()
	if err != OK:
		# host_solo() failing must be visible on the report, not a silent
		# 0-units run -- this is exactly how the missing Android INTERNET
		# permission showed up on first device test: no crash, just an
		# empty report with "warming up..." forever.
		_host_error = "host_solo() failed: %s" % error_string(err)
	else:
		_spawn_units()

	_report.text = _build_report()


func _spawn_units() -> void:
	var world: SimWorld = Net.host().world
	# Terrain before units: from 3.1 the harness measures the real render path,
	# and that path includes the ground. Leaving it out would have flattered the
	# draw-call figure the whole point of this scene is to report.
	_game_view.build_terrain(world.map.size, world.map.terrain)
	_centre_on_start(world)
	for i in UNIT_COUNT:
		var unit := world.spawn_unit(&"unit.villager", 1, _random_tile_near_start(world))
		_unit_ids.append(unit.id)
	_retarget_all()


## Point the camera at the starting settlement.
##
## MapGen (2.6) places the town centre near the middle of a 64x64 map, which
## projects roughly 900 px below the origin -- far off the bottom of a 648-tall
## viewport, so without this the harness measures an empty field. Up to 3.1 this
## shoved `_game_view.position` around by hand; 3.3's camera is what that hack
## was standing in for.
func _centre_on_start(world: SimWorld) -> void:
	_camera.setup(world.map.size)
	for e in world.entities.values():
		if e is SimBuilding:
			_start_tile = (e as SimBuilding).origin_tile()
			_camera.centre_on(Iso.sub_to_world(e.pos))
			return
	_start_tile = Vector2i(world.map.size.x / 2, world.map.size.y / 2)
	_camera.centre_on(Iso.tile_centre_to_world(_start_tile))


## A tile within SPREAD_TILES of the start, clamped into the map. Clamped rather
## than rejected-and-retried so this always terminates.
func _random_tile_near_start(world: SimWorld) -> Vector2i:
	var t := _start_tile + Vector2i(
			randi_range(-SPREAD_TILES, SPREAD_TILES),
			randi_range(-SPREAD_TILES, SPREAD_TILES))
	return Vector2i(
			clampi(t.x, 0, maxi(0, world.map.size.x - 1)),
			clampi(t.y, 0, maxi(0, world.map.size.y - 1)))


## One command per unit, each with its own target -- a single shared target
## for every unit_id would converge all of them onto the same tile instead of
## spreading out, which is a much weaker stress/visual case.
func _retarget_all() -> void:
	var world: SimWorld = Net.host().world
	for id in _unit_ids:
		Net.submit_command(MoveCommand.new(1, [id], _random_tile_near_start(world)))


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

	_report.text = _build_report()


func _build_report() -> String:
	var lines := PackedStringArray()
	lines.append("[b]AOD -- phase 0.7 stress test[/b]")
	lines.append("")
	if not _host_error.is_empty():
		lines.append("[color=#ff6b6b][b]%s[/b][/color]" % _host_error)
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
