## PLAN.md 7.1: the resource counters are driven entirely off EventBus, not off
## a GameView reference -- so this test drives it the same way, by emitting the
## two signals directly rather than running a snapshot through GameScene.
extends TestCase

var hud: ResourceHUD


func before_each() -> void:
	hud = ResourceHUD.new()
	hud.player_id = 1


func after_each() -> void:
	hud.free()


func test_resources_changed_updates_stock_for_the_watched_player() -> void:
	EventBus.resources_changed.emit(1, {"wood": 50, "gold": 5})
	assert_eq(hud.stock_of(&"wood"), 50)
	assert_eq(hud.stock_of(&"gold"), 5)
	assert_eq(hud.stock_of(&"stone"), 0, "an absent kind reads as zero, not an error")


func test_a_signal_for_a_different_player_is_ignored() -> void:
	EventBus.resources_changed.emit(2, {"wood": 999})
	assert_eq(hud.stock_of(&"wood"), 0, "player 2's stock must not paint player 1's HUD")


func test_villagers_changed_updates_the_headcount() -> void:
	EventBus.villagers_changed.emit(1, 2, 5)
	assert_eq(hud.villager_counts(), Vector2i(2, 5))


func test_a_villager_signal_for_a_different_player_is_ignored() -> void:
	EventBus.villagers_changed.emit(2, 9, 9)
	assert_eq(hud.villager_counts(), Vector2i(0, 0))


func test_two_huds_for_different_players_do_not_interfere() -> void:
	var other := ResourceHUD.new()
	other.player_id = 2

	EventBus.resources_changed.emit(1, {"food": 10})
	EventBus.resources_changed.emit(2, {"food": 20})

	assert_eq(hud.stock_of(&"food"), 10)
	assert_eq(other.stock_of(&"food"), 20)
	other.free()
