## Scenario export (PLAN.md 16.8): write a `campaign.json` / `scenario.json` pair and the icon
## slots beside a map, so a campaign is authored in the tool rather than by hand-editing JSON.
##
## ## ⛔ THIS IS THE SECOND CONSUMER OF 15.1's SCHEMA, AND THE SCHEMA IS WHAT MUST NOT MOVE
##
## Until now exactly one thing wrote a `scenario.json`: a person, in a text editor, with
## `ScenarioDef` on the other side of the file to complain when they got it wrong. A second writer
## is where a format quietly grows a dialect — so **nothing here invents a spelling**:
##
##   | what is written        | where the word comes from                        |
##   |------------------------|--------------------------------------------------|
##   | `mode`                 | `format/scenario_def.gd`'s `_MODES`, guarded      |
##   | `opponents[]`          | `format/ai_profile.gd`'s `IDS`, guarded           |
##   | `map.type`             | `MapGenerator.Type`, guarded                      |
##   | `objectives[]`         | the author's own records, `ObjectiveDef`-validated|
##   | the three icon names   | `format/scenario_def.gd`, `format/campaign_def.gd`|
##
## `FormatGuard.SCHEMA` checks all of those against the game's source at startup and
## **`schema_ok()` is the permission to export** — which is why `run()` takes the guard as a
## required argument rather than reading one from somewhere convenient. `Diplomacy.is_enemy`'s
## team table is the precedent this repo argues from: *a rule that can be left out is a rule that
## is off somewhere.*
##
## ## ⛔ THE MODE IS DERIVED FROM THE CONDITIONS AND IS NOT A CONTROL THE AUTHOR TOUCHES
##
## The two mode words and the condition list are not independent, and `ScenarioDef` refuses both
## disagreements outright:
##
##   - `last_man_standing` carrying objectives — *"its objective(s) would never be read"*;
##   - `scenario` with no win row — *"can never be won"*.
##
## So of the four combinations exactly two are legal, and each is legal for exactly one condition
## list. A mode picker would therefore be a control whose wrong setting authors a mission that
## **refuses to start**, for no expressive gain at all — 16.6's panel already warns about both
## halves of this precisely because a hand-written file can get it wrong. Deriving it means the
## tool cannot.
##
## ⚠️ **THE THIRD CASE IS THE ONE THAT HAS TO BE REFUSED: rows, but no `win` row.** It is legal in
## neither mode, so there is no spelling of it that starts — and it is a perfectly ordinary
## half-finished list, which is why 16.6 only *warns* about it while an author is working. An
## export is the moment it stops being half-finished.
##
## ## ⚠️ EXPORT CREATES; OPEN-THEN-SAVE REPLACES
##
## 16.4a's sentence, extended by one clause rather than contradicted. `save_as()` refuses to land
## on an existing map because *"without this the field an author types a title into would be a
## delete button"*, and that argument is louder here: the target is a **campaign folder under
## version control**, and the five How To Play maps are in one. So an export onto a scenario that
## already has a map is refused and says what to do instead — open it, and Save.
##
## ⚠️ **AND THE DOCUMENT IS RE-POINTED AT WHAT IT JUST WROTE**, exactly as `save_as()` re-points
## it. That is not a side effect to be tidied away: `MapDocument.save()` re-resolves
## `scenario_path` from its own directory, so after an export the Conditions panel edits the
## exported `scenario.json` — the file the game actually reads — instead of the sidecar it was
## parking rows in. 16.6's `home_text()` literally says *"nothing plays them yet, until 16.8
## writes this map a scenario"*, and this is the line that makes that sentence stop being true.
class_name ScenarioExport
extends RefCounted

## The `map` block and its two provenance keys, as the game spells them in a `scenario.json`.
##
## 📝 **NOT GUARDED, BECAUSE THE GAME READS THEM AS STRING LITERALS** — `ScenarioDef._read_map`
## does `m.get("seed", 0)`, so there is no declaration to compare against. Named here so the
## export and its tests spell them once, and `preview_exported_campaign.tscn` is what proves the
## game agrees.
const MAP_KEY := "map"
const MAP_TYPE_KEY := "type"
const MAP_SEED_KEY := "seed"

## Which icon slot a chosen PNG is for. The panel's three "Choose…" buttons, and the keys of
## `request.icons`.
enum Icon { SCENARIO, CAMPAIGN, BACKGROUND }

## What each slot is called in a request and what it is written as on disk.
##
## **THE FILENAMES COME OUT OF THE GUARDED STAND-INS**, never out of a literal here: a slot
## written under a name the game does not look for is a campaign that loads with no icon and
## nothing anywhere saying why.
const ICON_SLOTS := {
	Icon.SCENARIO: "scenario",
	Icon.CAMPAIGN: "campaign",
	Icon.BACKGROUND: "background",
}

