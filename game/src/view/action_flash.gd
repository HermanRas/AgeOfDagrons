## A brief marker at the tap target, coloured by what the tap actually did
## (PLAN.md 4.5) -- confirmation that a move, a gather order, or a build order
## landed, and which one, without the player having to read the panel to find
## out. Purely cosmetic: nothing here decides the action, it only announces one
## `GameScene` already committed to.
##
## Drawn as a placeholder diamond, the same convention `PlacementGhost` uses for
## the same reason -- this is feedback about a TILE, not a preview of a sprite,
## so there is nothing for real art to add.
class_name ActionFlash
extends Node2D

enum Kind { MOVE, GATHER, BUILD, ATTACK }

const _COLOR := {
	Kind.MOVE: Color(0.35, 1.0, 0.45, 0.85),
	Kind.GATHER: Color(0.95, 0.75, 0.25, 0.85),
	Kind.BUILD: Color(0.55, 0.75, 1.0, 0.85),
	# Red, and the only one of the four that is: the other three are things you
	# do to your own side of the map, and this is the one that is done TO
	# somebody. It has to be unmistakable at a glance on a phone.
	Kind.ATTACK: Color(1.0, 0.25, 0.2, 0.9),
}

## Quick enough to read as a flash rather than a lingering marker -- long enough
## to actually see on a phone screen.
const FADE_SECONDS := 0.35

var _kind: Kind = Kind.MOVE

## Bumped on every play() so a stale fade from an earlier flash cannot hide one
## that replaced it before the first tween finished (NoticeToast's own pattern).
var _token: int = 0


func _init() -> void:
	modulate.a = 0.0


## Show a flash of `kind` centred on `world_pos`, then fade it out.
func play(kind: Kind, world_pos: Vector2) -> void:
	_kind = kind
	position = world_pos
	scale = Vector2.ONE * 0.6
	modulate.a = 1.0
	queue_redraw()

	_token += 1
	# A flash spawned outside the tree (headless tests) still sets its final
	# visible state; it just never schedules the tween that would fade it,
	# same reasoning as NoticeToast.show_message().
	if is_inside_tree():
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "scale", Vector2.ONE, FADE_SECONDS)
		tw.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
		tw.finished.connect(_on_faded.bind(_token))


func current_kind() -> Kind:
	return _kind


func _on_faded(token: int) -> void:
	if is_instance_valid(self) and token == _token:
		modulate.a = 0.0


func _draw() -> void:
	var spec := PlaceholderSpec.new()
	spec.shape = PlaceholderSpec.Shape.DIAMOND
	spec.footprint_m = Vector2(Iso.METRES_PER_TILE, Iso.METRES_PER_TILE)
	spec.color = _COLOR[_kind]
	PlaceholderRenderer.draw_into(self, spec, 0)
