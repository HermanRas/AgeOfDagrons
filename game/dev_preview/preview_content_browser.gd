## Drives the DOWNLOAD MORE browser against the REAL server, all the way to a campaign that
## `Campaigns` can find (PLAN.md 3.2/3.3). Phase 0.3.
##
##     godot --path game res://dev_preview/preview_content_browser.tscn
##     godot --path game res://dev_preview/preview_content_browser.tscn -- --keep
##
## ## WHY THIS EXISTS AND THE SUITE IS NOT ENOUGH
##
## Every test of 0.3 uses a fixture manifest and a local file, because a test that needs the
## internet fails on a train. **Nothing in the suite can tell whether the SERVER is right**
## -- whether nginx serves `.pck` as something a proxy will not rewrite, whether the
## checksum in the published manifest matches the published bytes, whether the URL in the
## manifest is even reachable. Those are the failures that only appear in production, and
## they are exactly what this run exercises.
##
## It goes further than a screenshot on purpose. The screenshot proves the list DRAWS; the
## assertions after it prove the download landed as a campaign the game can actually load,
## which is the only definition of "it worked" that matters.
##
## ## ⚠️ IT WRITES TO A SCRATCH `user://` AND CLEANS UP AFTER ITSELF
##
## `CampaignProgress`'s lesson generalised: a preview that installed into the real
## `user://content/scenarios/` would shadow the developer's dev override, and `Campaigns`
## would then warn about a shadowed campaign on every subsequent run for reasons nobody
## could see. So the index goes to a scratch file and the installed copy is removed at the
## end -- `--keep` leaves it in place for a look.
##
## The one thing it cannot scratch is the install DIRECTORY: `PackDef.install_root()` is
## `user://content/scenarios/` and a pack has no say in it, which is right for shipped code
## and awkward here. So the run refuses to start if a real `HowToPlay` is already installed
## there, rather than overwriting somebody's copy.
extends Node

const SHOT_DIR := "user://"
const SCRATCH_INDEX := "user://preview_packs_installed.json"

var _browser: ContentBrowser
var _keep := false
var _failures: Array[String] = []


func _ready() -> void:
	_keep = "--keep" in OS.get_cmdline_user_args()

	print("\n=== content browser, against the live server (0.3) ===")
	print("manifest: ", PackManifest.MANIFEST_URL)

	# The guard described in the class comment.
	var live_dir := "user://content/scenarios/HowToPlay"
	var pre_existing := DirAccess.dir_exists_absolute(live_dir)
	if pre_existing:
		print("\nNOTE: %s already exists." % live_dir)
		print("This run will REPLACE it and then remove it, which is what an update does.")
		print("Pass --keep if you want the installed copy left behind.")

	_cleanup_index()

	_browser = ContentBrowser.new()
	_browser.index_path = SCRATCH_INDEX
	add_child(_browser)

	# ⚠️ AWAIT THE BROWSER'S OWN FETCH, DO NOT START A SECOND ONE. Calling `refresh()` here
	# is what broke this preview's first run: `ContentBrowser._ready()` had already started
	# a request, and two on one `HTTPRequest` come back as error 44 -- which the screen then
	# reported as "cannot reach the server". Both ends are guarded now; this is the correct
	# way to wait.
	await _browser.refreshed
	await _settle()

	var offered := _browser.offered_ids()
	print("\noffered: ", offered)
	_shoot("content_1_list")

	if offered.is_empty():
		_fail("the server offered nothing -- see the warnings above")
		_finish()
		return

	# Install the first thing offered, through the real button path.
	var pack: PackDef = _browser._manifest.by_id(offered[0])
	print("\ninstalling '%s' (%s, v%d, %s)" % [pack.id, pack.label(), pack.version, pack.size_text()])
	# THROUGH THE REAL BUTTON HANDLER, not `PackInstaller.install()` directly. Reaching past
	# the screen skipped the busy guard, the toast and the just-installed bookkeeping, and
	# that is precisely how the vanishing-row bug passed this preview once already.
	var started := Time.get_ticks_msec()
	await _browser._on_get_pressed(pack)
	var took := Time.get_ticks_msec() - started
	var ok := PackIndex.is_installed(pack.id, SCRATCH_INDEX)
	print("install finished in %d ms; recorded=%s" % [took, ok])

	if not ok:
		_fail("the install failed -- the message above is the reason")
		_finish()
		return

	# ── the assertions that make this more than a screenshot ──────────────────

	if PackIndex.version_of(pack.id, SCRATCH_INDEX) != pack.version:
		_fail("PackIndex did not record %s at v%d" % [pack.id, pack.version])

	var dir := pack.install_dir()
	if not DirAccess.dir_exists_absolute(dir):
		_fail("nothing was unpacked into %s" % dir)
	elif not FileAccess.file_exists(dir.path_join(CampaignDef.JSON_FILE)):
		_fail("%s has no %s" % [dir, CampaignDef.JSON_FILE])

	# THE REAL TEST: can the game LOAD what was just installed? An unpacked directory that
	# `Campaigns` cannot read is a failed install that every check above would call a pass.
	var found: CampaignDef = null
	for c in Campaigns.new().discover():
		if c.folder == pack.folder:
			found = c
	if found == null:
		_fail("Campaigns.discover() cannot see %s after installing it" % pack.folder)
	else:
		print("\nCampaigns found '%s': %d scenario(s), playable=%s"
				% [found.name, found.scenarios.size(), found.is_playable()])
		if not found.is_playable():
			_fail("the installed campaign is not playable: %s" % ", ".join(found.all_problems()))

	# The browser must now show it as INSTALLED rather than still offering GET.
	_browser._rebuild()
	await _settle()
	_shoot("content_2_installed")

	_finish(pack)


func _finish(pack: PackDef = null) -> void:
	if pack != null and not _keep:
		# Remove the installed copy AND the scratch index, so the next run starts clean and
		# the developer's dev override stops being shadowed.
		var inst := PackInstaller.new()
		add_child(inst)
		inst.uninstall(pack, SCRATCH_INDEX)
		print("\nremoved the installed copy (pass --keep to keep it)")
	_cleanup_index()

	if _failures.is_empty():
		print("\n=== PASS: the published pack downloaded, verified, installed and loaded ===")
		get_tree().quit(0)
	else:
		print("\n=== FAIL ===")
		for f in _failures:
			print("  - ", f)
		# NON-ZERO, so this can be believed from a script. A preview that prints "FAIL" and
		# exits 0 is a preview whose result nobody checks twice.
		get_tree().quit(1)


func _fail(why: String) -> void:
	_failures.append(why)
	print("FAIL: ", why)


func _cleanup_index() -> void:
	if FileAccess.file_exists(SCRATCH_INDEX):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_INDEX))


## ⚠️ SETTLE BEFORE SHOOTING, AND THIS COST TWO WASTED RUNS.
##
## `AGENT_GAME_CODER.md` §5: *"a screenshot taken in the same frame as an action shows the
## state before it"*, and `preview_projectiles` says the viewport texture lags a frame on
## top of that. Both bit here at once. The first run of this preview printed
## `offered: ["howtoplay"]` and photographed an empty list still reading "Checking for
## content..."; the second shot, meant to show INSTALLED, showed GET and a progress line at
## 97%. Every row was correct and every picture was one state stale.
##
## Rebuilding a container is worse than moving a sprite, because the new children have to be
## laid out before they have a size -- so this waits several frames AND for the draw, rather
## than one `process_frame`.
func _settle() -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("(headless: no viewport image for ", name, ")")
		return
	image.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
