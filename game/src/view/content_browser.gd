## DOWNLOAD MORE -- the list of content on the server a player can pick from (PLAN.md 3.2,
## 3.3). Phase 0.3, and the owner's ask on 2026-09-03: *"lets add a download more button
## with a list of content on the server for them to pick from"*.
##
## Reached from `CampaignScreen`'s footer, beside BACK.
##
## ## WHAT IT LISTS, AND WHY THAT IS NOT SIMPLY "THE OPTIONAL PACKS"
##
## Optional packs, **plus any REQUIRED pack that is not installed**. The second half is the
## one worth arguing: a required pack is fetched at boot with nobody asked, so listing it
## once it is present would be clutter -- but a boot download that FAILED (offline first
## run, server down, a phone that lost signal at the wrong moment) would otherwise be
## invisible and unrecoverable. There would be no button anywhere in the game to try again,
## and the front door would show an empty campaign list forever.
##
## So a missing required pack appears here with the same GET button as anything else. That
## is the manual retry, and it costs one predicate.
##
## ## THE SCREEN IS BUILT IN `_init()`
##
## `CampaignScreen`'s pattern and for its reason: the rows are DATA fetched at runtime, so a
## `.tscn` could not hold this list even in principle, and `_init()` is what makes the whole
## screen testable without a `SceneTree`.
##
## ## ⚠️ THE MANIFEST IS FETCHED, SO THIS SCREEN HAS A LOADING STATE AND A FAILED STATE
##
## Three states, and conflating any two of them wastes somebody's afternoon:
##
##   - **checking** -- the request is out. Says so, because a blank list mid-fetch reads as
##     "there is nothing".
##   - **failed** -- no answer, or a manifest this build cannot read. Says WHICH, because
##     "offline" and "the server is serving something wrong" want different responses.
##   - **empty** -- the manifest was read and has nothing to offer. This is the ordinary
##     state today, with one campaign published and that one required.
class_name ContentBrowser
extends Control

## Emitted once the manifest has been fetched and the rows rebuilt. **Await this rather than
## calling `refresh()` a second time** -- see that function's note.
signal refreshed(pack_count: int)

const _CAMPAIGN_SCENE := "res://scenes/menu/Campaign.tscn"

## `CampaignScreen`'s palette, so the pages behind the front door are one room.
const _GROUND := Color(0.16862746, 0.11372549, 0.078431375, 1.0)
const _PARCHMENT := Color(0.9372549, 0.8784314, 0.7529412, 1.0)
const _GOLD := Color(0.8980392, 0.7215686, 0.25882354, 1.0)
const _DIM := Color(0.6, 0.5372549, 0.4392157, 1.0)

const ROW_HEIGHT := 96

var _list: VBoxContainer
var _status: Label
var _back_button: Button
var _toast: NoticeToast

var _installer: PackInstaller
var _manifest: PackManifest = null
var _rows: Array[Control] = []

## The pack being downloaded right now, or null. One at a time, deliberately: two
## simultaneous downloads on a phone share one radio and finish later than two in sequence,
## and a single active job is also the only version of this screen whose progress line can
## be read at a glance.
var _busy: PackDef = null

## A manifest fetch is out. See `refresh()`.
var _fetching := false

## Pack ids installed during this visit, as a set. Keeps a just-installed required pack on
## screen as INSTALLED -- see `_offered_packs()`, where the reasoning is.
var _installed_here: Dictionary = {}

## Where `PackIndex` is read and written. A field so the suite can point the whole screen at
## a scratch file -- `CampaignProgress`'s lesson, which cost a false failure the day it was
## learned: a test must never touch the developer's own installed state.
var index_path: String = PackIndex.USER_FILE

## Set by the suite to skip the network. Nothing in the shipped build touches it.
var manifest_url: String = PackManifest.MANIFEST_URL


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = _GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	var heading := Label.new()
	heading.text = "DOWNLOAD MORE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", _GOLD)
	UiFont.title(heading, 30, true)
	page.add_child(heading)

	# A SCROLLCONTAINER FROM THE FIRST LINE. `CampaignScreen`'s note applies with more
	# force here: this list is as long as the server says it is, so "it fits today" is not
	# a fact about tomorrow.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", _PARCHMENT)
	page.add_child(_status)

	var footer := HBoxContainer.new()
	page.add_child(footer)
	_back_button = Button.new()
	_back_button.text = "BACK"
	_back_button.custom_minimum_size = Vector2(180, 58)
	UiFont.title(_back_button, 22)
	_back_button.pressed.connect(_on_back_pressed)
	footer.add_child(_back_button)

	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-NoticeToast.SIZE.x / 2.0, 24.0)
	add_child(_toast)

	_status.text = "Checking for content..."


