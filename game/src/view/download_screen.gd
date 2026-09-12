## The first-run download: fetches whatever is marked `required` before the front door
## opens (PLAN.md 3.2's *"boot -> check local versions against the manifest -> download
## missing -> verify checksum"*). Phase 0.3.
##
## ## ⚠️ IT IS NOT ON THE PATH IN THE STEADY STATE, AND THAT IS THE WHOLE DESIGN
##
## `BootScreen` starts the manifest check during the two seconds it already spends holding
## the title card -- dead time we were spending anyway -- and comes here **only if a
## required pack is actually missing**. A player who has everything never sees this screen
## at all, not even for a frame. The alternative was a screen that always loads, decides
## there is nothing to do, and flashes past; that is the version this replaced.
##
## ## NOTHING HERE MAY BLOCK THE GAME FROM STARTING
##
## PLAN.md 3.2: *"if a pack is absent or fails verification, the game runs on placeholders
## rather than failing"*. So every route out of this screen leads to the main menu:
##
##   - everything installed -> straight through, no interaction
##   - some pack failed -> the reason, and a CONTINUE button
##   - offline, or the manifest unreadable -> the same, said differently
##   - **a download the player does not want to wait for -> SKIP FOR NOW**
##
## A required campaign that never arrives leaves the campaign list empty, which
## `CampaignScreen` already has an honest empty state for, and DOWNLOAD MORE is the retry.
## **There is deliberately no way to get stuck here**, because a tutorial download failing
## must not cost somebody the skirmish they wanted to play.
##
## ⚠️ **AND THAT SENTENCE WAS ABOUT FAILURE ONLY, WHICH STOPPED BEING ENOUGH ON 2026-09-12.**
## Every route above answers a download that *went wrong*. None of them answered one that is
## simply going to take an hour -- and until the art pack there was no such thing: the whole
## required set was one 2.2 MB campaign, so the screen was over before a player could want
## out of it. `art_base_v1.zip` is **80 MB**, which on a handset is minutes at best and well
## over an hour on the 125 kbps connection 0.3 was deliberately tested against.
##
## So SKIP FOR NOW is not a new idea, it is this screen's own rule extended to the case that
## now exists. `PackInstaller.cancel()` was written for it from the start -- `_download()`'s
## comment calls it *"the player's escape"* -- and **nothing had ever called it.** Same shape
## as §6's rule about a guard that can be left out: the escape existed, was documented, and
## was unreachable.
##
## **Skipping is recoverable and that is what makes it safe to offer**: `ContentBrowser`
## lists a required pack that is not installed, so DOWNLOAD MORE is the retry for art exactly
## as it is for a failed campaign. Until then the game runs on placeholders, which PLAN.md
## 3.2 makes a supported state rather than a broken one.
##
## ## THE MANIFEST IS HANDED OVER, NOT RE-FETCHED
##
## `ScenarioScreen.pending`'s pattern: a `PackManifest` is a live object, not a path, so it
## cannot travel through `change_scene_to_file`. `BootScreen` parks it here. One-shot --
## taken and cleared in `_init()` -- so entering this scene with nothing parked (a preview,
## or a deep link) fetches its own rather than showing an empty screen.
class_name DownloadScreen
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

## `CampaignScreen`'s palette and `BootScreen`'s ground, so this reads as part of the boot
## rather than as a page of the menu.
const _GROUND := Color(0.05490196, 0.039215688, 0.023529412, 1.0)
const _PARCHMENT := Color(0.9372549, 0.8784314, 0.7529412, 1.0)
const _GOLD := Color(0.8980392, 0.7215686, 0.25882354, 1.0)

## Set by `BootScreen`. See the class comment: taken and cleared in `_init()`.
static var pending: PackManifest = null

var _heading: Label
var _status: Label
var _bar: ProgressBar
var _continue_button: Button
var _skip_button: Button

