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
## Three of the six subjects are rejected today, and the message distinguishes them from
## a typo on purpose -- "not built yet" and "you misspelled `bulding`" want different
## reactions from whoever reads the log:
##
##   `area`        needs 16.5's named regions, a new `MapData` field and a FORMAT_VERSION bump
##   `named_unit`  needs 16.7's per-entity overrides, which `state_hash()` must fold in
##   `ticks`       16.6's time limit. Nothing evaluates it yet
##
## A subject that silently evaluated as zero would be worse than a refusal: `== 0` is a
## comparison an unimplemented subject PASSES, so an unwinnable scenario would announce
## victory on tick 1.
class_name ObjectiveDef
extends RefCounted

## What is being counted. `AREA`, `NAMED_UNIT` and `TICKS` parse but are refused --
## they are named here so the refusal can say "not yet" rather than "unknown".
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
enum Owner { SELF, ENEMY, ALLY, INDEX }

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
	Subject.AREA: "16.5, named regions (a new MapData field and a FORMAT_VERSION bump)",
	Subject.NAMED_UNIT: "16.7, per-entity overrides (state_hash must fold them in)",
	Subject.TICKS: "16.6, the authored time limit",
}

const _OWNERS := {"self": Owner.SELF, "enemy": Owner.ENEMY, "ally": Owner.ALLY}

const _COMPARES := {">=": Compare.AT_LEAST, "<=": Compare.AT_MOST, "==": Compare.EXACTLY}

const _OUTPUTS := {"win": Output.WIN, "lose": Output.LOSE, "alert": Output.ALERT}

## Subjects that may name an `id`. `AGE` may not, and an `age` row carrying one is a
## sign the author meant something else.
##
## `RESOURCE` is in here and is the one that REQUIRES one -- see `_read_id`. The other
## two are optional, because "any unit" is a real question and "500 of any resource"
## would add food to stone.
const _NAMES_AN_ID: Array[Subject] = [Subject.UNIT, Subject.BUILDING, Subject.RESOURCE]

var subject: Subject = Subject.UNIT

## The def id counted, or `&""` for "any of that subject". Absent is legal and load
## bearing: PLAN.md 11.8's own example of *leave the enemy nothing* is
## `{"subject": "unit", "owner": "enemy", "compare": "==", "value": 0}` with no id.
var id: StringName = &""

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

	o.text = str(d.get("text", ""))
	return o


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
		problems.append("unknown owner '%s' (expected self, enemy, ally or a player number)"
				% key)
		return false
	owner = _OWNERS[key]
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
	return "%s %s %d" % [what, how, value]
