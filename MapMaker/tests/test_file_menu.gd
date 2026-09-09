## Card #93 — the File menu, Godot's stock dialogs, and the exit guard that did not exist.
##
## ## THE OWNER RULED FOR `PopupMenu` + `FileDialog`, WHICH TRADED A TESTABLE LIST FOR A `Window`
##
## 16.4a's Open dialog was an overlay `Control` **deliberately**, because *"half this tool's checks
## have no viewport"* — the suite drives `Editor` outside the tree — and its `ItemList` was
## therefore fully testable. A `FileDialog` is a `Window`: it cannot be popped here, cannot report
## itself visible, and browses the filesystem rather than a list this tool built.
##
## So the tests move to what is still checkable, and it is more than it sounds:
##
##   - **the dialogs' CONFIGURATION**, which is where the two decisions live that would be silently
##     wrong — the file mode (a map is a DIRECTORY) and the access mode (every map this tool opens
##     is outside `res://`);
##   - **the menu's ids**, because a separator occupies an index and carries no id;
##   - **`_on_dir_chosen`**, which is a plain function and carries the whole "is this a map"
##     question a browsable dialog created;
##   - **`request_exit`**, the guard that had no code at all before today;
##   - **`_dialog_open`**, which is why the `Ctrl+Z` modality test still works with a `Window`.
##
## What is NOT here: that the dialog appears, and that it is legible. `preview_editor` photographs
## it — an embedded subwindow does render into the parent viewport, which was measured rather than
## assumed.
extends TestCase

const EDITOR := preload("res://src/editor.gd")

var _editors: Array[Node] = []


func after_each() -> void:
	for e in _editors:
		e.free()
	_editors.clear()


func _open_editor() -> Node:
	var editor: Node = load("res://Editor.tscn").instantiate()
	# `_ready()` by hand: this harness has no tree, and that is the same path `run/main_scene`
	# takes. See `test_startup.gd`.
	editor._ready()
	_editors.append(editor)
	return editor


# ── the menu ────────────────────────────────────────────────────────────────

## Five items, and `New` is one of them.
##
## 📝 **THE OWNER'S MOCK SHOWED FOUR — Open, Save, SaveAs, Exit.** `New` is here anyway because
## dropping it would leave **no way to start a map**; it was a toolbar button until this change.
## Asserted by name so the departure is visible rather than implied, and so putting the button
## back is a decision somebody makes on purpose.
func test_the_file_menu_offers_every_file_action() -> void:
	var editor := _open_editor()
	var menu: PopupMenu = editor._file_menu.get_popup()
	var labels: Array[String] = []
	for i in menu.item_count:
		if not menu.is_item_separator(i):
			labels.append(menu.get_item_text(i))
	assert_eq(labels.size(), 5, "New, Open, Save, Save As, Exit — got %s" % [labels])
	for want in ["New", "Open", "Save", "Save As", "Exit"]:
		var found := false
		for got in labels:
			if got.begins_with(want):
				found = true
		assert_true(found, "no %s item — got %s" % [want, labels])


## ⚠️ THE ITEMS ARE ADDRESSED BY ID, NOT BY INDEX, AND A SEPARATOR IS WHY.
##
## `add_separator()` occupies an INDEX and carries no id, so anything keyed on position shifts the
## moment the menu grows a divider — and the divider is already there, before Exit. This is the
## same hazard `Tool.START`'s removal was: renumbering something other code compares by literal.
## `id_pressed` carries the id, so `_on_file_action` matches the enum.
func test_the_menu_is_keyed_by_id_and_a_separator_does_not_shift_them() -> void:
	var editor := _open_editor()
	var menu: PopupMenu = editor._file_menu.get_popup()
	var separators := 0
	for i in menu.item_count:
		if menu.is_item_separator(i):
			separators += 1
	assert_true(separators >= 1, "there is a divider before Exit")
	# EVERY ACTION'S ID RESOLVES TO AN ITEM, and the index it lands on is not the id.
	for id in [EDITOR.FileAction.NEW, EDITOR.FileAction.OPEN, EDITOR.FileAction.SAVE,
			EDITOR.FileAction.SAVE_AS, EDITOR.FileAction.EXIT]:
		var at := menu.get_item_index(int(id))
		assert_true(at >= 0, "action %d is not in the menu" % int(id))
		assert_eq(menu.get_item_id(at), int(id))
	# THE ONE THAT PROVES THE POINT: Exit's index is past the separator, so index != id.
	var exit_at := menu.get_item_index(int(EDITOR.FileAction.EXIT))
	assert_false(exit_at == int(EDITOR.FileAction.EXIT),
			"index and id happen to coincide — this test would not catch a shift")


