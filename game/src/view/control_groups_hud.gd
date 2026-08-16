## The 5-slot control-group stack (PLAN.md 10.1), top-left per UI_Design.md so
## it sits above the selection panel for one-handed left-thumb reach.
##
## Reads ONLY from `EventBus` (same separation `ResourceHUD` keeps, see its own
## header) -- `GameScene` is what crosses from `SimPlayer.control_groups` and
## `GameView`'s live facts into `icon`/`count` per slot, and this does not need
## to know that.
##
## Emits `group_selected`/`group_assign_requested` rather than acting itself:
## selecting a group also recentres the camera (10.5) and assigning one issues
## a `SetControlGroupCommand` (10.2) -- both are `GameScene`'s job, the same
## reason `SelectionPanel`'s train button only ever emits a request.
class_name ControlGroupsHud
extends VBoxContainer

signal group_selected(slot: int)
signal group_assign_requested(slot: int)

var _slots: Array[ControlGroupSlot] = []
var _detectors: Array[DoubleTapDetector] = []


## Built in `_init()`, not `_ready()` -- same reasoning as `ResourceHUD`: a
## bare `.new()` should be fully wired for a headless test.
func _init() -> void:
	add_theme_constant_override("separation", 8)
	for i in range(SimPlayer.CONTROL_GROUP_COUNT):
		var slot_widget := ControlGroupSlot.new(i)
		slot_widget.pressed.connect(_on_slot_pressed.bind(i))
		add_child(slot_widget)
		_slots.append(slot_widget)
		_detectors.append(DoubleTapDetector.new())

	EventBus.control_group_changed.connect(_on_control_group_changed)


func _exit_tree() -> void:
	EventBus.control_group_changed.disconnect(_on_control_group_changed)


## The local player's skin, applied to every slot's cropped icon. A property
## rather than two more arguments on `control_group_changed`, because it is a
## property of the STACK and not of a slot: control groups only ever hold the
## local player's units, so all five share one colour and one age. GameScene
## sets it from the same snapshot that feeds the signal.
func set_skin(age: int, colour: int) -> void:
	for slot_widget in _slots:
		slot_widget.set_skin(age, colour)


func slot_state(slot: int) -> Dictionary:
	if slot < 0 or slot >= _slots.size():
		return {}
	return {"icon": _slots[slot].icon_def_id, "count": _slots[slot].count}


func _on_control_group_changed(slot: int, icon: StringName, count: int) -> void:
	if slot >= 0 and slot < _slots.size():
		_slots[slot].set_state(icon, count)


## A single tap is not committed until `DOUBLE_TAP_MS` has passed with no
## second tap -- otherwise every double-tap-to-assign would also fire a
## reselect+recentre for the single tap that started it.
func _on_slot_pressed(slot: int) -> void:
	var now := Time.get_ticks_msec()
	var detector := _detectors[slot]
	if detector.register_tap(now):
		group_assign_requested.emit(slot)
		return
	# A widget not yet inside a tree cannot schedule a deferred timer -- true in
	# production only for a `pressed` firing before `_ready()`, but also what
	# lets a headless test drive two presses without one first, since nothing
	# here needs the tree until this line. `is_inside_tree()` first because
	# `get_tree()` itself logs an engine error when called on an orphan node,
	# even though it safely returns null.
	if is_inside_tree():
		get_tree().create_timer(DoubleTapDetector.DOUBLE_TAP_MS / 1000.0).timeout.connect(
				_on_single_tap_window_elapsed.bind(slot, now))


func _on_single_tap_window_elapsed(slot: int, tap_ms: int) -> void:
	if is_instance_valid(self) and _detectors[slot].is_still_pending(tap_ms):
		group_selected.emit(slot)
