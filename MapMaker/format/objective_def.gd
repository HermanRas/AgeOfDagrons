## One row of a scenario's authored win/lose vocabulary (PLAN.md 11.8). Phase 15.1.
##
## ## ONE LANGUAGE, WRITTEN DOWN ONCE
##
## A hand-written `scenario.json` and MapMaker's Map Conditions screen (16.6) must emit
## the SAME records, or there are two dialects and the tool can author maps the game
## misreads. This class is that language, and 16.6 writes it rather than inventing one.
##
## ## THIS CLASS PARSES AND VALIDATES. IT DOES NOT EVALUATE.
##
## Evaluation is `ObjectiveSystem`'s, in the sim, on the server (15.2). PLAN.md 4's
## invariant admits no exception for scripting: if the client decides it won, the client
## can decide it won. So this lives in `src/data/` beside every other Def, gets read on
## the front door's thread, and travels to the sim inside `MatchConfig`.
##
## `to_dict()` is what travels, and it is deliberately the parsed/normalised form rather
## than the author's raw text: the sim must never re-parse `">="`, because a comparison
## that arrives as a string is a comparison two builds could disagree about.
##
## ## INTEGER ONLY, AND THAT IS A DETERMINISM RULE
##
## `market.json`'s rule (PLAN.md 9): a percentage or a float in a victory rule is a rule
## two CPUs can disagree about. `value` is an int, every comparison is between ints, and
## there is no float anywhere in this file.
##
## ## WHAT IS REJECTED AT LOAD, AND WHY REJECTION IS THE SAFE DIRECTION
##
## Decision 4 of PLAN.md 15: **a malformed objective list must make the scenario refuse
## to start, not start and evaluate to true on tick 1.** `_trophy()`'s note is the
## precedent -- *"you lose when your trophy dies"* on a map with no trophies defeats
## everybody immediately. So `from_dict` returns **null** for anything it cannot promise
## to evaluate, and says why.
##
## One of the seven subjects is rejected today, and the message distinguishes it from a
## typo on purpose -- "not built yet" and "you misspelled `bulding`" want different
## reactions from whoever reads the log:
##
##   `named_unit`  needs 16.7's per-entity overrides, which `state_hash()` must fold in
##
## A subject that silently evaluated as zero would be worse than a refusal: `== 0` is a
## comparison an unimplemented subject PASSES, so an unwinnable scenario would announce
## victory on tick 1.
##
## ✅ **`area` WAS THE THIRD AND IS EVALUABLE AS OF 16.5 (2026-09-09).** `MapData.areas` gives
## a map named regions, `MapGen.build_from()` puts them on `SimWorld.areas`, and
## `ObjectiveSystem` counts what is standing in one. The row this class carried for the whole
## of Phase 15 -- *"needs 16.5's named regions, a new `MapData` field and a FORMAT_VERSION
## bump"* -- was right about the field and wrong about the bump: the field is optional and
## absent means no areas, so neither `FORMAT_VERSION` moved (PLAN.md §16 decision 7).
##
## ⚠️ **AND THE TRAP MOVED RATHER THAN CLOSED.** A refused subject cannot be got wrong; an
## `area` row naming a region the map has not got is the `stock.get(&"foood", 0)` failure
## exactly -- a rule that counts 0 forever, on an unwinnable scenario whose only symptom is
## that nothing happens. Two defences, because neither is enough on its own:
##
##   - **`ScenarioDef.build_config()` refuses it at launch**, naming the regions the map DOES
##     have. That is the first moment both halves exist -- this class parses on the front
##     door's thread and has never seen a map -- and it is the one that reaches a person.
##   - **`ObjectiveSystem._count` answers -1**, not 0, for a region the world does not carry.
##     Which covers a config built by hand in a test, or by 16.6's editor.
##
## ✅ **`ticks` WAS THE LAST OF THE THREE AND IS EVALUABLE AS OF 16.6 (2026-09-12).** It measures
## `SimWorld.tick` -- the match clock -- and needs no new state at all, which is why it was the
## cheapest of the three deferrals to close and the one that waited longest.
##
## ⚠️ **AND IT IS THE ONLY SUBJECT THAT MOVES IN ONE DIRECTION, which makes one comparison a
## trap rather than a choice.** See `_read_clock`: `<=` is refused, because a clock that only
## rises makes that row true on tick 1 and false ever after -- instant defeat as a lose row, and
## a dead no-op as a win row. It is the first refusal in this class that is about the COMPARISON
## rather than about a field, and it is deliberate rather than incidental.
class_name ObjectiveDef
extends RefCounted

