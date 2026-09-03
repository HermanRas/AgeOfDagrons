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
##
## A required campaign that never arrives leaves the campaign list empty, which
## `CampaignScreen` already has an honest empty state for, and DOWNLOAD MORE is the retry.
## **There is deliberately no way to get stuck here**, because a tutorial download failing
## must not cost somebody the skirmish they wanted to play.
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

var _installer: PackInstaller
var _manifest: PackManifest = null
var _failures: Array[String] = []

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
	_status.text = "Downloading %s..." % pack.label()
	_bar.value = 0.0


## `total` is 0 until `Content-Length` lands, so the bar is INDETERMINATE until then rather
## than sitting at 0% -- a bar pinned at zero for the first second of every download reads
## as a stall. `ProgressBar` has no indeterminate mode, so it is hidden instead and the
## status line carries megabytes until a total is known.
func _on_progress(pack: PackDef, bytes: int, total: int) -> void:
	if total > 0:
		_bar.visible = true
		_bar.value = 100.0 * bytes / total
		_status.text = "Downloading %s... %d%%" % [pack.label(), int(_bar.value)]
	else:
		_bar.visible = false
		_status.text = "Downloading %s... %.1f MB" % [pack.label(), float(bytes) / 1048576.0]


func _on_finished(pack: PackDef, ok: bool, message: String) -> void:
	if not ok:
		_failures.append("%s: %s" % [pack.label(), message])


func _finish() -> void:
	if _failures.is_empty():
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


func status_text() -> String:
	return _status.text
