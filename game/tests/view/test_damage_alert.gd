## `DamageAlert` -- the under-attack horn and the minimap's damage flash
## (project owner, 2026-08-30).
##
## WHAT CAN GO WRONG HERE IS THE DIFFING, exactly as it is for `MatchAudio`, and this
## class has one hazard that one does not: `SnapshotSystem` strips `hp` from an entity
## the player can no longer see, so a unit walking into fog arrives with no hp at all.
## Read naively that is a fall to zero, and every scouting villager would raise the
## alarm. That is the single most important assertion in this file.
##
## The two clocks are the other thing worth pinning. The horn is throttled to thirty
## seconds GLOBALLY and the flash is not throttled at all, and the reason is a design
## one -- a horn per hit teaches you to ignore horns, while a flash per hit is the thing
## you look at once the horn has sent you. A change that "tidied" the two into one
## cooldown would pass every structural check and break the feature.
##
## `now_ms` is injected throughout rather than slept for, which is the only way to test
## a thirty-second cooldown in a suite that runs in two minutes.
extends TestCase

const ME := 1
const THEM := 2


var alert: DamageAlert
var _spy: _AlarmSpy


func before_each() -> void:
	alert = DamageAlert.new()
	_spy = _AlarmSpy.new()
	# `sink` exists for exactly this -- see `MatchAudio.sink`, whose header explains why
	# faking the autoload itself is worse than injecting.
	alert.sink = _spy


func after_each() -> void:
	alert.sink = null


## One snapshot holding the given entries.
func _snap(entries: Array) -> Dictionary:
	return {"updated": entries}


func _entity(id: int, hp: int, owner_id: int = ME, alive: bool = true) -> Dictionary:
	return {"id": id, "owner_id": owner_id, "hp": hp, "alive": alive}


# ── the flash ───────────────────────────────────────────────────────────────

func test_losing_health_flashes_that_entity() -> void:
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 80)]), ME, 100)
	assert_true(alert.flashing(150).has(7), "the hit unit flashes")


func test_the_first_snapshot_flashes_nothing() -> void:
	# Every entity in it is new, so there is no previous hp to have fallen from.
	# Without this, joining a match in progress would light the whole minimap.
	alert.observe(_snap([_entity(7, 40), _entity(8, 10)]), ME, 0)
	assert_true(alert.flashing(0).is_empty())


func test_the_flash_expires_after_two_seconds() -> void:
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 80)]), ME, 100)
	assert_true(alert.flashing(100 + DamageAlert.FLASH_MS - 1).has(7), "still lit just before")
	assert_false(alert.flashing(100 + DamageAlert.FLASH_MS).has(7), "out at the deadline")


func test_healing_does_not_flash() -> void:
	alert.observe(_snap([_entity(7, 50)]), ME, 0)
	alert.observe(_snap([_entity(7, 90)]), ME, 100)
	assert_true(alert.flashing(150).is_empty(), "gaining health is not an attack")


func test_an_enemy_taking_damage_is_not_our_alarm() -> void:
	# Good news, and on a fogless test map it would be every fight on the board.
	alert.observe(_snap([_entity(7, 100, THEM)]), ME, 0)
	var sounded := alert.observe(_snap([_entity(7, 20, THEM)]), ME, 100)
	assert_false(sounded, "no horn for an enemy losing health")
	assert_true(alert.flashing(150).is_empty(), "and no flash")


func test_a_death_stops_the_flash_rather_than_starting_one() -> void:
	# The death has its own report (`MatchAudio` plays the death sound), and a corpse
	# flashing for two seconds points at somewhere there is no longer anything to
	# defend.
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 20)]), ME, 100)
	assert_true(alert.flashing(150).has(7))
	alert.observe(_snap([_entity(7, 0, ME, false)]), ME, 200)
	assert_false(alert.flashing(250).has(7), "a dead unit stops flashing")


func test_the_flash_phase_is_shared_by_every_blip() -> void:
	# A function of the clock alone, so six hit units pulse TOGETHER and read as one
	# alarm rather than six unrelated flickers.
	var on := DamageAlert.white_phase(0)
	assert_eq(DamageAlert.white_phase(DamageAlert.FLASH_PERIOD_MS / 2), on,
			"same phase inside one period")
	assert_eq(DamageAlert.white_phase(DamageAlert.FLASH_PERIOD_MS), not on,
			"and the opposite in the next")


# ── the fog hazard ──────────────────────────────────────────────────────────

