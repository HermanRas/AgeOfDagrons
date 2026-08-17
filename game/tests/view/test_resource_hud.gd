## PLAN.md 7.1: the resource counters are driven entirely off EventBus, not off
## a GameView reference -- so this test drives it the same way, by emitting the
## signals directly rather than running a snapshot through GameScene.
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


## Units on the map against the population limit (PLAN.md 4.11). This row read
## IDLE/TOTAL villagers until 2026-08-17, which was neither of the two things the
## HUD needs to say -- idle villagers are the age header's badge now.
func test_population_changed_updates_the_bottom_row() -> void:
	EventBus.population_changed.emit(1, 12, 20)
	assert_eq(hud.population(), Vector2i(12, 20))
	assert_eq(hud._pop_label.text, "12/20")


func test_a_population_signal_for_a_different_player_is_ignored() -> void:
	EventBus.population_changed.emit(2, 9, 9)
	assert_eq(hud.population(), Vector2i(0, 0))


func test_the_idle_count_does_not_touch_this_panel() -> void:
	# The two used to share `villagers_changed`, which is how the population row
	# came to be showing idle villagers in the first place.
	EventBus.idle_villagers_changed.emit(1, 7)
	assert_eq(hud.population(), Vector2i(0, 0))


## Found live: the icon pack ships its resource icons at 100x100 px, and a
## TextureRect's default EXPAND_KEEP_SIZE makes that its real minimum size
## regardless of custom_minimum_size unless expand_mode is set to ignore it
## (HudStyle.add_panel_background() already documents and avoids this same
## trap for the panel background texture; the per-icon TextureRects here did
## not, and five of them stacked in a VBoxContainer ballooned the whole panel
## to 532px tall, off the bottom of a 648px viewport).
func test_the_panel_does_not_balloon_to_the_icon_packs_native_pixel_size() -> void:
	assert_true(hud.get_minimum_size().y < 200.0,
			"5 icon rows at a real ~24px each, not the icon pack's native 100px each")


func test_two_huds_for_different_players_do_not_interfere() -> void:
	var other := ResourceHUD.new()
	other.player_id = 2

	EventBus.resources_changed.emit(1, {"food": 10})
	EventBus.resources_changed.emit(2, {"food": 20})

	assert_eq(hud.stock_of(&"food"), 10)
	assert_eq(other.stock_of(&"food"), 20)
	other.free()
