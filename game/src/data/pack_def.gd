## One entry in `downloads/packs.json` -- a downloadable pack (PLAN.md 3.2 for art and
## audio, 3.3 for campaigns and maps). Phase 0.3.
##
## ## THERE ARE TWO VERBS AND `kind` PICKS, NOT A FLAG
##
## PLAN.md 3.3: *"art and audio are MOUNTED, a campaign must be INSTALLED"*. Mounting is
## `load_resource_pack()`, which lands a `.pck` under `res://` read-only -- exactly right
## for a texture and impossible for a campaign, which has to be updatable, removable and
## shareable. Installing unpacks a `.zip` into `user://content/`.
##
## The verb is DERIVED FROM `kind` rather than declared beside it, so a manifest cannot
## say "campaign" and "mount" in the same breath. `packs.json` should say which of the two
## a pack wants rather than the client inferring it from the name -- and `kind` IS that
## saying; what the client must not infer it from is the FILENAME.
##
## ## `required` IS THE OWNER'S SPLIT, 2026-09-03
##
## *"some campaigns are auto download game required content like HowToPlay, while
## TheDragonBorn will be optional"*. Two classes, and they differ in WHO decides:
##
##   - `required: true`  -- the boot sequence fetches it with nobody asked. How To Play is
##     the tutorial; a game whose front door offers a campaign that is not there is broken.
##   - `required: false` -- listed in the DOWNLOAD MORE browser and fetched only when a
##     player picks it. This is where community content lives, and it is the majority case
##     for everything after the first campaign.
##
## **A required pack that fails to arrive is not fatal.** PLAN.md 3.2: *"if a pack is
## absent or fails verification, the game runs on placeholders rather than failing"*. The
## same rule extends to content -- an offline first run reaches the front door with no
## campaigns rather than a dead splash screen, which is `CampaignScreen`'s empty state and
## already written.
##
## ## ⚠️ THIS FILE ARRIVES OVER HTTP, SO EVERY FIELD IS HOSTILE UNTIL CHECKED
##
## `MapFile`'s header makes the same argument about a `user://` directory a player can
## open; this is that one step worse, because a manifest is fetched from a server and a
## server can be wrong, stale, or somebody else's. Two fields decide where bytes land on
## disk -- `id` and `folder` -- and both are therefore checked against
## `_is_safe_segment()`: one path segment, no separators, no `..`, no leading dot. A
## manifest naming `../../../project.godot` must be refused HERE, in the parse, rather than
## trusted as far as the installer. `PackInstaller` checks every zip entry as well, because
## a safe folder name says nothing about what is inside the archive.
class_name PackDef
extends RefCounted

## What a pack is, and therefore what is done with it. See the class comment: this is the
## manifest's own word, and the only thing that may pick between install and mount.
enum Kind {
	CAMPAIGN,   ## a zip of authored content, INSTALLED into `user://content/scenarios/`
	MAP,        ## a zip of authored maps, INSTALLED into `user://content/maps/`
	ART,        ## a `.pck`, MOUNTED read-only over `res://`
	AUDIO,      ## a `.pck`, MOUNTED read-only over `res://`
}

## The manifest's spelling of each `Kind`, and the parse is exact-match on these.
##
## A LIST RATHER THAN A `Kind.get(s.to_upper())` LOOKUP, deliberately: the wire words are a
## published contract and the enum is an implementation detail, so an enum rename must not
## silently invalidate every manifest in the wild.
const KIND_WORDS := {
	"campaign": Kind.CAMPAIGN,
	"map": Kind.MAP,
	"art": Kind.ART,
	"audio": Kind.AUDIO,
}

## SHA-256, lowercase hex. 64 characters and nothing else is accepted.
const SHA256_LENGTH := 64

## The pack's identity, and the key in `user://packs_installed.json`. One path segment --
## it names the download's scratch file, so it is checked like a folder even though a
## mounted pack never becomes a directory.
##
## ⚠️ **RENAMING AN `id` MAKES IT A DIFFERENT PACK** and every player re-downloads it. The
## board's keys carry the same warning for the same reason.
var id: String = ""