## ⛔ FIRST IN THE ROW, WITH A DIVIDER AFTER IT — the owner, off a screenshot, 2026-09-09:
## *"File needs to be the 1st button on panel with a devider."*
##
## It shipped sixth, after `Name` and the two size boxes, which put the tool's only menu somewhere
## no application has ever put one. ⚠️ **AND THE DIVIDER IS NOT DECORATION:** with nothing between
## them, `File` sits immediately left of the `Name` field and reads as its CAPTION — exactly the
## way `Size` captions the spin boxes two controls along. The row teaches that pattern and then
## breaks it.
##
## Asserted on the menu's own parent rather than by walking down from the screen, so the check
## survives a reshuffle of the rows above it.
func test_the_file_menu_leads_its_row_and_a_divider_follows_it() -> void:
	var editor := _open_editor()
	var row: Node = editor._file_menu.get_parent()
	assert_true(row != null, "the menu is not in a row at all")
	assert_eq(row.get_child(0), editor._file_menu,
			"File is at index %d, not first" % editor._file_menu.get_index())
	assert_true(row.get_child(1) is VSeparator,
			"nothing divides the menu from the fields — File reads as the Name box's caption")
	# AND THE FIELDS ARE STILL THERE, after it. A row that lost its name box would pass the two
	# assertions above.
	assert_true(editor._name_field.get_index() > 1, "the name field moved out of this row")


# ── the dialogs' configuration ──────────────────────────────────────────────

## ⚠️ `FILE_MODE_OPEN_DIR`, BECAUSE A MAP IS A DIRECTORY OF TWO FILES.
##
## `map.json` plus `map.png`. A dialog filtered to `*.json` would have an author picking the file
## INSIDE the folder while `MapDocument.open()` takes the folder — so every pick would need
## trimming, and any other `map.json` on the disk would look openable.
func test_the_open_dialog_picks_a_directory_and_not_a_file() -> void:
	var editor := _open_editor()
	assert_eq(editor._open_win.file_mode, FileDialog.FILE_MODE_OPEN_DIR)


## ⚠️ `ACCESS_FILESYSTEM`, BECAUSE EVERY MAP THIS TOOL OPENS IS OUTSIDE `res://`.
##
## Repo-root `maps/`, `scenarios/`, and the GAME's `user://maps/` — which is a different directory
## from this project's `user://`, and is 16.4a's third root. `ACCESS_RESOURCES` can see none of
## them, and the symptom would be a dialog that opens on an empty tree with no error.
func test_both_dialogs_can_see_outside_the_project() -> void:
	var editor := _open_editor()
	for win in [editor._open_win, editor._save_win]:
		assert_eq(win.access, FileDialog.ACCESS_FILESYSTEM,
				"a resource-mode dialog cannot reach maps/ or scenarios/")


## Save As picks the PARENT, not a filename.
##
## `MapDocument.save_as()` creates `<parent>/<slug>` from the name field, so a save-FILE dialog
## would ask an author to name a file that never gets created, and the refusal that stops Save As
## replacing an existing map — which keys on the resulting folder — would be asked about the wrong
## path.
func test_save_as_asks_for_a_parent_directory() -> void:
	var editor := _open_editor()
	assert_eq(editor._save_win.file_mode, FileDialog.FILE_MODE_OPEN_DIR,
			"Save As chooses where a new folder goes")


