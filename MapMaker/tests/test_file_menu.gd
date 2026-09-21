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

## Six items, and `New` is one of them.
##
## 📝 **THE OWNER'S MOCK SHOWED FOUR — Open, Save, SaveAs, Exit.** `New` is here anyway because
## dropping it would leave **no way to start a map**; it was a toolbar button until this change.
## Asserted by name so the departure is visible rather than implied, and so putting the button
## back is a decision somebody makes on purpose.
##
## ⚠️ **`Export Scenario…` IS THE SIXTH (16.8), AND IT IS A DEPARTURE FROM THE MOCK TOO.** It is a
## file command — it writes, to a second place, in a second format — so it belongs with the others
## rather than beside `Conditions…`, which is one of the three controls that say what the map *is*.
##
## ⛔ **THE COUNT IS ASSERTED AS WELL AS THE NAMES, AND THAT IS WHY THIS TEST EARNED ITS KEEP
## TODAY**: it is what turned adding a menu item into a decision rather than a diff nobody read.
## A names-only test would have gone green on a menu with two Exits in it.
func test_the_file_menu_offers_every_file_action() -> void:
	var editor := _open_editor()
	var menu: PopupMenu = editor._file_menu.get_popup()
	var labels: Array[String] = []
	for i in menu.item_count:
		if not menu.is_item_separator(i):
			labels.append(menu.get_item_text(i))
	assert_eq(labels.size(), 6,
			"New, Open, Save, Save As, Export Scenario, Exit — got %s" % [labels])
	for want in ["New", "Open", "Save", "Save As", "Export Scenario", "Exit"]:
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


# ── what the owner's testing pass found ─────────────────────────────────────

## ⛔ **THE FAVOURITES PANEL WAS EMPTY.** The owner, testing card #93, 2026-09-09: *"Open Map fav
## does not show the standard 3 locations."*
##
## Nothing had ever written to it. The tool's answer to "where are the maps" was the `Go to` row at
## the BOTTOM of the dialog, and **Favorites is the panel Godot puts at the top left with a star on
## it** — the first place a person looks. One control in the place nobody looks is worse than two
## controls for one job.
##
## ⚠️ **MERGED, NOT ASSIGNED, AND THAT IS THE HALF WORTH A TEST.** `set_favorite_list()` replaces
## the whole list and the dialog has its own star button, so seeding on every open could silently
## delete a folder the author had favourited — the same class of thing as the start wiping a wall
## across the map, which this same testing pass found an hour earlier.
func test_the_dialogs_offer_the_map_roots_as_favourites_without_eating_the_authors() -> void:
	var editor := _open_editor()
	var mine := "C:/somewhere/the/author/starred"
	editor._open_win.set_favorite_list(PackedStringArray([mine]))
	editor._seed_favourites(editor._open_win)
	var got: PackedStringArray = editor._open_win.get_favorite_list()
	# ⚠️ **GODOT STORES A FAVOURITE WITH A TRAILING SLASH**, measured here: this assertion read
	# `got.has(mine)` and failed against `"C:/somewhere/the/author/starred/"`. That is precisely
	# why `_seed_favourites()` compares on a stripped path — a plain `in` test would re-add every
	# root on every open and grow the list forever. Kept as a note because the naive form looks
	# correct and passes nothing.
	assert_true(_favourited(got, mine), "the author's own favourite was deleted: %s" % [got])
	# EVERY ROOT THAT EXISTS IS THERE. A root that does not exist is deliberately absent -- see
	# the test below.
	var roots := 0
	for entry in editor._sources.roots(editor._startup.root):
		var path := str(entry["path"]).simplify_path().trim_suffix("/")
		if not DirAccess.dir_exists_absolute(path):
			continue
		roots += 1
		assert_true(_favourited(got, path), "%s is a map root and is not in Favorites" % path)
	assert_true(roots >= 2, "this machine should have at least the authored and campaign roots")
	# AND SEEDING TWICE DOES NOT DUPLICATE, because it runs on every open.
	var before: int = got.size()
	editor._seed_favourites(editor._open_win)
	var again: PackedStringArray = editor._open_win.get_favorite_list()
	assert_eq(again.size(), before,
			"a second open added the roots again")


## Is `path` in the list, ignoring the trailing slash Godot adds when it stores one?
func _favourited(list: PackedStringArray, path: String) -> bool:
	var want := path.simplify_path().trim_suffix("/")
	for f in list:
		if str(f).simplify_path().trim_suffix("/") == want:
			return true
	return false