## What is being counted. `NAMED_UNIT` parses but is refused -- it is named here so the
## refusal can say "not yet" rather than "unknown". `AREA` joined the evaluated ones at 16.5
## and `TICKS` at 16.6, each by having a line DELETED from `_NOT_YET`, which is the whole
## mechanism.
##
## ⚠️ **`RESOURCE` IS APPENDED, NOT INSERTED, AND THAT IS A WIRE RULE.** `subject`
## travels as an int in `to_dict()`, so slipping a member in beside `AGE` -- where it
## reads better -- would renumber `AREA`, `NAMED_UNIT` and `TICKS` and silently
## reinterpret every objective already recorded or in flight. New subjects go on the end.
##
## `RESOURCE` arrived on 2026-09-02 with the owner's own objectives for scenario 2
## (*"Gather 500 food, and Age up to Age of Ember"*), which the five existing subjects
## could not express at all. It reads `SimPlayer.stock`, which is a BALANCE and not a
## running total -- see `ObjectiveSystem._stock_of`, and the latch its header explains.
enum Subject { UNIT, BUILDING, AGE, AREA, NAMED_UNIT, TICKS, RESOURCE }

## Whose things are counted. `INDEX` means an explicit player number in `owner_index`.
##
## **This is the axis the AI famously does not have** (Phase 14) and a win condition may
## have freely: the rule runs on the server, which can see the whole world. 15.2 routes
## `ENEMY`/`ALLY` through `Diplomacy` and passes the team table -- where the argument is
## REQUIRED with no default, for PLAN.md 4.13's reason.
##
## ⚠️ **`GAIA` IS APPENDED, NOT INSERTED, FOR `RESOURCE`'s REASON** -- `owner` travels as an
## int in `to_dict()`, so a member slipped in beside `SELF` would renumber the rest and
## silently reinterpret every objective already recorded or in flight.
##
## **AND IT DOES NOT WEAKEN "GAIA IS NOT AN ENEMY"** (`ObjectiveSystem`'s trap 1), which is
## the rule that keeps *leave the enemy nothing* from meaning *shoot every deer*. That rule
## is about what `ENEMY` resolves to and it is unchanged: `ENEMY` and `ALLY` are still
## resolved from `SimWorld.players`, which gaia has no row in. This is the opposite
## direction -- an author naming owner 0 **on purpose**, once, because the thing they want
## counted belongs to nobody. Scenario 4 is the first: *"kill the mother dragon"* is
## `unit.dragon`, gaia's, `== 0`, and there was no way to say it.
##
## `owner: 0` STAYS REFUSED and is not a synonym for this. "Player ids start at 1" is still
## true, an author who typed 0 for a player number has made a mistake, and a spelling
## (`"gaia"`) says what an index cannot.
enum Owner { SELF, ENEMY, ALLY, INDEX, GAIA }

## Integer comparisons only. Spelled as words rather than kept as `">="` so nothing
## downstream ever compares strings to decide what a rule means.
enum Compare { AT_LEAST, AT_MOST, EXACTLY }

## `ALERT` fires a `NoticeToast` and is what lets a scenario SAY something mid-match
## without ending it. Multiple `WIN` rows are ANDed (see `ScenarioDef`).
enum Output { WIN, LOSE, ALERT }

const _SUBJECTS := {
	"unit": Subject.UNIT,
	"building": Subject.BUILDING,
	"age": Subject.AGE,
	"area": Subject.AREA,
	"named_unit": Subject.NAMED_UNIT,
	"ticks": Subject.TICKS,
	"resource": Subject.RESOURCE,
}

## The resource kinds a `resource` row may name, which are `SimPlayer.stock`'s keys.
##
## PINNED HERE RATHER THAN LEFT OPEN, because a typo is the whole failure mode: `stock`
## is a plain Dictionary and `stock.get(&"foood", 0)` is 0, so a misspelled kind reads as
## "the player has none and never will" -- a scenario that cannot be won, with nothing on
## screen to say why. Four names is a list worth writing down twice.
const RESOURCE_KINDS := ["food", "wood", "gold", "stone"]

