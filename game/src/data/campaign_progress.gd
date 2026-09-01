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
## ## READ-ONLY HERE. 15.7 ADDS THE WRITE.
##
## 15.5 needs this to know which rows are locked; 15.7 raises it on a win. Kept read-only
## rather than stubbed with a `record()` that does nothing, because a write that silently
## fails is worse than one that does not exist — the caller cannot tell.
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
static func all() -> Dictionary:
	if not FileAccess.file_exists(USER_FILE):
		return {}
	var text := FileAccess.get_file_as_string(USER_FILE)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("%s: line %d: %s" % [USER_FILE, json.get_error_line(),
				json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_warning("%s is not a JSON object; treating every campaign as unstarted"
				% USER_FILE)
		return {}
	return json.data


## Scenarios completed in `folder`. **Never negative**, whatever the file says: a negative
## would pass straight into `unlocked_count()`'s `clampi` and lock the first scenario, which
## is a campaign the player cannot start and cannot explain.
static func completed(folder: String) -> int:
	var raw: Variant = all().get(folder, 0)
	# A string, a float or a dictionary in this slot is a hand-edited or corrupt file, not a
	# number to coerce quietly. `is int` and `is float` both pass, because JSON has one
	# number type and `1` may arrive either way depending on how it was written.
	if raw is int or raw is float:
		return maxi(0, int(raw))
	return 0