func _ready() -> void:
	_installer = PackInstaller.new()
	add_child(_installer)
	_installer.pack_progress.connect(_on_progress)
	refresh()


## Fetch the manifest and rebuild the rows. Public so a test can drive it, and so the
## screen can be refreshed after an install without a scene change.
##
## ⚠️ **RE-ENTRANT CALLS ARE DROPPED, AND A CALLER SHOULD `await refreshed` INSTEAD.**
## `_ready()` starts one of these, so anything that also called `refresh()` used to make two
## requests on one `HTTPRequest` and get error 44 back -- reported to the player as "cannot
## reach the server", which is a lie about the network. `PackInstaller` now refuses that
## too; this stops it being asked.
func refresh() -> void:
	if _fetching:
		return
	_fetching = true
	_status.text = "Checking for content..."
	_clear_rows()
	_manifest = await _installer.fetch_manifest(manifest_url)
	_fetching = false

	for w in _manifest.warnings:
		push_warning("packs.json: " + w)

	_rebuild()
	refreshed.emit(_manifest.packs.size())


## Show a manifest this screen did not fetch. The seam the suite uses: `ContentBrowser` can
## be built with no `SceneTree` (nothing in `_init()` needs one), so given a manifest it can
## have its whole row-state rule asserted headlessly -- which is where the vanishing-row bug
## should have been caught.
func show_manifest(manifest: PackManifest) -> void:
	_manifest = manifest
	_rebuild()


func _rebuild() -> void:
	_clear_rows()
	if _manifest == null:
		return

	var offered := _offered_packs()
	for pack in offered:
		var row := _build_row(pack)
		_rows.append(row)
		_list.add_child(row)

	if not offered.is_empty():
		_status.text = ""
	elif not _manifest.warnings.is_empty():
		# FAILED, not empty -- see the class comment. The first warning is the actionable
		# one; the rest are in the log.
		_status.text = "Could not read the content list.\n%s" % _manifest.warnings[0]
	else:
		_status.text = "There is no new content to download right now."


## Optional packs, plus any required pack that is missing, plus anything installed during
## THIS visit. See the class comment for the first two.
##
## ⚠️ **THE THIRD CLAUSE IS A UX FIX AND IT IS NOT COSMETIC.** Without it, pressing GET on
## the only published pack made the row VANISH and the screen read "There is no new content
## to download right now" -- because the pack is `required`, and a required pack that is
## installed is filtered out as clutter. Both halves were behaving as designed and the
## result told the player their download had failed. The toast saying otherwise fades after
## a few seconds; the empty list does not.
##
## Session-scoped rather than persisted, deliberately: on the NEXT visit the row is gone
## again, which is the clutter rule doing its job. What must not happen is a screen changing
## from "here is a thing" to "there is nothing" as the direct result of a successful press.
func _offered_packs() -> Array[PackDef]:
	var out: Array[PackDef] = []
	for pack in _manifest.packs:
		if pack.required and not PackIndex.needs_download(pack, index_path) \
				and not _installed_here.has(pack.id):
			continue
		out.append(pack)
	return out


## One pack: title and author top, description under it, and a verb on the right.
##
## NOT A `Button` THE WAY A CAMPAIGN ROW IS. `CampaignScreen`'s rows are buttons because
## the whole row means one thing -- open this campaign. A row here carries TWO verbs (get
## and delete), so the row is a panel and the buttons are buttons; making the row itself
## pressable would leave a player guessing which of the two a tap on the description meant.
func _build_row(pack: PackDef) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	row.add_child(box)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(text)

	var title := Label.new()
	title.text = pack.label()
	title.add_theme_color_override("font_color", _GOLD)
	UiFont.title(title, 22)
	text.add_child(title)

	# Author and size on one line. The size is here rather than beside the button because a
	# player deciding whether to spend mobile data wants it next to the name, and `author`
	# is what makes community content attributable.
	var by := Label.new()
	var bits: Array[String] = []
	if not pack.author.is_empty():
		bits.append(pack.author)
	bits.append(pack.size_text())
	by.text = "  ·  ".join(bits)
	by.add_theme_color_override("font_color", _DIM)
	text.add_child(by)

	if not pack.description.is_empty():
		var blurb := Label.new()
		blurb.text = pack.description
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.add_theme_color_override("font_color", _PARCHMENT)
		text.add_child(blurb)

	var verbs := VBoxContainer.new()
	verbs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(verbs)
	verbs.add_child(_build_action(pack, row))

	return row