## Subject -> the row of PLAN.md that has to land before it can be evaluated. Presence
## in this map is what makes a subject refused; adding the evaluator means deleting a
## line here, which is a smaller and more obvious change than finding a guard.
const _NOT_YET := {
	# `Subject.AREA` WAS HERE AND ITS REMOVAL IS 16.5's FIRST COMMIT. `Subject.TICKS` WAS HERE AND
	# ITS REMOVAL IS 16.6's. Kept as comments rather than deleted silently, because the pattern is
	# the contract: an evaluator arriving means one line goes from this map, and `test_objectives`
	# has a case asserting the subject is no longer refused -- so the two halves cannot land apart.
	Subject.NAMED_UNIT: "16.7, per-entity overrides (state_hash must fold them in)",
}

const _OWNERS := {"self": Owner.SELF, "enemy": Owner.ENEMY, "ally": Owner.ALLY,
	"gaia": Owner.GAIA}

## Subjects that read a `SimPlayer` rather than counting entities, and therefore cannot be
## asked about gaia.
##
## ⚠️ **THE REFUSAL IS THE WHOLE COST OF ADDING `GAIA` AND IT IS WORTH SPELLING OUT.**
## `w.player_for(0)` is null -- gaia has no row in `players` -- so `_age_of` would answer 0
## and `_stock_of` would answer 0 for it. Both are values a comparison PASSES: `<= 1`
## against "gaia's age" is true, and `<= 500` against "gaia's food" is true, on tick 1,
## forever. That is trap 3 (*`== 0` is a comparison an unimplemented subject passes*) coming
## back through the OWNER axis instead of the subject one, so it is refused at load in
## exactly the same place and for exactly the same reason.
const _NOT_ABOUT_GAIA: Array[Subject] = [Subject.AGE, Subject.RESOURCE]

const _COMPARES := {">=": Compare.AT_LEAST, "<=": Compare.AT_MOST, "==": Compare.EXACTLY}

const _OUTPUTS := {"win": Output.WIN, "lose": Output.LOSE, "alert": Output.ALERT}

## Subjects that may name an `id`. `AGE` may not, and an `age` row carrying one is a
## sign the author meant something else.
##
## `RESOURCE` is in here and is the one that REQUIRES one -- see `_read_id`. The other
## three are optional, because "any unit" is a real question and "500 of any resource"
## would add food to stone.
##
## ⚠️ **`AREA` IS IN HERE AND THAT IS WHY THE REGION HAS ITS OWN FIELD** (16.5). The obvious
## spelling for *"five villagers in the north pass"* is to put the region in `id` -- and it
## would have made `id` mean a def id on three subjects and a place name on a fourth, so
## `_NAMES_AN_ID` would have become a lie and this row could not also filter by def. Instead
## `area` is a key of its own and `id` goes on meaning exactly what it means everywhere else:
## empty is *"anything of mine standing there"*, and `unit.villager` narrows it.
const _NAMES_AN_ID: Array[Subject] = [Subject.UNIT, Subject.BUILDING, Subject.RESOURCE,
	Subject.AREA]

var subject: Subject = Subject.UNIT

## The def id counted, or `&""` for "any of that subject". Absent is legal and load
## bearing: PLAN.md 11.8's own example of *leave the enemy nothing* is
## `{"subject": "unit", "owner": "enemy", "compare": "==", "value": 0}` with no id.
var id: StringName = &""

## WHICH NAMED REGION (16.5), for `Subject.AREA` and for nothing else. `&""` everywhere else,
## and a row carrying one on another subject is refused -- see `_read_area`.
##
## Matched VERBATIM against `MapData.areas`' names. There is no folding, no trimming and no
## fuzzy match at either end: a near-miss must be a refusal an author can read rather than a
## region that quietly contains nothing.
var area: StringName = &""

var owner: Owner = Owner.SELF

## Only meaningful when `owner == Owner.INDEX`.
var owner_index: int = 0

var compare: Compare = Compare.AT_LEAST
var value: int = 0
var output: Output = Output.WIN

## What the tracker (15.6) draws for this row. Optional -- `describe()` builds a
## serviceable fallback, because an objective the player cannot read is a scenario that
## does not explain itself, and that is worse than an inelegant string.
var text: String = ""