## 📝 THE NATIVE DIALOG IS OFF, AND THAT IS FOR THE PREVIEW AS MUCH AS FOR THE THEME.
##
## A native dialog is drawn by the OS: it would ignore this tool's font and plate, and — the half
## that matters here — it would be **absent from `preview_editor`'s screenshots**, because a
## viewport capture cannot contain another process's window. Same structural blindness as the
## hardware cursor in 16.4e, which is why that one needed a printed report instead.
func test_the_dialogs_are_drawn_by_godot_so_a_screenshot_can_contain_them() -> void:
	var editor := _open_editor()
	for win in [editor._open_win, editor._save_win]:
		assert_false(win.use_native_dialog, "a native dialog cannot be photographed")


# ── modality, which is a bool here ──────────────────────────────────────────

## ⚠️ `_dialog_open` IS A FIELD BECAUSE A `Window` CANNOT ANSWER OUTSIDE A TREE.
##
## The `Ctrl+Z` guard has to know whether a modal is up, and `test_undo`'s
## `test_the_shortcut_is_ignored_while_the_open_dialog_is_up` drives it in this harness. Reading
## `_open_win.visible` there would answer false always, so the guard would look correct and be off
## in exactly the tests written to check it.
func test_the_tool_knows_a_dialog_is_up_without_a_viewport() -> void:
	var editor := _open_editor()
	assert_false(editor.dialog_is_up())
	editor.open_dialog()
	assert_true(editor.dialog_is_up(), "and this is what the Ctrl+Z guard reads")
	editor.close_dialog()
	assert_false(editor.dialog_is_up())


## Save As with no map says so rather than popping a dialog over nothing.
func test_save_as_with_no_document_does_not_open_a_dialog() -> void:
	var editor := _open_editor()
	editor._document = null
	editor.save_as_dialog()
	assert_false(editor.dialog_is_up())


# ── "is that folder actually a map" ─────────────────────────────────────────

## ⛔ THE FAULT THE STOCK DIALOG CREATED, AND THE ONLY THING THAT ANSWERS IT.
##
## 16.4a's list could offer **only** folders `MapSources` had already parsed, so *"that is not a
## map"* was unreachable by construction. A browsable dialog hands back any directory at all, and
## the very first thing an author will do is confirm one level too high — `maps/` itself, or a
## campaign folder rather than a scenario's.
##
## ⚠️ **THE DOCUMENT MUST BE UNTOUCHED**, which is 16.4a's own rule in one line: *"a partial load
## that silently shows an empty canvas over somebody's authored map is how a file gets overwritten
## with nothing."*
func test_a_directory_that_is_not_a_map_is_refused_and_changes_nothing() -> void:
	var editor := _open_editor()
	var before: MapDocument = editor.document()
	var name_before: String = editor._name_field.text
	# `user://` ALWAYS EXISTS AND NEVER HOLDS A MAP, so this needs no fixture on disk.
	editor._on_dir_chosen(ProjectSettings.globalize_path("user://"))
	assert_eq(editor.document(), before, "the open document must survive a bad pick")
	assert_eq(editor._name_field.text, name_before)
	# AND IT SAYS WHICH LEVEL IS WRONG. "Not a map" sends an author hunting; naming `map.json`
	# tells them they are one directory too high, which is the actual mistake nine times in ten.
	assert_true(editor._notice_label.text.contains("map.json"),
			"the notice must name what it looked for: %s" % editor._notice_label.text)


## A refused pick leaves the dialog up, so the next click can be the right folder.
func test_a_refused_pick_leaves_the_dialog_open() -> void:
	var editor := _open_editor()
	editor.open_dialog()
	editor._on_dir_chosen(ProjectSettings.globalize_path("user://"))
	assert_true(editor.dialog_is_up(), "an author is one click from the right folder")


# ── the exit guard, which had no code at all before today ───────────────────

