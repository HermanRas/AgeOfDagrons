## The renderable stand-in for one sim entity (PLAN.md 6.3). Pooled by
## EntityViewPool rather than instanced per spawn.
##
## As of 0.2a/0.2b this actually draws. It resolves its visual ID through the
## asset seam (GameDataRegistry.atlas_for) and renders whichever of the two
## things it got back -- a baked atlas frame or a procedural placeholder -- with
## no other part of the view layer caring which. Adding real art is therefore a
## data change, not a code change.
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

## Setting this drops the resolved visual, so a pooled node reused for a
## different entity kind picks up the right art on its next draw.
var visual_id: StringName = &"":
	set(value):
		if visual_id == value:
			return
		visual_id = value
		_visual = null
		_props_resolved = false
		_anim_time = 0.0
		_frame = 0
		queue_redraw()

## The owner's age, which picks a BUILDING's skin (PLAN.md 2.7.1). 0 means "no
## age", which is what gaia-owned scenery and every unit want -- units use one
## actor in all four ages, so this is simply ignored for them.
##
## Clears the resolved visual like `visual_id` does, because a player advancing
## an age re-skins their standing buildings in place: the node stays, the art
## behind it changes.
var skin_age: int = 0:
	set(value):
		if skin_age == value:
			return
		skin_age = value
		_visual = null
		# And the props with it: the mill has none until age 3.
		_props_resolved = false
		queue_redraw()

## The owner's palette index (SimPlayer.colour), which picks the per-player
## BAKE -- not a tint applied here. Player colour is in the pixels (PLAN.md 1):
## each unit ships as eight atlases and this chooses between them, which is why
## there is no shader and no `modulate` on the sprite.
##
## -1 is untinted, and that is the right answer for anything gaia owns. Some
## 0 A.D. wildlife actors declare a playercolor mask anyway (colours.json's
## note), so this keys off WHO OWNS the entity, never off whether the art has
## a mask.
var skin_colour: int = -1:
	set(value):
		if skin_colour == value:
			return
		skin_colour = value
		_visual = null
		queue_redraw()

## Shifts the ART without shifting the NODE, which is what lets a large footprint
## sort correctly under a Y-sorted parent (3.1).
##
## Godot Y-sorts children by `position.y` and offers no per-node sort origin, so
## a building's node is placed at its front tile -- the point it must sort by --
## and this carries the equal and opposite offset so the sprite still lands on the
## footprint centre. GameView sets the pair together; see Iso.footprint_sort_offset.
var draw_offset: Vector2 = Vector2.ZERO:
	set(value):
		if draw_offset == value:
			return
		draw_offset = value
		# The rim is a real child node, so it takes the shift as a POSITION where
		# the sprite takes it as a canvas transform. Without this an outlined unit
		# that also carries a sort offset would have its rim adrift from it.
		if _outline != null:
			_outline.position = draw_offset
		queue_redraw()

var anim: StringName = &"idle"
var facing: int = 0
var health_pct: float = 1.0
var selected: bool = false
var team_color: Color = Color.WHITE

## True once the entity behind this view is a corpse or rubble (PLAN.md 4.7,
## 5.5): no selection ring, no health dot, and slowly transparent via
## `modulate` rather than by hiding outright, so a fading corpse is still
## visible mid-fade instead of popping straight to gone.
var dead: bool = false:
	set(value):
		if dead == value:
			return
		dead = value
		queue_redraw()

## Set by GameView when a building is standing in front of this entity
## (Occlusion.hides). Draws a player-coloured rim over the building so the player
## can see somebody is back there, instead of the unit being shoved in front of
## the roof -- which is what used to happen and what it looked like.
##
## The rim is a CHILD node, created the first time it is needed: most entities
## are never occluded, and buildings never are.
var occluded: bool = false:
	set(value):
		if occluded == value:
			return
		occluded = value
		if occluded and _outline == null:
			_outline = OutlineView.new()
			add_child(_outline)
		if _outline != null:
			_outline.visible = occluded
		queue_redraw()

## The colour the rim is drawn in -- the owner's, since telling WHOSE unit is
## behind the building is most of the value.
var outline_colour: Color = Color.WHITE

var _outline: OutlineView = null
var _visual: AtlasEntry = null
## Decorative props standing around this entity (GameDataRegistry.props_for),
## resolved to atlases and screen offsets. `_props_resolved` rather than a null
## check, because the empty list is the answer for almost everything and must not
## be re-resolved every frame.
var _props: Array[Dictionary] = []
var _props_resolved: bool = false
var _from_pos: Vector2 = Vector2.ZERO
var _to_pos: Vector2 = Vector2.ZERO
var _elapsed: float = INTERP_SECONDS          # start "arrived" so the first update snaps
var _anim_time: float = 0.0
var _frame: int = 0


## The resolved atlas-or-placeholder for this view. Resolved lazily on first use
## rather than in EntityViewPool.acquire() so that pooling stays testable without
## the autoload, and so a view that is never drawn never parses an atlas.
func visual() -> AtlasEntry:
	if _visual == null:
		_visual = GameDataRegistry.atlas_for(visual_id, skin_age, skin_colour)
	return _visual