## Returns null for anything that cannot be promised an evaluation, appending the reason
## to `problems`. See the class comment for why refusal rather than a default.
##
## `problems` is passed in rather than returned beside the def because a scenario wants
## every complaint about every row at once -- an author fixing one typo per run is an
## author running this five times.
static func from_dict(d: Dictionary, problems: Array[String]) -> ObjectiveDef:
	var o := ObjectiveDef.new()

	var subject_key := str(d.get("subject", "")).to_lower()
	if not _SUBJECTS.has(subject_key):
		problems.append("unknown subject '%s' (expected one of %s)"
				% [subject_key, ", ".join(_SUBJECTS.keys())])
		return null
	o.subject = _SUBJECTS[subject_key]
	if _NOT_YET.has(o.subject):
		problems.append("subject '%s' is not evaluable yet -- it needs %s"
				% [subject_key, _NOT_YET[o.subject]])
		return null

	if not o._read_owner(d, problems):
		return null

	var compare_key := str(d.get("compare", ">="))
	if not _COMPARES.has(compare_key):
		problems.append("unknown compare '%s' (expected >=, <= or ==)" % compare_key)
		return null
	o.compare = _COMPARES[compare_key]

	var output_key := str(d.get("output", "win")).to_lower()
	if not _OUTPUTS.has(output_key):
		problems.append("unknown output '%s' (expected win, lose or alert)" % output_key)
		return null
	o.output = _OUTPUTS[output_key]

	# JSON numbers come back as FLOATS -- int() at the boundary, every time, which is
	# the same trap `MapData.from_dict()` and `AIProfile` both document. Here it is a
	# determinism rule and not only tidiness: see the class comment.
	if not d.has("value"):
		problems.append("objective has no 'value'")
		return null
	o.value = int(d.get("value", 0))
	if o.value < 0:
		problems.append("negative value %d -- nothing this counts can go below zero" % o.value)
		return null

	if not o._read_id(d, subject_key, problems):
		return null

	if not o._read_area(d, subject_key, problems):
		return null

	if not o._read_clock(problems):
		return null

	o.text = str(d.get("text", ""))
	return o


## The one refusal `ticks` needs (16.6), and it is about the COMPARISON rather than a field.
##
## ⚠️ **`ticks <= N` IS NEVER WHAT AN AUTHOR MEANT, IN EITHER OUTPUT, AND BOTH READINGS ARE
## SILENT.** The clock starts at 0 and only rises, so the row is satisfied on **tick 1** and
## stops being satisfied later:
##
##   - as a **win** row it latches on the first tick (`ObjectiveSystem`'s checklist rule) and
##     contributes nothing to the AND for the rest of the match -- a time limit that is not
##     one, on a scenario that looks like it has one;
##   - as a **lose** row it fires on tick 1 and **defeats the player before they have moved**.
##
## That is trap 3 wearing a comparison instead of a subject: a rule that passes for a reason
## nothing on screen explains. Every other subject counts something that can go up *and* down,
## so `<=` is meaningful on all six of them and this is the only place the asymmetry bites.
##
## **THE TWO SHAPES THAT WORK ARE BOTH `>=`**, and the message names them, because an author
## who typed `<=` has a real intention and needs the spelling rather than a refusal:
##
##   - *"you have ten minutes"* is `>=` with `output: "lose"` -- the clock passes the limit and
##     the match ends. A lose row does not latch, so it fires on the tick it becomes true.
##   - *"survive ten minutes"* is `>=` with `output: "win"`, which latches correctly.
##
## `==` is left alone: it is satisfied on exactly one tick, which a lose row acts on and a win
## row latches, so both do what they say. It is fragile rather than wrong, and refusing it would
## be this function guessing at intent instead of refusing a contradiction.
##
## 📝 **THIS NARROWS THE VOCABULARY, which is a thing to do deliberately and not by accident.**
## It is the same move `_NOT_ABOUT_GAIA` makes one axis over -- a combination refused at load
## because both of its readings are values a comparison passes. If the owner would rather have
## `<=` and a documented footgun, deleting this function is the whole change.
func _read_clock(problems: Array[String]) -> bool:
	if subject != Subject.TICKS or compare != Compare.AT_MOST:
		return true
	problems.append("a 'ticks' objective cannot use '<=' -- the clock starts at 0, so the row"
			+ " is already true on tick 1 and never true again."
			+ " For a time LIMIT use '>=' with output 'lose';"
			+ " for 'survive that long' use '>=' with output 'win'")
	return false


