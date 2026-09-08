## PLAN.md 9.1's age indicator, plus the debug advance affordance bolted to it
## until 9.2 makes advancing a real researched action.
extends TestCase

var badge: AgeBadge


func before_each() -> void:
	badge = AgeBadge.new()


func after_each() -> void:
	badge.free()


func test_it_opens_on_age_one() -> void:
	assert_eq(badge.age, 1)
	assert_eq(badge.next_age(), 2)


func test_the_numeral_comes_from_ages_json_not_from_the_number() -> void:
	# 9.1 shows a ROMAN numeral, and the mapping is data -- ages.json carries
	# both a numeral and a name for exactly this.
	badge.age = 3
	assert_eq(badge._numeral.text, "III")
	badge.age = 4
	assert_eq(badge._numeral.text, "IV")


func test_the_last_age_offers_no_advance() -> void:
	badge.age = GameDataRegistry.age_count()
	assert_eq(badge.next_age(), 0)


func test_pressing_it_asks_for_the_next_age() -> void:
	var asked: Array[int] = []
	badge.advance_requested.connect(func(next: int) -> void: asked.append(next))
	badge.age = 2
	badge._on_pressed()
	assert_eq(asked, [3] as Array[int])


func test_pressing_at_the_last_age_asks_for_nothing() -> void:
	# Rather than emitting an age the sim would refuse. DebugSetAgeCommand
	# rejects out-of-range instead of clamping, so an emission here would show up
	# as a command that silently does nothing -- worth not producing at all.
	var asked: Array[int] = []
	badge.advance_requested.connect(func(next: int) -> void: asked.append(next))
	badge.age = GameDataRegistry.age_count()
	badge._on_pressed()
	assert_true(asked.is_empty())


func test_it_stays_visible_at_the_last_age() -> void:
	# Greyed, not hidden: a HUD element that disappears at age 4 reads as a bug,
	# and the numeral is still the thing 9.1 actually asks for.
	badge.age = GameDataRegistry.age_count()
	assert_true(badge.visible)
	assert_eq(badge._numeral.text, "IV")
	assert_eq(badge._hint.text, "MAX")


func test_the_badge_never_asks_for_an_age_the_command_would_refuse() -> void:
	# The two agree by construction -- both read GameDataRegistry.age_count() --
	# and this is what notices if one of them stops.
	var w := SimWorld.new()
	var cfg := MatchConfig.new()
	cfg.player_ids = [1]
	w.setup(cfg)

	for age in range(1, GameDataRegistry.age_count() + 1):
		badge.age = age
		var next := badge.next_age()
		if next == 0:
			continue
		assert_true(DebugSetAgeCommand.new(1, next).validate(w),
				"the badge offers age %d and the sim accepts it" % next)


# ── a swallowed press says why (project owner, 2026-08-28) ──────────────────

func _refusals() -> Array:
	var seen: Array = []
	badge.advance_unavailable.connect(func(reason: StringName) -> void: seen.append(reason))
	return seen


func test_pressing_at_the_last_age_says_so_instead_of_going_dead() -> void:
	# "MAX" is drawn under the numeral and does not read as an answer to a press.
	# The report was "age up, does not tell you why its failing when clicked".
	var seen := _refusals()
	badge.age = GameDataRegistry.age_count()
	badge._on_pressed()
	assert_eq(seen, [&"maxed"])


func test_pressing_mid_research_says_so_too() -> void:
	var seen := _refusals()
	badge.advancing = true
	badge._on_pressed()
	assert_eq(seen, [&"advancing"])


func test_a_press_that_is_honoured_reports_no_refusal() -> void:
	# The two signals are exclusive, or a successful press would toast at the player
	# for no reason.
	var seen := _refusals()
	var asked: Array[int] = []
	badge.advance_requested.connect(func(next: int) -> void: asked.append(next))
	badge.age = 1
	badge._on_pressed()
	assert_eq(asked, [2] as Array[int])
	assert_true(seen.is_empty())


# -- the advance ring --------------------------------------------------------

