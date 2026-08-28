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