## Every file this export wrote, absolute, in the order written. Empty when it refused.
var written: Array[String] = []

## Worth saying, and not a refusal. `MapDocument.warnings`' distinction a fourth time: the files
## are on disk and the campaign will load — these are the things an author still has to do.
var warnings: Array[String] = []


# ── what the panel asks before it can offer anything ────────────────────────

## Repo-root `scenarios/`: where campaigns live, and the only place this writes.
##
## PLAN.md §16 decision 4 — the authored source, in git, outside the Godot project. Never inside
## `game/` (which is `res://` and read-only once exported) and never into `user://`, because
## installing content is the game's job.
static func scenarios_root() -> String:
	return MapSources.repo_dir(MapSources.SCENARIOS_SUBDIR)


## Every campaign already on disk: `{folder, path, name, description, scenarios}`.
##
## **Read with `ScenarioFile.read`'s parser and not `JSON.parse_string`**, for `Campaigns`' reason:
## a campaign is shareable content, so these bytes are as untrusted as a network packet, and the
## static helper pushes an engine error per malformed file.
##
## A folder with no `campaign.json` is not a campaign and is skipped in silence — `Campaigns`'
## own rule, so the tool's list and the game's agree about what it is looking at.
static func campaigns_in(root := "") -> Array[Dictionary]:
	var base := root if not root.is_empty() else scenarios_root()
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(base)
	if dir == null:
		return out
	var folders := dir.get_directories()
	folders.sort()
	for folder in folders:
		var path := base.path_join(folder)
		var json_path := path.path_join(CampaignDef.JSON_FILE)
		if not FileAccess.file_exists(json_path):
			continue
		var ignored: Array[String] = []
		var d := ScenarioFile.read(json_path, ignored)
		out.append({
			"folder": folder,
			"path": path,
			"name": str(d.get("name", folder)),
			"description": str(d.get("description", "")),
			"scenarios": _order_list(d),
		})
	return out


## The next free `scenario_N` folder in `campaign_dir`.
##
## ⚠️ **BY WHAT IS ON DISK AND NOT BY THE ORDER LIST'S LENGTH.** A campaign whose order names
## three folders may hold a fourth the list forgot — `Campaigns` reports exactly that as a note,
## because it is what a half-written mission looks like — and handing that number back would aim
## the export at somebody's work in progress.
static func next_scenario_folder(campaign_dir: String) -> String:
	var n := 1
	while DirAccess.dir_exists_absolute(campaign_dir.path_join("scenario_%d" % n)):
		n += 1
	return "scenario_%d" % n


## A request with everything derivable already filled in. The panel puts this in its controls.
##
## **The opponent count is the map's seats minus one**, because that is the only number that
## cannot be wrong: a scenario is the human plus bots, and the map decides how many can stand on
## it. `passive` for every one of them, for `AIProfile.DEFAULT_LEVEL`'s reason.
static func default_request(doc: MapDocument) -> Dictionary:
	var seats := doc.seats() if doc != null else 0
	var opponents: Array[String] = []
	for i in maxi(seats - 1, 1):
		opponents.append(AIProfile.DEFAULT_LEVEL)
	return {
		"campaign_folder": "",
		"campaign_name": "",
		"campaign_description": "",
		"folder": "",
		"name": doc.map_name if doc != null else "",
		"description": "",
		"message": "",
		"opponents": opponents,
		"starting_age": 1,
		"icons": {},
	}


# ── the export ──────────────────────────────────────────────────────────────