## Both skin axes at once, so a caller that knows the owner sets them in one
## call and cannot leave the view half-re-skinned between two assignments.
func set_skin(age: int, colour: int) -> void:
	skin_age = age
	skin_colour = colour


## Supply the visual directly instead of resolving it through the seam.
##
## Exists because whether an ID resolves to a real atlas or a placeholder depends
## on whether the art pack happens to be staged, and that must not decide how this
## class behaves or what a test can check. Passing an entry in makes the frame
## clock testable against a known animation instead of against whatever art is on
## the machine.
func set_visual(entry: AtlasEntry) -> void:
	# visual_id FIRST: its setter clears _visual, so assigning in the other order
	# would throw the entry away again.
	visual_id = entry.id if entry != null else &""
	_visual = entry
	# Injected art means a test standing outside the seam; it has no props and
	# must not go looking for any through the autoload.
	_props = []
	_props_resolved = true
	_anim_time = 0.0
	_frame = 0
	queue_redraw()


func set_target_transform(pos: Vector2, _tick: int) -> void:
	_from_pos = position
	_to_pos = pos
	_elapsed = 0.0


## Place without interpolating, for an entity's FIRST position.
##
## set_target_transform() always glides from wherever the node currently is, which
## for a just-acquired view is the origin, or worse, wherever the pooled node was
## when its previous occupant died. Either way a newly spawned entity slid across
## the map for 100 ms before settling. Interpolation is for entities that moved;
## an entity that has only just appeared has nowhere to have moved from.
func snap_to(pos: Vector2) -> void:
	position = pos
	_from_pos = pos
	_to_pos = pos
	_elapsed = INTERP_SECONDS


func advance(delta: float) -> void:
	_advance_anim(delta)

	if _elapsed >= INTERP_SECONDS:
		return
	_elapsed = minf(_elapsed + delta, INTERP_SECONDS)
	position = _from_pos.lerp(_to_pos, _elapsed / INTERP_SECONDS)


func play_anim(name: StringName, p_facing: int) -> void:
	if anim != name:
		anim = name
		_anim_time = 0.0
		_frame = 0
		queue_redraw()
	if facing != p_facing:
		facing = p_facing
		queue_redraw()


func set_health_dot(pct: float) -> void:
	if health_pct == pct:
		return
	health_pct = pct
	queue_redraw()


func set_dead(value: bool) -> void:
	dead = value


## 1.0 is fully opaque; PLAN.md 4.7's 10 s corpse fade rides this down to 0
## before DeathSystem despawns it. GameView only ever passes anything but 1.0
## for a unit corpse -- rubble (5.5) has no fade timer and stays opaque.
func set_corpse_fade(alpha: float) -> void:
	modulate.a = alpha


func set_selected(on: bool) -> void:
	if selected == on:
		return
	selected = on
	queue_redraw()


func set_team_color(c: Color) -> void:
	if team_color == c:
		return
	team_color = c
	queue_redraw()


## Current frame within the playing animation. Exposed for tests -- the frame
## clock is the one piece of 0.2b that has behaviour worth asserting headless.
func current_frame() -> int:
	return _frame


func _advance_anim(delta: float) -> void:
	var vis := visual()
	var count := vis.frame_count(anim)
	if count <= 1:
		return

	_anim_time += delta
	var fps := vis.fps(anim)
	if fps <= 0.0:
		return

	var raw := int(_anim_time * fps)
	var next := raw % count if vis.loops(anim) else mini(raw, count - 1)
	if next != _frame:
		_frame = next
		queue_redraw()


## Selection ring (PLAN.md 4.3): a flat ellipse on the ground, drawn UNDER the
## sprite so a villager stands inside her ring rather than on top of it.
##
## Sized from the visual's DECLARED footprint in metres rather than from the
## sprite's pixel bounds. The declared figure is the measured ground the thing
## occupies; the sprite is mostly air above it, so a bounds-sized ring round a 10 m
## tree would be a circle six tiles wide.
const RING_COLOR := Color(0.35, 1.0, 0.45, 0.9)
const RING_WIDTH := 2.0
const RING_SEGMENTS := 24
## Nothing is allowed a ring tighter than this, or a villager's 0.6 m footprint
## draws a ring too small to see it is there.
const RING_MIN_METRES := 1.2


func _draw_selection_ring() -> void:
	var spec := GameDataRegistry.placeholder_for(visual_id)
	var extent := Vector2(
		maxf(spec.footprint_m.x, RING_MIN_METRES) * 0.5,
		maxf(spec.footprint_m.y, RING_MIN_METRES) * 0.5)

	var points := PackedVector2Array()
	for i in range(RING_SEGMENTS + 1):
		var a := TAU * float(i) / float(RING_SEGMENTS)
		# Built in METRE space and projected, so the ring lies flat on the ground
		# plane and comes out as the right isometric ellipse for free.
		points.append(draw_offset + Iso.metres_to_world(
				Vector2(cos(a) * extent.x, sin(a) * extent.y)))
	draw_polyline(points, RING_COLOR, RING_WIDTH, true)


