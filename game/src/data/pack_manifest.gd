## `downloads/packs.json`, parsed (PLAN.md 3.2). Phase 0.3.
##
## ## THE URL IS THE CONTRACT AND IT MUST NEVER MOVE
##
## `https://aod.dragoon.co.za/downloads/packs.json`, unversioned, with the versions INSIDE
## it. A shipped APK has that string baked in, so moving or renaming the file strands every
## copy already installed -- there is no second channel to tell them where it went.
## `web/README.md` says the same thing from the server's side.
##
## ## ONE BAD ENTRY COSTS ONE PACK
##
## `CampaignDef`'s rule, and it earned itself there: a work-in-progress scenario folder made
## a whole campaign unplayable. A manifest is worse, because it is edited by hand on a
## server at the moment somebody is publishing something -- so a typo in the pack being
## added must not take the four that already worked offline with it. Unusable entries land
## in `warnings` and are kept out of `packs`.
##
## ## A FUTURE `format_version` IS REFUSED, NOT GUESSED
##
## `MapFile`'s rule. An older client meeting a newer manifest cannot know what changed, and
## the failure of guessing is silent: it would offer packs whose meaning it has misread. So
## it stops, says so, and the game runs on what is already installed -- which is exactly
## the placeholder path PLAN.md 3.2 already requires for a pack that will not download.
class_name PackManifest
extends RefCounted

## Bumped only when the SHAPE changes in a way an old client cannot read. Adding a field
## is not a bump -- unknown fields are ignored, which is what lets the server publish
## `licence` or `screenshots` tomorrow without stranding today's build.
const FORMAT_VERSION := 1

## Where the client looks, baked into the build. See the class comment.
const MANIFEST_URL := "https://aod.dragoon.co.za/downloads/packs.json"

## Usable packs, in manifest order. Order is the publisher's and is preserved, so the
## DOWNLOAD MORE list can be curated by editing the file.
var packs: Array[PackDef] = []

## Everything wrong, in the order found. Never printed from here -- `Campaigns.warnings`'
## argument: a caller that wants to show somebody a broken manifest needs the text, and one
## that does not can ignore it.
var warnings: Array[String] = []

## When the publisher says it was generated. Decoration -- shown in a log line, never
## compared against anything. The client trusts `version` per pack and nothing else here,
## because a clock on a server is not a fact about a file.
var generated: String = ""


## Parse manifest text. Never returns null; an unreadable manifest is an empty `packs` and
## a populated `warnings`, which is the same shape as a manifest with nothing in it.
static func parse(text: String) -> PackManifest:
	var out := PackManifest.new()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		# The line number matters: a hand-edited manifest is the expected way this breaks.
		var j := JSON.new()
		var err := j.parse(text)
		if err != OK:
			out.warnings.append("packs.json: line %d: %s" % [j.get_error_line(), j.get_error_message()])
		else:
			out.warnings.append("packs.json is empty or null")
		return out
	if not parsed is Dictionary:
		out.warnings.append("packs.json is %s, not an object" % type_string(typeof(parsed)))
		return out
	var root: Dictionary = parsed

	var fv := _as_int(root.get("format_version", 0))
	if fv == 0:
		out.warnings.append("packs.json has no `format_version`")
		return out
	if fv > FORMAT_VERSION:
		out.warnings.append(("packs.json is format_version %d and this build reads %d;"
				+ " update the game to install new content") % [fv, FORMAT_VERSION])
		return out

	out.generated = str(root.get("generated", ""))

	var raw_packs: Variant = root.get("packs", [])
	if not raw_packs is Array:
		out.warnings.append("`packs` is %s, not an array" % type_string(typeof(raw_packs)))
		return out

	var seen: Dictionary = {}
	var index := 0
	for entry in (raw_packs as Array):
		var pack := PackDef.from_dict(entry)
		var where := "packs[%d]" % index
		index += 1
		if not pack.is_usable():
			for p in pack.problems:
				out.warnings.append("%s: %s" % [where, p])
			continue
		if seen.has(pack.id):
			# FIRST WINS, and it is said out loud. Two rows with one id is a publishing
			# mistake, and silently taking the last would make which one you got depend on
			# file order -- the same trap `Campaigns` shadowing warns about.
			out.warnings.append("%s: pack id '%s' is already declared; ignoring the second"
					% [where, pack.id])
			continue
		seen[pack.id] = true
		out.packs.append(pack)

	return out


## The packs the boot sequence fetches with nobody asked (the owner's split, 2026-09-03).
func required_packs() -> Array[PackDef]:
	var out: Array[PackDef] = []
	for p in packs:
		if p.required:
			out.append(p)
	return out


## What DOWNLOAD MORE lists. Everything a player may choose, including things they already
## have -- the browser shows installed state per row rather than hiding what is installed,
## because a list that silently drops what you own cannot offer you an update to it.
func optional_packs() -> Array[PackDef]:
	var out: Array[PackDef] = []
	for p in packs:
		if not p.required:
			out.append(p)
	return out


func by_id(pack_id: String) -> PackDef:
	for p in packs:
		if p.id == pack_id:
			return p
	return null


## JSON has one number type, so `1` may arrive as `1.0`. Duplicated from `PackDef` rather
## than reached across for, because that one is this file's private business and a static
## helper borrowed between classes is how two files come to share a bug.
static func _as_int(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	return 0
