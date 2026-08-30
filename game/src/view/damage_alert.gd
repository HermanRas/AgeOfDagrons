## "YOU ARE UNDER ATTACK" — one alarm, and the minimap says where (project owner,
## 2026-08-30).
##
## The ask, verbatim: *"when a unit / building take damage we need an alert the player
## sound with a cool down 30sec global, with any of our unit flashing between its normal
## color and white on the mini map for 2sec after taking damage, the sound tells you to
## look at mini map, the flashing units / building tell you where multiple units /
## building are taking damage."*
##
## THE TWO HALVES ARE ON DIFFERENT CLOCKS AND THAT IS THE DESIGN. The sound is rare on
## purpose -- it is a summons, and a horn that blows every time an archer is scratched
## teaches you to ignore horns. The FLASH is not rate-limited at all, because it is the
## thing you look at once the horn has sent you: it has to show every entity currently
## being hit, or the player looks at the map and sees one blip out of the six that are
## actually burning. So `alarm_due()` is throttled to `ALARM_COOLDOWN_MS` and
## `flashing()` is not throttled at all.
##
## IT DIFFS SNAPSHOTS, exactly as `MatchAudio` does, and that file's header is the long
## version of why: `src/sim/` may not make noise or touch the tree, a snapshot is a full
## statement rather than a delta, and diffing works identically on a host and on a joined
## client because both receive the same snapshots. The three consequences it lists apply
## here word for word, and one of them is sharper for this class than for that one:
##
##   **A REMEMBERED ENTITY CARRIES NO `hp`.** `SnapshotSystem` strips the live fields
##   from an entity the player can no longer see, so a building that walks into the fog
##   arrives with its hp absent. Read naively that is a fall from 400 to 0 -- every unit
##   that steps out of vision would raise the alarm. So a missing `hp` is skipped, never
##   defaulted, and that is the single most important line in this file.
##
## Kept separate from `MatchAudio` rather than folded into its `_transitions`, because
## the two want different state: that class keeps one entry per entity per tick and
## forgets it immediately, and this one has to remember an hp for as long as an entity is
## visible and a flash for two seconds after the fact. It also has an output that is not
## a sound, which is most of the point of it.
class_name DamageAlert
extends RefCounted

## How long a hit entity flashes on the minimap.
const FLASH_MS := 2000

## How long the alarm stays quiet after sounding. GLOBAL -- one cooldown for the whole
## match, not one per entity: the owner asked for "a cool down 30sec global", and a
## per-entity cooldown would sound thirty horns for thirty units, which is the failure
## this number exists to prevent.
const ALARM_COOLDOWN_MS := 30000

## How fast the flash alternates. 200 ms is five changes a second, which reads as a
## pulse rather than a strobe -- and it is comfortably slower than the 10 Hz the
## minimap redraws at, so every phase of it is actually drawn. A period near or below
## the redraw rate would alias into a blip that looks merely dim.
const FLASH_PERIOD_MS := 200

## The alarm. `ui.under_attack` already existed in `audio.json` before this class did --
## 0 A.D.'s `alarmattackplayer`, on the UI bus -- which is the horn the owner asked for
## ("a trumpet sound would be perfect") and is what that clip is.
const ALARM_SOUND := &"ui.under_attack"

## id -> hp last seen, for entities the local player owns. Only theirs: an enemy losing
## hp is good news and needs no alarm, and on a fogless test map it would be every fight
## on the board.
var _hp: Dictionary = {}

## id -> the msec at which its flash ends.
var _flash_until: Dictionary = {}

var _last_alarm_ms: int = -ALARM_COOLDOWN_MS

## Set false by the test suite and the AI-vs-AI preview, exactly as `MatchAudio.enabled`
## is: they step thousands of ticks with nobody listening.
var enabled := true