## ⚠️ A FAVOURITE POINTING AT A MISSING DIRECTORY IS A DEAD ENTRY NOBODY CAN TELL FROM A LIVE ONE.
##
## The game's `user://maps/` does not exist until somebody saves a map from a match, and Godot's
## favourites list has no disabled state — so the root is omitted rather than listed dead. That is
## the same answer the `Go to` buttons give by being DISABLED with the path in their tooltip: both
## controls say "this root is not available", in the only way each can.
func test_a_root_that_does_not_exist_is_not_offered_as_a_favourite() -> void:
	var editor := _open_editor()
	editor._open_win.set_favorite_list(PackedStringArray())
	editor._seed_favourites(editor._open_win)
	var got: PackedStringArray = editor._open_win.get_favorite_list()
	assert_true(got.size() > 0, "nothing was seeded at all")
	for f in got:
		assert_true(DirAccess.dir_exists_absolute(str(f).trim_suffix("/")),
				"%s is favourited and is not there" % f)


## ⛔ **`map.png` WAS LISTED BESIDE `map.json` IN EVERY MAP FOLDER.** The owner, same pass: *"does
## not filter to .json files only."*
##
## 📝 **IT IS A LEGIBILITY FIX AND NOT A SELECTION FIX.** In `FILE_MODE_OPEN_DIR` the files are
## listed for context and cannot be picked — the OK button returns the DIRECTORY. So the filter
## changes what an author reads, and the surviving `map.json` is the signal wanted: a folder showing
## one is a map. Verified in a photograph of the dialog inside `maps/sample_duel`, because whether
## `add_filter` reaches the list in a directory mode is an engine behaviour and not a promise.
##
## Asserted on BOTH dialogs, so they read alike.
func test_both_dialogs_list_only_a_maps_own_data_file() -> void:
	var editor := _open_editor()
	for win in [editor._open_win, editor._save_win]:
		var filters: PackedStringArray = (win as FileDialog).filters
		assert_eq(filters.size(), 1, "expected one filter, got %s" % [filters])
		assert_true(str(filters[0]).begins_with("*.json"),
				"the filter is not the map's data file: %s" % filters[0])
		# AND THE MODE IS STILL A DIRECTORY MODE, which is what makes the filter cosmetic. A
		# switch to OPEN_FILE to make the filter "do something" is the tempting wrong fix.
		assert_eq((win as FileDialog).file_mode, FileDialog.FILE_MODE_OPEN_DIR,
				"a map is a directory of two files — see `_on_dir_chosen`")


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


# ── the keyboard route to all four (board `16.x-shortcuts`) ─────────────────

## ⛔ **THE CARD'S ONE HARD RULE: A KEY MUST NOT BE A SECOND DOOR.** Each arm of `_input` calls
## `_on_file_action`, which **is** the menu's `id_pressed` handler — not `save()` and friends
## behind it. So these tests assert the key reaches the same ACTION the menu item does; what
## that action then does is the business of the tests above.
##
## 📝 Driven straight at `_input`, as `test_undo` does. The ordering that makes `_input` the
## right binding is Godot's and is argued in the function's header; what is pinned here is that
## the keys are bound at all and land on the right actions.
func test_ctrl_n_starts_a_new_map() -> void:
	var editor := _open_editor()
	# ⚠️ **TYPED, NOT INFERRED.** `Editor.tscn`'s root has no `class_name`, so `_open_editor()`
	# hands back a bare `Node` and every call on it returns untyped `Variant` — `:=` cannot
	# infer from that, and the whole file then fails to parse rather than this one line.
	var before: MapDocument = editor.document()
	editor._input(_key(KEY_N))
	assert_true(editor.document() != before, "Ctrl+N did not replace the document")


func test_ctrl_o_raises_the_open_dialog() -> void:
	var editor := _open_editor()
	assert_false(editor.dialog_is_up(), "nothing is up to begin with")
	editor._input(_key(KEY_O))
	assert_true(editor.dialog_is_up(), "Ctrl+O did not reach open_dialog()")


## ⚠️ **SHIFT IS THE WHOLE DIFFERENCE BETWEEN SAVE AND SAVE AS**, and getting it backwards
## would overwrite the map an author meant to copy — so both halves are asserted, not just
## that the key did something. `save_as_dialog()` raises a dialog; `save()` never does.
func test_ctrl_shift_s_is_save_as_and_plain_ctrl_s_is_not() -> void:
	var editor := _open_editor()
	editor._input(_key(KEY_S, true))
	assert_true(editor.dialog_is_up(), "Ctrl+Shift+S did not reach save_as_dialog()")

	# ⚠️ **NAMELESS ON PURPOSE.** The name field defaults to "New Map", so a plain Ctrl+S on a
	# fresh editor would write a real `maps/new_map` folder into the repo — and `maps/` is
	# authored content, not a scratch directory (owner, 2026-09-04). Blanking the name makes
	# `save()` refuse before it writes, which does not weaken the assertion: what is being
	# checked is that no DIALOG was raised, and `save()` raises none at any point.
	var other := _open_editor()
	other._name_field.text = ""
	other.document().map_name = ""
	other._input(_key(KEY_S))
	assert_false(other.dialog_is_up(),
			"plain Ctrl+S must SAVE, not open the Save As browser")


