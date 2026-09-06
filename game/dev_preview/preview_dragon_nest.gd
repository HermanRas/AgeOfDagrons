## The dragon nest, drawn through the real seam, next to things whose size is known
## (PLAN.md 13.2).
##
## ## WHY THIS NEEDS EYES AND NOT AN ASSERTION
##
## `vis.dragon_nest` is a **composite with no bespoke art**: the shrine's atlas as the core and
## 34 props arranged around it. Everything a test can check about that is already checked —
## every prop id resolves, the offsets are inside the footprint, the atlases exist. **None of
## that says it looks like a nest.** Whether 22 bushes and 12 standing stones read as an
## overgrown henge or as a suspiciously regular circle of shrubbery is a question for a person,
## which is `preview_walls`' reason for existing too.
##
## ## THE SCALE COMPANIONS ARE THE POINT, NOT DECORATION
##
## A 17.6 m composite photographed alone tells you nothing: every screenshot of a single object
## fills the frame. So a **villager** (~1 m, the human yardstick) and the **mother dragon**
## herself (9.19 m, the thing that lives here) stand beside it. The three together answer the
## question actually worth asking — *can a player tell at a glance that this is a landmark and
## that the dragon belongs to it* — and the dragon-to-nest ratio is what says whether she looks
## like she fits in her own nest.
##
## ## AND SINCE 13.2b, THE HATCHLING — WHICH IS THE WHOLE OF THE VISUAL PROOF FOR `scale`
##
## `vis.dragon_baby` is `vis.dragon_rigged` at 20%, which is the first time anything in this
## game has drawn one atlas at two sizes. **No headless test can judge the result**: the data
## agreeing with itself is asserted in `tests/view/test_visual_scale.gd`, and what is left over
## is exactly the part a person has to look at — does it read as a juvenile dragon, or as a
## dragon that has been moved further away. It stands between the villager and the mother
## because that is the comparison the owner's figure was chosen against.
##
## `_report_scale()` prints the half a screenshot cannot settle: **where the feet ended up.** A
## sprite scaled about its frame's corner and one scaled about its anchor are both small
## dragons in a picture and are several metres apart on the ground.
##
## ## WHAT A FAILURE LOOKS LIKE
##
## - **A magenta box in the middle** means the core did not resolve — the shrine atlas is the
##   core precisely so this cannot happen, so magenta means that wiring broke.
## - **Bushes painted over the shrine** means the prop depth sort is wrong. It is sorted by
##   `x+y`, because `Iso._project` puts screen y at `(x+y) * half.y` and `EntityView` splits
##   behind-the-core from in-front at `at.y < 0`. Sorting by world `y` produces exactly this
##   and looks like a renderer bug.
## - **Props outside the drawn footprint** means `building.dragon_nest`'s 10×10 no longer
##   contains the layout, and the art will hang over tiles the nest does not claim.
##
## Usage:
##   Godot --path game res://dev_preview/preview_dragon_nest.tscn
extends Node2D

const SHOT_PATH := "user://dragon_nest.png"

## ⚠️ **RAISED FROM 12 TO 24 FOR 13.4'S PARTICLES.** Twelve was plenty for static art: the
## nest, the villager and the two dragons are all standing still and settle in a frame or
## two. A blast is `FlameParticles.LIFETIME_BLAST` long, so at 12 frames the screenshot
## caught it a fifth of the way through -- a cluster of embers still on the ground rather
## than a fireball. 24 frames is about 0.4 s at 60 fps, which is the middle of its life and
## the frame worth judging. It costs the still nothing else, since everything else in the
## scene is static.
const SETTLE_FRAMES := 24

## Tile 0,0 of the drawn ground sits here, and everything else is projected from it, so the
## nest's own origin lands where its footprint says it does.
const ORIGIN := Vector2(700.0, 250.0)

## `building.dragon_nest`'s footprint, read from the def rather than repeated: the whole point
## of drawing it is to see whether the art fits inside it, and a number copied to here would
## make the two agree by construction.
var _footprint := Vector2i(10, 10)

var _frames := 0

var _blasts: BlastEffects = null


