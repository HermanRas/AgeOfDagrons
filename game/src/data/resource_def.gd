## One entry from data/resources.json (PLAN.md 9). Phase 0.4.
##
## `amounts` is indexed by SimResourceNode.size_class (0 small, 1 medium,
## 2 large), and since 2026-08-17 so is `visuals`: the size classes pick the
## sprite as well as the amount. That was the point of the ore request -- a
## 200-gold seam and an 800-gold seam had been pixel-identical, which made the
## size classes data no player could act on.
class_name ResourceDef
extends RefCounted

var id: StringName = &""
## food | wood | gold | stone -- which stockpile a gathered load lands in.
var kind: StringName = &""
## The node's look when nothing has said which size -- the build menu, a portrait,
## a caller that has only a def_id. Also the fallback for every size when `visuals`
## below is empty, which is every kind that has one bake for all three.
var visual: StringName = &""

## One visual per size class, small to large, or empty to use `visual` for all of
## them. Short lists are allowed and CLAMP rather than fail: stone ships two actors
## for three classes, so its medium and large share the quarry.
var visuals: Array[StringName] = []

## Tiles claimed per size class, small to large, or empty for one tile at every
## size. Clamps when short, like `visuals` and `amounts`.
##
## A TREE IS ONE TILE AND A MINE IS NOT (project owner, 2026-08-17). A one-tile
## footprint under a 244 px sprite is what let units walk through the middle of a
## gold seam and buildings go up on ground the player can see is solid rock -- and
## it is why the occlusion band had to be widened by hand to cover art the
## footprint knew nothing about.
##
## Matched to the art through the projection visuals.json documents: a footprint of
## (Fx, Fy) TILES draws a diamond (Fx + Fy) * 32 px wide, so a 244 px seam wants
## Fx + Fy = 7.6, i.e. 4x4. Trees stay at one tile deliberately -- an oak's canopy
## is 232 px of overhang above a trunk that really does stand on one tile, and
## claiming 4x4 for each would make a twelve-tree forest an impassable wall.
var footprints: Array[Vector2i] = []

## Tiles a TAP is allowed to land on, per size class, or empty to use `footprints`.
## A screen-space affordance and nothing more: no part of this reaches the sim, so a
## node can be easy to hit without becoming harder to walk past.
##
## THE TWO HAD TO COME APART FOR THE TREE (project owner, 2026-08-23). An oak's trunk
## is drawn well up-screen of the tile it stands on, so a player aiming at the trunk
## taps the grass behind it and the tree is simply hard to select. Widening
## `footprints` to fix that is exactly what the note above forbids -- it would make a
## twelve-tree forest impassable -- and it is the wrong tool anyway, because the
## problem is where the art is, not what ground the tree holds.
var pick_footprints: Array[Vector2i] = []

## Which surfaces this node may stand on -- a `SimMap.Domain` name, `land` for all but
## one thing in the game (6.5's fish).
##
## IT EXISTS BECAUSE `spawn_resource_node` ASKED THE WRONG QUESTION. It called
## `can_place_building`, whose own comment says buildings are land-only and the domain
## is therefore not a parameter -- correct about buildings and quietly fatal to a fish,
## which was refused every tile of the sea it was supposed to live in.
var domain: StringName = &"land"

## Starting amount per size class, small to large.
var amounts: Array[int] = []
## How many villagers can work this node at once.
var gather_slots: int = 1

## Wildlife only (the deer). Empty for inert nodes.
var is_wildlife: bool = false
var roam_radius: int = 0
var flees: bool = false


static func from_dict(p_id: StringName, d: Dictionary) -> ResourceDef:
	var r := ResourceDef.new()
	r.id = p_id
	r.kind = StringName(d.get("kind", ""))
	r.visual = StringName(d.get("visual", ""))
	r.amounts = GameDefs.int_list(d.get("amounts", []))
	r.visuals = GameDefs.name_list(d.get("visuals", []))
	for f in (d.get("footprints", []) as Array):
		r.footprints.append(GameDefs.tile_size(f, Vector2i.ONE))
	for f in (d.get("pick_footprints", []) as Array):
		r.pick_footprints.append(GameDefs.tile_size(f, Vector2i.ONE))
	r.domain = StringName(d.get("domain", "land"))
	r.gather_slots = int(d.get("gather_slots", 1))

	var w: Variant = d.get("wildlife")
	if w is Dictionary:
		r.is_wildlife = true
		r.roam_radius = int((w as Dictionary).get("roam_radius", 0))
		r.flees = bool((w as Dictionary).get("flees", false))
	return r


## Starting amount for a size class, clamped rather than out-of-range: a map
## generator asking for a size this resource does not define should get the
## nearest one, not crash the sim.
func amount_for(size_class: int) -> int:
	if amounts.is_empty():
		return 0
	return amounts[clampi(size_class, 0, amounts.size() - 1)]


func size_class_count() -> int:
	return amounts.size()


## The sprite for a size class. Clamped for the same reason `amount_for()` is: a
## kind with two actors for three classes must draw its nearest one, not nothing.
## `size_class < 0` means "no preference" and gets the plain `visual`, which is what
## a portrait or a build-menu icon wants.
func visual_for_size(size_class: int) -> StringName:
	if visuals.is_empty() or size_class < 0:
		return visual
	return visuals[clampi(size_class, 0, visuals.size() - 1)]


## Tiles a node of this size claims. One tile unless the kind says otherwise.
func footprint_for_size(size_class: int) -> Vector2i:
	if footprints.is_empty():
		return Vector2i.ONE
	return footprints[clampi(size_class, 0, footprints.size() - 1)]


## Tiles a tap on a node of this size may land on. Defaults to the ground footprint,
## which is the right answer for everything whose art sits inside the tiles it claims
## -- only the tree overrides it today. Clamps when short, like every list here.
func pick_footprint_for_size(size_class: int) -> Vector2i:
	if pick_footprints.is_empty():
		return footprint_for_size(size_class)
	return pick_footprints[clampi(size_class, 0, pick_footprints.size() - 1)]
