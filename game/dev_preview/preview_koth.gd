## CAN THE PLAYER SEE WHERE THE SCORING GROUND IS, AND WHO HOLDS IT?
##
## PLAN.md 11.2's own words for why the ring is part of the row and not a polish item: *"a scored
## zone the player cannot see is a rule they can only lose to."* That is a question about a picture,
## so `test_koth.gd` cannot answer it — it proves the arithmetic and would pass just as green with
## the ring drawn one pixel wide in a colour indistinguishable from grass.
##
## ## IT STARTS A REAL MATCH, WHICH IS THE WHOLE DIFFERENCE FROM A WIDGET PREVIEW
##
## `preview_minimap_teams` photographs `Minimap` on its own, correctly: blip colour is a pure
## fact-to-colour mapping and standing up a 2v2 to look at two pixels would be machinery between
## the question and the answer. **The ring is the opposite case.** Its position comes from
## `MapGen._place_koth_zone()`, crosses the wire as five ints, is read back by `GameView`, and is
## resolved to a colour by `GameScene` — four places, and a widget preview would photograph none of
## them. So this goes through `Net.pending_match` into the real `Game.tscn`, exactly as
## `preview_saved_map` does, and only the scene swap is done by hand.
##
## ## ⚠️ IT SHOOTS A 6x NEAREST-NEIGHBOUR CROP AS WELL, AND THAT IS NOT DECORATION
##
## `preview_minimap_teams`' lesson, which is `preview_projectiles`' lesson: the minimap is a 240 px
## diamond and a 13-tile zone on a 96-tile map is about sixteen pixels square inside it. At 1:1
## *"I cannot see it"* and *"it is not drawn"* look identical — which is exactly the trap this
## project has paid for twice. `INTERPOLATE_NEAREST`, never the default, or the enlargement meant
## to support the judgement smears the outline into the terrain it is being judged against.
##
## ## THREE STATES, BECAUSE THE RING MEANS THREE THINGS
##
## Empty, held, and CONTESTED — and the third is the one nobody would think to look at. A tie has
## no UNIQUE leader, so `koth_holder` drops to 0 and the ring goes neutral in the middle of a
## fight, which is correct and is the state most likely to be read as a bug. ⚠️ **Both sides are
## still SCORING there** (PLAN.md §11.9's ladder, 1 each) — the neutral ring means "nobody is
## ahead", never "nobody is progressing", and those were the same thing until 2026-09-11.
##
## Usage:
##   Godot --path game res://dev_preview/preview_koth.tscn
##       [-- --seed 7] [--type forest]
extends Node

const SHOT_DIR := "user://"
const ZOOM := 6

## Frames to let a step's snapshot reach the HUD. `preview_saved_map`'s constant and its reason:
## a screenshot taken in the same frame as an action shows the state before it.
const UI_FRAMES := 12

var _game: Node = null
var _step := 0
var _frames := 0
var _resume_at := 0
var _ok := true

## The units this preview put on the hill, so it can take them off again for the contested shot.
var _mine: Array[SimUnit] = []
var _theirs: Array[SimUnit] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map_seed := int(_arg(args, "--seed", "7"))
	var type_name := _arg(args, "--type", "forest")

	var type := MapGenerator.Type.FOREST
	for i in MapGenerator.Type.values():
		if MapGenerator.type_name(i).to_lower() == type_name.to_lower():
			type = i as MapGenerator.Type
	# A GENERATED MAP, WHICH IS THE BRANCH EVERY SKIRMISH TAKES. An authored `koth` region is the
	# other half of the owner's "both" ruling and `test_koth.gd` pins it; what a picture is needed
	# for is the case a player will actually meet, where the hill is placed rather than drawn.
	var cfg := MatchConfig.debug_generated(map_seed, type, 2)
	cfg.mode = MatchConfig.Mode.KING_OF_THE_HILL
	print("── a King of the Hill match ──")
	print("  %s, seed %d, %d players, mode %s"
			% [MapGenerator.type_name(type), map_seed, cfg.player_ids.size(),
			MatchConfig.mode_name(cfg.mode)])

	Net.pending_match = cfg
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < _resume_at:
		return
	match _step:
		0:
			_hold(UI_FRAMES)
		1:
			_ok = _report_zone() and _ok
			_shoot("koth_empty")
			_march_on(1, 2)
			_hold(UI_FRAMES)
		2:
			_ok = _report_holding("player 1 alone on the hill", 1) and _ok
			_shoot("koth_held")
			# THE SAME NUMBER EACH, which is a tie and therefore nobody's hill.
			_march_on(2, 2)
			_hold(UI_FRAMES)
		3:
			_ok = _report_holding("two units each — contested", 0) and _ok
			_shoot("koth_contested")
			print("")
			print("OK — three shots written. Look at the _zoom crops: the ring is sixteen"
					+ " pixels square at 1:1 and this page is about whether it reads.")
			get_tree().quit(0 if _ok else 1)
			return
	_step += 1


