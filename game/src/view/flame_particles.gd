## Fire, as particles. The one place that knows what flame looks like in this game
## (PLAN.md 13.4, owner's ask 2026-09-06).
##
## Two customers and they are deliberately built by the same factory, because two
## independently-tuned fires would drift into two different fires: the dragon's breath
## landing on a patch of ground (`BlastEffects`) and a building burning down
## (`EntityView.set_burning`). One palette, one spark, one set of physics; the callers pass
## a size and a mode.
##
## ## ⚠️ THE SPARK IS GENERATED IN CODE AND MUST STAY THAT WAY
##
## `spark_texture()` paints a 32x32 radial falloff at load. It is **not** an asset, and that
## is a decision rather than a shortcut: a `res://assets/` PNG would put this feature behind
## the art agent's queue, add a row to `LICENCES.md` for a blurred dot, and put one more
## file in the APK -- for something four lines of `Image.set_pixel` produce exactly. It also
## cannot go missing, which matters more than it sounds: `GameDataRegistry.atlas_for` is
## total and answers a magenta placeholder box for anything unresolved, and a hundred
## magenta boxes fountaining out of a burning house is a worse bug report than no fire.
##
## Cached in a static, so the whole game shares one 4 KB texture rather than one per
## burning building.
##
## ## GPU RATHER THAN CPU PARTICLES, AS ASKED, AND THE ONE THING TO WATCH
##
## The owner asked for GPU particles by name and they are the right default: the work goes
## to the GPU, which on a phone is the half of the chip with room. ⚠️ **`GPUParticles2D`
## needs a compute-capable driver, and Godot's `gl_compatibility` renderer falls back to
## running them on the CPU** -- so on an old Android device this is quietly `CPUParticles2D`
## with extra steps rather than broken. Worth knowing before anybody blames a frame-rate
## report on the fire; `AMOUNT_*` below are sized so that the CPU path is survivable.
##
## ## COLOURS ARE A RAMP AND THE RAMP IS THE WHOLE LOOK
##
## A flame is not orange -- it is white-hot at the base, orange in the body and dark red as
## it dies, and reading that gradient is how an eye tells fire from a spray of confetti.
## `ParticleProcessMaterial.color_ramp` does it in one gradient, per particle, over its own
## lifetime, which is why there is no per-particle colour code anywhere here.
class_name FlameParticles
extends RefCounted

## Building fire: small, steady, and deliberately not a bonfire. It sits on a house that is
## still standing and still fighting, so it has to read at a glance without hiding the
## sprite or the health dot above it.
const AMOUNT_BUILDING := 14
const LIFETIME_BUILDING := 1.1

## The blast: one shot, everything at once, gone in a second. `explosiveness = 1.0` is what
## makes it a bang rather than a fountain -- every particle is emitted on the same frame.
const AMOUNT_BLAST := 64
const LIFETIME_BLAST := 0.9

## How far up a flame climbs, in pixels per second. Negative is up: this is screen space,
## not the isometric ground plane, and fire goes up the SCREEN regardless of which way the
## ground is facing.
const RISE := 52.0

## The spark, as a fraction of the emitter's own size. Kept small: the look comes from many
## small embers, and a few large ones read as smoke.
const SPARK_SCALE_MIN := 0.35
const SPARK_SCALE_MAX := 0.9

static var _spark: ImageTexture = null


## A soft round ember, 32x32, white with an alpha falloff. Cached for the process.
##
## WHITE AND NOT ORANGE, because the colour comes from `color_ramp` and a texture that was
## already orange would multiply twice and lose the white-hot base entirely.
##
## The falloff is `(1 - r)^2` rather than linear: a linear ramp reads as a disc with a soft
## rim, and squaring it puts most of the brightness in the middle, which is what an ember
## looks like.
static func spark_texture() -> ImageTexture:
	if _spark != null:
		return _spark
	const SIZE := 32
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var mid := (SIZE - 1) * 0.5
	for y in range(SIZE):
		for x in range(SIZE):
			var d := Vector2(x - mid, y - mid).length() / mid
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_spark = ImageTexture.create_from_image(img)
	return _spark