func test_progress_is_clamped_to_a_fraction() -> void:
	badge.progress = 2.5
	assert_almost_eq(badge.progress, 1.0, 0.001)
	badge.progress = -1.0
	assert_almost_eq(badge.progress, 0.0, 0.001)


func test_a_badge_mid_research_refuses_to_start_another() -> void:
	# A double tap would otherwise restart the research and snap the ring back to
	# empty for no reason the player could see. AdvanceAgeCommand refuses it too;
	# this is the half that never asks.
	var asked: Array[int] = []
	badge.advance_requested.connect(func(next: int) -> void: asked.append(next))
	badge.age = 1
	badge.advancing = true
	badge._on_pressed()
	assert_true(asked.is_empty())

	badge.advancing = false
	badge._on_pressed()
	assert_eq(asked, [2] as Array[int])


func test_the_hint_reads_differently_in_each_of_the_three_states() -> void:
	badge.age = 1
	badge.advancing = false
	assert_eq(badge._hint.text, "ADVANCE", "there is something to do")

	badge.advancing = true
	assert_eq(badge._hint.text, "...", "it is under way and the ring is the feedback")

	badge.advancing = false
	badge.age = GameDataRegistry.age_count()
	assert_eq(badge._hint.text, "MAX", "there is nothing left to reach")


func test_advancing_and_progress_are_independent() -> void:
	# The tick a research STARTS is progress 0.0, and the badge must already have
	# stopped offering another -- so "advancing" cannot be inferred from progress.
	badge.advancing = true
	assert_almost_eq(badge.progress, 0.0, 0.001)
	assert_eq(badge._hint.text, "...")


# ── the dragon claim shares this ring (13.2c, owner's ask 2026-09-07) ──────
#
# *"lets reuse the exact same spot as the age up... the age up ring draws over the dragon
# tame, since a age up is quick no conflict."*

func test_the_claim_ring_is_its_own_state_and_is_off_by_default() -> void:
	assert_false(badge.claim_active)
	assert_almost_eq(badge.claim_progress, 0.0, 0.001)
	assert_false(badge._arc_shown(), "and nothing is animating")


func test_the_claim_progress_is_clamped_like_the_age_one() -> void:
	badge.claim_progress = 4.0
	assert_almost_eq(badge.claim_progress, 1.0, 0.001)
	badge.claim_progress = -2.0
	assert_almost_eq(badge.claim_progress, 0.0, 0.001)


func test_a_claim_and_an_advance_at_once_gives_the_ring_to_the_advance() -> void:
	# ⚠️ EXCLUSIVE, NOT LAYERED, and this is the assertion that says so. A literal
	# overdraw would leave the claimant's colour running on past the gold wherever the
	# claim is further round -- one ring in two colours, which reads as a broken gauge
	# rather than as two features. The advance is tens of seconds; the claim is 360.
	badge.claim_active = true
	badge.claim_progress = 0.8
	badge.advancing = true
	badge.progress = 0.3
	assert_true(badge._age_ring_wins(), "the advance owns the ring while it is in flight")

	badge.advancing = false
	badge.progress = 0.0
	assert_false(badge._age_ring_wins(), "and hands it back where the claim now stands")
	assert_almost_eq(badge.claim_progress, 0.8, 0.001, "which has kept running underneath")


func test_the_claim_ring_is_animated_and_a_quiet_badge_is_not() -> void:
	# The spark is the only thing on this badge that moves on its own, so `_process` is
	# gated to the seconds an arc is actually on screen -- a per-frame redraw of something
	# that cannot have changed is what the MapMaker's "the tool is very slow" turned out
	# to be.
	#
	# ⚠️ **AND THIS TEST IS BLIND TO THE FAULT IT LOOKS LIKE IT COVERS.** Declaring
	# `_process` is what makes Godot process a node, and it is re-applied when the node
	# ENTERS A TREE -- which a bare `.new()` never does, so `_init`'s `set_process(false)`
	# is the last word here and was not in a real scene. `AgeBadge._ready` re-asserts the
	# gate and `preview_age_badge`'s report is what can see it. Every assertion below
	# passed while every badge in the game was animating.
	assert_false(badge.is_processing(), "age 1, nothing in flight")

	badge.claim_active = true
	badge.claim_progress = 0.25
	assert_true(badge.is_processing())

	badge.claim_active = false
	assert_false(badge.is_processing())

	badge.progress = 0.5
	assert_true(badge.is_processing(), "and an advance animates it too")