## Write the pair. Problems back as sentences; **empty means exported**, and `written` says what
## landed.
##
## `guard` is required and has no default — see the class comment on why.
func run(doc: MapDocument, request: Dictionary, guard: FormatGuard,
		root := "") -> Array[String]:
	written = []
	warnings = []
	var base := root if not root.is_empty() else scenarios_root()
	var problems := _refusals(doc, request, guard, base)
	if not problems.is_empty():
		return problems

	var campaign_dir := base.path_join(str(request["campaign_folder"]))
	var scenario_dir := campaign_dir.path_join(str(request["folder"]))
	if DirAccess.make_dir_recursive_absolute(scenario_dir) != OK \
			and not DirAccess.dir_exists_absolute(scenario_dir):
		return ["could not create %s" % scenario_dir] as Array[String]

	# ⛔ **THE MAP GOES FIRST, AND A FAILURE HERE IS FATAL RATHER THAN A WARNING.** `MapDocument.save`
	# draws the opposite line for the `scenario.json` it writes beside an already-saved map — the
	# terrain is on disk, so the author has not lost their work. Here nothing is on disk yet: a
	# `scenario.json` naming a map that failed to write is a mission whose PLAY button is greyed with
	# *"has no saved map"*, which is a worse outcome than having exported nothing at all.
	var was_dir := doc.dir
	doc.dir = scenario_dir
	var map_problems := doc.save(base)
	if not map_problems.is_empty():
		doc.dir = was_dir
		return map_problems
	written.append(scenario_dir.path_join(MapFile.META_FILE))
	written.append(scenario_dir.path_join(MapFile.TERRAIN_FILE))

	var scenario_path := scenario_dir.path_join(ScenarioDef.JSON_FILE)
	if not _write_json(scenario_path, _scenario_record(doc, request), problems):
		return problems
	written.append(scenario_path)

	var campaign_path := campaign_dir.path_join(CampaignDef.JSON_FILE)
	if not _write_json(campaign_path, _campaign_record(campaign_path, request), problems):
		return problems
	written.append(campaign_path)

	_copy_icons(request, campaign_dir, scenario_dir)

	# ⛔ **THE MAP IS SAVED A SECOND TIME, AND WITHOUT IT THE CONDITIONS HAVE TWO HOMES.**
	#
	# The first save above ran when the folder held a map and **no `scenario.json`** — so
	# `MapDocument.save()` asked `ScenarioFile.path_beside()`, got nothing, and correctly parked the
	# rows in the sidecar. There is one now, and it is the file the game reads objectives from. This
	# save re-resolves: it `erase`s the sidecar's now-stale copy and writes the rows into the
	# scenario instead. Leaving the first pass's copy behind would be the *"stale second copy beside
	# the authoritative one"* that `side.erase("objectives")` exists to prevent — created here
	# rather than survived from an older file.
	#
	# One extra save is cheaper than an argument threaded into `save()` for a case it cannot see
	# coming, and it re-runs the validator so `doc.warnings` describes the file that is actually on
	# disk.
	var conditions_problems := doc.save(base)
	if not conditions_problems.is_empty():
		warnings.append("the export wrote, but re-saving the map to move its conditions into %s"
				% ScenarioDef.JSON_FILE
				+ " failed — %s" % "; ".join(PackedStringArray(conditions_problems)))
	# ⚠️ **THE MODE IS READ BACK, BECAUSE `save()` RESOLVES `scenario_path` AND NOT
	# `scenario_mode`.** Only `MapDocument.open()` ever set the second, so without this the document
	# would hold a scenario path and no idea what that scenario says decides it — and
	# `objective_problems()` reads exactly that pair to warn an author who empties the condition
	# list of a `scenario`-mode file.
	var ignored: Array[String] = []
	doc.scenario_mode = ScenarioFile.mode_in(ScenarioFile.read(doc.scenario_path, ignored))
	_warn_about_empty_slots(campaign_dir, scenario_dir)
	return [] as Array[String]


## Everything that stops an export, in the author's terms. Empty means go.
##
## ## ⚠️ WHY THESE ARE REFUSALS WHERE 16.4b's ARE WARNINGS
##
## `MapDocument.save()` warns and writes anyway, on the rule that *a validator that refuses to
## save is one people learn to route around* — and the thing it is protecting is an author's
## half-finished work, which they still have when the file is on disk.
##
## An export is the opposite act. It writes into a **campaign folder under version control**, and
## every item below produces a mission the game **refuses to start**: the PLAY button on the
## scenario screen is greyed and the reason is printed in a log in another project. There is
## nothing half-finished to preserve, because the author can simply export again.
func _refusals(doc: MapDocument, request: Dictionary, guard: FormatGuard,
		base: String) -> Array[String]:
	var out: Array[String] = []
	if guard == null or not guard.schema_ok():
		# THE GUARD'S OWN SENTENCE, which names each declaration that moved. A summary here would
		# leave somebody to go and find out which.
		out.append(guard.schema_refusal() if guard != null
				else "the scenario schema was never checked, so exporting is refused")
		return out
	if doc == null or doc.data == null:
		out.append("there is no map open")
		return out

	_check_folder(out, str(request.get("campaign_folder", "")), "campaign")
	_check_folder(out, str(request.get("folder", "")), "scenario")
	if str(request.get("name", "")).strip_edges().is_empty():
		out.append("the scenario needs a name — it is what the scenario list shows")
	if doc.map_name.strip_edges().is_empty():
		out.append("the map needs a name before it can be saved")
	# ⚠️ **ONLY WHEN THE FOLDERS ARE USABLE**, because the path below is built out of them: a blank
	# campaign folder would make this test *"is there a map in `scenarios/scenario_1`"*, which is a
	# question about a directory the author never named.
	if out.is_empty():
		_check_not_taken(out, doc, request, base)

	_check_seats(out, doc, request)
	_check_age(out, request)
	_check_conditions(out, doc)
	return out