## Small dot above the sprite, coloured by HealthDot's thresholds (4.6). Hidden
## at full health and on a corpse/rubble -- a dead thing is not "healthy", it is
## not a combat participant any more, and 5.6's rubble has no damage tiers to
## report once it has fallen.
const HEALTH_DOT_RADIUS := 4.0
const HEALTH_DOT_GAP := 4.0


func _draw_health_dot() -> void:
	if dead or health_pct >= 1.0:
		return
	var spec := GameDataRegistry.placeholder_for(visual_id)
	var above := draw_offset + Iso.height_to_world(spec.height_m) \
			- Vector2(0.0, HEALTH_DOT_RADIUS + HEALTH_DOT_GAP)
	draw_circle(above, HEALTH_DOT_RADIUS, HealthDot.color_for(health_pct))


func _draw() -> void:
	if selected:
		_draw_selection_ring()
	_draw_health_dot()

	var vis := visual()

	# draw_offset is a translation on the canvas transform rather than a term added
	# to each rect, so it applies AFTER the mirror below and is itself never
	# mirrored -- a flipped building would otherwise shift the wrong way.
	if draw_offset != Vector2.ZERO:
		draw_set_transform(draw_offset)

	if vis.is_placeholder:
		# No props on a placeholder. A placeholder means the art is not mounted,
		# and dressing an untextured box with three perfectly-rendered plank
		# stacks would say the building is finished when it is not.
		PlaceholderRenderer.draw_into(self, vis.placeholder, facing)
		return

	# Props behind the building first, then the building, then the props in front
	# of it -- one painter's pass, sorted by projected depth exactly as the world
	# layer sorts entities against each other. Without the split, a stone pile
	# meant to sit at the near corner would be painted under the wall it is
	# standing in front of.
	var props := _props_here()
	for p in props:
		var at: Vector2 = p["at"]
		if at.y < 0.0:
			_draw_frame(p["visual"], &"idle", at)
	_draw_frame(vis, anim, Vector2.ZERO, true)
	for p in props:
		var at: Vector2 = p["at"]
		if at.y >= 0.0:
			_draw_frame(p["visual"], &"idle", at)


## One atlas frame, anchored so its own origin lands at `at` in this node's local
## space. Shared by the entity's own sprite and by every prop standing around it,
## so a prop cannot drift out of agreement with the thing it decorates about
## where the ground is.
func _draw_frame(vis: AtlasEntry, anim_name: StringName, at: Vector2,
		is_self: bool = false) -> void:
	if vis == null or vis.is_placeholder:
		return
	var f := vis.frame_at(anim_name, facing, _frame if anim_name == anim else 0)
	if f.is_empty():
		return
	var tex := vis.texture(int(f["page"]))
	if tex == null:
		return

	var rect: Rect2i = f["rect"]
	var anchor: Vector2 = f["anchor"]
	var src := Rect2(rect.position, rect.size)

	# Hand the rim the same frame this is about to draw, so the two can never
	# disagree about which animation, facing or position the unit is in. Only for
	# the entity's OWN sprite -- a prop standing beside a building is scenery and
	# has nobody behind it to announce.
	if is_self and _outline != null and _outline.visible:
		_outline.set_frame(tex, src, Rect2(at - anchor, Vector2(rect.size)),
				bool(f["flip_x"]), outline_colour)

	# The frame is placed so its anchor -- the projected world origin, exact by
	# construction rather than measured (PLAN.md 9.1) -- lands on `at`. Mirrored
	# facings reflect about that same point, so a flipped sprite stays on its
	# feet; `at.x` is negated under the mirror for the same reason draw_offset is
	# kept out of it.
	if bool(f["flip_x"]):
		draw_set_transform(draw_offset, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(
			tex, Rect2(anchor.x - rect.size.x - at.x, at.y - anchor.y,
					rect.size.x, rect.size.y), src
		)
		draw_set_transform(draw_offset, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(tex, Rect2(at - anchor, Vector2(rect.size)), src)


## This visual's props, resolved once and cached: `[{visual, at}]` with `at` the
## prop's screen offset from the entity's own origin. Empty for everything that
## declares none, which is all but three buildings.
##
## Resolved lazily and dropped whenever the skin changes, the same lifecycle
## `_visual` has -- the mill only gains its food crates at age 3, so the list is
## a function of the age and cannot be resolved once at spawn.
func _props_here() -> Array[Dictionary]:
	if _props_resolved:
		return _props
	_props_resolved = true
	_props = []
	for p in GameDataRegistry.props_for(visual_id, skin_age):
		var entry := GameDataRegistry.atlas_for(StringName(p["visual"]))
		if entry == null or entry.is_placeholder:
			continue          # a prop whose art is absent is simply not drawn
		_props.append({
			"visual": entry,
			"at": Iso.metres_to_world(p["offset_m"] as Vector2),
		})
	return _props