## ⛔ `dirty` WAS CORRECT AND UNREAD. THIS IS THE FIRST THING THAT ACTS ON IT.
##
## 16.2a computes it properly — `UndoStack._clean_at`, with both cases that otherwise go on
## claiming "saved" tested by name — and the **only** reader was the status line's UNSAVED word.
## So the window's X was the cheapest way to lose work in this project, and since 16.4a made Save
## replace shipped campaign content in place, the same gesture could lose an afternoon.
##
## ⚠️ **WITH NO TREE THE GUARD REFUSES RATHER THAN QUITTING**, which is the safe direction: this
## branch is only reachable from a test or a headless run, and neither has anything to lose by
## staying. A guard whose failure mode is "quit anyway" is not a guard.
func test_exiting_with_unsaved_work_does_not_just_leave() -> void:
	var editor := _open_editor()
	editor.set_brush(SimMap.Terrain.ROCK)
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.apply_tool(Vector2i(5, 5))
	assert_true(editor.document().dirty, "there is work to lose")
	editor.request_exit()
	assert_true(editor._notice_label.text.to_upper().contains("UNSAVED"),
			"it has to say why it did not leave: %s" % editor._notice_label.text)


## A new map is dirty from the first frame, so the guard must not be *always* on either.
##
## `MapDocument.create()` sets `dirty` because the map exists nowhere on disk. That is correct and
## it means "no unsaved changes" is a state this tool reaches only after a save or an open — so
## this test drives it through `dirty` directly rather than by saving, which would write a folder.
func test_exiting_with_nothing_to_lose_is_not_blocked() -> void:
	var editor := _open_editor()
	editor.document().dirty = false
	editor._notice_label.text = ""
	editor.request_exit()
	assert_eq(editor._notice_label.text, "",
			"a clean map must not be told it has unsaved changes")


## ⚠️ THE WINDOW'S X AND THE MENU ITEM ARE ONE FUNCTION.
##
## Guarding only the menu item would be a guard on the route nobody takes — the exact shape of
## `if Net.host() != null and <rule>`, which shipped three dead refusals in the game because solo
## play never takes the branch that matters. `_notification` routes
## `NOTIFICATION_WM_CLOSE_REQUEST` to `request_exit()`, and `_ready()` turns off
## `auto_accept_quit` so the request is a question rather than a courtesy notice.
func test_the_window_close_request_goes_through_the_same_guard() -> void:
	var editor := _open_editor()
	editor.set_brush(SimMap.Terrain.ROCK)
	editor.set_tool(EDITOR.Tool.PAINT)
	editor.apply_tool(Vector2i(6, 6))
	editor._notice_label.text = ""
	editor._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_true(editor._notice_label.text.to_upper().contains("UNSAVED"),
			"the X must reach the guard, not bypass it: %s" % editor._notice_label.text)


## The unsaved-changes dialog does not default to discarding.
##
## A `ConfirmationDialog`'s OK takes Enter, and the whole point of this dialog is that somebody
## reached it by accident. "Save and exit" is a third button because the two-button form makes an
## author cancel, save, and then find Exit again.
func test_the_exit_question_offers_saving_and_does_not_default_to_discarding() -> void:
	var editor := _open_editor()
	var win: ConfirmationDialog = editor._exit_win
	assert_true(win.ok_button_text.to_lower().contains("discard"),
			"the OK button must say what it does: %s" % win.ok_button_text)
	assert_false(win.get_ok_button().text == "OK", "OK is not an answer to this question")


# ── the three roots, which a FileDialog cannot show at once ─────────────────

## ⚠️ THE REFUND FOR WHAT A `FileDialog` COSTS.
##
## 16.4a's list showed every map from three roots at once. A `FileDialog` starts in ONE directory,
## so scenario 4's map — the thing 16.10 exists to re-author — went from a row in a list to four
## levels of browsing. `jump_to_root()` is three buttons inside the dialog's own box.
func test_the_dialog_can_jump_to_the_maps_root() -> void:
	var editor := _open_editor()
	editor.open_dialog()
	assert_true(editor.jump_to_root(MapSources.Source.AUTHORED),
			"repo-root maps/ is the one root that always exists")
	assert_eq(editor._open_win.current_dir.simplify_path().rstrip("/"),
			editor.maps_dir().simplify_path().rstrip("/"))