## The `area` half of a row: which named region (16.5).
##
## TWO REFUSALS, and they are `_read_id`'s two read the other way round:
##
##   - an `area` row with NO region, which cannot be measured at all. The `id` field does not
##     stand in for it: *"five villagers"* with no place is `subject: "unit"`, and an author who
##     wrote `area` meant somewhere.
##   - a region named on a subject that has no place in it, which means the author meant
##     `subject: "area"` and did not say so. Silently ignoring the key is the alternative and it
##     is how *"ten villagers in the north pass"* ships as *"ten villagers"* -- a scenario that
##     is winnable the wrong way and looks correct in the file.
##
## ⚠️ **THE REGION IS *NOT* CHECKED AGAINST A MAP HERE, AND CANNOT BE.** This class is read by
## the front door, which has a `scenario.json` and no `map.png`; `ScenarioDef.build_config()` is
## the first place both exist and is where an unknown region is refused by name. Same division
## `_read_id` already makes for unit and building ids, and for the same stated reason: this class
## must not need the registry -- or, here, the map -- to parse a file.
func _read_area(d: Dictionary, subject_key: String, problems: Array[String]) -> bool:
	# JSON has no StringName; convert at the boundary, `_read_id`'s rule.
	area = StringName(str(d.get("area", "")).strip_edges())

	if subject == Subject.AREA:
		if area.is_empty():
			problems.append("an 'area' objective must name the region in 'area'"
					+ " -- the region a MapMaker map declares, spelled exactly")
			return false
		return true

	if not area.is_empty():
		problems.append("subject '%s' is not measured in a place, so it cannot name area '%s'"
				% [subject_key, area] + " -- did you mean subject 'area'?")
		return false
	return true


## The `id` half of a row: which unit, which building, which resource.
##
## THREE REFUSALS, and the third is the one that would otherwise cost an afternoon:
##
##   - A subject that names nothing carrying an id (`age`), which means the author meant
##     a different subject.
##   - A `resource` row with NO id, which cannot be measured at all.
##   - A `resource` row naming something that is not one of the four KINDS. `stock` is a
##     plain Dictionary, so a typo reads as a balance of zero that never rises -- an
##     unwinnable scenario whose only symptom is that nothing ever happens. Unit and
##     building ids are NOT checked the same way, and deliberately: `GameDataRegistry`
##     already validates the roster and this class is loaded by the front door, which
##     must not need the registry to parse a file.
func _read_id(d: Dictionary, subject_key: String, problems: Array[String]) -> bool:
	# JSON has no StringName, so everything off the wire is a String and
	# `&"unit.villager" == "unit.villager"` is FALSE. Convert at the boundary.
	id = StringName(str(d.get("id", "")))

	if not id.is_empty() and not _NAMES_AN_ID.has(subject):
		problems.append("subject '%s' counts no entities, so it cannot name id '%s'"
				% [subject_key, id])
		return false

	if subject != Subject.RESOURCE:
		return true

	if id.is_empty():
		problems.append("a 'resource' objective must name which resource in 'id' (one of %s)"
				% ", ".join(RESOURCE_KINDS))
		return false
	if not RESOURCE_KINDS.has(String(id)):
		problems.append("unknown resource '%s' (expected one of %s)"
				% [id, ", ".join(RESOURCE_KINDS)])
		return false
	return true


func _read_owner(d: Dictionary, problems: Array[String]) -> bool:
	# An INT ("player 3") or a NAME ("self"). Both are legal and mean different things,
	# so the type is load-bearing and must survive the round trip -- `AIProfile._rule_from`
	# makes the same distinction for `units` and for the same reason.
	var raw: Variant = d.get("owner", "self")
	if raw is float or raw is int:
		owner = Owner.INDEX
		owner_index = int(raw)
		if owner_index < 1:
			problems.append("owner index %d is not a player (player ids start at 1)"
					% owner_index)
			return false
		return true

	var key := str(raw).to_lower()
	if not _OWNERS.has(key):
		problems.append("unknown owner '%s'"
				% key + " (expected self, enemy, ally, gaia or a player number)")
		return false
	owner = _OWNERS[key]

	# See `_NOT_ABOUT_GAIA`. Reached with `subject` already read -- `from_dict` does that
	# first -- so the message can name both halves of the combination, which is what the
	# author has to change.
	if owner == Owner.GAIA and _NOT_ABOUT_GAIA.has(subject):
		problems.append("owner 'gaia' cannot be asked about '%s'"
				% _SUBJECTS.find_key(subject)
				+ " -- gaia is not a player, so it has no age and holds no resources")
		return false
	return true


