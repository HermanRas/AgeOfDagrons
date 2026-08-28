## ONE DECISION, AND THE OWNER HAS TO BE ABLE TO PLAY IT: does `vis.tree_banyan` go in
## the river pool, or does it repeat the teak?
##
## The art side baked it and flagged it rather than shipping it quietly
## (asset_request.md [P3], 2026-08-28): it projects 336-370 px wide against a 250 px
## band, worse than `vis.tree_teak` at 273-297 -- and **the teak was not pulled for being
## big, it was pulled because the project owner tapped its roots and gathered a different
## tree** (2026-08-23). That is a defect of the TAP, not of the picture, and the first
## version of this preview could not show it: it drew three still lifes and the owner
## said so -- *"does not allow me to give villagers instructions to gather the tree, to
## see if it has the same base problem"*.
##
## So the default mode is now the real game, hands on. A grove of banyans, six villagers
## of yours standing in it, and the actual tap path. **What to try, in order:**
##
##   1. Tap a trunk. Does the villager go to THAT tree, or to the one behind it?
##   2. Tap the visible roots and canopy EDGE, a tile or two out from the trunk. That is
##      the teak's failure: the art covers ground the entity does not own, so the tap
##      lands on the neighbour whose tile it really is.
##   3. Tap a villager standing under a canopy. Can you select her at all?
##
## Every tree in the world draws as a banyan while this runs, including the ones the map
## generated, so a wood of them is what you are judging rather than one specimen.
##
## `--chart` keeps the original still-life comparison, which is still the cheapest way to
## see the three silhouettes against each other at 1:1 with villagers for scale.
##
## Usage:
##   Godot --path game res://dev_preview/preview_banyan.tscn
##       -- a real match, banyans everywhere, yours to play. Escape/close to quit.
##   ... -- --chart      -- the three-page comparison, screenshots, quits.
##   ... -- --tree vis.tree_teak     -- judge a different species the same way.
extends Node

const SHOT_DIR := "user://"

## What every tree draws as. Overridable so the teak -- the one already judged
## unacceptable -- can be put on the same board for comparison.
const DEFAULT_TREE := &"vis.tree_banyan"

## How many extra trees to plant around the camera, and how far apart. A GROVE rather
## than one specimen, because the teak's defect only appears where two canopies overlap:
## one tree in a field is unambiguous to tap however wide it is.
const GROVE := 7
const GROVE_SPREAD := 3

## Villagers to hand the player, spread through the grove so some of them are standing
## under a canopy from the start -- which is question 3 above.
const HELPERS := 6

var _game: Node = null
var _tree: StringName = DEFAULT_TREE
var _chart := false
var _planted := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_chart = args.has("--chart")
	for i in range(args.size() - 1):
		if args[i] == "--tree":
			_tree = StringName(args[i + 1].strip_edges())

	if _chart:
		_build_chart()
		return

	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)
	_force_the_look()
	call_deferred("_plant")


## EVERY TREE IN THE WORLD DRAWS AS THE SUBJECT, by rewriting `vis.tree`'s variant list
## in the registry's memory.
##
## Poking a private dictionary, deliberately and only here. The alternatives were worse:
## a real `variant_pools` entry would have to be a MAP TYPE (`_validate_variant_pools`
## rejects anything else, which is the point of it), and a second resource def for a
## preview would put a fixture in the data the whole game loads. This process is a dev
## tool, `visuals.json` on disk is untouched, and the override is one assignment.
##
## A ONE-ELEMENT LIST IS THE TRICK: `variant_of` indexes it by the tile seed, so every
## tile resolves to the same species without the seed needing to be defeated.
func _force_the_look() -> void:
	var decl: Dictionary = GameDataRegistry._visuals.get(&"vis.tree", {})
	if decl.is_empty():
		push_warning("preview_banyan: vis.tree is not declared")
		return
	decl["variants"] = [String(_tree)]
	decl.erase("variant_pools")          # or the map's own biome would win instead
	print("  every tree now draws as %s  [%s]" % [_tree,
			GameDataRegistry.atlas_identity_for(_tree, 0, -1)])
	if GameDataRegistry.atlas_for(_tree, 0, -1).is_placeholder:
		push_warning("preview_banyan: %s has no staged art -- you are judging a magenta box"
				% _tree)


## A grove and a crew, on clear ground the player can already see.
##
## Deferred a frame after the scene is added: `Net.host()` is stood up by `Game.tscn`'s
## own `_ready`, and there is no world to plant in before that has run.
func _plant() -> void:
	var host := Net.host()
	if host == null:
		push_warning("preview_banyan: no host -- nothing to plant in")
		return
	var world: SimWorld = host.world
	var home := _home_tile(world)

	# Around the player's own base, so it is inside explored ground: the fog would
	# otherwise paint the whole experiment out, which is the mistake
	# `preview_projectiles._clear_ground` records paying for.
	var anchor := home + Vector2i(GROVE_SPREAD * 3, 0)
	for i in range(GROVE):
		var at := anchor + Vector2i(
				(i % 3) * GROVE_SPREAD, (i / 3) * GROVE_SPREAD)
		if world.spawn_resource_node(&"res.tree", at, 0) != null:
			_planted += 1
	for i in range(HELPERS):
		# Threaded THROUGH the grove rather than lined up beside it, so some of them
		# start under a canopy. That is question 3 and it needs no setting up by hand.
		world.spawn_unit(&"unit.villager", Net.local_player_id(),
				anchor + Vector2i(i % 3, (i / 3) * GROVE_SPREAD + 1))

	print("  planted %d of %d %s around %s, with %d villagers in them"
			% [_planted, GROVE, _tree, anchor, HELPERS])
	print("  TRY: tap a trunk; tap the roots a tile or two out; tap a villager under a canopy")
	if _game != null and _game._camera != null:
		_game._camera.centre_on(Iso.tile_centre_to_world(anchor + Vector2i(1, 1)))


## The player's town centre, which is the one thing they can definitely see.
func _home_tile(world: SimWorld) -> Vector2i:
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimBuilding and e.owner_id == Net.local_player_id():
			return (e as SimBuilding).tile()
	return world.map.size / 2


# ── `--chart`: the three still lifes, kept ─────────────────────────────────

## Its own script and its own node, because the two halves share nothing: the chart never
## boots a world and the live mode never draws a grid. See `banyan_chart.gd`.
func _build_chart() -> void:
	add_child((load("res://dev_preview/banyan_chart.gd") as GDScript).new())
