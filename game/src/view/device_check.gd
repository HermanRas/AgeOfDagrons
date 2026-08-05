## Phase 0.1 device diagnostic.
##
## The exit criterion for 0.1 is "it visibly runs on a physical Android phone".
## An empty scene proves the export pipeline works and nothing else, so this
## reports the things we actually made decisions about and would otherwise only
## discover much later:
##
##   - which renderer is really active on device (PLAN.md 1 chose Compatibility)
##   - real viewport / screen size / DPI, for UI scaling
##   - orientation, which should be locked landscape
##   - whether raw touch events arrive as InputEventScreenTouch (PLAN.md 7.4
##     disables mouse emulation, and every gesture depends on this)
##   - sustained FPS, the first data point against the PLAN.md 3.1 budget
##
## Tap anywhere: a marker is drawn at the touch point. If markers land where
## your finger is, the touch -> screen coordinate path is sound.
extends Control

const MAX_TRAIL := 24
const FPS_SAMPLE_SECONDS := 3.0
## Startup frames are wildly unrepresentative -- first-frame FPS reads as 1 and
## a warm-up spike reads as 120 on a 60 Hz panel. Ignore them so min/max mean
## something against the PLAN.md 3.1 budget.
const FPS_WARMUP_SECONDS := 1.5

var _info: RichTextLabel
## Markers must draw in a child added LAST, not in this node's own _draw():
## children paint over their parent, so the background ColorRect silently
## covered every marker. Cost a device round-trip to notice.
var _overlay: Control
var _touches: Dictionary = {}          # touch index -> Vector2
var _trail: Array[Vector2] = []
var _touch_events := 0
var _drag_events := 0
var _mouse_events := 0                 # should stay 0 with emulation disabled

var _uptime := 0.0
var _fps_min := 9999.0
var _fps_max := 0.0
var _fps_accum := 0.0
var _fps_frames := 0
var _fps_window := 0.0
var _fps_avg := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#2B1D14")          # UI_Design.md panel fill
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.scroll_active = false
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info.offset_left = 24
	_info.offset_top = 24
	_info.offset_right = -24
	_info.offset_bottom = -24
	# Sized for a 648px-tall design viewport (PLAN.md 3.0). At 20px the report
	# overflowed and silently clipped the touch section -- the one part that
	# needed reading. Keep this small enough that every line fits.
	_info.add_theme_font_size_override("normal_font_size", 15)
	_info.add_theme_font_size_override("bold_font_size", 17)
	add_child(_info)

	# Added last => drawn on top of the background and the report.
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_touch_markers)
	add_child(_overlay)

	# Populate immediately so the first frame already shows data rather than
	# a blank panel; _process refreshes it from then on.
	_info.text = _build_report()


func _process(delta: float) -> void:
	_uptime += delta
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
	_info.text = _build_report()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_touch_events += 1
		if t.pressed:
			_touches[t.index] = t.position
			_push_trail(t.position)
		else:
			_touches.erase(t.index)
		_overlay.queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag_events += 1
		_touches[d.index] = d.position
		_push_trail(d.position)
		_overlay.queue_redraw()
	elif event is InputEventMouseButton:
		# With emulate_mouse_from_touch disabled this should never fire from a
		# finger. If it climbs on device, that setting is still on.
		_mouse_events += 1


func _draw_touch_markers() -> void:
	# Trail persists after release so injected/quick taps remain visible.
	for i in _trail.size():
		var p: Vector2 = _trail[i]
		var fade := float(i + 1) / float(_trail.size())
		_overlay.draw_circle(p, 8.0, Color("#E5B842") * Color(1, 1, 1, 0.15 + 0.5 * fade))
	for idx in _touches:
		var p: Vector2 = _touches[idx]
		_overlay.draw_circle(p, 44.0, Color("#E5B84233"))
		_overlay.draw_arc(p, 44.0, 0.0, TAU, 48, Color("#E5B842"), 3.0)
		_overlay.draw_line(p - Vector2(60, 0), p + Vector2(60, 0), Color("#E5B842"), 2.0)
		_overlay.draw_line(p - Vector2(0, 60), p + Vector2(0, 60), Color("#E5B842"), 2.0)


