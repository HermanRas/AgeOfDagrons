## How far the player has got in each campaign (PLAN.md 15.5, written by 15.7).
##
## `{"HowToPlay": 1}` in `user://campaign_progress.json`, keyed by `CampaignDef.folder`.
##
## ## A SEPARATE FILE FROM THE CAMPAIGN, AND THAT IS STRUCTURAL
##
## The owner's correction to the first draft of `scenarios/README.md`: authored content and
## player progress have **separate lifetimes**, because an update is allowed to replace a
## campaign's folder wholesale and must not take the player's place in it with them. It also
## simply cannot live in `campaign.json` — that file is content, and content is read-only
## once installed.
##
## `folder` being the key is why `CampaignDef.folder` is load-bearing beyond identity:
## **renaming a campaign's directory forgets how far every player had got.**
##
## ## THE WRITE LANDED WITH 15.7 (2026-09-02)
##
## `record_completed()` below, called by `GameScene` on the tick the local player is shown
## VICTORY. The owner found the hole by playing for it: they reset this file to 0, won
## scenario 1 outright, and scenario 2 stayed locked — because until then **nothing in the
## game ever wrote this file**, which is the hole `pop_used`, `garrison_cap` and
## `ScenarioDef.message` were each in before something finally filled them.
##
## ## ⚠️ EVERY PATH THROUGH THIS FILE TAKES A `path`, AND THAT IS FOR THE TESTS
##
## `USER_FILE` is real state on whoever runs the suite. A test that wrote to it would
## rewrite the developer's own campaign progress, and a test that READ it passes on a fresh
## checkout and fails on a machine that has played the game — which has already happened
## once here, to `test_scenario_screen`'s heading test. So the path is a parameter with
## `USER_FILE` as its default: production calls take the default, tests pass their own.
##
## **PROGRESS IS A COUNT OF COMPLETIONS, so it is also the index of the first LOCKED
## scenario.** 0 completions unlocks scenario 1 only. `CampaignDef.unlocked_count()` owns
## that arithmetic and states why: an off-by-one here either locks the tutorial's first page
## or unlocks the lot.
##
## ## THE FILE IS PLAYER-WRITABLE, SO IT IS UNTRUSTED
##
## `user://` is a directory the player can open. Every value is clamped and type-checked
## rather than trusted, a half-finished write is a missing key rather than a crash, and
## parsing goes through `JSON.new().parse()` and never `JSON.parse_string()` — the static
## helper pushes an engine error per failure, which is a log somebody else can fill. Same
## argument `Campaigns._parse_json` makes, same reason.
class_name CampaignProgress
extends RefCounted

const USER_FILE := "user://campaign_progress.json"


## Completions per campaign folder. Empty when the file is absent, which is every player
## who has not finished a scenario yet and is not worth a warning.
static func all(path: String = USER_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("%s: line %d: %s" % [path, json.get_error_line(),
				json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_warning("%s is not a JSON object; treating every campaign as unstarted"
				% path)
		return {}
	return json.data


## Scenarios completed in `folder`. **Never negative**, whatever the file says: a negative
## would pass straight into `unlocked_count()`'s `clampi` and lock the first scenario, which
## is a campaign the player cannot start and cannot explain.
static func completed(folder: String, path: String = USER_FILE) -> int:
	var raw: Variant = all(path).get(folder, 0)
	# A string, a float or a dictionary in this slot is a hand-edited or corrupt file, not a
	# number to coerce quietly. `is int` and `is float` both pass, because JSON has one
	# number type and `1` may arrive either way depending on how it was written.
	if raw is int or raw is float:
		return maxi(0, int(raw))
	return 0


## Record that `scenario_index` of `folder` has been finished. Returns whether the file
## now records it (true also when it already did).
##
## ## PROGRESS IS A MAXIMUM AND IS NEVER DECREMENTED
##
## PLAN.md 15.7's own words, and the property is `SimPlayer.defeated`'s: one-way state is
## safe to read from anywhere, at any time, without asking when it was written. Three
## things fall out of it and all three are wanted:
##
##   - **Idempotent.** A result screen can be reached twice -- `GameScene._refresh_result`
##     latches, but a player may also replay a scenario they have already beaten, and
##     `maxi` makes that a no-op rather than a rewind.
##   - **Replaying scenario 1 after finishing 3 cannot re-lock 2 and 3.** That is the
##     failure a plain assignment would cause, and it would look like the game forgetting
##     the whole campaign.
##   - **A skipped scenario is not un-skipped.** If a later row is somehow completed first,
##     the count jumps and stays jumped.
##
## `scenario_index + 1` is the stored figure, because **progress is a COUNT of completions
## and is therefore also the index of the first LOCKED scenario** -- `CampaignDef`'s own
## note, where the off-by-one either locks the tutorial's first page or unlocks the lot.
## Finishing `scenarios[0]` is one completion.
##
## ## WHAT IT DOES WITH A FILE IT CANNOT READ
##
## ⚠️ **A corrupt or non-object file is REPLACED, and the other campaigns' rows in it go
## with it.** That is deliberate and it is the lesser loss: `all()` already treats such a
## file as "every campaign unstarted", so from the player's chair that progress is gone
## before this is called, and refusing to write would mean a campaign that can never record
## anything again. `all()` has already pushed a warning saying which line it failed on.
##
## Rows this class cannot interpret -- a string, a dictionary -- are written back UNTOUCHED
## when the file parses. Preserving something unreadable is kinder than deleting it, and
## `completed()` already clamps it to 0 on the way out.
static func record_completed(folder: String, scenario_index: int,
		path: String = USER_FILE) -> bool:
	if folder.is_empty():
		# Every skirmish. Not a warning: `MatchConfig.campaign_folder` is empty for every
		# match that is not a campaign mission, and the caller checks, so this is the belt
		# to that braces.
		return false
	if scenario_index < 0:
		push_warning("CampaignProgress: scenario index %d is not a scenario" % scenario_index)
		return false

	var data := all(path)
	var target := scenario_index + 1
	var raw: Variant = data.get(folder, 0)
	var have := int(raw) if (raw is int or raw is float) else 0
	if have >= target:
		return true               # already recorded; see "idempotent" above

	data[folder] = maxi(maxi(0, have), target)
	return _write(data, path)


static func _write(data: Dictionary, path: String) -> bool:
	# The directory exists for `USER_FILE` (it is `user://` itself) and may not for a test's
	# own path. Made rather than assumed, so a test does not have to know.
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		# SAID OUT LOUD, because a silent failure here is a campaign that never unlocks and
		# gives no reason -- which is exactly the shape of the bug 15.7 exists to fix.
		push_warning("CampaignProgress: cannot write %s (%s)"
				% [path, error_string(FileAccess.get_open_error())])
		return false
	# `store_string` and not `store_line`: the file is read with `get_file_as_string` and a
	# trailing newline is not worth a difference between what was written and what comes
	# back. Indented so a developer -- or the owner, who edits this by hand -- can read it.
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true
