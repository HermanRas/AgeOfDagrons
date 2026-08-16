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
