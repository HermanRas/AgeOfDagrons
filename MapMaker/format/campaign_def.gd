## ⚠️ **NOT THE GAME'S `CampaignDef`. A THREE-FILENAME STAND-IN** — see `format/scenario_def.gd`,
## which is the same stand-in for the same row and carries the whole argument.
##
## 16.8 writes a `campaign.json` and puts icons beside it. **All three names are decided by the
## game**, in `src/data/campaign_def.gd`, and a tool that spelled one of them differently would
## produce a campaign that loads with no icon and nothing anywhere saying why — the file would be
## on disk, correct, and looked for under another name.
##
## The game's own class is not copied for `ScenarioDef`'s reason one step down: it holds
## `Array[ScenarioDef]`, so copying it would drag that class in behind it.
##
## ⚠️ **`BACKGROUND_FILE` IS THE ONE WITH A CAPITAL IN IT** — `CampaignBackground.png`, where its
## two siblings are camelCase. That is the shipped content's spelling and it is checked here rather
## than remembered, because a case difference is invisible on Windows and fatal on a phone.
##
## ⚠️ **DO NOT GROW THIS FILE.** Anything needing `CampaignDef`'s behaviour — unlock arithmetic,
## `all_problems()` — is the tool trying to be the game's front door.
class_name CampaignDef
extends RefCounted

## **MUST MATCH the game's `src/data/campaign_def.gd`.** All three are checked at startup by
## declaration, not by hash — see the class comment.
const ICON_FILE := "campaignIcon.png"
const BACKGROUND_FILE := "CampaignBackground.png"
const JSON_FILE := "campaign.json"

## The key naming the scenario folders in play order.
##
## ⚠️ **NOT GUARDED, BECAUSE THE GAME READS IT AS A STRING LITERAL** — `Campaigns._read_campaign`
## does `d.get("scenarios", [])`, so there is no declaration to compare against. It is named here
## anyway so the export and its tests spell it in one place, and
## `preview_exported_campaign.tscn` is what proves the game agrees: a campaign whose order list
## the loader could not find reports *"no 'scenarios' list"* and is unplayable, loudly.
const ORDER_KEY := "scenarios"
