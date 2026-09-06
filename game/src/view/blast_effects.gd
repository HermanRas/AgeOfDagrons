## Where the dragon's breath landed, for about a second (PLAN.md 13.4, owner's ask
## 2026-09-06: *"i would still like some particle at the splash zone"*).
##
## ## NOTHING ABOUT THIS IS IN THE SIM, WHICH IS `SpentProjectiles`' ARGUMENT UNCHANGED
##
## A fireball has no hit points, blocks nothing, can be tapped by nobody and is never asked
## a question. The damage was resolved by `AbilitySystem` on one tick, before this node
## heard about it; this draws the noise afterwards. **The picture must never gate the
## damage** -- a sweep that hurt what it crossed as it crossed would be the client deciding
## a fight, and two clients would disagree about it by a frame (PLAN.md 4, which admits no
## exception for effects).
##
## ## HOW IT IS TOLD, AND WHY THAT NEEDED ONE FIELD ON THE WIRE
##
## `SpentProjectiles` infers everything from the snapshot the client already has, because a
## projectile IS an entity and its despawn arrives in `removed`. A breath weapon is not an
## entity at all: it is a number changing on the dragon. What was on the wire before
## 2026-09-06 was `ability_cooldown` and nothing else -- enough to grey an action slot, and
## not enough to say **where** anything landed.
##
## So `SimUnit.to_snapshot` now sends `ability_aim` **beside `ability_cooldown`, under the
## same condition**, and that placement is the whole reason it is affordable: 12.1f's rule
## is that a field carried by SOME entities splits the roster into another wire shape, and
## `ability_cooldown` had already made that split. A unit with a cooling ability was already
## its own shape; this rides in it. A unit that has never used an ability sends neither and
## is untouched.
##
## `GameView` watches for the cooldown RISING -- which only a fire can cause, since
## `AbilitySystem` otherwise counts it down one per tick -- and calls `play()`. An edge
## rather than "is it at maximum" so that a dropped snapshot does not swallow the effect,
## which at a 120 s cooldown would be the only one that fight was going to get.
##
## ⚠️ **FOG IS ALREADY HANDLED AND MUST NOT BE HANDLED AGAIN HERE.** A dragon you cannot see
## is not in `updated`, so no rise is ever observed and no fire is drawn -- which is right,
## and is exactly the property `SpentProjectiles` gets from `removed`. A guard in this file
## would be a second opinion about visibility.
class_name BlastEffects
extends Node2D

## The most alive at once. One dragon per map at a 120 s cooldown makes this unreachable
## today; it is here because `_burn` is a general ability effect and the day a second unit
## carries one, a battle line of them is a lot of emitters.
const MAX_ALIVE := 12


## Play one blast centred on `at`, sized to a `span_tiles` square of ground.
##
## `span_tiles` comes from the caster's own def (`radius * 2 + 1`) and is passed in rather
## than assumed -- see `FlameParticles.blast`, which refuses to guess it for the same
## reason.
##
## ONE-SHOT NODES RATHER THAN A POOL. An emitter lives about a second and there is at most
## one dragon on the map; pooling would be a lifetime to get wrong in exchange for an
## allocation nobody can measure. `finished` frees it, and the belt-and-braces timer below
## covers the case where `finished` never fires.
func play(at: Vector2, span_tiles: int) -> void:
	if alive_count() >= MAX_ALIVE:
		return
	var p := FlameParticles.blast(span_tiles)
	p.position = at
	# EMIT ON THE NEXT FRAME, NOT THIS ONE. `emitting = true` before the node is in the tree
	# is silently dropped by GPUParticles2D, which reads as "the effect never plays" and is
	# a miserable thing to debug -- so it is set after `add_child`.
	add_child(p)
	p.emitting = true

	# `finished` is the honest signal and it is not guaranteed to arrive: a `one_shot`
	# emitter that is never processed (a paused tree, a node freed under it) never emits it.
	# The timer is the floor, at twice the lifetime plus a margin, so nothing can accumulate.
	p.finished.connect(p.queue_free)
	var timer := get_tree().create_timer(FlameParticles.LIFETIME_BLAST * 2.0 + 0.5) \
			if is_inside_tree() else null
	if timer != null:
		timer.timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free())


## How many blasts are currently on screen. For the tests and for `MAX_ALIVE`.
##
## Counts children that are not queued for deletion: `queue_free` leaves a node in the tree
## until the end of the frame, so a plain `get_child_count()` would report a blast that has
## already finished and would hold the cap closed against a new one.
func alive_count() -> int:
	var n := 0
	for c in get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			n += 1
	return n


func clear() -> void:
	for c in get_children():
		c.queue_free()
