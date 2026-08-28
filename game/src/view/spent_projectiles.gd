## Arrows, bolts and stones lying where they landed, for a few seconds (project owner,
## 2026-08-28: *"in AOE arrows linger on the ground after hitting for a few seconds, can
## we simulate our arrows and rocks and bolts to work in the same way"*).
##
## **NOTHING ABOUT THIS IS IN THE SIM, and that is the whole design.** A spent arrow has
## no hit points, blocks nothing, can be tapped by nobody and is never asked a question by
## anything -- it is scenery with a timer. Keeping it in the sim would put a hundred
## entities on the wire during a siege (`SimProjectile` already costs one entry per shot
## while it flies, and the volleys of 2026-08-28 multiplied that by five), all of it fog
## filtered, hashed into `state_hash()` and sent to every client, to draw a mark on the
## ground. It would also have to be despawned deterministically, which is a rule two hosts
## can disagree about, for a decoration.
##
## So this is the same trick `MatchAudio` uses from the other end: **read the snapshot the
## client already has and infer**. A projectile leaves through `removed`, which is an
## explicit despawn, and `GameView` hands the last place its sprite had reached to `add()`.
##
## THE ONE AMBIGUITY IS THE ONE THAT MATTERS, AND IT IS ALREADY RESOLVED FOR US. An entity
## can leave a client's view two ways -- it despawned, or the client lost sight of it --
## and `MatchAudio`'s header records that "absence from `updated`" cannot tell them apart.
## Here it can: the fog case goes through `GameView`'s forget pass, which walks `_facts`
## for anything the snapshot did not mention, and only a real despawn reaches `removed`.
## An arrow that flies into the fog therefore leaves no litter, which is right -- you did
## not see it land.
##
## It needed one change in the sim even so, and that change was a bug fix in its own
## right: `ProjectileSystem` used to despawn a shot on the very tick it arrived, so its
## arrival position never reached a snapshot and every arrow in the game vanished about a
## tile and a half short of its target. See that file's header.
class_name SpentProjectiles
extends Node2D

## How long one stays on the ground, in seconds. The owner asked for "a few"; four is
## long enough to still be there when the eye comes back to a fight it heard start, and
## short enough that a two-minute siege does not carpet the ground.
const LIFETIME := 4.0

## The last of `LIFETIME` spent fading out, so they thin rather than blink. A hard cut is
## readable as a bug -- objects in this game do not otherwise disappear -- while a fade
## reads as the thing settling into the dirt.
const FADE := 1.5

## How dark a landed shot is drawn, as a modulate. It is lying in the dirt rather than
## catching the light in flight, and -- more usefully -- it stops a heap of spent arrows
## competing for attention with the ones still in the air, which are the ones the player
## has to react to.
const SHADE := Color(0.72, 0.70, 0.66, 1.0)

## The most kept at once. A castle with a full garrison looses twenty projectiles every
## two seconds, so a long siege would otherwise grow this without limit -- and past a
## point they are drawing on top of each other anyway. Oldest out first.
const MAX_KEPT := 240

## How far a landed shot is nudged off the exact point it hit, in pixels across and down.
##
## **WITHOUT THIS THE LITTER IS INVISIBLE, which the first run showed plainly.** A shot is
## aimed at the target's own position, so a spent arrow lands underneath the sprite that
## was standing there and is hidden by it -- and a volley lands eight of them on nearly
## the same spot, drawn on top of each other. The scatter is what turns a stack into
## litter. Down is half of across because the ground is drawn at half height.
const SCATTER := Vector2(11.0, 5.5)

## `[{visual, at, facing, age}]`, oldest first. A plain array rather than pooled nodes:
## these never move, never animate and never take input, so a node each would be a
## hundred `Node2D`s for a hundred `draw_texture_rect_region` calls that one `_draw()`
## already makes.
var _spent: Array[Dictionary] = []


