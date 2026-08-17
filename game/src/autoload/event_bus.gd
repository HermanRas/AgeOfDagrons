## Decouples the HUD from whoever happens to receive a snapshot (PLAN.md 6.2,
## 7.1). GameScene is the thing that hears `Net.snapshot_received` today, but the
## resource counters should not have to know that -- a future lobby screen or a
## second HUD panel can listen here without GameScene growing a reference to it.
##
## No `class_name`, for the same reason as `net.gd`: this script IS the
## "EventBus" autoload singleton, and a `class_name` of the same name would
## collide with that global identifier.
extends Node

## Stock deltas (PLAN.md 7.1's stone/gold/wood/food counters). `stock` is the
## player's FULL current dictionary, not a delta -- a HUD label wants "what is
## it now", and diffing back to that from a delta would be strictly more work for
## no benefit at the one-signal-per-snapshot rate this fires at.
signal resources_changed(player_id: int, stock: Dictionary)

## How many VILLAGERS are standing about doing nothing (PLAN.md 7.1), for the age
## header's idle badge. Villagers specifically -- an idle soldier is a garrison,
## not a mistake, and the badge is a button that walks to whatever it counts.
##
## Derived on the view side (`GameView.idle_villager_ids()`) rather than read out
## of the snapshot, because it is a headcount over entities and not per-player
## state the sim keeps.
##
## These two were ONE signal, `villagers_changed(player_id, idle, total)`, which
## fed both this and the resource panel's bottom row -- and made that row report
## idle-vs-total units, which is not what it is for (project owner, 2026-08-17).
## They count different things for different readers and are now separate.
signal idle_villagers_changed(player_id: int, idle: int)

## Units on the map against the population limit their buildings provide
## (PLAN.md 4.11), for the resource panel's bottom row. ALL units, not just
## villagers, and both numbers come straight from `player_state` -- unlike the
## idle count above, population is state the SIM owns (`SimPlayer.pop_used`/
## `pop_cap`, written by PopulationSystem) because the cap is a rule the server
## has to be able to enforce.
signal population_changed(player_id: int, used: int, cap: int)

## PLAN.md 10.1: one slot's display state. `icon` is the def_id of whichever
## unit/building type is most represented in the group's currently-alive
## members (10.4), or `&""` once every member has died -- ControlGroupsHud
## reads that as "draw an empty circle" rather than needing a separate
## emptied signal. GameScene computes this from SimPlayer.control_groups
## (server-authoritative, 10.6) crossed with GameView's live facts, the same
## division of labour resources_changed/idle_villagers_changed already use.
signal control_group_changed(slot: int, icon: StringName, count: int)
