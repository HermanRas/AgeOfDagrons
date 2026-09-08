# MapMaker

A Godot Tool for creating maps and levels for games. This tool allows you to design and edit maps using a user-friendly interface, making it easier to create complex scenarios for your games. With MapMaker, you can place objects, define areas, and customize win conditions to suit your Maps needs.

## Overview
root folder: `./MapMaker/` — a **second Godot project**, PC only, never shipped to a player and
never run on a phone. Pinned to the same Godot **4.7.1** as the game.

Planned as `PLAN.md` **Phase 16**, which carries the build order and the eight decisions behind it.

## What is built today

*Kept short on purpose — this is a spec, and `PLAN.md` §16's table is the status. Here so that
somebody reading the screens below knows which parts exist.*

| | |
|---|---|
| ✅ **Built** | the project and its self-checking format copies (16.1); the iso canvas and terrain painting, saved into repo-root `maps/` and played from the game's skirmish picker (16.2); **undo and redo** (16.2a); the object palette with icons cropped from the game's own atlases (16.3); **File ▸ Open** and Save As (16.4a); a map validated on save (16.4b) |
| 🚧 **Next** | select / move / edit cursors and drag-to-place walls (16.4) |
| ⏳ **Not yet** | areas (16.5), the Map Conditions editor (16.6), per-entity overrides and named units (16.7), scenario export (16.8), `HOW-To.md` (16.9), and the content the tool exists for (16.10) |

⚠️ **UNDO WAS MISSING FROM THIS DOCUMENT AND FROM THE PHASE TABLE**, and was added as `PLAN.md`
16.2a after a pre-kickoff review — *an editor without undo is not a tool anybody will author a
campaign in*, because a mis-drag across a painted coastline is otherwise unrecoverable and the
person using it stops experimenting, which is the one thing the tool exists to let them do. It is
`Ctrl+Z`, `Ctrl+Y` / `Ctrl+Shift+Z`, and two buttons on the tool row. **A whole mouse-drag counts
as one step**, so taking back a stroke is one keypress and not three hundred; a text field keeps
`Ctrl+Z` for its own typing while it has focus.

## Functions
uses standard map structure and metadata to create a map and scenario. The tool allows you to build maps by placing objects, defining areas, and customizing win conditions. It also provides a way to save and load maps, making it easy to share your creations with others.

Maps saved by the tool are available to load in the game under skirmish, and the map a match was
started on can be handed back to the tool for later editing.

## Where output goes

> **This replaces the first draft's `./maps`, which was ambiguous between three different
> directories** — corrected 2026-09-01, and the correction is the same one the campaigns folder
> got: nothing authored may be written inside `game/`, because that is Godot's `res://` and it is
> read-only the moment the game is exported.

| | |
|---|---|
| **`../maps/`** (repo root, in git) | authored maps — the tool's own output, and the authored source |
| **`../scenarios/`** (repo root, in git) | authored campaigns and scenarios; see that folder's README |
| **`user://content/maps/`** | where the **game** reads installed maps at runtime |
| **`user://maps/`** | the **player's** own saved maps, from the pause menu. A different directory on purpose: installing or replacing authored content must never be able to overwrite somebody's save, and uninstalling content must never delete one |

**MapMaker writes to the two repo-root folders and to nothing else.** It never writes inside
`game/`, and it never writes to `user://` — installing content is the game's job, and during
development the game reads the repo folders directly.

**Saving a MAP is not saving a MATCH.** What can come back out of a played game is the map it was
*started* on. Round-tripping a half-built settlement with rubble and corpses in it is a save
*game*, which is a different feature (`PLAN.md` 12.4) and must not be blurred into this one.

## How it reads the game's content