# ── the report ──────────────────────────────────────────────────────────────

## Where the hill landed, and that it is armed at all.
##
## ⚠️ **AN UNARMED KotH MATCH PLAYS EXACTLY LIKE A SKIRMISH AND SAYS NOTHING**, which is the one
## failure of this feature that no screenshot could show: `_king_of_the_hill()` falls back to
## conquest by design, so a hill that failed to place is a mode that silently is not the mode. The
## exit code is what carries that.
func _report_zone() -> bool:
	var world := _world()
	if world == null:
		return false
	print("")
	print("── the hill ──")
	if world.koth_zone.size.x <= 0 or world.koth_zone.size.y <= 0:
		push_error("no zone was placed, so this match is being decided by CONQUEST and the"
				+ " ring has nothing to draw -- see MapGen._place_koth_zone()")
		return false
	print("  zone:     %s  (%d x %d tiles)" % [world.koth_zone,
			world.koth_zone.size.x, world.koth_zone.size.y])
	print("  map:      %d x %d" % [world.map.size.x, world.map.size.y])
	print("  holder:   %d (0 is nobody)" % world.koth_holder)
	# ⚠️ **DIVIDED BY THE RATE AS WELL AS BY THE TICK RATE.** This printed
	# `target / TICK_HZ` until 2026-09-11, which was right only while the ladder did not exist
	# and every tick paid 1 -- it would now report 900s for a five-minute design figure.
	# All three rungs, because "time to win" is not one number once the rate varies.
	print("  target:   %d points" % WinConditionSystem.KOTH_TARGET_SCORE)
	for rung in [[3, "alone on it"], [2, "leading, with company"], [1, "present or tied"]]:
		print("              %.0fs %s (%d/tick at %d Hz)"
				% [float(WinConditionSystem.KOTH_TARGET_SCORE)
				/ (float(int(rung[0])) * float(SimClock.TICK_HZ)),
				rung[1], int(rung[0]), SimClock.TICK_HZ])

	# ⚠️ **THE VIEW'S COPY AND THE SIM'S, PRINTED TOGETHER, BECAUSE THEY ARE THE PAIR THAT CAN
	# DISAGREE.** The zone crosses the wire as five ints; a client that read them wrongly would
	# draw a ring somewhere else entirely and every test would still pass. This is the only place
	# the two are compared.
	var view := _view()
	if view != null:
		print("  the view reads: %s, holder %d" % [view.koth_zone(), view.koth_holder()])
		if view.koth_zone() != world.koth_zone:
			push_error("the client's zone is not the server's -- the snapshot's five ints"
					+ " are not arriving")
			return false
	return true


## What the score and the holder are doing, against what they should be.
##
## Printed rather than only asserted because the numbers are the half a picture cannot carry: a
## ring in the right place over a tally that is not moving is a mode that looks finished.
func _report_holding(what: String, expect_holder: int) -> bool:
	var world := _world()
	if world == null:
		return false
	# A FEW TICKS, so the tally has visibly moved rather than merely started.
	for i in range(5):
		world.step()
	print("")
	print("── %s ──" % what)
	print("  in the zone:  P1 %d, P2 %d" % [_in_zone(world, 1), _in_zone(world, 2)])
	print("  holder:       %d" % world.koth_holder)
	for p in world.players:
		print("  P%d score:     %d" % [p.id, p.score])
	if world.koth_holder != expect_holder:
		push_error("expected the holder to be %d and it is %d"
				% [expect_holder, world.koth_holder])
		return false
	# ⚠️ **THE TIE IS THE CASE WORTH CHECKING OUT LOUD, AND IT INVERTED ON 2026-09-11.** Under the
	# flat rule nobody could score here and this asserted exactly that -- *"P%d scored on a
	# contested hill"*. Under PLAN.md §11.9's ladder a tie has no UNIQUE leader, so every side
	# present takes the base point and nobody takes the bonus: **"the ring is neutral" and "nobody
	# is progressing" stopped being the same fact.** ✅ This guard is what caught the stale
	# assertion when the ladder landed, which is the preview earning its place -- the flat rule had
	# survived a green suite for two days.
	#
	# 📝 One point EACH and not more, which is the half that matters: a bug paying the bonus to
	# both sides of a tie would make parking two armies on a square the fastest route to the
	# target, and that is the failure the ladder is most likely to be broken into.
	if expect_holder == 0:
		var before: Dictionary = {}
		for p in world.players:
			before[p.id] = p.score
		world.step()
		for p in world.players:
			# PER PLAYER IS SOUND HERE because this preview is a two-player free-for-all, so
			# every player is their own side. The rule itself scores by side.
			var want := 1 if _in_zone(world, p.id) > 0 else 0
			var gained := p.score - int(before[p.id])
			if gained != want:
				push_error("P%d gained %d a tick on a contested hill, expected %d"
						% [p.id, gained, want])
				return false
		print("  contested pays:  1 a tick each — the hill is still running")
	return true


