## One `campaign.json` and the scenarios it names (PLAN.md 15.1, layout in 11.7).
## Phase 15.1.
##
## ## THE ORDER IS DECLARED, NOT SORTED
##
## `campaign.json` names its scenario folders in play order explicitly, for two reasons
## and the second is the one that would have bitten: **`scenario_10` sorts before
## `scenario_2`**, and a campaign's order is a design decision anyway. This is the same
## trap as `AgeDef`'s -- `ages.json` is a list rather than an id-keyed object *"because
## age order is the whole meaning of the data"*.
##
## It is also why a folder this file does not name is **reported rather than appended**.
## An unnamed folder is either a designer's work in progress or a typo in the order list,
## and silently playing it last is wrong for both.
##
## ## PROGRESS IS NOT IN HERE
##
## The owner's correction to the first draft of `scenarios/README.md`, and it is
## structural rather than stylistic: authored content and player progress have separate
## lifetimes, because an update is allowed to replace a campaign's folder wholesale and
## must not take the player's place in it with them. Progress is
## `user://campaign_progress.json`, keyed by `folder`, and it is 15.7's.
##
## `folder` is therefore load-bearing beyond identity: it is the progress key. Renaming a
## campaign's directory forgets how far every player had got.
class_name CampaignDef
extends RefCounted

const ICON_FILE := "campaignIcon.png"
const BACKGROUND_FILE := "CampaignBackground.png"
const JSON_FILE := "campaign.json"

## The directory name (`HowToPlay`). The campaign's identity AND the key into
## `user://campaign_progress.json` -- see the class comment.
var folder: String = ""

var name: String = ""
var description: String = ""

## In declared play order. May contain unplayable entries: a broken scenario 2 must not
## hide scenario 1, so the campaign loads and 15.5 greys the offender.
var scenarios: Array[ScenarioDef] = []

## Absolute paths, or "" when the file is absent. **Paths and not textures**, for
## PLAN.md 3.3's reason: outside `res://` there is no `.import` sidecar and `load()`
## cannot open these at all.
##
## ⚠️ **THE BACKGROUND IS 1920x1080 AND COSTS A REAL DECODE**, so 15.5 loads it when a
## campaign is OPENED -- never all of them behind a selection list. Holding a path rather
## than a texture is what makes that the caller's choice instead of this class's.
var icon_path: String = ""
var background_path: String = ""

## Which root this came from, for the log and for the screens to say where a campaign
## lives. First match wins by folder name (PLAN.md 3.3), so this is how you tell a dev
## override from an installed copy when both exist.
var root: String = ""

## Everything wrong with `campaign.json` itself. A scenario's own troubles stay on the
## scenario, so that one bad file costs one row rather than the campaign.
var problems: Array[String] = []

## Things worth SAYING that do not stop the campaign being played (2026-09-02).
##
## ## WHY THIS EXISTS: A WORK-IN-PROGRESS SCENARIO MUST NOT BRICK THE CAMPAIGN
##
## The owner started authoring a fourth How To Play mission -- a `scenario_4/` folder with
## its own `scenario.json`, not yet named in `campaign.json`'s order -- and **the whole
## campaign became unplayable**, because an unnamed folder was a `problems` entry and
## `is_playable()` is `problems.is_empty()`. Three tests failed and, far worse, the three
## finished missions could not be started.
##
## That complaint is still made, because it is the only warning a designer gets that a
## folder will never be played. But it is not FATAL, and the argument is that the fatal
## case is already covered somewhere else: an order list naming a folder that does not
## exist is a separate check and stays a `problem`. So of the two things an unnamed folder
## can mean -- *work in progress* or *a typo in the order list* -- the first wants the
## campaign to keep working and the second is caught by the other end of the same pair.
##
## **THE TEST FOR "LOADS WITHOUT COMPLAINT" THEREFORE READS `all_problems()` AND NOT THIS.**
## Notes are for the log and for a developer; problems are what stop a player.
var notes: Array[String] = []


func is_playable() -> bool:
	return problems.is_empty() and not playable_scenarios().is_empty()


func playable_scenarios() -> Array[ScenarioDef]:
	var out: Array[ScenarioDef] = []
	for s in scenarios:
		if s.is_playable():
			out.append(s)
	return out


## Every complaint from the campaign and from all of its scenarios, each prefixed with
## where it came from. What the loader logs and what 15.5 can show.
func all_problems() -> Array[String]:
	var out: Array[String] = []
	for p in problems:
		out.append("%s/%s: %s" % [folder, JSON_FILE, p])
	for s in scenarios:
		for p in s.problems:
			out.append("%s/%s/%s: %s" % [folder, s.folder, ScenarioDef.JSON_FILE, p])
	return out


## Every non-fatal note, prefixed the same way. Logged beside `all_problems()` so a
## designer sees it, and deliberately not folded into that one -- see `notes`.
func all_notes() -> Array[String]:
	var out: Array[String] = []
	for n in notes:
		out.append("%s/%s: %s" % [folder, JSON_FILE, n])
	return out


## How many scenarios a player with `progress` completions may enter.
##
## **`progress` is a count of completions, so it is also the index of the first LOCKED
## scenario** -- 0 completions unlocks scenario 1 only, which is `scenarios[0]`. Stated
## because an off-by-one here either locks the tutorial's first page or unlocks the lot.
##
## Clamped rather than trusted: progress is read from a writable file in `user://` that a
## player can edit and a half-finished write can truncate, and a value past the end would
## otherwise index nothing. 15.7 only ever raises it, and never decrements.
func unlocked_count(progress: int) -> int:
	return clampi(progress + 1, 0, scenarios.size())


func is_unlocked(index: int, progress: int) -> bool:
	return index >= 0 and index < unlocked_count(progress)
