## ⚠️ **NOT THE GAME'S `AIProfile`. A ONE-CONSTANT STAND-IN** — see `format/scenario_def.gd`,
## which is the same stand-in for the same row and carries the whole argument.
##
## A `scenario.json` names its opponents by AI level word (`"passive"`, `"easy"`, …) and
## `ScenarioDef._read_opponents` validates each one against `AIProfile.IDS`, refusing anything
## else. So the export's picker must offer exactly that list and no imitation of it: an opponent
## the game refuses is a **scenario that will not start**, authored by a tool that reported
## success, and the only symptom is a greyed PLAY button on the scenario screen.
##
## The game's own class is not copied because it is a rule engine — conditions, reservations,
## reaction delays — and a map-authoring tool has no business carrying one. Five words is the
## entire surface 16.8 touches.
##
## ⛔ **THE LIST IS ORDERED AND THE ORDER IS LOAD-BEARING**, which is why the whole line is
## checked rather than the presence of each word. `ScenarioDef._ai_level_of` converts a word to a
## `SimPlayer.AILevel` with `IDS.find()`, so **the two lists are coupled by POSITION** and the
## game's own comment says nothing at either end says so. An entry inserted in the middle would
## silently make every scenario that names a level below it play against a different bot — the
## `enum Type` hazard in `format/map_generator.gd`, wearing difficulties.
##
## ⚠️ **DO NOT GROW THIS FILE.** Anything needing a profile's behaviour is the tool trying to
## play the game.
class_name AIProfile
extends RefCounted

## **MUST MATCH the game's `src/data/ai_profile.gd`, ORDER INCLUDED.** Checked at startup by
## declaration, not by hash — see the class comment.
const IDS := ["passive", "easy", "normal", "hard", "unfair"]

## What a scenario gets when the author has not chosen. **`passive` is the first four How To Play
## missions' opponent** — it runs its whole economy and never attacks — and it is the safe default
## for the same reason it is theirs: a scenario an author has not finished thinking about must not
## be lost to a raid they did not plan.
const DEFAULT_LEVEL := "passive"
