## Overview
root folder: `./scenarios/` — **repo root, deliberately NOT inside `game/`** (moved 2026-09-01).

> **Two corrections to the first draft of this file, both made on the owner's instruction and both
> recorded here rather than silently applied.**
>
> 1. **This folder left `game/`.** Anything under `game/` is inside Godot's `res://`, which is
>    **read-only once the game is exported** and is baked into the APK. Campaigns are downloadable
>    and shareable content, so they cannot live there — and the size argument agrees: "How To Play"
>    alone is 1.7 MB of icons and one background, against §3.1's 300 MB APK ceiling, and it is the
>    smallest campaign there will ever be.
> 2. **`campaign.json` does not hold progress.** It said *"Contains progress"*; it cannot, for the
>    same read-only reason. Authored content and player progress are two different files with two
>    different lifetimes — see **Where this lives** below.

*folder structure:*
```
scenarios/
├── NameOfCampaign1/
│   ├── campaign.json # NameOfCampaign, description, scenario order, and other metadata
│   ├── campaignIcon.png # Icon for the campaign 256x256px
│   ├── CampaignBackground.png # campaign background 1920x1080px
│   ├── scenario_1/
│   ├── scenario_1/scenario.json # Contains NameOfScenario,description and other metadata
│   ├── scenario_1/scenarioIcon.png # Icon for the map 256x256px
│   ├── scenario_2/
│   └── scenario_3/
```

**`campaign.json` names its scenarios in play order explicitly**, rather than the game sorting the
folder names — `scenario_10` sorts before `scenario_2`, and a campaign's order is a design decision
anyway.

## Where this lives

Three places, and they are three because the content is authored in one, delivered through
another, and read from a third:

| | |
|---|---|
| **`./scenarios/`** (this folder, in git) | the **authored source**. Hand-written today, written by the MapMaker later. Outside the Godot project, so Godot never imports it and nothing here can end up in the APK by accident |
| **a content pack** | how a campaign reaches a player — the same delivery `PLAN.md` §3.2 already describes for art and audio: fetched, checksum-verified, installed |
| **`user://content/scenarios/`** | where the game **reads** campaigns at runtime, on every platform. Writable, so a campaign can be installed, updated, shared in and deleted again |
| **`user://campaign_progress.json`** | how far the **player** has got, per campaign — `{"HowToPlay": 1}`. A separate file because it belongs to the player and not to the campaign, and because the campaign's own folder is content that an update is allowed to replace wholesale |

**While developing, nothing is copied anywhere.** The game reads this folder directly when it is
running from the editor (including every headless test run), through a gitignored local config
naming the path — the same arrangement `tools/isobake.local.toml` uses for the art root. An
exported build has no such override and reads `user://content/` only.

⚠️ **AN ICON OUTSIDE `res://` IS NOT AN IMPORTED RESOURCE.** These PNGs never get a `.import`
sidecar, so `load()` and `ResourceLoader` **cannot open them** — the route is `Image.load()` plus
`ImageTexture.create_from_image()`. That is the same route a saved map's PNG takes, and it is the
price of the content being installable rather than baked in. Two consequences worth knowing before
the screens are built: there is no VRAM compression and no mipmap, and a 1920x1080 background
costs a real decode — so backgrounds load **when a campaign is opened**, never all at once for the
selection list.

## Game Screens

 - Scenario Selection Screen: Displays all available Campaigns for the player to choose from. Each Campaign is represented by an row icon on the left with a Title - TOP and brief description right where the title and description grow to right.
 - bottom of the screen has a "back" button that takes the player back to the main menu. The player can select a scenario by clicking on its icon, which will load the corresponding scenario screen.

## Scenario Screen

 - The scenario scr at the top the campaign title
 - a column on the left that displays the list scenario's only scenario 1 is available on start, in progress = 0, when scenario 1 is completed, progress = 1, and scenario 2 is unlocked, and so on. The column displays the scenario's icon, title.
 - Them main panel displays the campaign background, and the scenario Title, scenario description, and a "play" button that starts the scenario at the bottom.
 - The player can select a scenario by clicking on its icon, which will load the corresponding scenario to main panel.

**Progress only ever goes up.** It is a maximum, never decremented — replaying a scenario you have
already beaten cannot re-lock the one after it, and the write is idempotent because a result screen
can be reached twice.

## Scenario Message

 a metadata message can be set in the scenario.json file, and will be displayed to the player when the scenario is loaded. The message can be used to provide instructions, story elements, or other information to the player. The message can be set to display and require the user to press X to close. same field will be used to display a messages in skirmish for King of the Hill, and other scenarios. The message can be set to display and require the user to press X to close.

## What a scenario.json says

Beyond the name, description and message: which map to play, who the opponents are, and **how the
scenario is won**. The win rule is one of two shapes, and picking between them is the whole of it:

| `mode` | Means | Use it for |
|---|---|---|
| `last_man_standing` | leave the enemy nothing — no units, no buildings. The game's ordinary conquest rule, already built | any scenario whose goal is to beat somebody |
| `scenario` | an **authored objective list** decides it: counts of your own units or buildings, your age, and later areas and named units | "build a house", "reach age 2", anything that is not a fight |

**Every scenario loses the same way** — own nothing and you are out — so a scenario only ever has
to declare how it is *won*.

### The first campaign: "How To Play"

Three scenarios, each on a generated **River** map against a **Passive** opponent:

| | Teaches | Won by |
|---|---|---|
| 1 · How To Gather and Build | the economy | `scenario` — own 1 house and 10 villagers |
| 2 · How To Age Up | the age ladder | `scenario` — reach Age of Embers (age 2) |
| 3 · How To Find Opponent and Attack | fighting | **`last_man_standing`** — leave the enemy nothing |

⚠️ **Scenario 3 was specified as "0 enemy units on map" and that is not reachable against a
Passive AI**, which runs its whole economy and simply never attacks — so it keeps training
villagers, and an early army empties that count slower than the opponent's town centre refills it.
**Settled on the owner's call, 2026-09-01: it is `last_man_standing`** — *leave the enemy nothing*.
It needs no new rule, it keeps the Passive opponent, and it teaches the lesson the scenario is
named for: you cannot finish an enemy by chasing their villagers.

That also makes scenario 3 the **cheapest one to build** — it is the ordinary win condition on an
ordinary map, so it is playable before a single line of objective code exists, and it is what
proves the campaign launch path on its own.
