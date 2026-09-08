## The age indicator (PLAN.md 9.1: a roman numeral in a gold circle), doubling
## for now as the only way to advance an age at all.
##
## Two halves with very different lifespans, and it is worth being clear which is
## which:
##
##   The NUMERAL is real UI. 9.1 asks for exactly this and it stays.
##   The TAP-TO-ADVANCE is a debug affordance. Real advancement (9.2) costs
##   resources, takes time and is researched at a town centre, so it will be a
##   queue entry on the town centre's panel rather than a button here. When that
##   lands, this loses its button and keeps its numeral.
##
## It exists now because the age axis became load-bearing before the mechanism
## that drives it: buildings re-skin per age (2.7), the menus gate on age, and
## the sim refuses an order above the caller's age. Without a way to advance,
## none of that is reachable in a running game -- three quarters of the roster
## and every building skin past age 1 would be untestable on a device.
##
## Emits `advance_requested` rather than submitting a command itself, the same
## division `ControlGroupsHud` and `SelectionPanel` keep: GameScene owns the
## crossing into `Net.submit_command()`.
##
## Built in `_init()`, not `_ready()`, so a bare `.new()` is fully wired for a
## headless test -- the convention `ResourceHUD` and `ControlGroupsHud` follow.
##
## MIRRORED IN THE MOCKUP at `scenes/ui_builder/HUD.tscn`, under
## AgeHeader/Margin/Box/HBoxContainer/AgeBadge, so the header can be laid out in
## the editor. That copy is PRIMITIVES -- a rounded StyleBoxFlat for the ring and
## two Labels -- rather than an instance of this script, because the ui_builder
## scenes are drawn from primitives to stay editable without running the game
## (ControlGroupsHud.tscn mocks its slot rings the same way). The constants below
## are the shared contract between the two: SIZE, RING_WIDTH, FILL_COLOR and
## RING_COLOR all appear in that StyleBoxFlat, and the label font sizes in its
## Numeral/Hint nodes. Adjust the mockup, then bring the numbers back here --
## nothing checks that they agree, because a mockup that could not be edited
## freely would not be much of a mockup.
class_name AgeBadge
extends Button

signal advance_requested(next_age: int)

## The badge was pressed and it is NOT going to ask for anything -- `&"advancing"`
## while a research is already running, `&"maxed"` at the top of the ladder.
##
## It exists because a button that silently does nothing is the whole of the project
## owner's 2026-08-28 report, *"age up, does not tell you why its failing when
## clicked"*. Swallowing the press was right; swallowing it in silence was not. The
## REASON travels rather than the sentence, so the wording stays in `GameScene` with
## every other message the player reads, and this stays a widget that decides nothing.
signal advance_unavailable(reason: StringName)

## Sized to sit inside the age header's title row beside the pause button, which
## is 48 px -- not as a free-floating badge. The first version of this WAS free
## floating, at the top right, and landed straight on top of the resource
## counters; that is what running the game caught and a headless test could not.
const SIZE := 44.0
const RING_COLOR := HudStyle.GOLD
const RING_WIDTH := 3.0
const RING_SEGMENTS := 32
const FILL_COLOR := Color(0.17, 0.11, 0.08, 0.9)
## The advance ring: a dimmed track under a brighter gold fill, so how far round
## it has gone is readable without having to remember where it started.
const TRACK_COLOR := Color(0.35, 0.28, 0.16, 0.85)
const PROGRESS_COLOR := Color(1.0, 0.85, 0.35)
## The numeral goes grey once there is nothing left to advance to, rather than
## the button hiding: a HUD element that disappears at age 4 reads as a bug.
const MAXED_COLOR := Color(0.62, 0.58, 0.5)