## The folder names, which are identities rather than labels.
##
## ⛔ **A CAMPAIGN FOLDER IS THE PROGRESS KEY** — `user://campaign_progress.json` is keyed by it,
## and `CampaignDef`'s header says renaming the directory *"forgets how far every player had got"*.
## So it is taken verbatim rather than slugged: `HowToPlay` is the shipped campaign's own spelling
## and a tool that lower-cased it would author a second campaign beside it rather than adding to it.
##
## What is refused is only what a path cannot carry. `MapDocument.slug()` exists for the other
## case, where the author is naming a *thing* and the folder is derived from it.
func _check_folder(out: Array[String], folder: String, what: String) -> void:
	var clean := folder.strip_edges()
	if clean.is_empty():
		out.append("the %s folder cannot be blank — it is the folder's name on disk" % what)
		return
	for i in clean.length():
		var c := clean[i]
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
				or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok:
			out.append(("the %s folder \"%s\" cannot contain '%s' — letters, digits,"
					+ " underscore and hyphen only, because it is a directory name")
					% [what, clean, c])
			return


## ⛔ **EXPORT CREATES; IT DOES NOT REPLACE.** `save_as()`'s refusal, and the argument is louder
## here: the target is a **campaign folder under version control** and the five How To Play maps
## live in one, so a mistyped folder that landed on `scenario_3` would overwrite shipped content
## with a save that reported success. A GUI has no `--force` to offer, and the message therefore
## names the gesture that DOES replace a scenario, because that is a thing an author legitimately
## wants (it is 16.10's whole job) and they would otherwise go looking for a setting.
##
## ⚠️ **THE DOCUMENT'S OWN DIRECTORY IS THE EXCEPTION**, so re-exporting a scenario the author is
## already editing is allowed. Without that, an author who exported, noticed the description was
## wrong and exported again would be refused on their own file — and the second export is the
## ordinary way to fix the first.
func _check_not_taken(out: Array[String], doc: MapDocument, request: Dictionary,
		base: String) -> void:
	var scenario_dir := base.path_join(str(request["campaign_folder"]).strip_edges()) \
			.path_join(str(request["folder"]).strip_edges())
	if scenario_dir == doc.dir or not MapFile.exists_in(scenario_dir):
		return
	out.append(("there is already a map in %s — an export creates a scenario rather than"
			+ " replacing one, so change the scenario folder. To replace that scenario"
			+ " deliberately, open its map with File ▸ Open and press Save") % scenario_dir)


## The opponents, against the map and against the game's own cap.
##
## ⛔ **`opponents.size() + 1 > seats` IS THE GAME'S GATE AND IT IS COPIED RATHER THAN INVENTED.**
## `SkirmishScreen` refuses to start a saved map with more active slots than it seats, and its
## comment is the reason this is a refusal and not a warning: *"`MapGen.build_from()` gives a
## player a town centre and villagers only by spawning the entities the map LISTS for their index
## — so a player beyond the map's count starts alive, owning nothing, and is defeated on the first
## tick the win condition looks."*
##
## ⚠️ **FEWER IS A WARNING, NOT A REFUSAL, AND THAT IS THE SAME RULE READ THE OTHER WAY.** The
## skirmish screen allows it (`active < seats` is not an error there), so refusing it here would
## make the tool stricter than the game about a map that plays perfectly well with a spare start
## on it. Said, because a start nobody is standing in is usually a miscount rather than a plan.
func _check_seats(out: Array[String], doc: MapDocument, request: Dictionary) -> void:
	var opponents := _opponents_in(request)
	for level in opponents:
		if not AIProfile.IDS.has(level):
			out.append("unknown opponent AI level '%s' — expected one of %s"
					% [level, ", ".join(PackedStringArray(AIProfile.IDS))])
	if opponents.is_empty():
		out.append("a scenario needs at least one opponent — a match needs two players")
	var players := opponents.size() + 1
	if players > MapGenerator.MAX_PLAYERS:
		out.append("%d opponents plus the player is more than the %d a map supports"
				% [opponents.size(), MapGenerator.MAX_PLAYERS])

	var seats := doc.seats()
	if seats == 0:
		# THE MAP'S OWN GATE, and `MapDocument.seats()` records why it is not `starts.size()`: a
		# player with a start marker and no base opens the match owning nothing.
		out.append("this map seats nobody — every player needs a start AND the base behind it,"
				+ " which is what the palette's start tool places")
		return
	if players > seats:
		out.append("this map seats %d and the scenario names %d — %s"
				% [seats, players,
				"drop %d opponent(s), or give the map more starts" % (players - seats)])
	elif players < seats:
		warnings.append("this map seats %d and the scenario names %d, so %d start(s) will stand"
				% [seats, players, seats - players]
				+ " empty — harmless, and usually a miscount")