var kind: Kind = Kind.CAMPAIGN

## Bumped by the publisher whenever the bytes change. **Independent of the game version**
## (PLAN.md 3.2) -- naming a pack after the build would force a full re-download on every
## code release. Compared against `PackIndex`'s record to decide "missing, outdated, or
## already here".
var version: int = 0

## Fetched at boot with nobody asked, or offered in DOWNLOAD MORE. See the class comment.
var required: bool = false

## For `CAMPAIGN` and `MAP`: the directory the archive installs to, and it MUST equal the
## campaign's own folder name -- `CampaignDef.folder` is the identity AND the progress key,
## and `Campaigns` shadows by folder name, so a pack that unpacked to a different directory
## would read as a second campaign and lose the player's progress in the first.
##
## Empty for `ART`/`AUDIO`, which have no directory at all.
var folder: String = ""

## Human-facing, all three shown in the DOWNLOAD MORE list. `author` is here because
## community content has an author and the list should say so; it is decoration to the
## client and identity to a player deciding whether to trust a download.
var title: String = ""
var author: String = ""
var description: String = ""

## Bytes, from the publisher. Checked against what actually arrived BEFORE the hash is
## computed, because a truncated download is the common failure and a cheap length
## comparison names it exactly rather than reporting "checksum mismatch" -- which reads as
## corruption or tampering and sends somebody hunting the wrong fault.
var size: int = 0

var sha256: String = ""

## Every URL this pack can be fetched from, in order, tried in order. **A LIST so adding a
## mirror is a manifest edit with no client change** (PLAN.md 3.2).
var urls: Array[String] = []

## Everything wrong with this entry. Non-empty means the pack is not offered at all --
## `PackManifest` keeps it out of the usable list and says why, on `CampaignDef`'s
## precedent: one broken entry costs one pack rather than the manifest.
var problems: Array[String] = []


## Parse one entry. Never returns null: a hopeless row comes back with `problems` set, so
## the caller can report WHICH row was bad rather than "the manifest did not load".
static func from_dict(raw: Variant) -> PackDef:
	var out := PackDef.new()
	if not raw is Dictionary:
		out.problems.append("entry is %s, not an object" % type_string(typeof(raw)))
		return out
	var d: Dictionary = raw

	out.id = str(d.get("id", ""))
	if out.id.is_empty():
		out.problems.append("no `id`")
	elif not _is_safe_segment(out.id):
		# Reported with the offending text quoted, because the whole point is that
		# somebody looks at it.
		out.problems.append("`id` '%s' is not a plain name" % out.id)

	var kind_word := str(d.get("kind", ""))
	if kind_word.is_empty():
		out.problems.append("no `kind`; expected one of %s" % ", ".join(KIND_WORDS.keys()))
	elif not KIND_WORDS.has(kind_word):
		out.problems.append("`kind` '%s' is not one of %s"
				% [kind_word, ", ".join(KIND_WORDS.keys())])
	else:
		out.kind = KIND_WORDS[kind_word]

	# JSON has one number type, so an int arrives as a float whenever the publisher's
	# tooling writes `2.0`. `GameDataRegistry` and `CampaignProgress` both take the same
	# care; refusing an int-valued float here would fail a manifest that is not wrong.
	out.version = _as_int(d.get("version", 0))
	if out.version < 1:
		out.problems.append("`version` must be 1 or more, got %s" % str(d.get("version", "")))

	out.required = bool(d.get("required", false))

	out.title = str(d.get("title", ""))
	out.author = str(d.get("author", ""))
	out.description = str(d.get("description", ""))

	out.size = _as_int(d.get("size", 0))
	if out.size < 1:
		out.problems.append("`size` must be 1 or more, got %s" % str(d.get("size", "")))

	out.sha256 = str(d.get("sha256", "")).to_lower()
	if out.sha256.is_empty():
		out.problems.append("no `sha256`")
	elif not _is_hex_of_length(out.sha256, SHA256_LENGTH):
		out.problems.append("`sha256` is not %d hex characters" % SHA256_LENGTH)

	for u in _as_array(d.get("urls", [])):
		var url := str(u)
		# https ONLY, and this is not pedantry: a manifest is fetched over TLS and then
		# names where the payload comes from, so allowing http here would let a rewritten
		# manifest downgrade the transport for the part that actually lands on disk. The
		# checksum is the real defence; this closes the cheaper hole.
		if url.begins_with("https://"):
			out.urls.append(url)
		elif url.is_empty():
			out.problems.append("empty entry in `urls`")
		else:
			out.problems.append("`urls` entry '%s' is not https" % url)
	if out.urls.is_empty() and not out.problems.any(func(p: String) -> bool:
			return p.begins_with("`urls`") or p.begins_with("empty entry")):
		out.problems.append("no `urls`")

	# The folder rules differ by verb, so they are checked after `kind` is known.
	out.folder = str(d.get("folder", ""))
	if out.installs():
		if out.folder.is_empty():
			out.problems.append("a '%s' pack needs a `folder` to install into" % kind_word)
		elif not _is_safe_segment(out.folder):
			out.problems.append("`folder` '%s' is not a plain directory name" % out.folder)
	elif not out.folder.is_empty():
		# Said out loud rather than ignored: a `folder` on a mounted pack means whoever
		# wrote the manifest believes it unpacks somewhere, and it does not.
		out.problems.append("a '%s' pack is mounted and cannot take a `folder`" % kind_word)

	return out