## The normalised form, for `MatchConfig` and therefore for the wire (15.2).
##
## Enums travel as ints and the comparison is already decided, so the sim never re-reads
## the author's `">="`. `id` becomes a String because JSON has no StringName; the sim end
## converts back at its own boundary, the way every other def already does.
func to_dict() -> Dictionary:
	return {
		"subject": int(subject),
		"id": String(id),
		# THE REGION TRAVELS AS A STRING, like `id`, and `MatchConfig` needed no edit for it --
		# `_objectives_to_wire()` calls this function. A joining client builds its own world from
		# the same `MapData` (2.4a), so both ends resolve the same name to the same rectangles.
		"area": String(area),
		"owner": int(owner),
		"owner_index": owner_index,
		"compare": int(compare),
		"value": value,
		"output": int(output),
		"text": text,
	}


static func from_wire(d: Dictionary) -> ObjectiveDef:
	var o := ObjectiveDef.new()
	o.subject = int(d.get("subject", Subject.UNIT)) as Subject
	o.id = StringName(str(d.get("id", "")))
	# Absent from a host built before 16.5, which reads as no region -- and such a host has no
	# `area` subject to select either, so the pair is consistent. `MatchConfig.from_dict`'s
	# forward-compatibility shape, one level down.
	o.area = StringName(str(d.get("area", "")))
	o.owner = int(d.get("owner", Owner.SELF)) as Owner
	o.owner_index = int(d.get("owner_index", 0))
	o.compare = int(d.get("compare", Compare.AT_LEAST)) as Compare
	o.value = int(d.get("value", 0))
	o.output = int(d.get("output", Output.WIN)) as Output
	o.text = str(d.get("text", ""))
	return o


## What 15.6's tracker draws when the author wrote no `text`.
##
## Never empty, and that is the point: a row with no label is a line the player reads as
## a bug. The progress figure is the tracker's to append ("Reach 10 villagers 4 / 10"),
## because only the sim knows it.
func describe() -> String:
	if not text.is_empty():
		return text
	var what := String(id) if not id.is_empty() else "units"
	if subject == Subject.AGE:
		what = "Age"
	elif subject == Subject.RESOURCE:
		# Capitalised because a resource id is a bare word ("food") where a unit id is a
		# namespaced one ("unit.villager"), and "food at least 500" reads as a fragment.
		what = String(id).capitalize()
	elif subject == Subject.TICKS:
		# ⚠️ **NOT OPTIONAL, because `id` is empty on every ticks row** (`_NAMES_AN_ID` refuses
		# one) and the default above is the word "units" -- so without this branch a time limit
		# would draw on the tracker as *"units at least 6000"*, which is not a clumsy label but
		# a WRONG one. An author is expected to write `text` here more than anywhere else; this
		# is what the player reads when they did not.
		#
		# TICKS AND NOT SECONDS, which is PLAN.md 16.6's instruction and `ages.json`'s rule:
		# converting here would put a second unit in front of the one person -- the author --
		# who has to type the number in the first place.
		what = "Elapsed ticks"
	# A `match` rather than subscripting a dictionary literal: GDScript will not compile
	# `{...}[key]` inline, and the failure is a whole-file compilation error that makes
	# every static on this class vanish -- so `ObjectiveDef.from_dict` reported
	# "Nonexistent function in base 'GDScript'" from four files away.
	var how := "at least"
	match compare:
		Compare.AT_MOST:
			how = "at most"
		Compare.EXACTLY:
			how = "exactly"
	# THE REGION IS PART OF THE SENTENCE, not an afterthought: "units at least 5" and "units in
	# north_pass at least 5" are different objectives, and this string is what the tracker draws
	# when an author wrote no `text`. `what` is already "units" or the def id, so the place slots
	# in between it and the comparison, which is where it reads.
	if subject == Subject.AREA and not area.is_empty():
		what = "%s in %s" % [what, area]
	return "%s %s %d" % [what, how, value]