## `starting_age`, which the game clamps rather than refuses.
##
## ⚠️ **CLAMPED THERE MEANS A TYPO IS SILENT THERE**, which is exactly why it is checked here:
## `ScenarioDef.from_dict` does `clampi(int(d.get("starting_age", 1)), 1, 4)`, so an author who
## meant age 3 and typed 30 gets age 4 and no complaint anywhere. The tool is where there is
## somebody to tell.
func _check_age(out: Array[String], request: Dictionary) -> void:
	var age := int(request.get("starting_age", 1))
	if age < 1 or age > 4:
		out.append("starting age %d is outside 1..4 — the game would silently clamp it" % age)


## The condition list against the two modes, which is the whole of the mode decision.
##
## See the class comment: of the four combinations exactly two are legal, the mode is derived, and
## the third case — rows with no win row — is legal in neither and is the one thing to refuse.
func _check_conditions(out: Array[String], doc: MapDocument) -> void:
	if not doc.objectives.is_empty() and doc.win_count() == 0:
		out.append("this map has %d condition(s) and none of them is a win"
				% doc.objectives.size()
				+ " — a scenario with rows but no win row can be spelled in neither mode."
				+ " Add a win condition, or remove them all to mean 'beat them'")
	# ⚠️ **EVERY ROW IS RE-VALIDATED HERE EVEN THOUGH THE PANEL ALREADY REFUSED BAD ONES**, because
	# `MapDocument._objectives_in()` deliberately KEEPS a row it cannot parse rather than dropping
	# it — a map opened from a hand-written scenario can carry one. Exporting it would write a
	# `scenario.json` the game's loader refuses in full, and the export is the last moment anybody
	# is looking.
	for i in doc.objectives.size():
		var row_problems: Array[String] = []
		if ObjectiveDef.from_dict(doc.objectives[i], row_problems) == null:
			out.append("condition %d cannot be read by the game's loader — %s"
					% [i + 1, " | ".join(PackedStringArray(row_problems))])
	# ⚠️ **AND THE REGION CHECK, WHICH IS THE ONE ONLY THIS TOOL CAN MAKE.** `ScenarioDef` refuses an
	# `area` row naming a region the map has not got, but only at LAUNCH; here the map is open in
	# front of the person who can fix the spelling.
	#
	# `unknown_area_problems()` and not `objective_problems()`: the latter's two list-level
	# complaints are about the MODE, which this export derives — and a map opened FROM a scenario
	# still carries that scenario's mode, so it would raise a complaint about a file nothing here is
	# writing. See that function's header for why it is a split rather than a filter.
	out.append_array(doc.unknown_area_problems())
	# ⚠️ **AND THE SAME FOR A NAMED HERO (16.7).** `ScenarioDef.build_config()` refuses a row about
	# somebody the map never named, so exporting one authors a mission whose PLAY button is greyed
	# — and `ObjectiveSystem` answers -1 rather than 0 for it precisely so the scenario is
	# unwinnable rather than instantly decided, which is not a state worth shipping either.
	out.append_array(doc.unknown_name_problems())
	# ⚠️ **AND THE SAME FOR A DEF ID** (board `16.x-unknown-def-id`, 2026-09-21).
	# `build_config()` refuses these too now, so exporting one writes a mission that will not
	# start -- and before that refusal existed it wrote one that was LOST ON TICK 1, which is
	# how the trap was found. Added here as well as in `objective_problems()` because an export
	# is the moment a draft becomes a shipped mission.
	out.append_array(doc.unknown_def_id_problems())


# ── the two records ─────────────────────────────────────────────────────────