var _installer: PackInstaller
var _manifest: PackManifest = null
var _failures: Array[String] = []

## The player pressed SKIP. Kept apart from `_failures` deliberately: a download somebody
## chose to stop is not something that went wrong, and reporting it on the
## "SOME CONTENT DID NOT DOWNLOAD" screen would tell them their own decision was an error.
var _skipped := false

## Where `PackIndex` is read and written -- a field so the suite never touches the
## developer's own installed state (`CampaignProgress`'s lesson).
var index_path: String = PackIndex.USER_FILE

var manifest_url: String = PackManifest.MANIFEST_URL

## Off in tests and previews, so a headless run can inspect the finished state instead of
## having the scene changed out from under it.
var auto_advance := true


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_manifest = pending
	pending = null

	var bg := ColorRect.new()
	bg.color = _GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	_heading = Label.new()
	_heading.text = "GETTING READY"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_color_override("font_color", _GOLD)
	UiFont.title(_heading, 28, true)
	column.add_child(_heading)

	_status = Label.new()
	_status.text = "Checking for content..."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", _PARCHMENT)
	column.add_child(_status)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.max_value = 100.0
	_bar.value = 0.0
	# The percentage is in `_status` with the pack's name beside it, which is more use than
	# a bare number floating in the bar.
	_bar.show_percentage = false
	column.add_child(_bar)

	# Hidden until there is something to acknowledge. A CONTINUE button on a screen that is
	# about to advance on its own invites a player to press it and then wonder whether they
	# interrupted something.
	_continue_button = Button.new()
	_continue_button.text = "CONTINUE"
	_continue_button.custom_minimum_size = Vector2(220, 58)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiFont.title(_continue_button, 22)
	_continue_button.visible = false
	_continue_button.pressed.connect(_go_to_menu)
	column.add_child(_continue_button)

	# SKIP, shown only once a download is actually running. Hidden before that for
	# `_continue_button`'s reason turned around: on a screen that is still deciding whether
	# there is anything to fetch, an escape hatch invites somebody to flee a wait that may
	# not be about to happen.
	_skip_button = Button.new()
	_skip_button.text = "SKIP FOR NOW"
	_skip_button.custom_minimum_size = Vector2(220, 58)
	_skip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiFont.title(_skip_button, 22)
	_skip_button.visible = false
	_skip_button.pressed.connect(_on_skip)
	column.add_child(_skip_button)


func _ready() -> void:
	_installer = PackInstaller.new()
	add_child(_installer)
	_installer.pack_started.connect(_on_started)
	_installer.pack_progress.connect(_on_progress)
	_installer.pack_finished.connect(_on_finished)
	run()


## Do the work. Public so a preview and the suite can drive it without a boot.
func run() -> void:
	if _manifest == null:
		_status.text = "Checking for content..."
		_manifest = await _installer.fetch_manifest(manifest_url)

	for w in _manifest.warnings:
		push_warning("packs.json: " + w)

	var wanted: Array[PackDef] = []
	for pack in _manifest.required_packs():
		if PackIndex.needs_download(pack, index_path):
			wanted.append(pack)

	if wanted.is_empty():
		# Either everything is present, or the manifest could not be read at all. The two
		# are told apart for the player's benefit: "nothing to do" should not be reported
		# as an error, and an unreadable manifest should not be reported as success.
		if _manifest.warnings.is_empty():
			_finish()
		else:
			_heading.text = "COULD NOT CHECK FOR CONTENT"
			_status.text = ("%s\n\nThe game will start with whatever is already installed."
					% _manifest.warnings[0])
			_bar.visible = false
			_offer_continue()
		return

	await _installer.install_all(wanted, index_path)
	_finish()