## ── the dragon claim's ring (PLAN.md 13.2c, owner's ask 2026-09-07) ─────────
##
## *"lets reuse the exact same spot as the age up, with the player that claimed its
## colour. the age up ring draws over the dragon tame, since a age up is quick no
## conflict."*
##
## So this badge draws TWO different countdowns on one ring, and the age one wins. The
## claim's is the longer by a wide margin -- `NestSystem.GROW_TICKS` is 360 s against an
## advance's tens of seconds -- which is exactly why sharing the spot is affordable: the
## thing that interrupts is the short one.
##
## ⚠️ **DRAWN EXCLUSIVELY, NOT LAYERED, AND THAT IS THE ONE PLACE THIS DEPARTS FROM THE
## LITERAL WORDS.** "Draws over" as an actual overdraw only hides the claim arc where the
## two happen to overlap: an advance at 30% over a claim at 80% would paint gold from 12
## o'clock to 4 and leave the claimant's colour running on from there to 10 -- a two-tone
## ring that reads as one broken gauge rather than as two features. While an advance is in
## flight the badge is the advance's, and the claim's ring comes back where it now stands
## when the advance lands. That is what "no conflict" means in practice.
##
## THE TRACK IS NEUTRAL AND NOT `TRACK_COLOR`. That one is a dimmed GOLD, chosen to sit
## under the gold fill; a claimant's blue arc on a brown track reads as a gold ring that
## has gone wrong somewhere.
const CLAIM_TRACK_COLOR := Color(0.16, 0.16, 0.18, 0.85)

## ⚠️ **HOW DARK A PLAYER COLOUR IS ALLOWED TO ARRIVE ON THE TRACK.** `colours.json` is a
## CIE L* ladder spanning white at 100 down to blue at 36, and it is a ladder for
## separating players from EACH OTHER -- nothing in it promises a rung is legible as a 4 px
## arc on a dark badge. Measured with `Color.get_luminance()`: the track is 0.16 and the
## badge fill 0.12, against blue's 0.25 and red's 0.19. Those two are the whole problem and
## the other six are already clear.
##
## `claim_arc_color` lifts a colour toward white until it reaches this, which keeps the hue
## -- identification is the entire job of the colour and desaturating it would undo the
## reason the owner asked for it. Untouched at 0.40 and above, so six of the eight are the
## palette entry exactly.
const CLAIM_ARC_MIN_LUMINANCE := 0.40

## The colour of whoever is claiming, straight out of `colours.json` (`GameScene` does the
## index -> Color step, as it does for the rally flag). Grey is the honest default for a
## claim whose owner is not in the last snapshot; nothing draws a ring in that state,
## because `claim_active` is what turns it on.
var claim_colour: Color = Color(0.6, 0.6, 0.6):
	set(value):
		if claim_colour == value:
			return
		claim_colour = value
		queue_redraw()

## Whether a claim is running at all, anybody's. Separate from `claim_progress > 0` for
## exactly the reason `advancing` is separate from `progress`: the tick a claim starts is
## progress 0.0 and the ring has to be there already, or six minutes reads as five and a
## half followed by a ring appearing out of nowhere.
var claim_active: bool = false:
	set(value):
		if claim_active == value:
			return
		claim_active = value
		_sync_spark_clock()
		queue_redraw()

## How far the claim has MATURED, 0.0 to 1.0. Comes from `GameView.claim_progress()`,
## which is where the wire's count-DOWN is turned into a ring that fills UP.
var claim_progress: float = 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(claim_progress, next):
			return
		claim_progress = next
		_sync_spark_clock()
		queue_redraw()