The tool needs the roster (what is placeable, and how big each thing's footprint is) and the art
(icons for the palette). **It reads both live out of the game's own folders** — `game/data/*.json`
and `game/assets/atlases/` — through a path in a local, gitignored config file, the same
arrangement `tools/isobake.local.toml` uses for the art root. Nothing is duplicated, so the
palette cannot drift out of step with the game's roster.

What it does carry as its own copy is the small set of pure-maths files the **map file format**
depends on. Those copies **check themselves at startup**: the tool reads the game's originals as
text, compares, and refuses to save — naming the file — if they have moved on. A tool that quietly
writes a stale format is worse than one that will not start.

## screens
### Main Screen
 - on the left side of the screen, there is a column that displays the list of placable objects.
 - the object panel has a dropdown for Player1-8 + Gaia, followed by a color picker.. the 1 player can have multiple color units depending on the map designers needs. The object panel has a 3rd drop down Unit, Building, Area, Terrain, followed by a search bar to filter the list of objects. The object panel displays the object icon.
 - the top of the screen has a menu bar with options for File, The File menu allows you to create a new map, open an existing map, save the current map, and export the map to a file. there is 3 cursors for selecting, moving, and editing objects on the map, and a button to open "Map Conditions". 
 - the main panel displays the map being created, with a grid overlay to help with object placement. The player can click to place and drag to place walls objects on the map, same as in game.. changing the cursor to edit and clicking a unit will allow you to edit the unit. move tool will allow you to move the unit and buildings.

> **Four corrections from building it (16.3 and 16.4a, 2026-09-08).** The spec above is otherwise
> what shipped; these four came out of the code rather than out of a preference, so they are marked
> here rather than silently differing.
>
> - **There is a fifth category, RESOURCES, and without it no map in this game is playable.** Every
>   tree, bush, mine and fish is a `ResourceDef` placed as a gaia entity, and the game's own
>   validator **fails a map with no resources near a start**. It is also the only category with a
>   **size** selector — a small gold mine and a large one are the same thing at different sizes,
>   and a placement that leaves it unset silently authors the small one.
> - ⚠️ **THE COLOUR PICKER IS LABELLED "ICON TINT", because a map file has no colour field.** An
>   entity on disk is `{def_id, player, x, y, size_class}`; the **lobby** assigns colours in join
>   order out of `colours.json`. So the picker changes which baked art the *palette* shows you and
>   nothing about the saved map — calling it the player's colour would be a promise the format
>   cannot keep. *"One player can have multiple colour units"* is therefore a `PLAN.md` §16.7
>   question (per-entity overrides), not a palette one.
> - **AREA IS DELIBERATELY NOT A TAB YET.** The map file has no area field until 16.5, so an Area
>   tab would let you draw a region the save then throws away without saying so. It arrives with
>   the field, and a test fails the day the field exists so it cannot be forgotten.
> - **Terrain is chosen on the palette's Terrain tab and nowhere else.** There was briefly a row of
>   named terrain buttons on the toolbar as well; two controls for one brush only ever agreed in one
>   direction, so the buttons were deleted rather than kept.
>
> **Carcasses are not placeable** (owner's ruling, 2026-09-08) — the six of them are what hunting
> leaves behind, so the Resource tab lists five things and not eleven. The flag lives in
> `game/data/resources.json`, so the roster decides and the tool obeys.

### File ▸ Open, and the one rule worth knowing before you press Save

**Open lists three places**, and the third is not in the table above because it is not somewhere
the tool *writes*: repo-root `maps/`, the player's own `user://maps/`, and **`../scenarios/`** —
walked one level deeper, since a campaign's maps sit at `<campaign>/<scenario>/map.json`. That
third root is what makes `PLAN.md` 16.10 possible at all: the five How To Play maps are in there,
and re-authoring them means opening them.

⚠️ **SO: OPEN THEN SAVE REPLACES; SAVE AS CREATES.** `Save` writes back to wherever a map came
from — which is exactly what re-authoring means, and exactly what you do not want after merely
looking at somebody else's map. The status line always shows which file `Save` is about to
replace. **`Save As` refuses a name that is already taken** rather than overwriting it, because a
window has no `--force` to offer and without that refusal the box you type a title into is a
delete button.

A map that will not load is **reported and does not open** — the canvas keeps whatever was on it.
A partial load showing an empty canvas over your authored map is how a file gets saved as nothing.

### Map Conditions
 - The Map Conditions screen allows the player to define win conditions for the map. The player can set trigger conditions, objectives, and other parameters that determine how the map is played. The player can also set the starting resources and units for each player.
 - Condition types include:
   - trigger: a condition that is made up of a type (unit, building, area, age, named_unit), a condition (less than, greater than, equal to), and a value (number of units or buildings), output (win, loose, alert). The trigger can be set to activate when the condition is met.
   - count: a condition that requires a certain number of type (unit, building, area, named_unit) to be present on the map or area.
   - The player can also set a time limit for the map, which will end the game if the time runs out — counted in **sim ticks**, not seconds, because the simulation must behave identically on a phone and a desktop.

**The conditions written here are the same records a hand-written `scenario.json` carries**, and
that is a hard rule rather than a convenience: two dialects would mean the tool could author a map
the game misreads. `PLAN.md` §11.8 is where the vocabulary is written down — one language, one
place, two editors.

⚠️ **A LOSE CONDITION IS ALREADY THERE, ON EVERY MAP.** The first draft required the designer to
set at least one: they do not have to, because owning no units and no buildings is defeat in this
game whatever else a map says. So a map only ever has to declare **how it is won** — and a map
whose answer is "beat the other player" needs **no conditions at all**, since that is the game's
ordinary win condition. Conditions are for goals that are *not* a fight.

### unit and building editor screen
 - when a unit or building is selected with the edit cursor, the editor screen allows the player to customize its properties, including health, attack power, movement speed, and NAME attributes. The named units will be saved in the map metadata and can be used in triggers and win conditions. 

This is the most expensive screen in the tool, and the cost is on the *game* side rather than
here: a placed entity that overrides its own stats means the simulation has to carry those
overrides and fold them into its state hash, or two players would disagree about how much health a
scripted hero has. It is `PLAN.md` 16.7 and it is deliberately last — everything else in the tool
is usable without it.

## Placeable Areas
 - The MapMaker tool allows the player to place areas on the map, which can be used to define regions for objectives, triggers, and other gameplay elements. The player can customize the size, shape, and properties of each area, making it easy to create complex maps with multiple objectives.

Areas are a **new field in the map file**, so they need a format version bump and a matching
reader on the game side. Until both ends exist, an objective referring to an area is rejected when
the scenario loads rather than quietly counting zero.

## HOW-To.md 
a guide for using the MapMaker tool, including instructions for creating maps and campaigns, placing objects, and defining win conditions. The HOW-To.md file provides step-by-step instructions and tips for getting the most out of the MapMaker tool.

Written **last** (`PLAN.md` 16.9): a guide to an interface still being built is a guide that will
be wrong.


### Note for Coder AI 
The format, which the MapMaker now inherits
map.png + map.json in one directory. The one rule I'd want the tool to read first:
R is the terrain kind and is the only channel that is data. G and B are a cosmetic tint so the file still looks like a map in an image viewer, and a loader must never read them.