func _ready() -> void:
	var bd: BuildingDef = GameDataRegistry.building(&"building.dragon_nest")
	if bd == null:
		printerr("building.dragon_nest is not declared -- nothing to preview")
		get_tree().quit(1)
		return
	_footprint = bd.footprint

	var ground := Node2D.new()
	ground.draw.connect(_draw_ground.bind(ground))
	add_child(ground)

	# ⚠️ **THE NEST SITS AT THE CENTRE OF ITS FOOTPRINT, NOT AT ITS CORNER, AND THE FIRST
	# VERSION OF THIS PREVIEW GOT IT WRONG.** `MapData.footprint_rect_of` anchors a footprint
	# top-left, so it is tempting to draw the art at 0,0 and the outline from there -- which
	# put half the nest outside its own footprint and looked like a data fault. But a
	# `SimBuilding`'s `pos` is the footprint's CENTRE in sub-tile units (five tiles off the
	# top-left for an 8x8 town centre), so the sprite is centred and the outline has to be
	# drawn around it. Getting this backwards makes correct data look broken.
	_place(bd.visual, Vector2i.ZERO, "%s  %dx%d tiles" % [bd.name, bd.footprint.x, bd.footprint.y])

	# THE SCALE COMPANIONS, well clear of the nest's 4.4-tile reach so nothing overlaps and
	# the comparison is not confused by occlusion. Both to the SOUTH-WEST, where there is
	# room for a caption -- to the east the labels ran off the viewport.
	_place(&"vis.villager", Vector2i(-9, 2), "villager  ~1 m")
	_place(&"vis.dragon_rigged", Vector2i(-4, 9), "mother dragon  9.19 m")
	# THE HATCHLING (13.2b), and it is here for the reason the other two are: 20% of
	# something is a number, and whether it reads as a juvenile dragon is a question for
	# a person. Standing between the villager and the mother on purpose -- that is the
	# comparison the owner's "bigger than a villager, obviously a baby" was about.
	# BEYOND THE VILLAGER RATHER THAN BETWEEN HER AND THE MOTHER, which is where it went
	# first: the mother's wingspan is 9 m of sprite and the hatchling landed inside it,
	# so the one comparison this shot exists for was drawn on top of one of the two things
	# being compared. In iso, screen y is (x+y) and screen x is (x-y) -- so the way to
	# move something sideways without moving it down the picture is to change x and y in
	# opposite directions, which is what this does against the villager's (-9, 2).
	_place(&"vis.dragon_baby", Vector2i(-13, 6), "hatchling  1.84 m (20%)")

	# ── 13.4's two fires, which are here for this scene's founding reason ──────────
	#
	# **PARTICLES ARE THE PUREST CASE OF "NO ASSERTION SETTLES THIS".** `test_fire_particles`
	# pins WHEN a fire appears, WHERE it is drawn and THAT it stops -- every fact that is not
	# taste. Whether the flames read as fire or as orange confetti, and whether they hide the
	# sprite they are supposed to be damaging, is a question for a person, which is the same
	# sentence this file's header opens with about the nest.
	#
	# ⚠️ **AND THE BLAST IS ALL BUT UNLOOKABLE-AT IN A REAL MATCH NOW.** The owner's 120 s
	# cooldown means one breath per two minutes, from the one dragon on the map, quite
	# possibly off screen -- so "play until you see it" is not a review, it is a wait. Here
	# it fires on a timer.
	var burning := _place(&"vis.house", Vector2i(4, -6), "house at 20% health -- burning")
	burning.set_health_dot(0.2)
	burning.set_burning(true)

	# THE SAME NODE THE MATCH USES, not a hand-built emitter, and the span read off the DRAGON
	# rather than typed here. A preview that stood up its own particles at its own size would
	# be reviewing something the game does not draw -- the trap `preview_walls` names about
	# photographing art the seam never resolves.
	_blasts = BlastEffects.new()
	add_child(_blasts)
	var dragon: UnitDef = GameDataRegistry.unit(&"unit.dragon")
	var span := dragon.ability_radius * 2 + 1 if dragon != null else 5
	var blast_at := ORIGIN + Iso.tile_to_world_f(Vector2(-2, -4))
	_blasts.play(blast_at, span)

	var marker := Label.new()
	marker.text = "fire breath: %dx%d tiles" % [span, span]
	marker.position = blast_at + Vector2(-110.0, 40.0)
	marker.size = Vector2(220.0, 20.0)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(marker)

	var report := Label.new()
	report.text = ("dragon nest: %s core + %d props   |   footprint %dx%d tiles = %.1f x %.1f m"
			% [_core_name(bd.visual), _prop_count(bd.visual),
			bd.footprint.x, bd.footprint.y,
			bd.footprint.x * Iso.METRES_PER_TILE, bd.footprint.y * Iso.METRES_PER_TILE])
	report.position = Vector2(20.0, 16.0)
	report.size = Vector2(1360.0, 22.0)
	add_child(report)

	_report_scale()


