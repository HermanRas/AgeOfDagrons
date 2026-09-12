#!/usr/bin/env python3
"""Build downloadable packs and the manifest the game reads (PLAN.md 3.2/3.3, phase 0.3).

    python tools/build_packs.py              # build everything into web/server/app/downloads/
    python tools/build_packs.py --dry-run    # say what would change, write nothing
    python tools/build_packs.py --only howtoplay

What to publish is `tools/packs.source.json`; what a campaign is CALLED comes out of its own
`campaign.json`. See that file's `_note` for why the two are separate.

OWNERSHIP: this script is the game-code agent's, by the owner's decision on 2026-09-03 --
a fourth named exception in `tools/` alongside `stage_audio.py`, `licence_audit.py` and
`prepare_ui_chrome.py`. It is recorded in AGENT_GAME_CODER.md §1 and announced in
`asset_request.md`, because ownership by agreement and ownership by drift look identical
six weeks later.

THE ZIP IS DETERMINISTIC, AND THAT IS LOAD-BEARING
--------------------------------------------------
Every entry gets a fixed timestamp and fixed permissions, and names are sorted. Without
that, zipping the same unchanged campaign twice produces two different SHA-256s -- and
since the manifest's whole job is to say "you already have this", a checksum that changes
on every build would re-download every pack on every publish, and would make the
version-bump guard below fire constantly and mean nothing.

THE ART PACK IS A ZIP AND NOT A `.pck`, AND THAT IS DELIBERATE
--------------------------------------------------------------
The project owner, 2026-09-12: *"if pck is just a zip, rather leave it zip."* A `.pck` is
NOT a zip -- it is Godot's own container -- but `ProjectSettings.load_resource_pack()`
accepts either, which was measured on 4.7.1 rather than taken from the docs. So the art
pack is built here, in Python, off the staged tree, with no Godot export step in the
pipeline at all.

The one consequence is on the client and it is written up in `AtlasEntry.page_texture()`:
files inside a hand-built zip are NOT imported resources, so `ResourceLoader`/`load()`
cannot open them and every atlas page is decoded with `Image.load_from_file` instead.

WHAT GOES IN THE ART PACK: WHAT THE GAME CAN ASK FOR, NOT WHAT IS ON DISK
-------------------------------------------------------------------------
The input is `game/data/visuals.json`, not a directory listing. The packer walks every
entry's `atlas` path plus every value of its `ages` map, and -- for the `colours` half --
every tinted sibling that exists beside them. That is `GameDataRegistry._atlas_path_for_skin`
re-implemented, and it has to be: those two must agree about what a skin resolves to or the
pack ships art nothing renders and misses art everything asks for.

Settled with the art agent in `asset_request.md` (2026-09-06). The alternative -- zip the
staged directory -- ships every retired bake forever, because **nothing in an atlas or a
recipe records that a visual id stopped pointing at it.** `vis.dragon` is the worked
example: still staged, deliberately kept as a fallback, referenced by nothing. A union of
declared paths drops it for the same reason it will drop the next one, with no skip list to
maintain.

WHAT IS NOT IN HERE YET
-----------------------
The `audio` kind. `game/assets/audio/` is fetched by `tools/stage_audio.py` and is
gitignored build output like the atlases; the client already handles the kind. It wants the
same treatment as art -- walk `data/audio.json`'s declared streams -- and is not written
because nothing is waiting on it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE_FILE = REPO / "tools" / "packs.source.json"
# ⚠️ THE OUTPUT DIRECTORY MIRRORS THE SERVER, and that is the point of the 2026-09-04 `web/`
# reorganisation: `web/server/` is a byte-for-byte picture of `/opt/aod/`, so a deploy is a
# recursive copy with no path translation to get wrong. `app/` is what `docker-compose.yml`
# bind-mounts as the document root, so a file's path under `web/server/app/` IS its URL path.
OUT_DIR = REPO / "web" / "server" / "app" / "downloads"
MANIFEST_NAME = "packs.json"

# The manifest shape the client reads. `PackManifest.FORMAT_VERSION` must agree.
FORMAT_VERSION = 1

# A fixed DOS timestamp for every entry -- see the module docstring. 1980-01-01 is the
# earliest a zip can express, so it is the conventional "no date" value.
FIXED_DATE = (1980, 1, 1, 0, 0, 0)

# Files that are never content: editor droppings and OS metadata. Anything else found in a
# campaign folder IS shipped, deliberately -- a campaign is authored content and guessing
# which of somebody's files matter is how a pack ends up missing an icon.
JUNK_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini"}
JUNK_SUFFIXES = {".import", ".tmp", ".bak", ".orig"}

# What the client insists on finding at the root of an unpacked archive, per kind. Mirrors
# `PackInstaller._expected_marker()`; building a pack that would be refused on arrival is
# the one failure this script can catch for free.
REQUIRED_MEMBER = {"campaign": "campaign.json"}

# Every kind this script can build. `audio` is handled by the client and not by here --
# see the module docstring.
BUILDABLE = ("campaign", "map", "art")

# Kinds that INSTALL (a zip unpacked into `user://content/`) rather than MOUNT. Mirrors
# `PackDef.installs()`, and the split decides whether a `folder` is required or refused.
INSTALLING = ("campaign", "map")

# ── the art pack ───────────────────────────────────────────────────────────────────────
# The asset seam, read to decide what the game can ask for. Both are inside the Godot
# project and both are committed; the ATLASES they name are gitignored build output.
VISUALS_FILE = REPO / "game" / "data" / "visuals.json"
COLOURS_FILE = REPO / "game" / "data" / "colours.json"

# `res://` paths in visuals.json map to this directory, and a zip member's name is the path
# with `res://` taken off -- `res://assets/atlases/x.atlas.json` is packed as
# `assets/atlases/x.atlas.json`, which is where a mounted pack lands it.
RES_ROOT = REPO / "game"
RES_PREFIX = "res://"

# What `GameDataRegistry._ATLAS_SUFFIX` calls an atlas, and the suffix the colour transform
# splices a slug in front of: `vis.villager.atlas.json` + `blue` ->
# `vis.villager.blue.atlas.json`.
ATLAS_SUFFIX = ".atlas.json"

# Keys in a `data/*.json` that are prose, not data. `GameDataRegistry._COMMENT_PREFIX`.
COMMENT_PREFIX = "_"

# ⚠️ PNG IS ALREADY DEFLATED, SO THE PAGES ARE **STORED** AND NOT COMPRESSED. The art agent
# measured it: the 12 largest pages at maximum compression went 30.46 MB -> 30.17 MB, 99% of
# original. Deflating 320 MB for 1% costs minutes on every build and every dry run. The
# `.atlas.json` files are a different matter -- 10 MB of repetitive JSON -- and are deflated.
STORE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".ogg", ".zip"}


def main() -> int:
    ap = argparse.ArgumentParser(description="Build packs and packs.json")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would change; write nothing")
    ap.add_argument("--only", metavar="ID", action="append", default=[],
                    help="build only this pack id (repeatable)")
    ap.add_argument("--out", type=Path, default=OUT_DIR,
                    help=f"output directory (default {OUT_DIR.relative_to(REPO)})")
    args = ap.parse_args()

    source = _read_json(SOURCE_FILE)
    if source is None:
        return 2
    base_url = str(source.get("base_url", "")).rstrip("/") + "/"
    if not base_url.startswith("https://"):
        # The client refuses a non-https url per pack, so building one is building a pack
        # nobody can install.
        print(f"ERROR: base_url must be https, got {base_url!r}", file=sys.stderr)
        return 2

    declared = source.get("packs", [])
    if not isinstance(declared, list) or not declared:
        print(f"ERROR: {SOURCE_FILE.name} declares no packs", file=sys.stderr)
        return 2

    published = _published_versions(args.out / MANIFEST_NAME)

    entries: list[dict] = []
    problems: list[str] = []
    for raw in declared:
        pack_id = str(raw.get("id", ""))
        if args.only and pack_id not in args.only:
            # Skipped, but its PUBLISHED entry is carried forward -- see `_carry_forward`.
            # Dropping it would publish a manifest that silently retires a live pack.
            carried = _carry_forward(pack_id, args.out / MANIFEST_NAME)
            if carried is not None:
                entries.append(carried)
            continue
        entry, problem = _build_one(raw, base_url, args.out, published, args.dry_run)
        if problem:
            problems.append(problem)
        if entry is not None:
            entries.append(entry)

    if problems:
        print("\nNOTHING WAS PUBLISHED. Fix these first:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    manifest = {
        "format_version": FORMAT_VERSION,
        "generated": _timestamp(),
        "packs": entries,
    }

    manifest_path = args.out / MANIFEST_NAME
    if args.dry_run:
        print(f"\n[dry-run] would write {manifest_path}")
        print(json.dumps(manifest, indent=2))
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"\nwrote {manifest_path}")
    print(f"  {len(entries)} pack(s): " + ", ".join(e["id"] for e in entries))
    print("\nUPLOAD THE PACK FILES FIRST AND packs.json LAST (web/README.md).")
    print("A manifest published ahead of its payload is a download failure for every")
    print("client that checks in between.")
    return 0


def _build_one(raw: dict, base_url: str, out: Path, published: dict,
               dry_run: bool) -> tuple[dict | None, str]:
    """Build one pack. Returns (manifest entry, problem). Either may be empty."""
    pack_id = str(raw.get("id", ""))
    kind = str(raw.get("kind", ""))
    folder = str(raw.get("folder", ""))
    version = raw.get("version")

    if not pack_id:
        return None, "a pack has no `id`"
    if kind not in BUILDABLE:
        return None, (f"{pack_id}: kind {kind!r} is not built by this script"
                      f" ({', '.join(BUILDABLE)} -- see the module docstring)")
    if not isinstance(version, int) or version < 1:
        return None, f"{pack_id}: `version` must be an integer of 1 or more"

    # The `folder` rule is the INVERSE of itself across the two verbs, and `PackDef`
    # refuses the wrong one on arrival. An installing pack needs a directory to unpack
    # into; a mounted one has no directory at all, and a `folder` on one means whoever
    # wrote the manifest believes it unpacks somewhere.
    if kind in INSTALLING and not folder:
        return None, f"{pack_id}: a {kind} pack needs a `folder` to install into"
    if kind not in INSTALLING and folder:
        return None, (f"{pack_id}: a {kind} pack is MOUNTED and cannot take a `folder`"
                      " (PackDef refuses it, so this would publish an unusable entry)")

    if kind == "art":
        members, title, description, problem = _art_members(raw, pack_id)
    else:
        members, title, description, problem = _content_members(raw, pack_id, kind)
    if problem:
        return None, problem
    if not members:
        return None, f"{pack_id}: nothing to pack"

    name = f"{kind}_{pack_id}_v{version}.zip"
    dest = out / name

    # ⚠️ WRITTEN TO A TEMPORARY FILE AND HASHED BY STREAMING, NOT BUILT IN MEMORY. The art
    # pack is ~230 MB; holding the payload as `bytes` to hash it doubles that, and the
    # digest has to be known BEFORE the version guard below decides whether to publish at
    # all. So: build beside the destination, hash it off disk, then promote or delete.
    out.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".building")
    try:
        _write_zip(tmp, members)
        size = tmp.stat().st_size
        digest = _sha256_of(tmp)

        # THE VERSION GUARD. See packs.source.json's `_note`: content changed under an
        # unchanged version means every existing install is stale and will never notice.
        was = published.get(pack_id)
        if was is not None and was["version"] == version and was["sha256"] != digest:
            return None, (f"{pack_id}: the content changed but `version` is still {version}."
                          f" Bump it to {version + 1} in tools/packs.source.json"
                          f" (a client that already has v{version} will never look again)")

        unchanged = was is not None and was["version"] == version and was["sha256"] == digest
        if dry_run:
            state = "unchanged" if unchanged else "would write"
            print(f"[dry-run] {state}: {name}  {size:,} bytes  {digest[:12]}...")
        else:
            os.replace(tmp, dest)
            print(f"{'unchanged' if unchanged else 'built':>9}: {name}"
                  f"  {size:,} bytes  {digest[:12]}...")
    finally:
        # A dry run, a guard refusal, or a crash mid-write all leave the temp behind.
        if tmp.exists():
            tmp.unlink()

    entry = {
        "id": pack_id,
        "kind": kind,
        "folder": folder,
        "version": version,
        "required": bool(raw.get("required", False)),
        "title": title,
        "author": str(raw.get("author", "")),
        "description": description,
        "size": size,
        "sha256": digest,
        "urls": [base_url + name],
    }
    return entry, ""


def _content_members(raw: dict, pack_id: str,
                     kind: str) -> tuple[list[dict], str, str, str]:
    """A `campaign` or `map` pack: a folder, zipped whole. Unchanged behaviour."""
    source_rel = str(raw.get("source", ""))
    src = REPO / source_rel
    if not src.is_dir():
        return [], "", "", f"{pack_id}: source {source_rel} is not a directory"

    required_member = REQUIRED_MEMBER.get(kind)
    if required_member and not (src / required_member).is_file():
        return [], "", "", f"{pack_id}: {source_rel} has no {required_member}"

    # `derive` rewrites the content's own metadata as the zip is built -- see
    # packs.source.json's note on the dummy pack. Anything not named here is copied
    # verbatim, so a derived pack stays in step with its original by construction.
    derive = raw.get("derive") or {}
    if derive and kind != "campaign":
        return [], "", "", f"{pack_id}: `derive` is only understood for campaign packs"

    title, description = _titles(src, kind)
    title = str(derive.get("name", title))
    description = str(derive.get("description", description))

    members = []
    for rel in _content_files(src):
        member = {"name": rel.as_posix(), "path": src / rel, "data": None}
        if derive and rel.as_posix() == "campaign.json":
            member["data"] = _derived_campaign_json(src, rel, derive)
            member["path"] = None
        members.append(member)
    if not members:
        return [], "", "", f"{pack_id}: {source_rel} has no files to pack"
    return members, title, description, ""


def _art_members(raw: dict, pack_id: str) -> tuple[list[dict], str, str, str]:
    """An `art` pack: the atlases the SEAM can ask for, resolved out of visuals.json.

    `select` picks which half:

      "base"     every entry's `atlas` and every value of its `ages` map. Required
                 content -- without it the game is placeholders.
      "colours"  the tinted siblings, `<name>.<slug>.atlas.json`, for entries flagged
                 `"colours": true`. Three quarters of the bytes, and OPTIONAL: a missing
                 tint falls back to the untinted bake in `_atlas_path_for_skin`, so a
                 player without this pack is grey and plays perfectly well.
      "all"      both, for anyone who wants one file.
    """
    select = str(raw.get("select", "all"))
    if select not in ("base", "colours", "all"):
        return [], "", "", (f"{pack_id}: `select` must be base, colours or all,"
                            f" got {select!r}")

    visuals = _read_json(VISUALS_FILE)
    if visuals is None:
        return [], "", "", f"{pack_id}: cannot read {VISUALS_FILE.name}"
    colours = _read_json(COLOURS_FILE)
    if colours is None:
        return [], "", "", f"{pack_id}: cannot read {COLOURS_FILE.name}"
    slugs = [str(c.get("id", "")).removeprefix("colour.")
             for c in colours.get("colours", []) if isinstance(c, dict)]
    if not slugs:
        return [], "", "", f"{pack_id}: {COLOURS_FILE.name} declares no colours"

    base_atlases: list[str] = []
    colour_atlases: list[str] = []
    missing: list[str] = []
    # Two sets, not one. See the loop below -- sharing them couples "have I already packed
    # this atlas" to "have I already looked for this atlas's tints", and those are different
    # questions the moment two visual entries name one file.
    seen_base: set[str] = set()
    seen_colour: set[str] = set()

    for visual_id, decl in visuals.items():
        if visual_id.startswith(COMMENT_PREFIX) or not isinstance(decl, dict):
            continue
        # The two axes of `_atlas_path_for_skin`, in the same order it composes them:
        # `ages` REPLACES the base path, and the colour transform is a suffix on
        # whichever of those a skin ended up with. So every one of these can be tinted.
        skins = [str(decl.get("atlas", ""))]
        ages = decl.get("ages")
        if isinstance(ages, dict):
            skins += [str(p) for p in ages.values()]

        # ⚠️ THE DEDUPE IS PER-LIST, AND A SHARED `seen` ACROSS THE WHOLE LOOP IS WRONG.
        # It was one in the first version, and it is a fault waiting for its first subject:
        # TWO ENTRIES MAY SHARE ONE ATLAS (`vis.dragon_baby` and `vis.dragon_rigged` do,
        # deliberately, 13.2b). Skipping an already-seen path would then skip the COLOUR
        # loop with it -- so if the first entry to name an atlas carries no `colours` flag
        # and a later one does, every tint of that unit silently leaves the pack. Harmless
        # today because neither dragon is tinted; it would have surfaced months later as
        # one unit being grey for every player.
        for skin in skins:
            if not skin:
                continue
            if skin not in seen_base:
                seen_base.add(skin)
                local = _res_path(skin)
                if local is None or not local.is_file():
                    # A DECLARED ATLAS THAT IS NOT ON DISK IS FATAL, and it is the guard
                    # the art agent asked for: `game/assets/atlases/` is gitignored, so
                    # this is what a fresh clone looks like. Publishing would ship a pack
                    # missing the art, and a game cannot tell that from art nobody baked.
                    missing.append(f"{visual_id} -> {skin}")
                    continue
                base_atlases.append(skin)

            if not bool(decl.get("colours", False)):
                continue
            for slug in slugs:
                tinted = _tinted_path(skin, slug)
                if tinted in seen_colour:
                    continue
                seen_colour.add(tinted)
                # ABSENCE IS NOT AN ERROR HERE, and the asymmetry with the branch above
                # is the seam's own: `_atlas_path_for_skin` only takes a tinted path
                # `if FileAccess.file_exists(tinted)`, so a colour nobody baked is a
                # supported state. `GameDataRegistry.missing_colour_atlases()` is what
                # reports those, and it is not this script's job to duplicate it.
                local = _res_path(tinted)
                if local is not None and local.is_file():
                    colour_atlases.append(tinted)

    if missing:
        shown = "\n      ".join(sorted(missing)[:8])
        more = f"\n      ... and {len(missing) - 8} more" if len(missing) > 8 else ""
        return [], "", "", (
            f"{pack_id}: {len(missing)} atlas(es) named in visuals.json are not staged."
            f" `game/assets/atlases/` is gitignored build output, so this is what a fresh"
            f" clone looks like -- run tools/stage_atlases.py, or rebake.\n      {shown}{more}")

    wanted = {"base": base_atlases, "colours": colour_atlases,
              "all": base_atlases + colour_atlases}[select]
    if not wanted:
        return [], "", "", (f"{pack_id}: `select` {select!r} matched no atlases."
                            " An empty art pack is never the intent")

    # Each atlas drags its own pages in. The `.atlas.json` names them as BARE FILENAMES
    # written beside it -- `AtlasEntry.from_atlas_dict` joins them to the JSON's directory
    # -- so the same join happens here and the two cannot disagree about where a page is.
    members: list[dict] = []
    page_problems: list[str] = []
    for atlas in sorted(wanted):
        local = _res_path(atlas)
        members.append({"name": _member_name(atlas), "path": local, "data": None})
        parsed = _read_json(local, quiet=True)
        if not isinstance(parsed, dict):
            page_problems.append(f"{atlas} is not readable JSON")
            continue
        pages = parsed.get("pages", [])
        if not pages:
            page_problems.append(f"{atlas} declares no pages")
            continue
        for page in pages:
            page_res = atlas.rsplit("/", 1)[0] + "/" + str(page)
            page_local = _res_path(page_res)
            if page_local is None or not page_local.is_file():
                page_problems.append(f"{atlas} names a page that is not there: {page}")
                continue
            members.append({"name": _member_name(page_res), "path": page_local,
                            "data": None})

    if page_problems:
        shown = "\n      ".join(page_problems[:8])
        return [], "", "", f"{pack_id}: {len(page_problems)} bad atlas page(s)\n      {shown}"

    # WHAT THE UNION LEFT BEHIND, said out loud. A staged atlas nothing declares is
    # correct to drop -- that is the whole design -- but it is also how a wiring mistake
    # looks, so the number goes on screen rather than being silently right.
    _report_art(pack_id, select, base_atlases, colour_atlases, members)

    # Art has no content file to read a name out of, so unlike a campaign its title lives
    # in packs.source.json. Named as the exception it is: `_titles`' rule is that a store
    # listing must not be able to drift from the content, and a pack of atlases has no
    # content that knows what it is called.
    return (members, str(raw.get("title", pack_id)),
            str(raw.get("description", "")), "")


def _report_art(pack_id: str, select: str, base: list[str], colours: list[str],
                members: list[dict]) -> None:
    """What went in, and what visuals.json declared that this pack is not carrying.

    The unreferenced count is the one line worth printing every time. Dropping a staged
    atlas nothing declares is the DESIGN -- but it is also exactly what a wiring mistake
    looks like from here, and the two are told apart by a person reading a number.
    """
    staged = len(list((RES_ROOT / "assets" / "atlases").glob("*" + ATLAS_SUFFIX)))
    declared = len(base) + len(colours)
    atlases = len([m for m in members if m["name"].endswith(ATLAS_SUFFIX)])
    pages = len(members) - atlases
    print(f"{pack_id}: select={select} -- packing {atlases} atlas(es) and {pages} page(s)"
          f" of {declared} declared ({len(base)} base, {len(colours)} colour)")
    if staged > declared:
        print(f"{'':>9}  {staged - declared} staged atlas(es) are declared by NOTHING in"
              f" visuals.json and are in no pack")


def _tinted_path(path: str, slug: str) -> str:
    """`.../vis.villager.atlas.json` + `blue` -> `.../vis.villager.blue.atlas.json`.

    `GameDataRegistry._tinted_path()`, and it must stay the same transform: isobake names
    tinted bakes this way and the seam derives the path rather than declaring it.
    """
    if not slug or not path.endswith(ATLAS_SUFFIX):
        return path
    return path[:-len(ATLAS_SUFFIX)] + f".{slug}{ATLAS_SUFFIX}"


def _res_path(res: str) -> Path | None:
    """A `res://` path as a file on this machine, or None if it is not one."""
    if not res.startswith(RES_PREFIX):
        return None
    rel = res[len(RES_PREFIX):]
    if not rel or rel.startswith("/") or ".." in rel.split("/"):
        return None
    return RES_ROOT / rel


def _member_name(res: str) -> str:
    """The zip member name for a `res://` path -- the path with the scheme taken off.

    That is what makes a mounted pack land its files back where the seam looks for them:
    `res://assets/atlases/x.png` is packed as `assets/atlases/x.png`, and
    `load_resource_pack()` re-roots it at `res://`.
    """
    return res[len(RES_PREFIX):]


def _titles(src: Path, kind: str) -> tuple[str, str]:
    """Title and description, read from the content itself -- never from the source file."""
    if kind != "campaign":
        return src.name, ""
    data = _read_json(src / "campaign.json") or {}
    return str(data.get("name", src.name)), str(data.get("description", ""))


def _content_files(src: Path) -> list[Path]:
    """Every shippable file under `src`, sorted, relative to it."""
    out = []
    for p in sorted(src.rglob("*")):
        if not p.is_file():
            continue
        if p.name in JUNK_NAMES or p.suffix in JUNK_SUFFIXES:
            continue
        out.append(p.relative_to(src))
    return out


def _write_zip(dest: Path, members: list[dict]) -> None:
    """A deterministic zip, written straight to disk. See the module docstring.

    Each member is `{"name", "path", "data"}` -- exactly one of `path` (copied from disk,
    streamed) and `data` (bytes we generated, currently only a derived campaign.json).

    SORTED BY NAME HERE and nowhere else, so determinism does not depend on every caller
    remembering to sort. The art selection walks a JSON object, whose key order is the
    file's, and that is a thing somebody will reorder one day.
    """
    # No directory entries: the client creates parents as it writes each file, and a
    # directory entry is one more name to have to validate for path traversal.
    with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=9) as z:
        for member in sorted(members, key=lambda m: m["name"]):
            name = member["name"]
            # Forward slashes always -- a zip built on Windows must unpack on Android.
            info = zipfile.ZipInfo(name, date_time=FIXED_DATE)
            info.compress_type = (zipfile.ZIP_STORED
                                  if _is_stored(name) else zipfile.ZIP_DEFLATED)
            info.external_attr = 0o644 << 16
            if member["data"] is not None:
                z.writestr(info, member["data"])
                continue
            # Streamed rather than read whole: an atlas page is up to 8 MB and there are
            # 364 of them.
            with z.open(info, "w") as out, open(member["path"], "rb") as src:
                while True:
                    chunk = src.read(1 << 20)
                    if not chunk:
                        break
                    out.write(chunk)


def _is_stored(name: str) -> bool:
    """Already-compressed formats go in uncompressed. See STORE_SUFFIXES."""
    return Path(name).suffix.lower() in STORE_SUFFIXES


def _sha256_of(path: Path) -> str:
    """The digest of a file, read in chunks -- the pack does not fit comfortably in RAM."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _derived_campaign_json(src: Path, rel: Path, derive: dict) -> bytes:
    """campaign.json with `derive`'s overrides applied."""
    data = json.loads((src / rel).read_bytes().decode("utf-8"))
    for field in ("name", "description"):
        if field in derive:
            data[field] = derive[field]
    # A `_note` saying what this is, so anyone who opens the INSTALLED copy on a device and
    # wonders why there are two How To Plays has the answer in front of them.
    data["_note"] = [
        "DERIVED COPY, built by tools/build_packs.py from " + src.name + ".",
        "Published as optional content to exercise the download path (phase 0.3).",
        "Not authored content -- edit the original, not this.",
    ]
    # `sort_keys=False` keeps the author's field order; indent 2 matches the source files.
    return (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def _published_versions(manifest_path: Path) -> dict:
    """`{id: {version, sha256}}` from the manifest already in the output directory."""
    data = _read_json(manifest_path, quiet=True)
    if not isinstance(data, dict):
        return {}
    out = {}
    for e in data.get("packs", []):
        if isinstance(e, dict) and "id" in e:
            out[str(e["id"])] = {
                "version": e.get("version"),
                "sha256": str(e.get("sha256", "")),
            }
    return out


def _carry_forward(pack_id: str, manifest_path: Path) -> dict | None:
    """A `--only` build must not retire the packs it skipped."""
    data = _read_json(manifest_path, quiet=True)
    if not isinstance(data, dict):
        return None
    for e in data.get("packs", []):
        if isinstance(e, dict) and str(e.get("id", "")) == pack_id:
            print(f"{'carried':>9}: {pack_id} (not rebuilt; kept from the live manifest)")
            return e
    return None


def _read_json(path: Path, quiet: bool = False):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        if not quiet:
            print(f"ERROR: {path} not found", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        if not quiet:
            print(f"ERROR: {path}: {e}", file=sys.stderr)
        return None


def _timestamp() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


if __name__ == "__main__":
    sys.exit(main())