func _in_zone(world: SimWorld, owner: int) -> int:
	var n := 0
	for e in world.entities.values():
		if e is SimUnit and e.alive and e.owner_id == owner \
				and (e as SimUnit).garrisoned_in == 0 \
				and world.koth_zone.has_point(e.tile()):
			n += 1
	return n


# ── standing units on the hill ──────────────────────────────────────────────

## Put `count` of `owner`'s villagers on the hill.
##
## ⚠️ **SPAWNED DIRECTLY INTO THE HOST'S WORLD RATHER THAN WALKED THERE**, which is
## `preview_garrison`'s trick and needs saying: ordering units across a generated map takes
## hundreds of ticks, can fail on terrain, and would make this page a test of pathfinding. What is
## being photographed is the ring, and the ring reads `koth_holder` — which reads positions.
##
## They go on DIFFERENT ROWS per owner so the two sides are visibly separate at 6x, and every tile
## is checked to be inside the zone before it is used, because a spawn that landed outside would
## make the whole report a measurement of nothing.
func _march_on(owner: int, count: int) -> void:
	var world := _world()
	if world == null:
		return
	var zone := world.koth_zone
	var row := zone.position.y + (1 if owner == 1 else 3)
	var placed := 0
	for i in range(count * 3):
		var tile := Vector2i(zone.position.x + 1 + i, row)
		if not zone.has_point(tile):
			break
		var u := world.spawn_unit(&"unit.villager", owner, tile)
		if u == null:
			continue
		if owner == 1:
			_mine.append(u)
		else:
			_theirs.append(u)
		placed += 1
		if placed >= count:
			break
	if placed < count:
		push_error("only %d of %d of P%d's units reached the hill -- the report below is"
				% [placed, count, owner] + " measuring something else")
		_ok = false


# ── plumbing ────────────────────────────────────────────────────────────────

func _world() -> SimWorld:
	var host := Net.host()
	if host == null or host.world == null:
		push_error("no host -- the match never started")
		return null
	return host.world


## The client's `GameView`, reached through the scene rather than held: `Game.tscn` builds it and
## this page is a spectator of the real screen, not its owner.
func _view() -> GameView:
	if _game == null:
		return null
	for child in _game.get_children():
		if child is GameView:
			return child as GameView
		for grandchild in child.get_children():
			if grandchild is GameView:
				return grandchild as GameView
	return null


func _hold(frames: int) -> void:
	_resume_at = _frames + frames


## The screenshot, and the crop that makes the ring judgeable.
##
## ⚠️ **THE DIAMOND'S CENTRE IS THE CONTROL'S LOCAL CENTRE PUT THROUGH ITS GLOBAL TRANSFORM, AND
## `global_position + SIZE / 2` IS NOT IT.** `Minimap` rotates 45° about its own pivot and in the
## real HUD it sits inside a positioned parent, so the unrotated offset lands somewhere off the
## diamond entirely — the first crop here came out holding the frame's top-right corner with the
## ring near the edge. `preview_minimap_teams` gets away with the simple form because its minimap
## is a direct child at a known position and nothing above it is transformed.
##
## The half-extent is still `SIZE / sqrt(2)`, which is the relation `SIZE` is itself derived from.
func _shoot(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR + shot_name + ".png")
	print("  wrote %s" % ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png"))

	var minimap := _find_minimap(_game)
	if minimap == null:
		# NOT AN ERROR. The full-screen shot is still written and still shows the HUD; what is
		# lost is the enlargement, and saying so beats a crop of the wrong corner.
		print("  (no minimap found, so no zoom crop -- the full shot still has the HUD)")
		return
	var area := int(Minimap.SIZE * 1.42) + 16
	var centre := minimap.get_global_transform() * (Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5)
	var from := Vector2i(centre) - Vector2i(area, area) / 2
	# CLAMPED TO THE VIEWPORT, because `get_region` off the edge returns an empty image and a
	# zero-byte PNG reads as a broken preview rather than as a crop that went off screen.
	from = from.clamp(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height())
			- Vector2i(area, area))
	var crop := img.get_region(Rect2i(from, Vector2i(area, area)))
	if crop.is_empty():
		print("  (the minimap is off screen, so no zoom crop)")
		return
	crop.resize(area * ZOOM, area * ZOOM, Image.INTERPOLATE_NEAREST)
	crop.save_png(SHOT_DIR + shot_name + "_zoom.png")
	print("  wrote %s" % ProjectSettings.globalize_path(SHOT_DIR + shot_name + "_zoom.png"))


func _find_minimap(node: Node) -> Minimap:
	if node is Minimap:
		return node as Minimap
	for child in node.get_children():
		var found := _find_minimap(child)
		if found != null:
			return found
	return null


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback
