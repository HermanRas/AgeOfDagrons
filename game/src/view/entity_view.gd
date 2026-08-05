## The renderable stand-in for one sim entity (PLAN.md 6.3). Pooled by
## EntityViewPool rather than instanced per spawn.
##
## Actual sprites/atlases don't exist until phase 0.2b/0.9 -- play_anim(),
## set_health_dot(), set_selected() and set_team_color() just record state
## for now so the interpolation and pooling contract is provable today, and
## wiring in real visuals later is a matter of reading these fields rather
## than changing this class's public API.
##
## advance() holds the interpolation logic. It is NOT driven by this node's
## own _process() -- EntityViewPool.advance_all() calls it on every active
## view once per frame, so there is a single, centrally-timed driver instead
## of every pooled child racing its own _process (and so it's drivable
## headless, with no live scene tree).
class_name EntityView
extends Node2D

## Must match SimClock.TICK_MS -- a snapshot arrives once per tick, and the
## view has exactly that long to glide from the old position to the new one
## before the next one lands.
const INTERP_SECONDS := 0.1

var entity_id: int = 0
var visual_id: StringName = &""

var anim: StringName = &"idle"
var facing: int = 0
var health_pct: float = 1.0
var selected: bool = false
var team_color: Color = Color.WHITE

var _from_pos: Vector2 = Vector2.ZERO
var _to_pos: Vector2 = Vector2.ZERO
var _elapsed: float = INTERP_SECONDS          # start "arrived" so the first update snaps


func set_target_transform(pos: Vector2, _tick: int) -> void:
	_from_pos = position
	_to_pos = pos
	_elapsed = 0.0


func advance(delta: float) -> void:
	if _elapsed >= INTERP_SECONDS:
		return
	_elapsed = minf(_elapsed + delta, INTERP_SECONDS)
	position = _from_pos.lerp(_to_pos, _elapsed / INTERP_SECONDS)


func play_anim(name: StringName, p_facing: int) -> void:
	anim = name
	facing = p_facing


func set_health_dot(pct: float) -> void:
	health_pct = pct


func set_selected(on: bool) -> void:
	selected = on


func set_team_color(c: Color) -> void:
	team_color = c