## The `scenario.json` this export writes.
##
## ## ⚠️ THE OBJECTIVES ARE THE AUTHOR'S WORDS, VERBATIM, AND THAT IS 16.6's WHOLE STORAGE RULE
##
## `ObjectiveDef.to_dict()` is the **wire** form — every enum an int, so the sim never re-parses a
## `">="`. A `scenario.json` is the opposite. `MapDocument.objectives` holds raw records for
## exactly this moment, and parsing them here to write them back out would emit a file of integers
## the game's own loader cannot read — *"and the tool looks perfect throughout, because it never
## re-parses its own output."*
##
## ## THE `map` BLOCK IS PROVENANCE AND IS OMITTED WHEN THERE IS NONE
##
## ⛔ **THE MAP IS THE SAVED `map.png` BESIDE THIS FILE.** `build_config()` does not call
## `MapGenerator` at all — the owner's ruling of 2026-09-01, *"generating is a one-off authoring
## step"* — so `type` and `seed` record only how the ground first came to exist.
##
## ⚠️ **A MAP AUTHORED IN THIS TOOL WAS NEVER GENERATED, SO IT HAS NO SEED**, and writing
## `"seed": 0` would be the kind of untrue field somebody later reads without checking. The block
## is therefore written only from what the sidecar actually carries, and omitted entirely when it
## carries nothing. `ScenarioDef._read_map` accepts that as of 16.8 — the seed requirement it used
## to enforce predates the map being a file, and its own message (*"a scenario that regenerates its
## map every run is not a scenario"*) describes a thing that can no longer happen.
func _scenario_record(doc: MapDocument, request: Dictionary) -> Dictionary:
	var record: Dictionary = {
		"_note": [
			"Written by MapMaker (PLAN.md 16.8). Edit it by hand freely -- this file is the",
			"authority and the tool re-reads it; only the `objectives` array is rewritten by",
			"the Conditions panel, and every other key it does not understand is carried",
			"through untouched.",
			"",
			"THE MAP IS THE map.png BESIDE THIS FILE (2.4c, PLAN.md 11.3), not a seed. Nothing",
			"generates a map at launch, so `map` below is provenance only and is absent",
			"entirely on a map that was authored rather than generated.",
		],
		"name": str(request["name"]).strip_edges(),
		"description": str(request.get("description", "")).strip_edges(),
		"message": str(request.get("message", "")),
		"mode": _mode_for(doc),
	}
	var provenance := _map_block(doc)
	if not provenance.is_empty():
		record[MAP_KEY] = provenance
	record["opponents"] = _opponents_in(request)
	record["starting_age"] = int(request.get("starting_age", 1))
	# ⚠️ **WRITTEN EVEN WHEN EMPTY**, `MapDocument.save()`'s rule for the sidecar: a conquest
	# scenario's empty list is a fact about it, and a key that appears only sometimes is a key
	# somebody later reads as missing rather than as empty. `ScenarioDef` refuses a
	# `last_man_standing` file that carries rows, so the two always agree by construction.
	record[ScenarioFile.OBJECTIVES_KEY] = doc.objectives.duplicate(true)
	return record


## `scenario` when the map declares how it is won, `last_man_standing` when it does not.
##
## See the class comment: this is derived rather than asked because three of the four combinations
## of mode and condition list are refused by `ScenarioDef`, and the fourth is not a choice.
static func _mode_for(doc: MapDocument) -> String:
	return ScenarioDef.mode_objectives() if not doc.objectives.is_empty() \
			else ScenarioDef.mode_conquest()


## `{type, seed}` out of the map's own sidecar, or `{}` for a map that was never generated.
##
## **BOTH KEYS ARE OPTIONAL AND INDEPENDENT.** A map opened from `preview_author_maps`' output
## carries `map_type` and `seed` at the sidecar's top level and `type`/`seed` again inside `meta`;
## one authored from New carries neither. Taking whichever is there, and writing only that, is what
## keeps the file honest in both directions.
func _map_block(doc: MapDocument) -> Dictionary:
	var out: Dictionary = {}
	var header := doc.header
	var meta: Dictionary = header.get("meta", {}) if header.get("meta") is Dictionary else {}

	# THE WORD, then the ENUM INDEX. `map_type` is written as a NAME (`"RIVER"`) and `meta.type` as
	# an int, and the scenario schema wants the name lower-cased -- so the int route goes through
	# `ScenarioDef.map_type_key()`, which reads the guarded enum rather than a second table.
	if header.has("map_type"):
		out[MAP_TYPE_KEY] = str(header["map_type"]).to_lower()
	elif meta.has("type"):
		out[MAP_TYPE_KEY] = ScenarioDef.map_type_key(int(meta["type"]))

	if header.has(MAP_SEED_KEY):
		out[MAP_SEED_KEY] = int(header[MAP_SEED_KEY])
	elif meta.has(MAP_SEED_KEY):
		out[MAP_SEED_KEY] = int(meta[MAP_SEED_KEY])
	return out