## ⛔ **CTRL+S REACHES `save()` — PROVEN BY ITS REFUSAL, WHICH WRITES NOTHING.**
##
## The map is left nameless on purpose. `MapDocument.save()` refuses that with *"the map needs
## a name before it can be saved"* and `_report_save` puts it on the notice line, so the key is
## shown to have reached the real save path **without creating a folder in the repo's `maps/`** —
## which is authored content and not a scratch directory (owner, 2026-09-04).
##
## 📝 And it is the reason `Ctrl+S` needs no "Save As if never saved" special case: `save()`
## derives `maps/<slug>` from the name itself when `dir` is empty, so the only thing standing
## between a brand-new map and a plain Ctrl+S is having named it — which this refusal says.
func test_ctrl_s_reaches_the_real_save_and_refuses_a_nameless_map() -> void:
	var editor := _open_editor()
	editor._name_field.text = ""
	editor.document().map_name = ""
	editor._notice_label.text = ""
	editor._input(_key(KEY_S))
	assert_true(editor._notice_label.text.to_lower().contains("name"),
			"Ctrl+S must reach save() and report its refusal: %s" % editor._notice_label.text)
	assert_eq(editor.document().dir, "", "and nothing was written")


## ⛔ **ONLY THE HISTORY KEYS GIVE WAY TO A FOCUSED TEXT FIELD, AND THIS IS THE ONE PART OF THE
## RULE A HEADLESS SUITE CAN SEE.** `_typing()` asks the viewport for its focus owner and this
## harness has no tree, so the decision is split into a pure static to keep it checkable.
##
## `LineEdit` implements `Ctrl+Z`/`Ctrl+Y` as its own text undo, so stealing them would break
## the field. It does **nothing** with `Ctrl+S`/`Ctrl+O`/`Ctrl+N`, so deferring those would not
## hand them to anybody — it would drop them, and drop them at the moment Ctrl+S matters most,
## because `save()` reads `_name_field.text` and naming a new map is when that field has focus.
##
## ⚠️ **THE BOARD CARD ASKED FOR THE OPPOSITE** (*"the existing guard is there to be reused
## rather than reasoned about per key"*) and its own preceding sentence is why this reverses it:
## *"Ctrl+S is not a text-editing key."* Asserted so the reversal is a decision on the record
## rather than an omission.
func test_only_the_history_keys_defer_to_a_focused_text_field() -> void:
	for code in [KEY_Z, KEY_Y]:
		assert_true(EDITOR.defers_to_text_field(code),
				"key %d edits text and must give way" % code)
	for code in [KEY_S, KEY_O, KEY_N]:
		assert_false(EDITOR.defers_to_text_field(code),
				"key %d is not a text-editing key, so deferring only loses it" % code)


## A modal has to include the keyboard, whatever the key is. Opening a second map behind the
## unsaved-changes question would change the answer to the question while it was on screen.
func test_a_file_key_is_ignored_while_a_dialog_is_up() -> void:
	var editor := _open_editor()
	# ⚠️ **TYPED, NOT INFERRED.** `Editor.tscn`'s root has no `class_name`, so `_open_editor()`
	# hands back a bare `Node` and every call on it returns untyped `Variant` — `:=` cannot
	# infer from that, and the whole file then fails to parse rather than this one line.
	var before: MapDocument = editor.document()
	editor.open_dialog()
	editor._input(_key(KEY_N))
	assert_eq(editor.document(), before, "Ctrl+N acted behind a modal dialog")
	editor.close_dialog()
	editor._input(_key(KEY_N))
	assert_true(editor.document() != before, "and it works again once the dialog is gone")


## The same two guards `Ctrl+Z` has, on the file keys: a bare `N` is somebody typing, and an
## echo is the keyboard's repeat rate deciding how many maps get thrown away.
func test_a_file_key_needs_ctrl_and_ignores_key_repeats() -> void:
	var editor := _open_editor()
	# ⚠️ **TYPED, NOT INFERRED.** `Editor.tscn`'s root has no `class_name`, so `_open_editor()`
	# hands back a bare `Node` and every call on it returns untyped `Variant` — `:=` cannot
	# infer from that, and the whole file then fails to parse rather than this one line.
	var before: MapDocument = editor.document()

	var bare := _key(KEY_N)
	bare.ctrl_pressed = false
	editor._input(bare)
	assert_eq(editor.document(), before, "a bare N is typing, not a shortcut")

	var echo := _key(KEY_N)
	echo.echo = true
	editor._input(echo)
	assert_eq(editor.document(), before, "a held Ctrl+N must not replace the map repeatedly")


static func _key(code: Key, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = true
	e.shift_pressed = shift
	return e


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