## A building burning: a continuous emitter, sized to the art it sits on.
##
## `spread_px` is how wide the fire is at its base -- the building's own drawn width, so a
## town centre burns across its roof and a house burns across a house. The emitter is a flat
## BOX rather than a point for exactly that: a point source is a candle, and a candle on a
## 10x10 town centre reads as a bug.
static func building_fire(spread_px: float, height_px: float) -> GPUParticles2D:
	var p := _emitter(AMOUNT_BUILDING, LIFETIME_BUILDING, maxf(6.0, spread_px * 0.28))
	var mat: ParticleProcessMaterial = p.process_material
	mat.emission_box_extents = Vector3(maxf(4.0, spread_px * 0.3),
			maxf(2.0, height_px * 0.12), 0.0)
	# Steady rather than explosive: a building burns for as long as it is hurt.
	p.explosiveness = 0.0
	p.one_shot = false
	return p


## The dragon's breath landing: one shot over the whole blast square.
##
## ⚠️ **`span_tiles` IS THE SIM'S OWN BLAST SIZE AND MUST BE PASSED IN, NEVER GUESSED
## HERE.** `AbilitySystem._burn` damages a square of `radius * 2 + 1` tiles centred on the
## aim, and `radius` is `units.json`'s. A picture drawn at a size this file chose would be a
## view telling the player the wrong thing about where the damage went -- which is the one
## failure mode PLAN.md 4's invariant is about, arriving through decoration instead of
## through a rule.
##
## The extents are the ISO PROJECTION of that square: a `span x span` tile block projects to
## a diamond `span * TILE_SIZE.x` across and `span * TILE_SIZE.y` down, and a box emitter
## covering its bounding rect is close enough for fire -- the corners it over-fills are
## outside the diamond by less than a tile, and nothing about a fireball wants a hard edge.
static func blast(span_tiles: int) -> GPUParticles2D:
	var span := float(maxi(1, span_tiles))
	var p := _emitter(AMOUNT_BLAST, LIFETIME_BLAST, span * Iso.TILE_SIZE.x * 0.18)
	var mat: ParticleProcessMaterial = p.process_material
	mat.emission_box_extents = Vector3(span * Iso.TILE_SIZE.x * 0.5,
			span * Iso.TILE_SIZE.y * 0.5, 0.0)
	# EVERYTHING ON ONE FRAME, which is what makes it a hit rather than a fire.
	p.explosiveness = 1.0
	p.one_shot = true
	return p


## The parts both share. Separated so the two fires cannot drift apart -- see the header.
static func _emitter(amount: int, lifetime: float, spark_px: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.texture = spark_texture()
	# ADDITIVE, because fire is light and not paint: overlapping embers should brighten
	# each other rather than stack up into an opaque orange blob.
	var canvas := CanvasItemMaterial.new()
	canvas.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = canvas

	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# UP THE SCREEN. `direction` is a unit vector and `gravity` keeps pushing, so a flame
	# accelerates as it rises and thins out at the top the way a real one does.
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 25.0
	mat.initial_velocity_min = RISE * 0.4
	mat.initial_velocity_max = RISE
	mat.gravity = Vector3(0.0, -RISE * 0.7, 0.0)
	mat.scale_min = spark_px * SPARK_SCALE_MIN / 16.0
	mat.scale_max = spark_px * SPARK_SCALE_MAX / 16.0
	mat.color_ramp = _ramp()
	mat.angle_min = -180.0
	mat.angle_max = 180.0
	p.process_material = mat
	return p


## White-hot, orange, dark red, gone. See the header for why this is a ramp and not a
## colour.
static func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.98, 0.80, 1.0),
		Color(1.0, 0.70, 0.20, 0.95),
		Color(0.85, 0.25, 0.06, 0.55),
		Color(0.30, 0.06, 0.02, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex
