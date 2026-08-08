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

## The other half of 7.1: idle vs. total villagers. Separate from
## `resources_changed` because it is not derived from `SimPlayer.stock` at all --
## it is a headcount over units, which lives on the view side (GameView.villager_
## counts()), not in the snapshot's player_state block.
signal villagers_changed(player_id: int, idle: int, total: int)

## PLAN.md 10.1: one slot's display state. `icon` is the def_id of whichever
## unit/building type is most represented in the group's currently-alive
## members (10.4), or `&""` once every member has died -- ControlGroupsHud
## reads that as "draw an empty circle" rather than needing a separate
## emptied signal. GameScene computes this from SimPlayer.control_groups
## (server-authoritative, 10.6) crossed with GameView's live facts, the same
## division of labour resources_changed/villagers_changed already use.
signal control_group_changed(slot: int, icon: StringName, count: int)
