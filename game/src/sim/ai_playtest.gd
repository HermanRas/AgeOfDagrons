## The PlayTest AI's opening, as DATA (PLAN.md 12.2a).
##
## Separated from `AISystem` on purpose: retuning the opening should not mean editing
## the interpreter, and a test can assert "by step N the AI owns a mill" against a list
## it can read. It is a `const` in its own file rather than a JSON in `data/` because
## that would need `GameDataRegistry` wiring for no gain today -- moving it is a small
## change if the opening ever wants editing without touching a `.gd` file at all.
##
## **This is the project owner's script, step for step**, with one addition at the end:
## an attack-move on the nearest enemy town centre. Without an ending a headless match
## never finishes, and finishing is what exercises the win condition and the result
## screen -- which is the difference between "the AI plays" and "I have an automated
## full-match regression test".
##
## ## How to read a step
##
##   do        the verb (see `AISystem` for what each one does)
##   units     who carries it out. An INT takes that many IDLE villagers, lowest id
##             first; "newest" takes the highest-id idle villager; "military" takes
##             every non-villager unit; "all" takes every idle villager.
##   timeout   ticks to wait before giving up and moving on. **Every step has one.**
##             On a generated map there may be no berry bush within reach, and a step
##             that waited forever would take the whole match with it.
##
## Unit selection leans on one property that does most of the work: **a villager sent
## to gather is no longer idle**, so "two to berries, one to stone, one to wood, the
## last builds a house" falls out of four steps that each take the idle ones. That is
## also how a person plays, which is why the script reads the way the owner wrote it.
class_name AIPlaytest
extends RefCounted

## Ticks, at 10 Hz. Generous: these are ceilings for giving up, not schedules.
const _SHORT := 120          # 12 s -- issuing an order to units already standing there
const _WALK := 400           # 40 s -- walk somewhere and start working
const _BUILD := 900          # 90 s -- walk, then raise a building
const _TRAIN := 900          # 90 s -- pay, queue, and wait for a spawn

const SCRIPT: Array[Dictionary] = [
	# Opening economy: the four jobs, then the fifth villager starts a house.
	{"do": "gather", "kind": &"food", "units": 2, "timeout": _WALK},
	{"do": "gather", "kind": &"stone", "units": 1, "timeout": _WALK},
	{"do": "gather", "kind": &"wood", "units": 1, "timeout": _WALK},
	{"do": "build", "def": &"building.house", "near": &"self", "units": 1, "timeout": _BUILD},

	# The two drop-off camps, each beside the resource it serves -- which is the whole
	# reason `near` names a resource rather than a fixed offset (2.4b puts the veins
	# nine tiles out in a random direction, so nothing here can assume where they are).
	{"do": "build", "def": &"building.mining_camp", "near": &"res.stone", "units": 1,
			"timeout": _BUILD},
	{"do": "build", "def": &"building.lumber_camp", "near": &"res.tree", "units": 1,
			"timeout": _BUILD},

	# The builder goes to gold, then the town advances.
	{"do": "gather", "kind": &"gold", "units": 1, "timeout": _WALK},
	{"do": "advance_age", "timeout": _TRAIN},

	# Two more villagers, then the farm: a mill and one field, worked by the pair that
	# was on berries plus whoever built it.
	{"do": "train", "at": &"building.town_center", "unit": &"unit.villager", "count": 2,
			"timeout": _TRAIN},
	{"do": "build", "def": &"building.mill", "near": &"self", "units": 1, "timeout": _BUILD},
	{"do": "build", "def": &"building.field", "near": &"building.mill", "units": 1,
			"timeout": _BUILD},
	{"do": "gather", "kind": &"food", "units": 3, "timeout": _WALK},

	# Then the military opening. A house first, or the barracks' five swordsmen run
	# into the population cap: 7 villagers + a scout + 5 soldiers is 13 against a town
	# centre's 10 plus one house's 5, and the cap is ENFORCED since 4.11.
	{"do": "build", "def": &"building.house", "near": &"self", "units": 1, "timeout": _BUILD},
	{"do": "build", "def": &"building.watch_tower", "near": &"self", "units": 1,
			"timeout": _BUILD},
	{"do": "build", "def": &"building.barracks", "near": &"self", "units": 1,
			"timeout": _BUILD},
	{"do": "gather", "kind": &"wood", "units": 1, "timeout": _WALK},
	{"do": "train", "at": &"building.barracks", "unit": &"unit.swordsman", "count": 5,
			"timeout": _TRAIN},

	# And the ending, which is the addition. Without it a headless match never finishes.
	{"do": "attack", "units": "military", "timeout": _SHORT},
]
