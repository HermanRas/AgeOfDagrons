## CAN YOU SEE THE SPARK, AND CAN YOU TELL WHOSE CLAIM THE RING IS?
##
## 13.2c put a second countdown on the age badge (the dragon claim, in the claimant's
## colour) and a spark at the head of whichever arc is drawn. Both are the project owner's
## ask of 2026-09-07 and **neither is answerable from an assertion**:
##
##   - the whole job of a spark is to be looked at, which is `preview_projectiles`' reason
##     for existing and the strongest one in this folder;
##   - and whether a 4 px arc in `colours.json`'s DARKEST rung reads as blue, on a badge
##     whose fill is darker still, is a question for a person. `test_age_badge` can only
##     assert that the lift happened and that the hue survived it.
##
## ⚠️ **IT SAVES AN 8x NEAREST-NEIGHBOUR CROP AS WELL AS THE SCREENSHOT.** The badge is 44
## px, the ring 4 px and an ember under a pixel across. At 1:1 "I cannot see it" and "it is
## not drawn" look identical, which is exactly the trap `preview_projectiles` records
## paying for, and `preview_minimap_teams` copies. `INTERPOLATE_NEAREST`, never the
## default: every smoothing filter turns an ember into a soft smudge halfway to the badge
## colour underneath -- the judgement this page exists to support, ruined by the
## enlargement meant to support it.
##
## ⚠️ **AND IT SHOOTS TWICE, A FEW FRAMES APART.** A spark is the one thing on this badge
## that moves on its own, so a single frame cannot tell a moving train of embers from five
## dots painted on. Two crops with the train in two places is the picture that answers it.
##
## ## THE WIDGET, NOT A MATCH
##
## `AgeBadge` takes both progresses as plain properties, so standing up a real match with a
## nest in it would put six minutes of simulation between the question and the answer --
## and leave which colour was on the ring up to who happened to kill the mother. The rows
## below are every state the ring has, side by side, which no match can produce at once.
##
## ## WHAT A FAILURE LOOKS LIKE
##
## - **A two-tone ring** in the BOTH row means the age/claim precedence has been layered
##   rather than made exclusive. The advance owns the ring outright while it is in flight.
## - **A gold arc in a claim row** means `claim_colour` is not reaching the badge.
## - **An ember outside the badge circle** means a spark constant has been retuned past
##   `SPARK_MAX_RADIUS`; `_report` prints the budget and warns.
## - **A claim ring you cannot find** in the blue or red row is the legibility question
##   `CLAIM_ARC_MIN_LUMINANCE` exists for, and the answer is to raise that constant.
##
## Usage:
##   Godot --path game res://dev_preview/preview_age_badge.tscn
extends Node

const SHOT_DIR := "user://"
## Long enough for the badges to have drawn and for the ember train to be somewhere other
## than where it started.
const SETTLE_FRAMES := 20
## Frames between the two shots. ~0.25 s at 60 fps against a 0.45 s spark period, so the
## train moves rather more than half a cycle -- far enough that the two crops cannot be
## mistaken for the same picture, which is the only thing the second one is for.
const SECOND_SHOT_AFTER := 15
const ZOOM := 5
## One badge on its own, big enough to count the embers. `HERO_ROW` indexes `ROWS`; the
## 55%-blue claim is the pick because a mid-arc head is the only place the whole train is
## visible -- at 97% it runs into the ring's own start and at 8% there is barely a trail.
const HERO_ZOOM := 16
const HERO_ROW := 5

## ⚠️ **THE ONE PAIRING THAT HAS TO BE TOLD APART, AND IT IS NOT A PLAYER FROM A PLAYER.**
## `colour.yellow` is the closest rung on the palette to the age ring's own gold, so the
## question this crop answers is *"is that my age advancing, or somebody taming a dragon"*
## — which is the only reading on this badge that would send a player to the wrong place.
##
## `ROWS` is laid out so grid row 2 carries `age 55%` in the left column and `claim 55%
## yellow` in the right, at the SAME fraction: the two badges are already side by side and
## the crop is one row of the grid. Same measured-not-eyeballed shape as
## `preview_minimap_teams`, which exists for the sky-blue-on-water version of this.
const COMPARE_ROW := 2
const COMPARE_ZOOM := 12