## INSTALL (unpack into `user://content/`) or MOUNT (`load_resource_pack()`). The one place
## the two verbs are told apart -- see the class comment.
func installs() -> bool:
	return kind == Kind.CAMPAIGN or kind == Kind.MAP


func mounts() -> bool:
	return not installs()


func is_usable() -> bool:
	return problems.is_empty()


## Where an installing pack unpacks to, under `user://`. Kept here rather than in the
## installer so the two roots are named once: `Campaigns.USER_ROOT` is the campaign half
## and 2.4c's `user://content/maps/` is the other.
##
## ⚠️ **`user://maps/` IS NOT THIS.** That is the player's own saved maps and an install
## must never write there -- PLAN.md 2.4c keeps them two directories precisely so that
## installing or replacing authored content cannot overwrite somebody's save, and
## uninstalling it cannot delete one.
func install_root() -> String:
	match kind:
		Kind.CAMPAIGN:
			return "user://content/scenarios/"
		Kind.MAP:
			return "user://content/maps/"
		_:
			return ""


func install_dir() -> String:
	var root := install_root()
	if root.is_empty() or folder.is_empty():
		return ""
	return root.path_join(folder)


## What a human calls this pack. Never empty, `ScenarioDef.describe()`'s rule: a manifest
## with no `title` still has to produce a row somebody can read.
func label() -> String:
	if not title.is_empty():
		return title
	if not folder.is_empty():
		return folder
	return id


## MB to one decimal, for the browser's row. Bytes are unreadable at this scale and this is
## the only place the figure is shown to a player.
func size_text() -> String:
	return "%.1f MB" % (float(size) / 1048576.0)


## One path segment and nothing clever: letters, digits, `_`, `-`, `.`, and no `..`, no
## separator, no leading dot.
##
## ⚠️ **THIS IS THE SECURITY CHECK AND IT IS DELIBERATELY A WHITELIST.** A blacklist of
## `..` and `/` would still pass a backslash on Windows, a URL-encoded separator, a drive
## letter, or a NUL -- and `DirAccess`/`FileAccess` disagree about which of those they
## normalise. Naming the characters that ARE allowed is the only version of this check that
## cannot be outflanked by an encoding nobody thought of.
static func _is_safe_segment(s: String) -> bool:
	if s.is_empty() or s.length() > 64:
		return false
	if s.begins_with("."):
		return false
	for i in s.length():
		var c := s[i]
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
				or (c >= "0" and c <= "9") or c == "_" or c == "-" or c == "."
		if not ok:
			return false
	return true


static func _is_hex_of_length(s: String, n: int) -> bool:
	if s.length() != n:
		return false
	for i in s.length():
		var c := s[i]
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")):
			return false
	return true


static func _as_int(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	return 0


static func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	return []