## ── the spark at the head of whichever ring is drawn ────────────────────────
##
## Owner, 2026-09-07: *"can we possibly add a spark like particle at the front of the
## progress bar as it loads, for both age up and dragon baby tame?"* Both of those are this
## one ring, so it is one implementation and whichever arc is on top gets it.
##
## ⚠️ **DRAWN, NOT A `CPUParticles2D`, AND THE REASON IS THE ONE `_draw`'s OWN HEADER GIVES
## FOR THE ARC.** A particle node would have to be re-positioned along the arc every frame
## from this same arithmetic, needs a dot texture the project does not have, and would draw
## a DIFFERENT picture in every screenshot -- so nothing could be asserted about it and the
## previews could not be compared run to run. The table below is deterministic: the same
## `t` always produces the same sparks.
##
## ⚠️ **AND IT IS BOUNDED, WHICH A PARTICLE SYSTEM IS NOT.** A `Control` does not clip its
## own `_draw` (the MapMaker's "map renders over UI" was one line of exactly this), and this
## badge sits in the age header a few pixels from the resource counters -- the same corner
## where 9.1's first free-floating version landed on top of them. `SPARK_MAX_RADIUS` is the
## cap and `test_age_badge` asserts no spark ever exceeds it, at every progress and across a
## full period.
const SPARK_COUNT := 5
## One full cycle of the ember train, in seconds. Fast enough to read as a spark rather
## than as five dots orbiting.
const SPARK_PERIOD_SEC := 0.45
## How far BACK along the arc the oldest ember sits, in radians. Clamped to the arc actually
## drawn, so a ring at 2% does not fling sparks anticlockwise past its own start.
##
## ⚠️ **0.9 AND NOT 0.55, BECAUSE FIVE EMBERS OVER A SHORT TRAIL ARE ONE BLOB.** At radius
## 19 a 0.55 rad trail is about 10 px of arc, so `SPARK_COUNT` embers landed 2 px apart and
## overlapped into a single smear -- two crops a third of a period apart came out
## indistinguishable, which is `preview_age_badge`'s whole reason for shooting twice. 0.9
## rad is ~17 px and the flecks separate.
const SPARK_TRAIL_RAD := 0.9
## ⚠️ **THERE ARE 2.5 PIXELS OUTSIDE THE RING AND THAT IS THE WHOLE SPARK BUDGET**, which
## is what the first version of this got wrong. `SPARK_MAX_RADIUS` is 21.5 and the arc sits
## at 19 with a half-width of 2, so an ember can drift at most about a pixel clear of the
## arc before it runs out of badge -- and one drawn *inside* the arc, in a colour close to
## the arc's, is invisible. `preview_age_badge`'s 5x crop is what showed that: the embers
## were drawn, in budget, on the arc, and could not be seen at all.
##
## **SO THE HEAD CARRIES IT AND THE EMBERS DECORATE IT.** A hot white TIP -- a short arc
## brighter and wider than the ring itself -- is what reads as "the front of the bar is
## burning", and it is also the honest shape: a spark at the leading edge is where the work
## is happening.
##
## 📝 **AND THE LIMIT IS WORTH KNOWING BEFORE ANYONE RETUNES THESE.** The embers are a
## shimmer in the tip's wake rather than particles you can count -- an ember drawn a pixel
## clear of a 4 px arc is still inside it. Measured both directions: drifting them INWARD
## (a negative `SPARK_DRIFT_PX`, onto the dark fill where a pale dot should pop) produced a
## byte-identical crop, because the jitter table keeps most of them under a pixel of travel
## either way. **The only lever that would make a showier spark is a smaller ring radius**,
## which is a change to something the owner has already approved the look of -- so it is
## theirs to ask for and not mine to take.
const SPARK_DRIFT_PX := 1.2
## The hot tip: how long an arc it covers, and how much wider than the ring it is drawn.
## The width is the binding constraint -- half of it plus the ring radius is exactly
## `SPARK_MAX_RADIUS`.
const SPARK_TIP_RAD := 0.10
const SPARK_TIP_WIDTH := RING_WIDTH + 2.0
## The white-hot core dot at the head, and the embers at birth.
const SPARK_CORE_PX := 2.0
const SPARK_EMBER_PX := 1.2
## ⚠️ **NOTHING MAY BE DRAWN FURTHER FROM THE CENTRE THAN THIS.** `SIZE * 0.5` is the
## badge's own edge; the half pixel is so a spark at the cap is inside it rather than on it.
const SPARK_MAX_RADIUS := SIZE * 0.5 - 0.5
## Per-ember drift, as a fraction of `SPARK_DRIFT_PX`, one entry per `SPARK_COUNT`.
##
## A LITERAL TABLE RATHER THAN A HASH OF THE INDEX, so what the sparks do is readable here
## and identical on every machine, in every run and in every screenshot. `randf()` in a
## `_draw` would make this badge a different picture every frame and unassertable.
const SPARK_JITTER := [0.9, 0.35, 1.0, 0.15, 0.65]

var age: int = 1:
	set(value):
		if age == value:
			return
		age = value
		_refresh()

## How far through an age advance, 0.0 to 1.0, drawn as a gold ring filling
## clockwise from 12 o'clock around the badge (PLAN.md 9.1's progress bar, bent
## into a circle). Comes from the SIM's tick count via GameView.age_progress_of;
## this never runs its own clock, so the ring cannot drift from the research it
## is reporting and every client draws the same fill on the same tick.
var progress: float = 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(progress, next):
			return
		progress = next
		_sync_spark_clock()
		queue_redraw()

## Whether an advance is in flight. Separate from `progress > 0` because the tick
## an advance STARTS is progress 0.0, and the badge must already have stopped
## offering another one.
var advancing: bool = false:
	set(value):
		if advancing == value:
			return
		advancing = value
		_refresh()

