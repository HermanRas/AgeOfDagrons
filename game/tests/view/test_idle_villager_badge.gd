## PLAN.md 7.1's idle VILLAGER count, made actionable. Driven off EventBus and
## tested the way `ResourceHUD` is, by emitting the signal rather than running a
## snapshot through GameScene.
##
## The two widgets briefly shared one signal, which is how the resource panel came
## to be reporting idle-vs-total units instead of population (project owner,
## 2026-08-17). Separate signals now, for separate questions.
extends TestCase

var badge: IdleVillagerBadge


func before_each() -> void:
	badge = IdleVillagerBadge.new()
	badge.player_id = 1


func after_each() -> void:
	badge.free()


func test_it_reports_the_idle_villager_count() -> void:
	EventBus.idle_villagers_changed.emit(1, 3)
	assert_eq(badge.count, 3)


func test_a_signal_for_a_different_player_is_ignored() -> void:
	EventBus.idle_villagers_changed.emit(2, 9)
	assert_eq(badge.count, 0, "player 2's idlers must not paint player 1's badge")


func test_pressing_it_asks_for_the_next_idle_villager() -> void:
	# An Array, not an int: a GDScript lambda captures locals BY VALUE, so a
	# counter incremented inside one never reaches the assert.
	var asked: Array[int] = []
	badge.cycle_requested.connect(func() -> void: asked.append(1))
	EventBus.idle_villagers_changed.emit(1, 5)

	for i in range(5):
		badge._on_pressed()
	assert_eq(asked.size(), 5, "five taps, five requests -- the walk is GameScene's to hold")


func test_pressing_it_with_nobody_idle_asks_for_nothing() -> void:
	# Rather than emitting a request GameScene would have to refuse. Same polite
	# half/enforcing half split AgeBadge keeps with DebugSetAgeCommand.
	var asked: Array[int] = []
	badge.cycle_requested.connect(func() -> void: asked.append(1))
	EventBus.idle_villagers_changed.emit(1, 0)
	badge._on_pressed()
	assert_true(asked.is_empty())


func test_it_stays_visible_with_nobody_idle() -> void:
	# Greyed, not hidden -- a HUD element that disappears reads as a bug, the
	# same call AgeBadge makes at the last age.
	EventBus.idle_villagers_changed.emit(1, 0)
	assert_true(badge.visible)


## The caption is drawn past the badge's own 22 px box so the column stays one
## square cell wide; without the widened hit test, "Idle" would look pressable
## and not be, and the ring alone is a small target for a thumb.
func test_the_caption_is_part_of_the_hit_area() -> void:
	assert_true(badge._has_point(Vector2(IdleVillagerBadge.SIZE * 0.5, IdleVillagerBadge.SIZE * 0.5)),
			"the ring itself")
	assert_true(badge._has_point(Vector2(IdleVillagerBadge.SIZE + IdleVillagerBadge.CAPTION_GAP + 1.0,
			IdleVillagerBadge.SIZE * 0.5)),
			"and the word beside it")
	assert_false(badge._has_point(Vector2(-4.0, IdleVillagerBadge.SIZE * 0.5)),
			"but not the age badge's side of the gap")


func test_it_matches_the_ui_builder_mockups_circle() -> void:
	# The mockup draws this from primitives (see the class header), so nothing
	# but this test notices if the two copies drift. StyleBoxFlat_o7l18 in
	# scenes/ui_builder/HUD.tscn carries these same numbers.
	assert_almost_eq(IdleVillagerBadge.SIZE, 22.0, 0.001)
	assert_almost_eq(IdleVillagerBadge.RING_WIDTH, 1.0, 0.001)
	assert_eq(IdleVillagerBadge.RING_COLOR, Color(0.898039, 0.0, 0.258824, 1.0))