## The right-hand verb, which is the whole state machine of a row.
func _build_action(pack: PackDef, row: Control) -> Control:
	var installed := PackIndex.is_installed(pack.id, index_path)
	var outdated := PackIndex.needs_download(pack, index_path)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)

	var action := Button.new()
	action.custom_minimum_size = Vector2(150, 52)
	UiFont.title(action, 20)
	if not installed:
		action.text = "GET"
	elif outdated:
		action.text = "UPDATE"
	else:
		action.text = "INSTALLED"
		action.disabled = true
	# ⚠️ THE PACK AND THE ROW ARE BOUND, NOT LOOKED UP. A handler that searched
	# `_manifest.packs` for "the pressed one" would need an index, and an index into a list
	# that is rebuilt after every install is the bug `CampaignScreen` avoids by rebuilding
	# rows wholesale.
	if not action.disabled:
		action.pressed.connect(_on_get_pressed.bind(pack))
	stack.add_child(action)

	# DELETE ONLY FOR CONTENT, AND ONLY WHEN IT IS THERE. A mounted pack cannot be
	# un-mounted -- Godot has no `unload_resource_pack()` -- so a delete button on art
	# would need a restart to mean anything, and `PackInstaller.uninstall()` refuses it.
	# A required pack is not deletable either: the game would re-fetch it on the next boot,
	# so the button would appear to do nothing.
	if installed and pack.installs() and not pack.required:
		var remove := Button.new()
		remove.text = "DELETE"
		remove.custom_minimum_size = Vector2(150, 44)
		UiFont.title(remove, 18)
		remove.pressed.connect(_on_delete_pressed.bind(pack))
		stack.add_child(remove)

	return stack


## GET or UPDATE. Public-by-convention despite the underscore so `preview_content_browser`
## can press it: a preview that reached past this into `PackInstaller.install()` would skip
## the busy guard, the toast and `_installed_here`, and it did -- which is how the vanishing
## row survived a passing preview run.
func _on_get_pressed(pack: PackDef) -> void:
	if _busy != null:
		_toast.show_message("One download at a time. %s is still going." % _busy.label())
		return
	_busy = pack
	_status.text = "Downloading %s..." % pack.label()

	var ok: bool = await _installer.install(pack, index_path)
	_busy = null

	if ok:
		_installed_here[pack.id] = true
		_toast.show_message("%s installed." % pack.label())
		_status.text = ""
	else:
		# The installer's own complaint is the useful text, and it is already specific --
		# "download is N bytes, manifest says M" rather than "failed".
		_toast.show_message("%s did not install." % pack.label())

	# Rebuild rather than patch the one row: an install changes what `PackIndex` says, and
	# every row's verb is derived from that.
	_rebuild()


func _on_delete_pressed(pack: PackDef) -> void:
	if _busy != null:
		return
	if _installer.uninstall(pack, index_path):
		_toast.show_message("%s removed." % pack.label())
	else:
		_toast.show_message("Could not remove %s." % pack.label())
	_rebuild()


## Live bytes. `total` is 0 until `Content-Length` arrives, which is why this reports MB
## rather than a percentage until it does -- a percentage of an unknown total is the
## classic divide-by-zero in a progress UI, and "0%" for the first second of every
## download reads as a stall.
func _on_progress(pack: PackDef, bytes: int, total: int) -> void:
	if total > 0:
		_status.text = "Downloading %s... %d%%" % [pack.label(), int(100.0 * bytes / total)]
	else:
		_status.text = "Downloading %s... %.1f MB" % [pack.label(), float(bytes) / 1048576.0]


func _clear_rows() -> void:
	# `free()` and not `queue_free()`, and detach first: `CampaignScreen.reload()`'s note.
	# A deferred free needs a tree to process it and this screen is built without one all
	# through the suite, so `queue_free` would leave the old rows in place and double the
	# list on the next rebuild.
	for row in _rows:
		_list.remove_child(row)
		row.free()
	_rows.clear()


## BACK. The one thing here that touches the tree, so it is not exercised in the suite --
## `test_help_screen`'s and `test_pause_menu`'s reason.
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_CAMPAIGN_SCENE)


## The line under the list. Read by the suite, because the three states this screen has --
## checking, failed, and genuinely empty -- are distinguishable ONLY by this text, and
## conflating any two of them is the fault the tests are guarding.
func status_text() -> String:
	return _status.text


## For the suite: the rows currently on screen, so a test can assert what is offered
## without reaching into the container.
func offered_ids() -> Array[String]:
	var out: Array[String] = []
	if _manifest == null:
		return out
	for p in _offered_packs():
		out.append(p.id)
	return out