var _numeral: Label
var _hint: Label


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 10.0)
	focus_mode = Control.FOCUS_NONE
	flat = true
	tooltip_text = "Advance an age (debug -- 9.2 makes this a researched action)"
	# A Button paints its own themed StyleBox under this script's children unless
	# every state is emptied -- the trap ControlGroupSlot and ActionSlot both
	# document.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)

	_numeral = Label.new()
	# THE BEST FIT FOR CINZEL DECORATIVE IN THE WHOLE GAME, and it is not a
	# coincidence: this label holds a Roman numeral, and Cinzel is drawn from Roman
	# capitalis inscriptions. I, II, III, IV in a display face at 18 px.
	UiFont.title(_numeral, 18)
	_numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_numeral.size = Vector2(SIZE, SIZE)
	_numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_numeral)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", HudStyle.GOLD)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0.0, SIZE - 4.0)
	_hint.size = Vector2(SIZE, 12.0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	pressed.connect(_on_pressed)
	# OFF UNTIL THERE IS AN ARC TO ANIMATE. A badge sitting at age 1 with nothing in
	# flight is the state most of a match is spent in, and a per-frame redraw of
	# something that cannot have changed is what the MapMaker's "the tool is very slow"
	# turned out to be. `_sync_spark_clock` turns it on and off from the two progresses.
	set_process(false)
	_refresh()


## ⚠️ **GODOT TURNS `_process` BACK ON WHEN THE NODE ENTERS THE TREE, so `set_process(false)`
## IN `_init` DOES NOT STICK.** Declaring `_process` at all is what enables per-frame
## processing, and that is re-applied on entry -- so the gate has to be re-asserted from
## here or every badge in the game redraws 60 times a second for the whole match, including
## the ~99% of it with no countdown running at all.
##
## ⚠️ **AND NO HEADLESS TEST CAN SEE IT.** A bare `AgeBadge.new()` never enters a tree, so
## `_init`'s `set_process(false)` is the last word there and
## `test_the_claim_ring_is_animated_and_a_quiet_badge_is_not` passed while every badge in a
## real scene was animating. `preview_age_badge`'s report prints `(animating)` per row and
## is what found it -- which is §5's rule arriving on this file: ask which failures your
## check is blind to.
func _ready() -> void:
	_sync_spark_clock()


## THE SPARK IS THE ONLY THING ON THIS BADGE THAT MOVES ON ITS OWN, and it is the only
## reason there is a `_process` here at all.
##
## Everything else redraws when a snapshot changes a property, which is ten times a second
## at most. A spark that only moved when the sim moved would stutter at exactly the rate
## the ring grows, so this one runs off the wall clock -- it is decoration, it decides
## nothing, and `progress` is still the only thing that says where the head IS.
##
## Cheap on purpose: a 44 px control and about fifteen draw calls, gated to the seconds an
## arc is actually on screen. That is the opposite end of the scale from the MapMaker's
## 9,216-tile canvas being invalidated per mouse-move.
func _process(_delta: float) -> void:
	queue_redraw()


func _sync_spark_clock() -> void:
	set_process(_arc_shown())


## Whether any arc -- age or claim -- is being drawn right now, which is the same question
## as "is there a spark to animate".
##
## An advance at exactly 0.0 draws no arc (see `_draw`'s early return), so `advancing` is
## deliberately NOT part of this: the tick a research starts there is nothing to put a
## spark on yet.
func _arc_shown() -> bool:
	if _age_ring_wins():
		return true
	return claim_active and claim_progress > 0.0


## Which of the two countdowns owns the ring this frame (owner, 2026-09-07: the age
## advance does, whenever there is one).
##
## A NAMED PREDICATE RATHER THAN A CONDITION INSIDE `_draw`, because a rule written into a
## `_draw` is a rule no test can see -- and this one is the whole of what the owner asked
## for. `CLAIM_TRACK_COLOR`'s header carries why it is exclusive rather than layered.
func _age_ring_wins() -> bool:
	return progress > 0.0


## A player colour lifted far enough off the badge to read as a 4 px arc, keeping its hue.
##
## `Color.get_luminance()` is linear in the channels it weights and white is 1.0, so lerping
## toward white by `k` lifts the luminance to `lum + k * (1 - lum)` -- which inverts in one
## step rather than in a loop. See `CLAIM_ARC_MIN_LUMINANCE` for the measured figures and
## for which two of the eight this touches.
##
## STATIC, so the test can measure the whole palette through it without standing up a badge.
static func claim_arc_color(base: Color) -> Color:
	var lum := base.get_luminance()
	if lum >= CLAIM_ARC_MIN_LUMINANCE:
		return base
	var k := (CLAIM_ARC_MIN_LUMINANCE - lum) / (1.0 - lum)
	var lifted := base.lerp(Color.WHITE, k)
	lifted.a = base.a
	return lifted


## The age after this one, or 0 when there is none. Read from `ages.json` rather
## than assumed to be 4, so adding a fifth age is a data change.
func next_age() -> int:
	return age + 1 if age < GameDataRegistry.age_count() else 0


func _refresh() -> void:
	var def: AgeDef = GameDataRegistry.age(age)
	# Falls back to the number rather than blanking: an age with no entry in
	# ages.json is a data bug, and showing "3" says more than showing nothing.
	_numeral.text = def.numeral if def != null and not def.numeral.is_empty() else str(age)

	var has_next := next_age() != 0
	var tint := HudStyle.GOLD if has_next else MAXED_COLOR
	_numeral.add_theme_color_override("font_color", tint)
	# Three states, not two: at the top of the ladder there is nothing to do,
	# mid-research the button is inert and the ring is the feedback, and
	# otherwise it invites a press.
	if not has_next:
		_hint.text = "MAX"
	elif advancing:
		_hint.text = "..."
	else:
		_hint.text = "ADVANCE"
	_hint.add_theme_color_override("font_color", tint)
	queue_redraw()


## The badge is a circle with a track and a fill drawn on it, rather than a
## TextureProgressBar in radial mode.
##
## The tutorial approach (peanuts-code GD0015) wraps a radial texture, which is
## the right answer when the bar has ART -- a bevelled gauge, a segmented dial.
## This one is a 3 px gold ring that already exists here as a `draw_arc`, so a
## texture would mean commissioning art to reproduce a line we are drawing
## anyway, and it would have to be re-cut every time SIZE or RING_WIDTH moved.
## `draw_arc` follows those constants for free and stays in step with the
## mockup's StyleBoxFlat.
##
## Fills CLOCKWISE FROM 12 O'CLOCK, which is why the angles start at -PI/2:
## Godot's zero angle is 3 o'clock and its positive direction is clockwise in
## screen space (y down), so a naive 0..TAU*progress would start the fill at the
## right-hand side and read as arbitrary.
func _draw() -> void:
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius := SIZE * 0.5 - RING_WIDTH
	draw_circle(centre, radius, FILL_COLOR)

	var has_next := next_age() != 0
	# ⚠️ **THE AGE ADVANCE WINS THE RING OUTRIGHT** (owner, 2026-09-07). See
	# `CLAIM_TRACK_COLOR`'s header for why the two are exclusive rather than layered, and
	# for why sharing one spot is affordable at all: an advance is tens of seconds and a
	# claim is 360.
	if _age_ring_wins():
		_draw_ring(centre, radius, progress, TRACK_COLOR, PROGRESS_COLOR)
		return
	if claim_active and claim_progress > 0.0:
		_draw_ring(centre, radius, claim_progress,
				CLAIM_TRACK_COLOR, claim_arc_color(claim_colour))
		return

	draw_arc(centre, radius, 0.0, TAU, RING_SEGMENTS,
			RING_COLOR if has_next else MAXED_COLOR, RING_WIDTH, true)


## One countdown: a dimmed full track, the filled arc over it, and the spark at its head.
##
## Both callers pass their own two colours and nothing else differs, which is the point --
## the age ring and the claim ring are the same gauge reporting different clocks, and a
## second copy of this arithmetic is how they would drift apart.
func _draw_ring(centre: Vector2, radius: float, fraction: float,
		track: Color, arc: Color) -> void:
	# The unfilled remainder stays visible as a dimmed track, so the ring reads
	# as "part way round" rather than as an arc floating on nothing.
	draw_arc(centre, radius, 0.0, TAU, RING_SEGMENTS, track, RING_WIDTH, true)
	var start := -PI * 0.5
	# Segment count scaled to the arc drawn, or a nearly-empty ring is rendered
	# with the same 32 points as a full one and reads as a polygon.
	var segments := maxi(2, int(ceil(RING_SEGMENTS * fraction)))
	var head := start + TAU * fraction
	draw_arc(centre, radius, start, head, segments, arc, RING_WIDTH + 1.0, true)
	_draw_spark(centre, radius, fraction, head, arc)


## The spark at the head of the arc: a white-hot tip, a core, and a train of embers behind.
##
## DRAWN IN THREE PIECES, LARGEST FIRST, because they overlap and the brightest has to end
## up on top -- a tip drawn over the core would flatten the glow it exists to give.
##
## THE EMBERS TRAIL BACKWARD, which is why the angles subtract: `draw_arc` fills clockwise
## from 12 o'clock (see `_draw`'s own header on why `start` is -PI/2), so behind the head is
## the smaller angle. Sparks thrown FORWARD would sit on track the ring has not reached yet
## and read as the gauge overshooting.
func _draw_spark(centre: Vector2, radius: float, fraction: float,
		head: float, arc: Color) -> void:
	var hot := arc.lerp(Color.WHITE, 0.85)
	# THE TIP: a short stretch of ring drawn hotter and wider than the rest of it. This is
	# the piece that actually reads at 44 px -- see `SPARK_DRIFT_PX`'s header for why
	# nothing outside the ring can.
	draw_arc(centre, radius, head - SPARK_TIP_RAD, head, 4, hot, SPARK_TIP_WIDTH, true)

	# The embers, brightest at birth and fading back along the tip's wake. Nearly white
	# rather than the arc's own colour: an ember in the arc's colour, drawn on the arc, is
	# the version that could not be seen.
	for e in spark_embers(_spark_time(), radius, fraction, head):
		var c := arc.lerp(Color.WHITE, 0.8)
		c.a = float(e["alpha"])
		draw_circle(centre + (e["offset"] as Vector2), float(e["radius"]), c)

	# THE CORE LAST AND SMALLEST, so the head is unambiguously the brightest pixel on the
	# badge -- which is what makes a player's eye go to where the countdown has got to.
	var at := centre + Vector2(cos(head), sin(head)) * radius
	draw_circle(at, SPARK_CORE_PX, Color(hot.r, hot.g, hot.b, 0.55))
	draw_circle(at, SPARK_CORE_PX * 0.55, Color.WHITE)


## Where the embers are at time `t`, as `{offset, radius, alpha}` with `offset` measured
## from the badge's centre.
##
## PURE AND PUBLIC so the geometry can be measured without a rendered frame: the property
## that actually matters here is that nothing escapes `SPARK_MAX_RADIUS`, and a `Control`
## does not clip its own `_draw` -- an ember a few pixels out lands on the resource
## counters, which is where 9.1's first version of this whole badge ended up.
##
## THE PHASES ARE EVENLY SPREAD AND WRAP, so the train is continuous rather than five dots
## appearing together and fading together.
static func spark_embers(t: float, radius: float, fraction: float,
		head: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# CLAMPED TO THE ARC THAT EXISTS. At 2% the drawn arc is ~0.13 rad, so a fixed 0.55 rad
	# trail would put four of the five embers anticlockwise of 12 o'clock -- ahead of the
	# gauge's own start, on track it will not reach until the very end.
	var trail := minf(SPARK_TRAIL_RAD, TAU * fraction)
	for i in range(SPARK_COUNT):
		var phase := fposmod(t / SPARK_PERIOD_SEC + float(i) / float(SPARK_COUNT), 1.0)
		var angle := head - trail * phase
		var out_px: float = SPARK_DRIFT_PX * float(SPARK_JITTER[i]) * phase
		var r := radius + out_px
		out.append({
			"offset": Vector2(cos(angle), sin(angle)) * r,
			# Shrinking as it fades, so an ember reads as burning out rather than as
			# being switched off.
			"radius": SPARK_EMBER_PX * (1.0 - 0.55 * phase),
			"alpha": 1.0 - phase,
		})
	return out


## The wall clock the spark runs on, in seconds. Its own function so the arithmetic above
## can be exercised at a chosen `t` -- `spark_embers` takes the time rather than reading
## it, which is what makes it assertable at all.
func _spark_time() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## Silently does nothing at the last age, or while an advance is already running,
## instead of emitting one the sim would reject anyway. AdvanceAgeCommand
## refuses both cases too -- this is the polite half, that one is the enforcing
## half, and they must agree.
func _on_pressed() -> void:
	if advancing:
		advance_unavailable.emit(&"advancing")
		return
	var next := next_age()
	if next == 0:
		advance_unavailable.emit(&"maxed")
		return
	advance_requested.emit(next)