## ⚠️ **FIVE ROWS IN TWO COLUMNS, AND THE FIRST VERSION WAS TEN IN ONE.** The default
## window is 1152x648 and ten badges 78 px apart need 796 -- so the last two rows were
## photographed off the bottom of the viewport and `get_region` filled the crop with white,
## which reads as a rendering fault rather than as a layout one. Anything laid out by
## arithmetic in this folder owes the viewport the same sum.
const ORIGIN := Vector2(300.0, 76.0)
const COLUMN_DX := 380.0
const ROW_DY := 108.0
const ROWS_PER_COLUMN := 5

## One row per state worth judging. `[label, age_progress, claim_progress, colour index]`,
## where a colour index of -1 means no claim.
##
## THE THREE FRACTIONS ARE 0.08, 0.55 AND 0.97 rather than a tidy quarter/half/full: a
## nearly-empty and a nearly-full arc are the two the segment count and the trail clamp
## behave differently at, and a ring at exactly 1.0 hides its own head under its own start.
const ROWS := [
	["no countdown", 0.0, 0.0, -1],
	["age 8%", 0.08, 0.0, -1],
	["age 55%", 0.55, 0.0, -1],
	["age 97%", 0.97, 0.0, -1],
	["claim 8% blue", 0.0, 0.08, 0],
	["claim 55% blue", 0.0, 0.55, 0],
	["claim 97% red", 0.0, 0.97, 1],
	["claim 55% yellow", 0.0, 0.55, 2],
	["claim 55% white", 0.0, 0.55, 7],
	["BOTH: age wins", 0.35, 0.9, 0],
]

var _badges: Array[AgeBadge] = []
var _frames := 0
var _shots := 0


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = HudStyle.DARK_BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	for i in range(ROWS.size()):
		var row: Array = ROWS[i]
		var at := ORIGIN + Vector2(COLUMN_DX * float(i / ROWS_PER_COLUMN),
				ROW_DY * float(i % ROWS_PER_COLUMN))

		# ABOVE THE BADGE, not beside it. Two columns of labels to the left of two columns
		# of badges is four columns of things, and the crop then has to be wide enough for
		# text that is not the subject.
		var label := HudPanel.text_label(String(row[0]), 15)
		label.position = at + Vector2(-84.0, -26.0)
		label.size = Vector2(212.0, 22.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)

		# THE REAL WIDGET, wired the way `GameScene._refresh_hud` wires it -- including the
		# index -> Color step through the registry, because a preview that hands the badge
		# a hand-picked Color would not be photographing the palette.
		var badge := AgeBadge.new()
		badge.position = at
		# An age past 1 so the numeral is not the thing the eye goes to, and mid-ladder so
		# ADVANCE is still offered.
		badge.age = 2
		badge.progress = float(row[1])
		badge.claim_active = int(row[3]) >= 0
		badge.claim_progress = float(row[2])
		if badge.claim_active:
			badge.claim_colour = GameDataRegistry.colour(int(row[3]))
		badge.advancing = badge.progress > 0.0
		add_child(badge)
		_badges.append(badge)


func _process(_delta: float) -> void:
	_frames += 1
	if _shots == 0 and _frames >= SETTLE_FRAMES:
		_shots = 1
		_report()
		_shoot("age_badge_ring")
		return
	if _shots == 1 and _frames >= SETTLE_FRAMES + SECOND_SHOT_AFTER:
		_shots = 2
		_shoot("age_badge_ring_later")
		get_tree().quit()


