## Client-side root of the view layer (PLAN.md 6.3, 8). Turns a snapshot
## Dictionary (PLAN.md 7.2) into pooled EntityView updates and drives their
## interpolation every frame. Never touches SimWorld -- everything it knows
## comes from apply_snapshot().
class_name GameView
extends Node2D

var pool: EntityViewPool = EntityViewPool.new()

var _last_tick: int = -1


func _ready() -> void:
	add_child(pool)


func apply_snapshot(snap: Dictionary) -> void:
	_last_tick = int(snap.get("tick", _last_tick))

	for entry in snap.get("updated", []):
		var id := int(entry.get("id", 0))
		var view := pool.get_view(id)
		if view == null:
			view = pool.acquire(id, _visual_id_of(entry))
		else:
			# A building changes visual when its phase does -- foundation to complete
			# to rubble are three separate atlases (ASSET_MISSING.md 1.2), not states
			# inside one, so the view has to be re-pointed rather than just redrawn.
			var wanted := _visual_id_of(entry)
			if view.visual_id != wanted:
				view.visual_id = wanted

		var p: Dictionary = entry.get("pos", {})
		var sub_pos := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
		view.set_target_transform(Iso.sub_to_world(sub_pos), _last_tick)

		var max_hp := float(entry.get("max_hp", 0))
		if max_hp > 0.0:
			view.set_health_dot(float(entry.get("hp", 0)) / max_hp)

	for id in snap.get("removed", []):
		pool.release(int(id))


## Snapshots carry the entity's DEFINITION id (`unit.villager`); the asset seam is
## keyed by VISUAL id (`vis.villager`). Translating between them is exactly what
## GameDataRegistry is for -- passing def_id straight to the seam resolves to the
## magenta unknown and renders a whole match in placeholder colours without
## reporting anything (found at 2.6).
func _visual_id_of(entry: Dictionary) -> StringName:
	var def_id := StringName(entry.get("def_id", ""))
	# `phase` is present only for buildings (SimBuilding.to_snapshot).
	return GameDataRegistry.visual_for(def_id, int(entry.get("phase", -1)))


func _process(delta: float) -> void:
	pool.advance_all(delta)
