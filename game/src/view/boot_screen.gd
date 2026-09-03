## Splash/boot screen (PLAN.md 1.3): the title card, shown briefly before the
## main menu. Separate from `project.godot`'s own `boot_splash/image` --
## that one is the engine's native flicker-frame before ANY scene runs, too
## brief to control; this is a real scene with a timed hold and a tap to
## skip it, the same title art reused for a deliberate first impression.
## ## IT ALSO CHECKS FOR REQUIRED CONTENT, IN THE TIME IT WAS ALREADY SPENDING (0.3)
##
## PLAN.md 3.2 puts the pack check at boot. Doing it on its own screen would mean a screen
## that loads, finds nothing to do and flashes past on every launch; doing it HERE costs
## nothing, because the two-second title hold is dead time already.
##
## So the manifest request goes out as this scene appears, and where it goes next depends on
## the answer: `Download.tscn` if a required pack is missing, `MainMenu.tscn` otherwise. **A
## player who has everything never sees the download screen at all.**
##
## ⚠️ **THE CHECK HAS A BUDGET AND LOSING THE RACE IS NOT A FAILURE.** A phone on a dead
## network must not hold the splash for the manifest's full 15-second timeout, so if the
## answer has not arrived within `CHECK_BUDGET_SECONDS` the boot goes to the menu anyway.
## Nothing is lost: DOWNLOAD MORE on the campaign screen is the retry, and it lists a
## required pack that is missing for exactly this reason.
##
## `class_name` added 2026-09-03 so the suite can name the type and assert the routing.
## Nothing had referenced this script before -- it was only ever `Boot.tscn`'s -- and the
## §6.1 rule that autoloads must NOT carry one does not apply here: this is a scene script,
## not a singleton, so there is no identifier for it to shadow.
class_name BootScreen
extends Control

const HOLD_SECONDS := 2.0
const _SPLASH_PATH := "res://assets/ui/boot_splash.png"
const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _DOWNLOAD_SCENE := "res://scenes/menu/Download.tscn"

## How long the boot will wait for the manifest AFTER the title hold expires. Deliberately
## shorter than `PackInstaller.MANIFEST_TIMEOUT_SECONDS`: that one bounds the request, this
## one bounds how long a player stares at a splash because of it.
const CHECK_BUDGET_SECONDS := 2.5

var _advanced := false

var _installer: PackInstaller

## The manifest, once it lands. Null means "not back yet, or it failed" -- and those two are
## the same thing to this screen, which is why they share a variable.
var _manifest: PackManifest = null
var _check_settled := false
var _hold_expired := false

## Off in the suite, which builds this screen to assert the routing without a tree to
## change scenes in.
var auto_advance := true

## Where `PackIndex` is read -- a field so the suite never reads the developer's own
## installed state, which would make the routing test pass or fail depending on whose
## machine it ran on. `CampaignProgress`'s lesson, and `test_scenario_screen` learned the
## same one about progress.
var index_path: String = PackIndex.USER_FILE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color("#0E0A06")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var art := TextureRect.new()
	art.texture = load(_SPLASH_PATH)
	# LINEAR. This is the one site where NEAREST was worst: the splash is scaled to
	# FILL a phone, so it is magnified rather than reduced, and nearest-neighbour
	# magnification of a painted plate is visible stair-stepping on every edge.
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# ⚠️ EXPAND_IGNORE_SIZE IS THE FIX, AND `stretch_mode` NEVER WAS.
	#
	# The owner reported the splash "cutting off" on 2026-08-30, and the mode it was
	# set to -- KEEP_ASPECT_CENTERED -- cannot cut anything: it fits inside the rect
	# and pillarboxes. What was cutting it off was the RECT.
	#
	# `TextureRect` defaults to `EXPAND_KEEP_SIZE`, whose MINIMUM SIZE is the
	# texture's own -- 1376x768 here. A minimum size wins over anchors, so
	# PRESET_FULL_RECT did not make this control the size of the screen; it made it
	# 1376x768 pinned at the top-left of a viewport that is 1152x648 in the preview
	# and narrower still on a handset. The plate drew at 1:1 and the right-hand and
	# bottom thirds hung off the window. The photograph in `preview_menus` shows the
	# strapline sliced in half by the bottom edge, which is a crop no stretch mode
	# on this list produces.
	#
	# So: IGNORE_SIZE first, which lets the control actually be the screen, and then
	# STRETCH_SCALE, which fills it exactly and cuts nothing on any aspect. The
	# alternative once the rect is right is KEEP_ASPECT_CENTERED, which is honest to
	# the art and leaves ~140 px of dead background down each side of a 2.2 phone;
	# the owner asked for it stretched to fit. A two-second title card with no
	# readable geometry in it is the cheapest possible place to spend the distortion.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	# THE CONTENT CHECK, started as the splash appears. See the class comment.
	_installer = PackInstaller.new()
	add_child(_installer)
	_installer.manifest_ready.connect(_on_manifest)
	_installer.fetch_manifest()

	get_tree().create_timer(HOLD_SECONDS).timeout.connect(_on_hold_expired)


func _on_manifest(manifest: PackManifest) -> void:
	# ⚠️ KEPT EVEN WITH WARNINGS, and the first draft of this got it wrong by discarding any
	# manifest that had one. `PackManifest` reports a malformed ENTRY and keeps the rest --
	# one bad pack costs one pack -- so throwing the whole thing away would mean a typo in
	# some future community row silently stopped the tutorial from installing.
	#
	# An unreadable manifest needs no special case: it has no packs, so `_needs_download()`
	# answers false and the boot goes to the menu.
	_manifest = manifest
	_check_settled = true
	_maybe_advance()


func _on_hold_expired() -> void:
	_hold_expired = true
	# Start the budget only now, so a slow network costs at most this much VISIBLE delay
	# rather than delaying from the moment the scene loaded.
	if not _check_settled:
		get_tree().create_timer(CHECK_BUDGET_SECONDS).timeout.connect(_on_budget_expired)
	_maybe_advance()


func _on_budget_expired() -> void:
	# Losing the race is not a failure -- see the class comment.
	_check_settled = true
	_maybe_advance()


func _maybe_advance() -> void:
	if _hold_expired and _check_settled:
		_advance()


## A TAP SKIPS THE WAIT, NOT THE DOWNLOAD. If the manifest is already back and says
## something is missing, a tap still routes to the download screen -- a tap means "get on
## with it", not "skip the tutorial I do not have yet". If it has not arrived, the tap goes
## to the menu, because the alternative is a title card that ignores a finger.
func _gui_input(event: InputEvent) -> void:
	var tapped := (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed)
	if tapped:
		_advance()


func _advance() -> void:
	if _advanced:
		return          # the hold timer, the budget and a tap can all arrive; the first wins
	_advanced = true
	if not auto_advance:
		return
	if _needs_download():
		DownloadScreen.pending = _manifest
		get_tree().change_scene_to_file(_DOWNLOAD_SCENE)
		return
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


## Is any `required` pack missing or outdated? The whole of the routing decision, and it
## lives in `PackIndex` so it can be tested without a `SceneTree` -- see that function.
func _needs_download() -> bool:
	return PackIndex.any_required_missing(_manifest, index_path)


# ── readers, for the suite ───────────────────────────────────────────────────

## Which scene this boot would go to. Asserted directly, because the routing is the whole
## of what 0.3 added here and `change_scene_to_file` cannot be called without a tree.
func next_scene() -> String:
	return _DOWNLOAD_SCENE if _needs_download() else _MAIN_MENU_SCENE