func _push_trail(p: Vector2) -> void:
	_trail.append(p)
	while _trail.size() > MAX_TRAIL:
		_trail.pop_front()


# ── reporting ──────────────────────────────────────────────────────────────

func _build_report() -> String:
	var vp := get_viewport_rect().size
	var win := DisplayServer.window_get_size()
	var screen := DisplayServer.screen_get_size()
	var landscape := screen.x >= screen.y

	var lines := PackedStringArray()
	lines.append("[b]AOD -- phase 0.1 device check[/b]")
	lines.append("")
	lines.append("[b]engine[/b]")
	lines.append("  godot        %s" % Engine.get_version_info().string)
	lines.append("  renderer     %s" % _renderer_report())
	lines.append("  driver       %s" % _probe(RenderingServer, "get_current_rendering_driver_name"))
	lines.append("  adapter      %s" % _probe(RenderingServer, "get_video_adapter_name"))
	lines.append("")
	lines.append("[b]device[/b]")
	lines.append("  os           %s" % OS.get_name())
	lines.append("  model        %s" % OS.get_model_name())
	lines.append("  viewport     %d x %d" % [vp.x, vp.y])
	lines.append("  window       %d x %d" % [win.x, win.y])
	lines.append("  screen       %d x %d   %s" % [screen.x, screen.y,
			"LANDSCAPE" if landscape else "[color=#ff6b6b]PORTRAIT -- orientation not locked?[/color]"])
	lines.append("  dpi          %d" % DisplayServer.screen_get_dpi())
	lines.append("  refresh      %.1f Hz" % DisplayServer.screen_get_refresh_rate())
	lines.append("")
	lines.append("[b]performance[/b]  (budget: 60 fps, floor 30 -- PLAN.md 3.1)")
	lines.append("  now          %d fps" % Engine.get_frames_per_second())
	if _uptime < FPS_WARMUP_SECONDS:
		lines.append("  avg / min / max   warming up...")
	else:
		lines.append("  avg / min / max   %s / %s / %s" % [
				("%.0f" % _fps_avg) if _fps_avg > 0.0 else "--",
				("%.0f" % _fps_min) if _fps_min < 9999.0 else "--",
				("%.0f" % _fps_max) if _fps_max > 0.0 else "--"])
	lines.append("")
	lines.append("[b]touch[/b]  (tap anywhere)")
	lines.append("  active       %d" % _touches.size())
	lines.append("  touch events %d" % _touch_events)
	lines.append("  drag events  %d" % _drag_events)
	lines.append("  mouse events %s" % _mouse_report())
	lines.append("")
	lines.append(_verdict())
	return "\n".join(lines)


func _renderer_report() -> String:
	var actual := _probe(RenderingServer, "get_current_rendering_method")
	var configured := str(ProjectSettings.get_setting(
			"rendering/renderer/rendering_method", "?"))
	if actual == "?" or actual.is_empty():
		return "%s (configured)" % configured
	var ok := actual == "gl_compatibility"
	return "%s  %s" % [actual,
			"[color=#69db7c]OK[/color]" if ok
			else "[color=#ff6b6b]expected gl_compatibility[/color]"]


func _mouse_report() -> String:
	var emulating: bool = bool(ProjectSettings.get_setting(
			"input_devices/pointing/emulate_mouse_from_touch", true))
	if _mouse_events == 0:
		return "0  [color=#69db7c]OK[/color]"
	return "%d  [color=#ffd43b]%s[/color]" % [_mouse_events,
			"emulate_mouse_from_touch is ON -- disable it (PLAN.md 7.4)" if emulating
			else "unexpected mouse input"]


func _verdict() -> String:
	if _touch_events == 0:
		return "[color=#ffd43b]waiting for a touch event...[/color]"
	return "[color=#69db7c]raw touch input confirmed -- gesture layer can be built on this[/color]"


## Calls an optional engine method, tolerating API drift. Godot 4.7 postdates
## some of what this script was written against; a diagnostic must never crash
## on the device it exists to diagnose.
func _probe(obj: Object, method: String) -> String:
	if obj != null and obj.has_method(method):
		return str(obj.call(method))
	return "?"
