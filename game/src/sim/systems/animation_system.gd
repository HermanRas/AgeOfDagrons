## Drives `SimUnit.anim` from task and movement state, so the villager
## animation set baked at 0.9/13.2 (idle, walk, walk_carry_wood/gold/food,
## work_chop/work_mine/work_hunt, work_build -- units.json's own note lists
## the full vocabulary) actually plays instead of every unit sitting in its
## default "idle" forever. `EntityView.play_anim()` and the wire format
## (`SimUnit.to_snapshot()`'s `anim` field) already existed; nothing on the
## view side needed to change; only the sim never decided which anim to send.
##
## Runs after MovementSystem (so `has_waypoint()` already reflects this
## tick's arrival, not last tick's) and after GatherSystem/BuildSystem (so a
## `stop()` they issued this tick has already retired the task), and before
## DeathSystem -- a unit that dies this same tick gets DeathSystem's own
## die/decay instead, which is why this skips dead units rather than racing it.
##
## Recomputed fresh every tick from current task/movement state rather than
## reserved into its own field, the same convention SeparationSystem's slot
## ranking and GameView's derived facts both already use: no extra state to
## keep in sync, and a mid-cycle change (order cancelled, node depleted)
## reflects the very next tick with nothing to unwind.
class_name AnimationSystem
extends SimSystem

## Resource kind -> the work anim gathering it plays. Keyed by KIND, not by
## node type -- res.berry_bush and res.deer would both be "food" and both
## play work_hunt, which is what the vocabulary offers; there is no separate
## "harvest a bush" anim to reach for instead.
const _GATHER_ANIM := {
	&"wood": &"work_chop",
	&"gold": &"work_mine",
	&"stone": &"work_mine",
	&"food": &"work_hunt",
}

const _CARRY_ANIM := {
	&"wood": &"walk_carry_wood",
	&"gold": &"walk_carry_gold",
	&"food": &"walk_carry_food",
}


func process_tick(w: SimWorld) -> void:
	for e in w.entities.values():
		if e is SimUnit and e.alive:
			var u: SimUnit = e
			u.anim = _anim_for(w, u)


func _anim_for(w: SimWorld, u: SimUnit) -> StringName:
	if u.has_waypoint():
		return _CARRY_ANIM.get(u.carry_kind, &"walk") if u.carry_amount > 0 else &"walk"

	# Still walking there, or the search for a route has not come back yet
	# (4.2) -- nothing to show but standing still either way.
	if u.path_pending:
		return &"idle"

	if u.task == SimUnit.Task.GATHER:
		var node := w.get_entity(u.task_target_id) as SimResourceNode
		if node != null:
			# Simplification, cosmetic only: plays the work anim once arrived
			# and adjacent, whether or not this particular unit currently
			# holds one of the node's gather_slots (6.3) -- a villager
			# waiting its turn reads as "also working" rather than idling
			# oddly next to a busy tree, and nothing gameplay-visible reads
			# gather_slots off the anim.
			return _GATHER_ANIM.get(node.kind, &"work_chop")
	elif u.task == SimUnit.Task.BUILD:
		return &"work_build"
	elif u.task == SimUnit.Task.ATTACK:
		# Arrived and swinging (4.13). Sent for ANY attacker, including the
		# villager, whose atlas has no `attack` clip -- `AtlasEntry.resolve_anim()`
		# falls back rather than drawing nothing, so she reads as standing her
		# ground instead of vanishing. Deciding here whether the art exists would
		# put a question about atlases inside the sim, which may not ask one.
		return &"attack"

	return &"idle"