## The `campaign.json`: created if there is none, and otherwise **added to**.
##
## ## ⛔ IT REPLACES ONE KEY AND PRESERVES EVERYTHING ELSE, INCLUDING WHAT IT CANNOT READ
##
## `ScenarioFile`'s rule one level up, and the shipped `HowToPlay/campaign.json` is why it matters:
## its `_note` block is eighteen lines of the reasoning behind the campaign, and a writer that
## rebuilt the file from the fields it understands would delete that in a save that reported
## success. So the file is parsed, the order list is appended to, and it is written back.
##
## ⚠️ **THE FOLDER IS APPENDED, NEVER INSERTED, AND THE ORDER IS NOT SORTED.** `campaign.json` names
## its folders **in play order** and `CampaignDef`'s header says that order *"is not derivable"* —
## `scenario_10` sorts before `scenario_2`, and a campaign's order is a design decision anyway. A
## new scenario goes last because that is the only position the tool can be right about; moving it
## is one line in a text editor.
##
## ⚠️ **AND A FOLDER ALREADY IN THE LIST IS NOT APPENDED TWICE.** Re-exporting the same scenario
## folder is the ordinary way to fix one, and a duplicate entry would make the campaign play it
## twice and shift every index after it — which is what `CampaignProgress` records a win against.
func _campaign_record(campaign_path: String, request: Dictionary) -> Dictionary:
	var problems: Array[String] = []
	var existing := ScenarioFile.read(campaign_path, problems)
	# A FILE THAT WOULD NOT PARSE IS NOT SILENTLY REPLACED. `read()` answers `{}` for both "there is
	# no file" and "the file is broken", and only the second puts a sentence in `problems` -- so the
	# two are told apart by that array rather than by asking the filesystem twice.
	if not problems.is_empty():
		warnings.append("%s could not be read, so it was rebuilt from scratch and anything it"
				% CampaignDef.JSON_FILE
				+ " held is gone — %s" % "; ".join(PackedStringArray(problems)))
		existing = {}

	var record := existing.duplicate(true)
	if not record.has("_note"):
		record["_note"] = [
			"Written by MapMaker (PLAN.md 16.8). Edit it by hand freely: the tool preserves",
			"every key it does not understand, and only ever APPENDS to the list below.",
			"",
			"`scenarios` NAMES ITS FOLDERS IN PLAY ORDER AND THAT ORDER IS NOT DERIVABLE --",
			"scenario_10 sorts before scenario_2, and the order is a design decision anyway.",
			"Re-order this list by hand; the tool will not touch what is already in it.",
			"",
			"PROGRESS IS NOT IN THIS FILE and cannot be: an update may replace this folder",
			"wholesale and must not take the player's place in the campaign with it. Progress",
			"is user://campaign_progress.json, keyed by this folder's NAME.",
		]
	# ⚠️ **THE NAME AND DESCRIPTION ARE WRITTEN ONLY WHEN THE FILE HAS NONE.** Adding a scenario to
	# an existing campaign must not rename it: the panel shows an existing campaign's name in a
	# disabled field for exactly this reason, and an empty field arriving here would otherwise blank
	# the title of the shipped campaign.
	if str(record.get("name", "")).strip_edges().is_empty():
		record["name"] = _campaign_name(request)
	if not record.has("description"):
		record["description"] = str(request.get("campaign_description", "")).strip_edges()

	var order := _order_list(record)
	var folder := str(request["folder"]).strip_edges()
	if not order.has(folder):
		order.append(folder)
	record[CampaignDef.ORDER_KEY] = order
	return record


static func _campaign_name(request: Dictionary) -> String:
	var typed := str(request.get("campaign_name", "")).strip_edges()
	# THE FOLDER IS THE FALLBACK, which is what `Campaigns._read_campaign` does with a file that
	# names no campaign (`str(d.get("name", folder))`). Agreeing with it means a campaign never
	# shows up in the list as an empty row.
	return typed if not typed.is_empty() else str(request.get("campaign_folder", "")).strip_edges()