## What the scale actually DOES to a drawn frame, printed rather than left to the eye.
##
## ⚠️ **THE FAULT A PICTURE CANNOT SETTLE ON ITS OWN IS WHERE THE FEET WENT.** A sprite
## scaled about its frame's top-left corner and one scaled about its ANCHOR look identical
## in isolation -- both are small dragons -- and differ by several metres of ground.
## `_draw_frame` folds the scale into the canvas transform, which scales every local
## coordinate including the frame's offset from the anchor, so the anchor stays exactly on
## the node origin. That is checkable, so it is checked here: **the drawn rect's anchor
## point must be (0, 0) local for both, at any scale.**
##
## The other half is the ratio, which is only worth printing because it comes from two
## places that have to agree by hand -- `scale` and the authored `footprint_m`. See
## visuals.json's `_note_dragon_baby`.
func _report_scale() -> void:
	var adult := GameDataRegistry.atlas_for(&"vis.dragon_rigged")
	var baby := GameDataRegistry.atlas_for(&"vis.dragon_baby")
	print("scale: adult %.2f, hatchling %.2f" % [adult.scale, baby.scale])

	if adult.is_placeholder or baby.is_placeholder:
		print("  (art not staged -- placeholder boxes, so the drawn sizes below are absent)")
		return

	for pair in [["adult", adult], ["hatchling", baby]]:
		var e: AtlasEntry = pair[1]
		var f := e.frame_at(&"idle", 0, 0)
		if f.is_empty():
			print("  %s: no idle frame" % pair[0])
			continue
		var rect: Rect2i = f["rect"]
		var anchor: Vector2 = f["anchor"]
		# Exactly what `EntityView._draw_frame` computes, with `at` at the origin.
		var dest := Rect2(-anchor * e.scale, Vector2(rect.size) * e.scale)
		print("  %s: frame %dx%d px -> drawn %.1fx%.1f px, feet at (%.1f, %.1f)"
				% [pair[0], rect.size.x, rect.size.y, dest.size.x, dest.size.y,
				dest.position.x + anchor.x * e.scale, dest.position.y + anchor.y * e.scale])

	var ph_adult := GameDataRegistry.placeholder_for(&"vis.dragon_rigged")
	var ph_baby := GameDataRegistry.placeholder_for(&"vis.dragon_baby")
	var ratio := ph_baby.footprint_m.x / maxf(0.001, ph_adult.footprint_m.x)
	print("  metres declared at %.3f of the adult against a sprite scale of %.3f"
			% [ratio, baby.scale])
	if absf(ratio - baby.scale) > 0.01:
		printerr("  ⚠️ the hatchling's footprint_m and its scale disagree -- "
				+ "its selection ring will not fit its sprite")


func _place(visual_id: StringName, tile: Vector2i, caption: String) -> EntityView:
	var view := EntityView.new()
	view.visual_id = visual_id
	view.position = ORIGIN + Iso.tile_to_world_f(Vector2(tile))
	# `idle` rather than `static`: `AtlasEntry.resolve_anim` falls back, so this works for a
	# building's single static clip AND for the dragon's real idle without a special case.
	view.play_anim(&"idle", 0)
	add_child(view)

	var label := Label.new()
	label.text = caption
	label.position = view.position + Vector2(-110.0, 40.0)
	label.size = Vector2(220.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	return view


## Grass, plus the nest's own footprint outlined on it. The outline is the load-bearing part:
## it is what makes "does the art fit the tiles it claims" a thing you can see rather than
## infer.
func _draw_ground(on: Node2D) -> void:
	var spec := PlaceholderSpec.from_dict({
		"shape": "diamond", "footprint_m": [2.0, 2.0], "color": "#4a6f30",
	})
	for tx in range(-13, 10):
		for ty in range(-9, 14):
			# `draw_into` paints at the CanvasItem's own origin, so the position goes through
			# the transform -- `preview_placeholders._draw_grid`'s arrangement.
			on.draw_set_transform(
					ORIGIN + Iso.tile_to_world(Vector2i(tx, ty)), 0.0, Vector2.ONE)
			PlaceholderRenderer.draw_into(on, spec, 0)
	on.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# CENTRED ON THE ART, because that is where a building's origin is -- see `_ready()`.
	var h := Vector2(_footprint) * 0.5
	var corners := PackedVector2Array([
		ORIGIN + Iso.tile_to_world_f(Vector2(-h.x, -h.y)),
		ORIGIN + Iso.tile_to_world_f(Vector2(h.x, -h.y)),
		ORIGIN + Iso.tile_to_world_f(Vector2(h.x, h.y)),
		ORIGIN + Iso.tile_to_world_f(Vector2(-h.x, h.y)),
	])
	on.draw_polyline(corners + PackedVector2Array([corners[0]]),
			Color(1.0, 0.85, 0.3, 0.9), 2.0)


func _core_name(visual_id: StringName) -> String:
	var e := GameDataRegistry.atlas_for(visual_id)
	return "PLACEHOLDER (core did not resolve)" if e == null or e.is_placeholder \
			else "real art"


func _prop_count(visual_id: StringName) -> int:
	return GameDataRegistry.props_for(visual_id, 1).size()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	get_viewport().get_texture().get_image().save_png(SHOT_PATH)
	print("wrote ", ProjectSettings.globalize_path(SHOT_PATH))
	get_tree().quit(0)