func test_entering_a_tree_does_not_leave_a_quiet_badge_animating() -> void:
	# The half of the rule above that a headless test CAN reach: `_ready` re-asserting the
	# gate. Driven by hand, which is the harness's own pattern -- there is no tree here, so
	# what this pins is that `_ready` asks at all, not the engine behaviour that makes it
	# necessary. Deleting the `_sync_spark_clock()` call from `_ready` fails this.
	badge.progress = 0.6
	badge._ready()
	assert_true(badge.is_processing(), "an arc is on screen")

	badge.progress = 0.0
	badge.claim_active = false
	badge._ready()
	assert_false(badge.is_processing(), "and a badge with no countdown is quiet again")


func test_the_tick_an_advance_starts_has_no_arc_to_spark() -> void:
	# `_draw` returns early at exactly 0.0, so there is no head to put a spark on -- and
	# `advancing` is deliberately not part of `_arc_shown` for that reason.
	badge.advancing = true
	badge.progress = 0.0
	assert_false(badge._arc_shown())


# ── the spark (owner's ask, same day) ──────────────────────────────────────

func _ring_radius() -> float:
	return AgeBadge.SIZE * 0.5 - AgeBadge.RING_WIDTH


func test_no_spark_ever_leaves_the_badge() -> void:
	# ⚠️ THE PROPERTY THAT ACTUALLY MATTERS. A `Control` does not clip its own `_draw`
	# (the MapMaker's "map renders over UI" was one line of exactly this), and this badge
	# sits in the age header a few pixels from the resource counters -- which is where
	# 9.1's first free-floating version of the whole thing landed. Swept across a full
	# spark period and the whole travel of the ring.
	var r := _ring_radius()
	var worst := 0.0
	for step in range(41):
		var fraction := float(step) / 40.0
		for frame in range(24):
			var t := AgeBadge.SPARK_PERIOD_SEC * float(frame) / 23.0
			var head := -PI * 0.5 + TAU * fraction
			for e in AgeBadge.spark_embers(t, r, fraction, head):
				worst = maxf(worst, (e["offset"] as Vector2).length() + float(e["radius"]))
	assert_true(worst <= AgeBadge.SPARK_MAX_RADIUS,
			"the furthest ember reaches %.2f of a %.2f budget" % [worst, AgeBadge.SPARK_MAX_RADIUS])
	# The core and the tip are both drawn AT the head, so they are arithmetic rather than
	# a sweep -- and the tip is the binding one: half its width plus the ring radius is
	# the budget exactly, which is why it cannot be widened without moving the ring.
	assert_true(r + AgeBadge.SPARK_CORE_PX <= AgeBadge.SPARK_MAX_RADIUS,
			"and neither does the core glow")
	assert_true(r + AgeBadge.SPARK_TIP_WIDTH * 0.5 <= AgeBadge.SPARK_MAX_RADIUS,
			"nor the hot tip, which is drawn wider than the ring")


func test_the_embers_trail_BEHIND_the_head_and_never_ahead_of_it() -> void:
	# Thrown forward they would sit on track the ring has not reached yet, which reads as
	# the gauge overshooting. `draw_arc` fills clockwise from 12 o'clock, so behind the
	# head is the SMALLER angle -- the one direction that is easy to get backwards.
	var r := _ring_radius()
	var head := -PI * 0.5 + TAU * 0.5          # 6 o'clock, angle +PI/2
	for e in AgeBadge.spark_embers(0.1, r, 0.5, head):
		var offset: Vector2 = e["offset"]
		assert_true(offset.angle() <= head + 0.0001,
				"an ember at %.3f rad is not ahead of a head at %.3f" % [offset.angle(), head])