func test_an_entity_that_walks_into_fog_is_not_reported_as_hurt() -> void:
	# THE ONE THAT WOULD HAVE SHIPPED. A remembered entry carries no `hp` at all --
	# SnapshotSystem strips the live fields -- so a missing hp read as 0 would make
	# every unit stepping out of vision a mortal wound, complete with horn.
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	var sounded := alert.observe(
			_snap([{"id": 7, "owner_id": ME, "alive": true}]), ME, 100)
	assert_false(sounded, "no horn for an entity with no hp on the wire")
	assert_true(alert.flashing(150).is_empty(), "and no flash")


func test_an_entity_that_leaves_and_returns_is_not_reported_as_hurt() -> void:
	# It may have been healed or hurt while away and the snapshot cannot say which. It
	# is treated as newly seen, which is the right trade: damage the player could not
	# have acted on is not worth a false alarm about damage that is over.
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([]), ME, 100)
	var sounded := alert.observe(_snap([_entity(7, 30)]), ME, 200)
	assert_false(sounded, "a re-sighted unit is new, not wounded")


# ── the horn ────────────────────────────────────────────────────────────────

func test_the_first_hit_sounds_the_alarm() -> void:
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	assert_true(alert.observe(_snap([_entity(7, 80)]), ME, 100))
	assert_eq(_spy.calls.size(), 1)
	assert_eq(String(_spy.calls[0]), String(DamageAlert.ALARM_SOUND))


func test_the_alarm_is_silent_for_thirty_seconds_afterwards() -> void:
	# The point of the whole cooldown: a horn that blows every time an archer is
	# scratched teaches you to ignore horns.
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 90)]), ME, 100)
	for t in [200, 5000, DamageAlert.ALARM_COOLDOWN_MS]:
		alert.observe(_snap([_entity(7, 90)]), ME, t)
		alert.observe(_snap([_entity(7, 80)]), ME, t + 10)
	assert_eq(_spy.calls.size(), 1, "one horn, however much is happening: %s" % [_spy.calls])


func test_the_alarm_returns_once_the_cooldown_has_run() -> void:
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 90)]), ME, 100)
	var later := 100 + DamageAlert.ALARM_COOLDOWN_MS
	alert.observe(_snap([_entity(7, 90)]), ME, later)
	assert_true(alert.observe(_snap([_entity(7, 80)]), ME, later + 10))
	assert_eq(_spy.calls.size(), 2)


func test_the_cooldown_is_global_and_not_per_entity() -> void:
	# Thirty units hit at once is one attack, not thirty. A per-entity cooldown would
	# sound thirty horns, which is the failure this number exists to prevent.
	var full: Array = []
	var hurt: Array = []
	for id in range(1, 31):
		full.append(_entity(id, 100))
		hurt.append(_entity(id, 60))
	alert.observe(_snap(full), ME, 0)
	alert.observe(_snap(hurt), ME, 100)
	assert_eq(_spy.calls.size(), 1, "one horn for thirty casualties: %s" % [_spy.calls])
	assert_eq(alert.flashing(150).size(), 30, "and all thirty flash")


func test_the_flash_is_not_throttled_with_the_horn() -> void:
	# THE TWO CLOCKS. The horn is rare on purpose; the flash is what you look at once
	# the horn has sent you, so it must show everything currently being hit -- or the
	# player looks at the map and sees one blip out of six.
	alert.observe(_snap([_entity(7, 100), _entity(8, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 90), _entity(8, 100)]), ME, 100)
	assert_eq(_spy.calls.size(), 1)
	# Well inside the horn's cooldown, so nothing sounds -- but the second unit is
	# being hit now and has to show.
	alert.observe(_snap([_entity(7, 90), _entity(8, 90)]), ME, 5000)
	assert_eq(_spy.calls.size(), 1, "still no second horn")
	assert_true(alert.flashing(5050).has(8), "but the newly hit unit flashes")


func test_a_disabled_alert_stays_silent() -> void:
	# Set false by the AI-vs-AI preview, which steps thousands of ticks with nobody
	# listening -- the same switch `MatchAudio.enabled` is.
	alert.enabled = false
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 10)]), ME, 100)
	assert_eq(_spy.calls.size(), 0, "no sound")
	assert_true(alert.flashing(150).has(7), "the flash is a picture, not a noise")


func test_reset_forgets_the_match() -> void:
	# An alert outliving its match would compare the new world's entity 1 against the
	# old one's -- `MatchAudio.reset` exists for the same reason.
	alert.observe(_snap([_entity(7, 100)]), ME, 0)
	alert.observe(_snap([_entity(7, 50)]), ME, 100)
	alert.reset()
	assert_true(alert.flashing(150).is_empty(), "no flash carried over")
	assert_false(alert.observe(_snap([_entity(7, 20)]), ME, 200),
			"and entity 7 is a stranger again")


class _AlarmSpy:
	var calls: Array = []

	func play_sfx(sound_id: StringName) -> bool:
		if sound_id != &"":
			calls.append(String(sound_id))
		return true
