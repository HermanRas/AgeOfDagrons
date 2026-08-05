## Reuses EntityView nodes across spawn/despawn cycles rather than
## instancing/freeing a Node2D per entity every time it leaves and re-enters
## view (PLAN.md 6.3).
class_name EntityViewPool
extends Node2D

var _active: Dictionary = {}          # int id -> EntityView
var _free: Array[EntityView] = []


func acquire(id: int, visual_id: StringName) -> EntityView:
	if _active.has(id):
		return _active[id]

	var view: EntityView
	if not _free.is_empty():
		view = _free.pop_back()
	else:
		view = EntityView.new()
		add_child(view)

	view.entity_id = id
	view.visual_id = visual_id
	view.visible = true
	_active[id] = view
	return view


func release(id: int) -> void:
	if not _active.has(id):
		return
	var view: EntityView = _active[id]
	_active.erase(id)
	view.visible = false
	view.set_selected(false)
	_free.append(view)


func get_view(id: int) -> EntityView:
	return _active.get(id)


func advance_all(delta: float) -> void:
	for view in _active.values():
		view.advance(delta)