func test_a_barely_started_ring_keeps_its_sparks_on_the_arc_it_has_drawn() -> void:
	# At 2% the drawn arc is ~0.13 rad against a 0.55 rad trail, so a fixed trail would
	# put four of the five embers anticlockwise of 12 o'clock -- ahead of the gauge's own
	# start, on track it will not reach until the very end.
	var r := _ring_radius()
	var start := -PI * 0.5
	var fraction := 0.02
	var head := start + TAU * fraction
	for e in AgeBadge.spark_embers(0.3, r, fraction, head):
		assert_true((e["offset"] as Vector2).angle() >= start - 0.0001,
				"no ember is anticlockwise of the ring's own start")


func test_an_ember_fades_and_shrinks_over_its_life_rather_than_switching_off() -> void:
	# Asserted as an ORDERING over the train rather than as figures: the phases are spread
	# evenly, so ember 0 is always the youngest at t = 0 and the alphas must descend from
	# it. Numbers here would be a test that fails the day the period is retuned.
	var sparks := AgeBadge.spark_embers(0.0, _ring_radius(), 1.0, 0.0)
	assert_eq(sparks.size(), AgeBadge.SPARK_COUNT)
	for i in range(1, sparks.size()):
		assert_true(float(sparks[i]["alpha"]) < float(sparks[i - 1]["alpha"]),
				"ember %d is dimmer than the one in front of it" % i)
		assert_true(float(sparks[i]["radius"]) < float(sparks[i - 1]["radius"]),
				"and smaller")


func test_the_train_is_deterministic_and_wraps() -> void:
	# ⚠️ WHY THERE IS A JITTER TABLE AND NOT A `randf()`. A spark drawn from a random
	# number is a different picture in every frame and in every screenshot, so nothing
	# above could be asserted and no preview could be compared run to run.
	var r := _ring_radius()
	var a := AgeBadge.spark_embers(0.17, r, 0.5, 1.0)
	var b := AgeBadge.spark_embers(0.17, r, 0.5, 1.0)
	for i in range(a.size()):
		assert_eq(a[i]["offset"], b[i]["offset"], "the same time gives the same sparks")
	var wrapped := AgeBadge.spark_embers(0.17 + AgeBadge.SPARK_PERIOD_SEC, r, 0.5, 1.0)
	for i in range(a.size()):
		assert_true((a[i]["offset"] as Vector2).distance_to(wrapped[i]["offset"]) < 0.001,
				"and a full period later the train is where it started")


# ── a player colour has to survive being a 4 px arc ───────────────────────

func test_every_palette_colour_comes_out_light_enough_to_see() -> void:
	# ⚠️ `colours.json` IS A LADDER FOR TELLING PLAYERS APART FROM EACH OTHER, and nothing
	# in it promises a rung is legible against a dark badge. Measured: the track is 0.16
	# and the fill 0.12, against blue's 0.25 and red's 0.19.
	for i in range(GameDataRegistry.colour_count()):
		var lifted := AgeBadge.claim_arc_color(GameDataRegistry.colour(i))
		assert_true(lifted.get_luminance() >= AgeBadge.CLAIM_ARC_MIN_LUMINANCE - 0.001,
				"colour %d comes out at %.3f" % [i, lifted.get_luminance()])


func test_a_colour_that_is_already_bright_enough_is_left_exactly_alone() -> void:
	# Six of the eight, and the lift must not touch them: every pixel of hue shift is a
	# pixel of the identification this ring exists to give.
	var yellow := GameDataRegistry.colour(2)
	assert_true(yellow.get_luminance() > AgeBadge.CLAIM_ARC_MIN_LUMINANCE, "yellow is bright")
	assert_eq(AgeBadge.claim_arc_color(yellow), yellow)


func test_the_lift_keeps_the_hue_rather_than_washing_the_colour_out() -> void:
	# The blue end is the one that gets lifted at all, and a lifted blue that reads as
	# grey would be worse than a dark one -- identification is the whole job.
	var blue := GameDataRegistry.colour(0)
	var lifted := AgeBadge.claim_arc_color(blue)
	assert_true(lifted.get_luminance() > blue.get_luminance(), "it really was lifted")
	assert_true(absf(lifted.h - blue.h) < 0.02, "and it is still the same hue")
	assert_true(lifted.b > lifted.r and lifted.b > lifted.g, "and still recognisably blue")