## The numbers behind the picture, so a disagreement between the two is settleable.
##
## Three separate things a screenshot cannot say: how much room the sparks have and how
## much of it they use, what the lift did to each palette colour, and which badge is
## actually drawing which ring.
func _report() -> void:
	var radius := AgeBadge.SIZE * 0.5 - AgeBadge.RING_WIDTH
	print("ring radius %.1f px, spark budget %.1f px from the centre"
			% [radius, AgeBadge.SPARK_MAX_RADIUS])
	print("    core glow reaches %.2f, the hot tip %.2f"
			% [radius + AgeBadge.SPARK_CORE_PX, radius + AgeBadge.SPARK_TIP_WIDTH * 0.5])

	# Swept rather than reasoned about, for `test_age_badge`'s reason and to catch a
	# retuned constant here as well as there.
	var worst := 0.0
	for step in range(41):
		var fraction := float(step) / 40.0
		for frame in range(24):
			var t := AgeBadge.SPARK_PERIOD_SEC * float(frame) / 23.0
			var head := -PI * 0.5 + TAU * fraction
			for e in AgeBadge.spark_embers(t, radius, fraction, head):
				worst = maxf(worst, (e["offset"] as Vector2).length() + float(e["radius"]))
	print("    furthest ember reaches %.2f" % worst)
	if worst > AgeBadge.SPARK_MAX_RADIUS \
			or radius + AgeBadge.SPARK_CORE_PX > AgeBadge.SPARK_MAX_RADIUS \
			or radius + AgeBadge.SPARK_TIP_WIDTH * 0.5 > AgeBadge.SPARK_MAX_RADIUS:
		push_warning("preview_age_badge: a spark is drawn outside the badge -- a Control "
				+ "does not clip its own _draw, so it lands on the resource counters")

	print("the claim arc, per palette colour (luminance before -> after the lift, "
			+ "floor %.2f):" % AgeBadge.CLAIM_ARC_MIN_LUMINANCE)
	for i in range(GameDataRegistry.colour_count()):
		var base := GameDataRegistry.colour(i)
		var lifted := AgeBadge.claim_arc_color(base)
		var moved := "lifted" if lifted != base else "untouched"
		print("    %d  %s -> %s   %.3f -> %.3f  %s" % [i, base.to_html(false),
				lifted.to_html(false), base.get_luminance(), lifted.get_luminance(), moved])

	_report_gold_confusion()

	print("what each row is drawing:")
	for i in range(_badges.size()):
		var b := _badges[i]
		var which := "age" if b._age_ring_wins() \
				else ("claim" if b.claim_active and b.claim_progress > 0.0 else "plain ring")
		print("    %-18s %s%s" % [String((ROWS[i] as Array)[0]), which,
				"  (animating)" if b.is_processing() else ""])


## HOW FAR EVERY PLAYER COLOUR IS FROM THE AGE RING'S GOLD, and what else separates them.
##
## ⚠️ **THE CONFUSION THIS BADGE CAN ACTUALLY CAUSE IS NOT PLAYER-AGAINST-PLAYER.** Two
## claimants are never on this ring at once -- `_publish_claim` reports one -- so
## `colours.json`'s whole ladder is answering a question that is not asked here. The
## question that IS asked is *"is that my age advancing, or somebody taming a dragon"*,
## because those two mean entirely different things and one of them is a thing to go and
## look at.
##
## MEASURED ON HUE AND CIE `L*`, which is `preview_minimap_teams`' method and reached for
## the same reason: sky blue and shallow water are six degrees apart in hue and are told
## apart by lightness instead. Here it is worth knowing whether EITHER axis separates them.
func _report_gold_confusion() -> void:
	var gold := AgeBadge.PROGRESS_COLOR
	print("the age ring's gold is %s (hue %.0f deg, L* %.0f). "
			% [gold.to_html(false), gold.h * 360.0, _lightness(gold)]
			+ "distance from each claim colour:")
	var worst_name := ""
	var worst := 1e9
	for i in range(GameDataRegistry.colour_count()):
		var arc := AgeBadge.claim_arc_color(GameDataRegistry.colour(i))
		# HUE WRAPS, so 350 deg and 10 deg are twenty apart and not three hundred and forty.
		var d_hue := absf(arc.h - gold.h)
		d_hue = minf(d_hue, 1.0 - d_hue) * 360.0
		var d_l := absf(_lightness(arc) - _lightness(gold))
		# A CRUDE COMBINED SCORE, and crude on purpose: what it is for is picking out the
		# one row worth looking at, not for deciding anything. 16 L* is the ladder's own
		# rung spacing, so a degree of hue and a sixteenth of a rung count the same here.
		var score := d_hue + d_l
		print("    %d  %s  hue %5.0f deg, L* %5.0f" % [i, arc.to_html(false), d_hue, d_l])
		if score < worst:
			worst = score
			worst_name = "%d (%s)" % [i, arc.to_html(false)]
	print("    closest to the gold: colour %s" % worst_name)
	print("    what still separates them: the TRACK (%s gold-brown against %s neutral) "
			% [AgeBadge.TRACK_COLOR.to_html(false), AgeBadge.CLAIM_TRACK_COLOR.to_html(false)]
			+ "and the HINT ('...' while advancing, 'ADVANCE' or 'MAX' while not)")


