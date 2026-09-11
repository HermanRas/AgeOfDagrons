## One difficulty's worth of AI behaviour, loaded from `data/ai_<level>.json`
## (PLAN.md 12.2b). The five levels are `SimPlayer.AILevel`.
##
## ## WHY RULES AND NOT A SCRIPT, which is the whole point of this class
##
## What this replaces is `AIPlaytest.SCRIPT`: a numbered list of steps, walked in
## order, **each with a timeout in ticks after which it was abandoned**. That shape
## caused the open defect in `BUGS.md` -- p2 gave up on a barracks 73 wood short,
## moved to the next step, and died holding 950 wood. A person waits for the wood.
##
## The project owner's call, 2026-08-27: *"we should not be using timers for AI, but
## resource triggers"*, and the argument that settles it is about MAPS rather than
## about that one bug. **A timeout in ticks only means anything if you already know
## how far the villager has to walk.** 2.4b puts the veins nine tiles out in a random
## direction; a custom map (12.4) can put the gold across the water. The same script
## is then a different script, and nothing in it says so. Conditions travel; timers
## do not.
##
## The speed halving of 2026-08-23 proved it from the other end: one change to
## `units.json` invalidated every timeout in the script at once, because they were all
## secretly calibrated against walking distance. That is what a hidden dependency
## looks like when it finally fires.
##
## ## A rule fires when its conditions hold, and never expires
##
## Rules are evaluated **in order, first match wins**, once per think interval. There
## is no "current step" and no progress pointer: the AI's state is the world.
##
## **WHICH MEANS EVERY RULE NEEDS A CONDITION THAT GOES FALSE ONCE IT IS SATISFIED,**
## or it fires again next interval and the AI queues five houses. That is what
## `fewer_than` is for, and it counts foundations and production queues precisely so
## that "I have already started one" reads as "I have one".
##
## ## Saving up, which pure "build when affordable" cannot do on its own
##
## If a rule fires whenever it is affordable, a cheap rule starves an expensive one
## forever: 200 wood becomes a house every time, and the 400 for a barracks never
## accumulates. So the FIRST rule whose non-resource conditions hold **reserves its
## cost**, and rules below it may only spend what is left over. That is the flip side
## of the bug this design fixes, and building it in from the start is cheaper than
## discovering it in an AI-vs-AI run.
##
## Costs are read from the real `BuildingDef`/`UnitDef`, never written in the JSON, so
## a rule cannot drift out of step with what a barracks actually costs.
class_name AIProfile
extends RefCounted

## Matches `SimPlayer.AILevel`; the file for each is `data/ai_<id>.json`.
const IDS := ["passive", "easy", "normal", "hard", "unfair"]

var id: StringName = &""

## Reaction delay, in ticks, drawn per decision. **The difficulty knob**, and it
## models the right thing: a weak player is not worse at knowing a barracks is needed,
## they are slower to notice they can afford one. Unfair is 0 -- it acts the tick the
## conditions come true.
##
## Drawn DETERMINISTICALLY from `(player_id, tick, rule)` and never from `randi()`:
## `src/sim/` may not draw randomly at all without desyncing two hosts, and
## `AISystem`'s header already commits to it. `WildlifeSystem` hashes its roam targets
## the same way and for the same reason.
var lag_min := 0
var lag_max := 0

## The highest age this profile will advance to. Passive stops at 2 by design
## (`AI_Player_difficulty.md`), and it is enforced HERE as well as by the rule set --
## a modder writing a rule file cannot age a passive bot to 4 by adding a rule.
var max_age := 4

## Whether idle soldiers are sent at the enemy by the standing orders. False for
## Passive, which *"never attack"*. Not the same as owning no army: a passive bot with
## no military rules has nothing to send anyway, and this is the belt to that braces.
var attacks := true

## Extra units at match start, `def_id -> count`. Unfair only, and the one thing in
## this file that is not a rule: *"starts with 8 villagers and 2 swordsmen and 1
## scout"* is a handicap applied by `SimWorld.setup()`, not a decision the AI makes.
var start_units: Dictionary = {}

## Whether the profile researches from `techs.json`. **Inert until 9.3** -- that file
## is deliberately empty, so every level's "can use tech tree upgrades" is a promise
## the data cannot keep yet. Declared now so the rule files say what they mean and
## nothing has to be re-read when `TechSystem` lands.
var techs := false

## Each: {"do": StringName, "when": Dictionary, ...verb arguments}. See
## `AISystem._matches` for the condition vocabulary.
var rules: Array[Dictionary] = []

