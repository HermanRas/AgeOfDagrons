## Everything the tool needs before it can author a map: the game project, the roster, and
## the format guard (PLAN.md 16.1/16.2).
##
## ## WHY THIS IS ITS OWN CLASS — A PLAYTEST BUG, 2026-09-04
##
## 16.2 shipped with the startup work living in `Boot.gd`, which then handed its result to
## `Editor.setup()`. The project owner changed `run/main_scene` to `Editor.tscn` — **which is
## the obvious thing to do, because the editor is the tool** — and the whole of that work was
## skipped:
##
##   - the roster was never loaded, so `GameDataRegistry.building()` returned null for
##     everything. A start still placed a town centre (there is a hardcoded 10x10 fallback)
##     and its villagers, but **no resources at all**: 14 entities where there should have
##     been 48, and nobody would know why;
##   - `_guard_ok` kept its `false` default, so **Save refused** with "format copies have
##     drifted" when nothing had drifted.
##
## ⚠️ **THE LESSON IS THE SHAPE, NOT THE FIELD.** A screen that only works when something
## else ran first is a screen that will one day be opened directly — by a main-scene change,
## by a preview, by an export preset. So the requirement lives here, both callers ask for it,
## and `Editor` asks on its own behalf if nobody has. `setup()` is now an optimisation
## (don't redo the work Boot already did), never a precondition.
##
## ## IT REPORTS WHICH THING IS WRONG, AND THAT WAS THE SECOND HALF OF THE BUG
##
## The editor's status line said *"format copies have drifted"* for **any** not-ready reason,
## so a missing game project — the actual fault — was reported as a corrupt tool. Three
## genuinely different problems with three different fixes, so `reason` names the one that
## fired.
class_name Startup
extends RefCounted

enum State { OK, NO_GAME_PROJECT, NO_ROSTER, FORMAT_DRIFTED }

var state: State = State.OK
var root: GameRoot = null
var guard: FormatGuard = null

## One sentence, or empty when `state` is OK. Written for the person looking at the tool.
var reason: String = ""


## Resolve, load and check. Cheap enough to call from a screen's `_ready()`: a few JSON
## parses and seven file hashes.
static func check() -> Startup:
	var s := Startup.new()
	s.root = GameRoot.resolve()
	if s.root.path.is_empty():
		s.state = State.NO_GAME_PROJECT
		# ⚠️ THE EXPORTED CASE IS NAMED EXPLICITLY, because `export_presets.cfg` puts
		# `MapMaker.exe` in the repo root where `../game` does not exist. An exported tool
		# therefore NEEDS `mapmaker.local.json`, and "cannot find the game project" on its
		# own would send somebody hunting for a bug instead of writing one line of JSON.
		s.reason = ("cannot find the game project — %s. An EXPORTED MapMaker cannot derive"
				+ " it, so set \"game_root\" in %s next to the executable.") \
				% ["; ".join(PackedStringArray(s.root.problems)), GameRoot.LOCAL_CONFIG]
		return s

	if not GameDataRegistry.load_from(s.root):
		s.state = State.NO_ROSTER
		s.reason = "could not read the roster from %s/data — %s" \
				% [s.root.path, "; ".join(PackedStringArray(GameDataRegistry.load_warnings))]
		return s

	s.guard = FormatGuard.check(s.root)
	if not s.guard.passed():
		s.state = State.FORMAT_DRIFTED
		s.reason = "the format copies have drifted — saving is disabled"
		return s
	return s


## May the tool write a map?
##
## **THE ONLY QUESTION A CALLER SHOULD ASK**, and all three failures answer it the same way
## for different reasons — a map saved without a roster has no footprints and a map saved by
## a drifted tool is one the game cannot read.
func can_save() -> bool:
	return state == State.OK
