## Loads a PNG that lives OUTSIDE `res://` — a campaign icon, a scenario icon, a campaign
## background (PLAN.md 3.3, 15.4, 15.5).
##
## ⚠️ **`load()` AND `ResourceLoader` CANNOT OPEN THESE AT ALL, AND THAT IS THE WHOLE
## REASON THIS EXISTS.** Godot's importer only ever sees `res://`, so a file under
## `user://content/scenarios/` or in the repo-root `scenarios/` override has **no `.import`
## sidecar** and is not a resource. `scenarios/README.md` states the route — `Image.load()`
## plus `ImageTexture.create_from_image()` — and this is that route in one place, so the two
## screens cannot drift into two versions of it. It is the same route a saved map's PNG
## takes, and it is the price of the content being installable rather than baked into the
## APK.
##
## **TWO CONSEQUENCES WORTH KNOWING BEFORE ANYTHING CALLS THIS**, both from
## `scenarios/README.md` and neither fixable here: there is **no VRAM compression and no
## mipmap** on the result, and a decode is real work — the 1920×1080 campaign background is
## the one that matters, which is why `CampaignDef` holds *paths and not textures* and why
## a background is loaded when a campaign is OPENED rather than for every row of a
## selection list.
##
## **NULL IS THE ONLY FAILURE**, deliberately. A campaign is downloadable, shareable
## content — the same argument `Campaigns._parse_json` makes for `JSON.new().parse()` — so
## a missing, truncated or malicious file is an ordinary Tuesday, not an exception. Every
## caller draws a placeholder instead; nobody gets a crash and nobody gets a stack trace in
## somebody else's log.
class_name ContentImage
extends RefCounted


## The texture at `path`, or null if there is not one. Absolute paths, as `CampaignDef` and
## `ScenarioDef` hold them.
##
## The `file_exists` guard is not redundant with the null check below: `Image.load_from_file`
## pushes an ENGINE error for a path that is not there, and an absent icon is a normal state
## for authored content (`CampaignDef.icon_path` is `""` exactly when the file is missing).
## Checking first keeps a legitimately icon-less campaign from printing anything.
static func load_texture(path: String) -> ImageTexture:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