## `MatchConfig.Mode` -> the tick an `attack` rule may first fire in that game type.
## **REPLACES the rule's own `after_ticks` rather than adding to it**, so a mode listed
## here can commit the army EARLIER than the profile's opening, which is the whole
## point of it.
##
## ## Why a clock per game type at all, when timers are the thing this class replaced
##
## Because `after_ticks` is a **conquest** clock and three of the four modes are not
## conquest. Easy's opening is 5 minutes *"followed by random follow-up attacks"* --
## a promise about how long you get before a bot comes at YOU. In King of the Hill the
## same number said how long before the bot bothered to turn up at all, and since a
## KotH match is won at 9,000 points and the ladder pays 3 a tick to a side holding
## alone, **the fastest possible match is 3,000 ticks.** The owner's playtest of
## 2026-09-11 finished 9,000 to 0 with the bot still at home waiting for its clock.
##
## The class header's argument against timers still stands and this does not weaken it:
## it is an argument about timers that ABANDON a goal because a villager walked further
## than expected. This one gates when aggression unlocks, which is the one thing on the
## board that genuinely is measured in match time rather than in distance -- and a hill
## you must hold for five minutes is match time on both sides of the comparison.
##
## ⚠️ **IT APPLIES TO `attack` RULES AND NOTHING ELSE.** `AISystem._matches` checks the
## verb before it looks here, because a profile-wide clock applied to every rule would
## stop a bot GATHERING for the first minute of a Trophy match.
var mode_after_ticks: Dictionary = {}

## Lowercase game-type spellings a profile may use, the same boundary idiom as
## `ScenarioDef._MODES`. **The enum is the authority and this is only the spelling**, so
## a new mode gets a row here in front of you rather than being silently unnameable.
const _MODES := {
	"last_man_standing": MatchConfig.Mode.LAST_MAN_STANDING,
	"trophy": MatchConfig.Mode.TROPHY,
	"king_of_the_hill": MatchConfig.Mode.KING_OF_THE_HILL,
	"scenario": MatchConfig.Mode.SCENARIO,
}


## The tick an attack rule may first fire, given what the rule itself asked for. A mode
## with no entry is unchanged -- which is what keeps Last Man Standing exactly as it was.
func attack_clock(mode: int, rule_after_ticks: int) -> int:
	return int(mode_after_ticks.get(mode, rule_after_ticks))


static func from_dict(d: Dictionary) -> AIProfile:
	var a := AIProfile.new()
	a.id = StringName(str(d.get("id", "")))
	# JSON numbers come back as FLOATS -- int() at the boundary, every time. The same
	# trap `MapData.from_dict()` documents.
	var lag: Variant = d.get("lag_ticks", [0, 0])
	if lag is Array and (lag as Array).size() >= 2:
		a.lag_min = maxi(0, int((lag as Array)[0]))
		a.lag_max = maxi(a.lag_min, int((lag as Array)[1]))
	a.max_age = clampi(int(d.get("max_age", 4)), 1, 4)
	a.attacks = bool(d.get("attacks", true))
	a.techs = bool(d.get("techs", false))

	var starts: Variant = d.get("start_units", {})
	if starts is Dictionary:
		for k in (starts as Dictionary):
			# JSON has no StringName, so everything off the wire is a String and
			# `&"unit.villager" == "unit.villager"` is FALSE. Convert at the boundary.
			a.start_units[StringName(str(k))] = maxi(0, int((starts as Dictionary)[k]))

	var clocks: Variant = d.get("mode_after_ticks", {})
	if clocks is Dictionary:
		for k in (clocks as Dictionary):
			var name := str(k)
			if not _MODES.has(name):
				# LOUDLY, because the failure is otherwise invisible: a bot with a typo'd
				# game type quietly keeps its conquest clock and loses hills for a week.
				push_warning("AIProfile %s: '%s' is not a game type; the clock is ignored"
						% [a.id, name])
				continue
			a.mode_after_ticks[int(_MODES[name])] = maxi(0, int((clocks as Dictionary)[k]))

	for entry in d.get("rules", []):
		if entry is Dictionary:
			a.rules.append(_rule_from(entry as Dictionary))
	return a


## Normalised so `AISystem` never has to ask whether a value arrived as a String or a
## StringName, or as a float. Everything a rule names is a def id or a resource kind,
## and both are StringNames everywhere else in the sim.
static func _rule_from(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		var key := str(k)
		var v: Variant = d[k]
		match key:
			"when":
				out["when"] = _when_from(v if v is Dictionary else {})
			"do", "def", "unit", "at", "near", "kind":
				out[key] = StringName(str(v))
			"units":
				# An INT ("take that many idle villagers") or a NAME ("military",
				# "newest", "all"). Both are legal and mean different things, so the
				# type is load-bearing and must survive the round trip.
				out[key] = int(v) if (v is float or v is int) else str(v)
			"count":
				out[key] = int(v)
			_:
				out[key] = v
	return out


static func _when_from(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		var key := str(k)
		var v: Variant = d[k]
		match key:
			"age", "age_min", "age_max", "after_ticks":
				out[key] = int(v)
			"stock", "fewer_than", "at_least", "gathering_fewer_than":
				var m: Dictionary = {}
				if v is Dictionary:
					for kk in (v as Dictionary):
						m[StringName(str(kk))] = int((v as Dictionary)[kk])
				out[key] = m
			_:
				out[key] = v
	return out