## ⛔ THE DIALOG OPENS IN `maps/`, NOT IN THE PROJECT DIRECTORY.
##
## Found in the first screenshot and by nothing else: a `FileDialog` with no `current_dir` starts
## in the **project folder**, so the first Open showed an author `.godot`, `src`, `tests` and
## `project.godot` — the tool's own source, with not a map in sight. Every test passed, because
## there is nothing wrong with a dialog that opens somewhere.
func test_the_open_dialog_starts_where_the_maps_are() -> void:
	var editor := _open_editor()
	editor.open_dialog()
	assert_eq(editor._open_win.current_dir.simplify_path().rstrip("/"),
			editor.maps_dir().simplify_path().rstrip("/"),
			"the first Open must not land in the tool's own source tree")


## ⚠️ AND IT ONLY DOES THAT ONCE, WHICH IS THE OTHER HALF OF BEING RIGHT.
##
## Re-pointing it on every open would throw away wherever the author had browsed to — worse than
## the bug for anybody working outside `maps/`, and 16.10's whole job is re-authoring maps that
## live under `scenarios/`.
func test_the_dialog_remembers_where_the_author_browsed_to() -> void:
	var editor := _open_editor()
	editor.open_dialog()
	var elsewhere := ProjectSettings.globalize_path("user://")
	editor._open_win.current_dir = elsewhere
	editor.close_dialog()
	editor.open_dialog()
	assert_eq(editor._open_win.current_dir.simplify_path().rstrip("/"),
			elsewhere.simplify_path().rstrip("/"),
			"the second Open must not drag the author back to maps/")


## ⚠️ ASSIGNING `file_mode` OVERWRITES THE TITLE AND THE OK BUTTON.
##
## The first render came out headed *"Open a Directory"* with a button reading *"Select Current
## Folder"* — Godot's generic wording for the mode, silently replacing the strings set before it.
## Both describe the widget rather than the job. Pinned, because the order of two assignments is
## not something a reader would think to check.
func test_the_dialogs_say_what_they_are_for_and_not_what_they_are() -> void:
	var editor := _open_editor()
	assert_eq(editor._open_win.title, "Open a map")
	assert_false(editor._open_win.title.contains("Directory"),
			"the mode's generic title has overwritten ours — set it AFTER file_mode")
	assert_eq(editor._open_win.ok_button_text, "Open this map")
	assert_eq(editor._save_win.ok_button_text, "Save here")


## ⚠️ THE BUTTONS ARE FILLED ON OPEN, NOT AT CONSTRUCTION, AND THAT IS AN ORDERING BUG AVOIDED.
##
## `_ready()` runs `_build_ui()` **before** `_startup` is resolved — deliberately, so a directly
## opened screen still builds — and `MapSources.roots()` needs `_startup.root` to derive the GAME's
## `user://maps/` by reading `config/name` out of the game's `project.godot`. Building the buttons
## in `_build_dialogs()` would have asked with a null root and produced a permanently disabled
## button for the one root that is hardest to reach by browsing.
func test_the_root_buttons_are_built_from_the_roots_as_they_are_when_opened() -> void:
	var editor := _open_editor()
	# BEFORE ANY OPEN the row holds nothing -- which is the state that used to be permanent.
	assert_eq(editor._open_roots.get_child_count(), 0)
	editor.open_dialog()
	# A LABEL PLUS ONE BUTTON PER ROOT.
	var roots: int = editor._sources.roots(editor._startup.root).size()
	assert_eq(editor._open_roots.get_child_count(), roots + 1,
			"a 'Go to' label and one button per root")
	assert_true(roots >= 2, "there are three roots on a normal checkout, got %d" % roots)
