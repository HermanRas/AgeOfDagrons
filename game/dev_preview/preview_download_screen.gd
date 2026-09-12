extends Node

## What the FIRST BOOT looks like, in its four states. Phase 0.3, and it should have
## existed since then -- **nothing in the repo had ever drawn this screen.** 0.3 was closed
## on the owner running it on hardware, which was the right call and leaves no picture
## behind; the art pack then added a button to it.
##
##     godot --path game res://dev_preview/preview_download_screen.tscn
##
## ## WHY A PICTURE, WHEN FIVE TESTS ALREADY PASS
##
## §6: **a `VBoxContainer` overflows -- it does not clip, scroll or compress past its
## children's minimum sizes.** The lobby shipped with its bottom nav strip off the screen
## and *"every structural test passed"*. This column gained a fifth child (SKIP FOR NOW) on
## 2026-09-12, and `showing_skip()` being true says nothing about whether the button is on
## the viewport.
##
## So it measures as well as photographs: every visible child's rect against the viewport,
## **printed and warned about**, because a button hanging 20 px off the bottom edge is
## invisible in a thumbnail and obvious in a number.
##
## The four states are the four routes out of that screen, and the third is the new one:
##   1. offline -- no manifest at all. PLAN.md 3.2's placeholder rule, and the state the
##      owner tested on hardware with the network off
##   2. downloading -- a percentage, a size, and a way out
##   3. skipped -- the player pressed it; goes straight to the menu, no failure page
##   4. failed -- what went wrong, and CONTINUE
##
## ⚠️ **A MANIFEST IS PARKED BEFORE EVERY CONSTRUCTION, AND THAT IS NOT DECORATION.**
## `DownloadScreen._ready()` calls `run()`, which fetches `packs.json` over the real network
## when nothing is parked -- so a preview that just instantiated the screen would hit the
## live server four times and take its timing from the owner's connection.
## `DownloadScreen.pending` is one-shot (taken and cleared in `_init`), which is exactly the
## handover this needs.

const _SHOTS := "user://preview_download_screen"

var _screen: DownloadScreen


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_SHOTS)
	get_window().size = Vector2i(1152, 648)

	# The offline boot: a manifest carrying a warning and no packs, which is exactly what
	# `fetch_manifest()` returns with the network down. `run()` takes that branch itself.
	var offline := PackManifest.new()
	offline.warnings.append("cannot reach https://aod.dragoon.co.za/downloads/packs.json (error 44)")
	await _shoot("1_offline", offline, func() -> void: pass)

	await _shoot("2_downloading", PackManifest.new(), func() -> void:
		var pack := _pack("Game art", 80041115)
		_screen._on_started(pack)
		_screen._on_progress(pack, 26000000, 80041115)
	)
	await _shoot("3_skipped", PackManifest.new(), func() -> void:
		var pack := _pack("Game art", 80041115)
		_screen._on_started(pack)
		_screen._on_progress(pack, 26000000, 80041115)
		_screen.press_skip()
	)
	await _shoot("4_failed", PackManifest.new(), func() -> void:
		var pack := _pack("Game art", 80041115)
		_screen._on_started(pack)
		_screen._on_finished(pack, false, "checksum does not match; the download was corrupt")
		_screen._finish()
	)

	print("\nshots in %s" % ProjectSettings.globalize_path(_SHOTS))
	get_tree().quit(0)


func _shoot(name: String, pending: PackManifest, arrange: Callable) -> void:
	if _screen != null:
		_screen.queue_free()
		await get_tree().process_frame

	DownloadScreen.pending = pending
	_screen = DownloadScreen.new()
	# ⚠️ OFF, OR THE PREVIEW REPLACES ITSELF. `_go_to_menu()` is gated on this exactly so a
	# headless run can inspect the finished state instead of having the scene changed out
	# from under it -- `preview_campaign`'s problem, solved in the screen rather than here.
	_screen.auto_advance = false
	add_child(_screen)
	await get_tree().process_frame

	arrange.call()
	# §5: a screenshot taken in the same frame as an action shows the state before it, and
	# a Control added to a tree has size (0, 0) for the rest of that frame. Two frames.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	img.save_png(_SHOTS.path_join("%s.png" % name))
	_report(name)


## Every visible control against the viewport. The check no assertion in the suite makes.
func _report(name: String) -> void:
	var view := Vector2(get_window().size)
	print("\n-- %s --  viewport %dx%d" % [name, int(view.x), int(view.y)])
	var off := 0
	for node in _walk(_screen):
		var c := node as Control
		if not c.is_visible_in_tree() or c.size == Vector2.ZERO:
			continue
		var r := Rect2(c.global_position, c.size)
		var label := "%s (%s)" % [c.name, c.get_class()]
		if c is Button or c is Label:
			label += " '%s'" % str(c.get("text")).substr(0, 28).replace("\n", " / ")
		var fits := r.position.x >= 0 and r.position.y >= 0 \
				and r.end.x <= view.x and r.end.y <= view.y
		print("   %-52s %s%s" % [label, r, "" if fits else "   <-- OFF THE VIEWPORT"])
		if not fits:
			off += 1
	if off > 0:
		push_warning("%s: %d control(s) are off the viewport" % [name, off])


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		if child is Control:
			out.append(child)
		out.append_array(_walk(child))
	return out


func _pack(title: String, size: int) -> PackDef:
	return PackDef.from_dict({
		"id": "base", "kind": "art", "version": 1, "required": true,
		"title": title, "size": size, "sha256": "0".repeat(64),
		"urls": ["https://example.invalid/art_base_v1.zip"],
	})