## The order list as plain strings. `[]` for a file that has none or whose `scenarios` is not a
## list — both of which `Campaigns` reports as a `problem` on its own side, so nothing is hidden
## by reading them the same way here.
static func _order_list(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = d.get(CampaignDef.ORDER_KEY, [])
	if not raw is Array:
		return out
	for entry in (raw as Array):
		out.append(str(entry))
	return out


static func _opponents_in(request: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = request.get("opponents", [])
	if not raw is Array:
		return out
	for entry in (raw as Array):
		out.append(str(entry).strip_edges().to_lower())
	return out


# ── the icon slots ──────────────────────────────────────────────────────────

## Copy whichever icons the request names into their slots.
##
## ## ⚠️ A SLOT IS A FILENAME, NOT A PICTURE, AND THE TOOL CANNOT DRAW ONE
##
## What 16.8 owes here is the **slot**: the right name, in the right folder, so that a PNG dropped
## beside the file is found. The game looks for three exact names and reports nothing at all when
## one is absent — `CampaignDef.icon_path` is simply `""` and the screen draws a plate — so an
## author who spells one `campaign_icon.png` gets a campaign that looks unfinished and no error
## anywhere. That silence is the whole reason this copies rather than instructs.
##
## **COPIED, NEVER MOVED OR LINKED.** The source is somebody's art directory, and a tool that
## relocated a file out of it would be destroying work to decorate a menu.
##
## ⚠️ **A FAILED COPY IS A WARNING AND NOT A REFUSAL**, `MapDocument.save()`'s line: the campaign
## is written and plays perfectly without a picture. Losing an export over an icon would be
## refusing to write the thing that matters over the thing that does not.
func _copy_icons(request: Dictionary, campaign_dir: String, scenario_dir: String) -> void:
	var icons: Dictionary = request.get("icons", {}) if request.get("icons") is Dictionary else {}
	for slot in [Icon.SCENARIO, Icon.CAMPAIGN, Icon.BACKGROUND]:
		var source := str(icons.get(ICON_SLOTS[slot], "")).strip_edges()
		if source.is_empty():
			continue
		if not FileAccess.file_exists(source):
			warnings.append("no file at %s, so the %s icon slot was left empty"
					% [source, ICON_SLOTS[slot]])
			continue
		var target := _icon_target(slot, campaign_dir, scenario_dir)
		var bytes := FileAccess.get_file_as_bytes(source)
		if bytes.is_empty():
			warnings.append("%s is empty or unreadable, so the %s icon slot was left empty"
					% [source, ICON_SLOTS[slot]])
			continue
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			warnings.append("could not write %s (error %d)"
					% [target, FileAccess.get_open_error()])
			continue
		f.store_buffer(bytes)
		f.close()
		written.append(target)


## Where each slot's file goes. The names come out of the guarded stand-ins — see `ICON_SLOTS`.
static func _icon_target(slot: int, campaign_dir: String, scenario_dir: String) -> String:
	match slot:
		Icon.SCENARIO: return scenario_dir.path_join(ScenarioDef.ICON_FILE)
		Icon.CAMPAIGN: return campaign_dir.path_join(CampaignDef.ICON_FILE)
		Icon.BACKGROUND: return campaign_dir.path_join(CampaignDef.BACKGROUND_FILE)
	return ""


## Say which slots are still empty, and name the file to drop in.
##
## ⚠️ **CHECKED ON DISK RATHER THAN AGAINST THE REQUEST**, which is what makes it right on the
## second export: a campaign that already had its icon from the first scenario must not be
## reported as missing one every time somebody adds a mission to it.
##
## **IT NAMES THE PATH, NOT THE PROBLEM.** *"No campaign icon"* sends an author looking for a
## setting; the full path is something they can drag a file onto.
func _warn_about_empty_slots(campaign_dir: String, scenario_dir: String) -> void:
	for pair in [
		[scenario_dir.path_join(ScenarioDef.ICON_FILE), "the scenario's tile"],
		[campaign_dir.path_join(CampaignDef.ICON_FILE), "the campaign's tile"],
		[campaign_dir.path_join(CampaignDef.BACKGROUND_FILE), "the campaign screen's backdrop"],
	]:
		if not FileAccess.file_exists(str(pair[0])):
			warnings.append("no picture for %s yet — drop a PNG at %s" % [pair[1], pair[0]])


# ── writing ─────────────────────────────────────────────────────────────────

## Write `record` as pretty JSON. False with the reason in `out_problems`.
##
## ⚠️ **`ints_restored()` IS NOT OPTIONAL HERE.** Everything carried forward out of an existing
## `campaign.json`, and every objective record that arrived through a `JSON.parse` at open time,
## has had its integers widened to floats — so a plain round trip writes `"value": 14.0` and
## `"starting_age": 1.0` across content under version control. `ScenarioFile`'s class comment has
## the full argument; this is the second door into it.
##
## **Never pushes an engine error**: a write can fail for ordinary reasons and the caller is a UI
## that has to say so.
static func _write_json(path: String, record: Dictionary,
		out_problems: Array[String]) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		out_problems.append("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(ScenarioFile.ints_restored(record), "  ", false) + "\n")
	f.close()
	return true