## Remember one, at the world position and sprite facing its view last had.
##
## `facing` is the SPRITE index, not the sim facing -- the caller has already been
## through `Iso.sim_facing_to_sprite`, exactly as `EntityView.play_anim` demands, so the
## conversion lives in one place and this cannot disagree with the sprite that was on
## screen a frame ago.
## `seed` scatters it -- pass the entity id, which is unique per shot and gives every
## arrow of one volley its own resting place. Nothing about this has to match between
## clients: it is a mark on the grass, and two players seeing an arrow a few pixels apart
## is not a thing anybody can act on. It is a hash rather than `randf()` only so that a
## redraw does not shuffle the litter every frame.
func add(visual: StringName, at: Vector2, facing: int, seed: int = 0) -> void:
	if visual == &"":
		return
	var h := _hash(seed)
	var nudge := Vector2(
			(float(h % 1000) / 1000.0 - 0.5) * 2.0 * SCATTER.x,
			(float((h >> 10) % 1000) / 1000.0 - 0.5) * 2.0 * SCATTER.y)
	_spent.append({"visual": visual, "at": at + nudge, "facing": facing, "age": 0.0})
	if _spent.size() > MAX_KEPT:
		_spent = _spent.slice(_spent.size() - MAX_KEPT)
	queue_redraw()


## The same cheap integer scramble `WildlifeSystem` uses, for the same reason: it only
## has to be stable and well spread. Copied rather than shared because that one is sim
## code and this is a decoration -- a view reaching into `src/sim/` for a hash function
## would be the first thread of exactly the coupling PLAN.md 4 forbids.
static func _hash(n: int) -> int:
	var x := absi(n) & 0x7FFFFFFF
	x = (x ^ (x >> 15)) * 0x2545F491
	x = (x ^ (x >> 13)) * 0x27220A95
	return (x ^ (x >> 16)) & 0x7FFFFFFF


## Everything currently on the ground, for the tests and for `preview_projectiles`.
func count() -> int:
	return _spent.size()


func clear() -> void:
	_spent.clear()
	queue_redraw()


## DRIVEN BY ITS OWN `_process`, unlike `EntityView`, which is advanced centrally by
## `EntityViewPool.advance_all()`. These are not pooled and not tied to an entity, so
## there is no central driver to hang them off -- and unlike a unit's animation, nothing
## here has to stay in step with a tick.
func _process(delta: float) -> void:
	if _spent.is_empty():
		return
	var kept: Array[Dictionary] = []
	for s in _spent:
		s["age"] = float(s["age"]) + delta
		if float(s["age"]) < LIFETIME:
			kept.append(s)
	_spent = kept
	queue_redraw()


func _draw() -> void:
	for s in _spent:
		_draw_one(s)


func _draw_one(s: Dictionary) -> void:
	var entry := GameDataRegistry.atlas_for(StringName(s["visual"]))
	# A placeholder is a magenta box the size of the thing it stands for. Drawing one
	# HERE would be a bright rectangle lying in a field for four seconds per shot, which
	# is a far worse way to report missing art than the flying projectile already does.
	if entry.is_placeholder:
		return
	var f := entry.frame_at(AtlasEntry.STATIC_ANIM, int(s["facing"]), 0)
	if f.is_empty():
		return
	var tex := entry.texture(int(f["page"]))
	if tex == null:
		return

	var age := float(s["age"])
	var alpha := 1.0 if age < LIFETIME - FADE else (LIFETIME - age) / FADE
	var tint := SHADE
	tint.a = clampf(alpha, 0.0, 1.0)

	var rect: Rect2i = f["rect"]
	var anchor: Vector2 = f["anchor"]
	var at: Vector2 = s["at"]
	var src := Rect2(rect.position, rect.size)
	# The same anchor arithmetic and the same mirror as `EntityView._draw_frame`, for the
	# same reason: the anchor is the projected world origin, so placing it on `at` puts
	# the shaft where the shot ended rather than where its top-left corner happened to be.
	if bool(f["flip_x"]):
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(tex,
				Rect2(anchor.x - rect.size.x - at.x, at.y - anchor.y,
						rect.size.x, rect.size.y), src, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(tex, Rect2(at - anchor, Vector2(rect.size)), src, tint)