func _on_started(pack: PackDef) -> void:
	_status.text = "Downloading %s... (%s)" % [pack.label(), pack.size_text()]
	_bar.value = 0.0
	# THE SIZE IS IN THE STATUS LINE FROM THE FIRST FRAME, and that is the other half of
	# offering a skip: "Downloading Game art..." gives a player nothing to decide with, and
	# the manifest has known the figure all along. `size_text()` is the browser's own
	# formatting, so the number here and the number in DOWNLOAD MORE cannot disagree.
	_skip_button.visible = not _skipped


## `total` is 0 until `Content-Length` lands, so the bar is INDETERMINATE until then rather
## than sitting at 0% -- a bar pinned at zero for the first second of every download reads
## as a stall. `ProgressBar` has no indeterminate mode, so it is hidden instead and the
## status line carries megabytes until a total is known.
func _on_progress(pack: PackDef, bytes: int, total: int) -> void:
	if total > 0:
		_bar.visible = true
		_bar.value = 100.0 * bytes / total
		_status.text = "Downloading %s... %d%% of %s" % [pack.label(), int(_bar.value),
				pack.size_text()]
	else:
		_bar.visible = false
		_status.text = "Downloading %s... %.1f MB of %s" % [pack.label(),
				float(bytes) / 1048576.0, pack.size_text()]


## Stop at the next boundary and go. `cancel()` is checked between packs and between steps
## rather than mid-write, so this never leaves a half-unpacked directory behind -- which is
## why the screen does not change until the installer says it has stopped.
func _on_skip() -> void:
	_skipped = true
	_skip_button.visible = false
	_status.text = "Stopping..."
	# `_installer` is built in `_ready()`, so it is null on a screen that was constructed and
	# never entered a tree -- which is every headless test of this file, and `_go_to_menu`'s
	# `auto_advance` guard exists for the same reason. The FLAG is what the rest of the class
	# reads; cancelling is what it does to a download that is actually running.
	if _installer != null:
		_installer.cancel()


func _on_finished(pack: PackDef, ok: bool, message: String) -> void:
	# A cancelled pack reports `ok == false` with "cancelled", which is correct for the
	# installer and wrong for this screen: it would put the player's own choice on the
	# SOME CONTENT DID NOT DOWNLOAD page as though something had broken.
	if not ok and not _skipped:
		_failures.append("%s: %s" % [pack.label(), message])


func _finish() -> void:
	if _skipped or _failures.is_empty():
		_go_to_menu()
		return

	# SAY WHAT FAILED AND WHY, then let them past. The installer's messages are specific --
	# "download is N bytes, manifest says M" -- and repeating them here is the only place a
	# player ever sees them.
	_heading.text = "SOME CONTENT DID NOT DOWNLOAD"
	_status.text = "\n".join(_failures) + "\n\nYou can try again from DOWNLOAD MORE on the campaign screen."
	_bar.visible = false
	_offer_continue()


func _offer_continue() -> void:
	_continue_button.visible = true
	# Two buttons on a finished screen is one too many, and SKIP would now mean nothing.
	_skip_button.visible = false
	if auto_advance:
		# Focus it, so the button a player is being asked to press is the one a hardware
		# key or a controller lands on.
		_continue_button.grab_focus()


func _go_to_menu() -> void:
	if not auto_advance:
		return
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


# ── readers, for the suite ───────────────────────────────────────────────────

func failures() -> Array[String]:
	return _failures


func showing_continue() -> bool:
	return _continue_button.visible


## Exposed rather than left to a test to reach into `_skip_button`, on 16.3's lesson about
## the owner picker: **a control's state is a fact a test must be able to compare against
## the field behind it**, or the two drift and no check can see it.
func showing_skip() -> bool:
	return _skip_button.visible


func skipped() -> bool:
	return _skipped


## Press SKIP the way a finger would. For the suite and `preview_touch_controls`' rule --
## a `BaseButton` answers a raw touch, so this control needs no `TouchSlider` treatment.
func press_skip() -> void:
	_skip_button.pressed.emit()


func status_text() -> String:
	return _status.text