## CIE `L*`, lifted verbatim from `preview_minimap_teams` — the same measure the eight-player
## palette was chosen on, so a figure here is comparable with the ones in that file's report.
func _lightness(c: Color) -> float:
	var y := 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)
	return (116.0 * pow(y, 1.0 / 3.0) - 16.0) if y > 0.008856 else (903.3 * y)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 \
			else pow((channel + 0.055) / 1.055, 2.4)


func _shoot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR + name + ".png")
	print("wrote ", ProjectSettings.globalize_path(SHOT_DIR + name + ".png"))

	# THE WHOLE GRID, derived from the layout rather than from a measured rect: a badge is
	# `SIZE` wide and `SIZE + 10` tall (the hint label lives in the extra ten), and its
	# label sits 26 px above it.
	#
	# CLAMPED TO THE IMAGE, because a crop running off the viewport comes back WHITE rather
	# than failing -- which is how the first version's two missing rows presented, and it
	# reads as a rendering fault rather than as a layout one.
	var top_left := Vector2i(ORIGIN) - Vector2i(90, 34)
	var area := Vector2i(int(COLUMN_DX) + int(AgeBadge.SIZE) + 180,
			int(ROW_DY) * (ROWS_PER_COLUMN - 1) + int(AgeBadge.SIZE) + 90)
	var rect := Rect2i(top_left, area).intersection(
			Rect2i(Vector2i.ZERO, img.get_size()))
	if rect.size != area:
		push_warning("preview_age_badge: the grid does not fit the %dx%d viewport -- "
				% [img.get_width(), img.get_height()]
				+ "the crop is short by %s px" % str(area - rect.size))
	var crop := img.get_region(rect)
	crop.resize(rect.size.x * ZOOM, rect.size.y * ZOOM, Image.INTERPOLATE_NEAREST)
	crop.save_png(SHOT_DIR + name + "_zoom.png")
	print("wrote ", ProjectSettings.globalize_path(SHOT_DIR + name + "_zoom.png"))

	# ⚠️ **AND ONE BADGE ON ITS OWN AT `HERO_ZOOM`, WHICH IS THE ONLY CROP THE EMBERS SHOW
	# UP IN.** The grid at 5x is enough to judge a ring colour and the precedence rule; an
	# ember is barely a pixel across and needs ten times that. Same lesson as
	# `preview_projectiles`' "crop to the printed coordinate at 8x" -- the difference
	# between "I cannot see it" and "it is not drawn" is a magnification.
	var hero_at := ORIGIN + Vector2(COLUMN_DX * float(HERO_ROW / ROWS_PER_COLUMN),
			ROW_DY * float(HERO_ROW % ROWS_PER_COLUMN))
	var hero := img.get_region(Rect2i(Vector2i(hero_at) - Vector2i(6, 6),
			Vector2i(int(AgeBadge.SIZE) + 12, int(AgeBadge.SIZE) + 12)))
	hero.resize(hero.get_width() * HERO_ZOOM, hero.get_height() * HERO_ZOOM,
			Image.INTERPOLATE_NEAREST)
	hero.save_png(SHOT_DIR + name + "_head.png")
	print("wrote ", ProjectSettings.globalize_path(SHOT_DIR + name + "_head.png"),
			"  (%s at %dx)" % [String((ROWS[HERO_ROW] as Array)[0]), HERO_ZOOM])

	# THE GOLD-AGAINST-YELLOW PAIR, one grid row wide. See `COMPARE_ROW`.
	var pair_y := ORIGIN.y + ROW_DY * float(COMPARE_ROW)
	var pair := img.get_region(Rect2i(
			Vector2i(int(ORIGIN.x) - 8, int(pair_y) - 8),
			Vector2i(int(COLUMN_DX) + int(AgeBadge.SIZE) + 16, int(AgeBadge.SIZE) + 24)))
	pair.resize(pair.get_width() * COMPARE_ZOOM, pair.get_height() * COMPARE_ZOOM,
			Image.INTERPOLATE_NEAREST)
	pair.save_png(SHOT_DIR + name + "_gold_vs_yellow.png")
	print("wrote ", ProjectSettings.globalize_path(SHOT_DIR + name + "_gold_vs_yellow.png"),
			"  (%s | %s at %dx)" % [String((ROWS[COMPARE_ROW] as Array)[0]),
			String((ROWS[COMPARE_ROW + ROWS_PER_COLUMN] as Array)[0]), COMPARE_ZOOM])