## WHERE SOUNDS GO. Null means the `AudioManager` autoload. Injected rather than the test
## swapping the autoload out from under the tree -- see `MatchAudio.sink` for the full
## reason, which is that faking an autoload means reparenting a live singleton the rest
## of the project is holding.
var sink: Object = null


func _out() -> Object:
	return sink if sink != null else AudioManager


## Feed one snapshot. `now_ms` is injectable so a test can drive the two clocks in this
## class without sleeping for thirty seconds.
##
## Returns true if the alarm sounded, which is what a test asserts on -- the caller does
## not need it.
func observe(snap: Dictionary, local_player_id: int, now_ms: int = -1) -> bool:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()

	var hit := false
	var seen: Dictionary = {}
	for e in snap.get("updated", []):
		var entry: Dictionary = e
		var id := int(entry.get("id", 0))
		if id == 0 or int(entry.get("owner_id", 0)) != local_player_id:
			continue
		# A REMEMBERED ENTITY CARRIES NO `hp` -- see the header. Skipped rather than
		# defaulted, or every unit walking into the fog reports a mortal wound.
		if not entry.has("hp"):
			continue
		seen[id] = true
		var hp := int(entry["hp"])
		# A dead entity is not a damaged one. The death is its own report (`MatchAudio`
		# plays the death sound) and a corpse flashing on the minimap for two seconds
		# would be pointing at somewhere there is no longer anything to defend.
		if not bool(entry.get("alive", true)):
			_hp.erase(id)
			_flash_until.erase(id)
			continue
		if _hp.has(id) and hp < int(_hp[id]):
			_flash_until[id] = now_ms + FLASH_MS
			hit = true
		_hp[id] = hp

	# Forget anything not in this snapshot. It may be dead or merely out of vision and
	# the snapshot cannot say which -- so the memory goes, and if it comes back it is
	# treated as newly seen rather than as having lost every point it took while away.
	# That is the right trade: a unit healed in the fog would otherwise read as damage
	# the moment it reappeared, and a unit hurt in the fog is not something the player
	# could have acted on anyway.
	for id in _hp.keys():
		if not seen.has(id):
			_hp.erase(id)

	if not hit:
		return false
	return _sound_alarm(now_ms)


## The horn, if it is allowed to blow. Separate from the flash above because the two are
## on different clocks by design -- see the class header.
func _sound_alarm(now_ms: int) -> bool:
	if not enabled:
		return false
	if now_ms - _last_alarm_ms < ALARM_COOLDOWN_MS:
		return false
	_last_alarm_ms = now_ms
	# FLAT, not positional. It is a summons to look at the minimap, and a horn that got
	# quieter because the fighting is off-screen would be quietest exactly when it
	# matters most. `MatchAudio` makes the same call for a building completing.
	_out().play_sfx(ALARM_SOUND)
	return true


## Which entities are mid-flash, as `id -> true`, and whether the flash is currently on
## its WHITE phase. Returned together because the minimap wants both and asking twice
## would let the two answers straddle a period boundary.
##
## Expired entries are dropped here rather than on a timer: this is called once per
## snapshot, which is ten times a second, and a timer per hit unit would be a node per
## arrow.
func flashing(now_ms: int = -1) -> Dictionary:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var out: Dictionary = {}
	for id in _flash_until.keys():
		if now_ms >= int(_flash_until[id]):
			_flash_until.erase(id)
			continue
		out[id] = true
	return out


## Whether the flash is on its white phase right now. A function of the CLOCK and not of
## any one entity, so every flashing blip pulses together -- which is what makes six of
## them read as one alarm rather than as six unrelated flickers.
static func white_phase(now_ms: int = -1) -> bool:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	return int(now_ms / FLASH_PERIOD_MS) % 2 == 0


## Reset between matches, for `MatchAudio.reset`'s reason: an alert outliving its match
## would compare the new world's entity 1 against the old one's.
func reset() -> void:
	_hp.clear()
	_flash_until.clear()
	_last_alarm_ms = -ALARM_COOLDOWN_MS
