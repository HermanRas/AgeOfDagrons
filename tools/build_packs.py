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

WHAT IS NOT IN HERE YET
-----------------------
Art and audio `.pck` building. PLAN.md 3.2 wants `pack_art_v1.pck` built from the staged
atlases; that reads the art pipeline's output and belongs beside it. This script does the
`campaign` and `map` kinds -- the zip-and-install half of 3.3 -- and grows the `.pck` half
when there is an art pack to publish.
"""

from __future__ import annotations

import argparse
import hashlib
import json
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
    source_rel = str(raw.get("source", ""))

    if not pack_id:
        return None, "a pack has no `id`"
    if kind not in ("campaign", "map"):
        return None, (f"{pack_id}: kind {kind!r} is not built by this script yet"
                      " (campaign and map only -- see the module docstring)")
    if not isinstance(version, int) or version < 1:
        return None, f"{pack_id}: `version` must be an integer of 1 or more"
    if not folder:
        return None, f"{pack_id}: a {kind} pack needs a `folder` to install into"

    src = REPO / source_rel
    if not src.is_dir():
        return None, f"{pack_id}: source {source_rel} is not a directory"

    required_member = REQUIRED_MEMBER.get(kind)
    if required_member and not (src / required_member).is_file():
        return None, f"{pack_id}: {source_rel} has no {required_member}"

    # `derive` rewrites the content's own metadata as the zip is built -- see
    # packs.source.json's note on the dummy pack. Anything not named here is copied
    # verbatim, so a derived pack stays in step with its original by construction.
    derive = raw.get("derive") or {}
    if derive and kind != "campaign":
        return None, f"{pack_id}: `derive` is only understood for campaign packs"

    title, description = _titles(src, kind)
    title = str(derive.get("name", title))
    description = str(derive.get("description", description))

    files = _content_files(src)
    if not files:
        return None, f"{pack_id}: {source_rel} has no files to pack"

    name = f"{kind}_{pack_id}_v{version}.zip"
    dest = out / name
    payload = _zip_bytes(src, files, derive)
    digest = hashlib.sha256(payload).hexdigest()

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
        print(f"[dry-run] {state}: {name}  {len(payload):,} bytes  {digest[:12]}...")
    else:
        out.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(payload)
        print(f"{'unchanged' if unchanged else 'built':>9}: {name}"
              f"  {len(payload):,} bytes  {digest[:12]}...")

    entry = {
        "id": pack_id,
        "kind": kind,
        "folder": folder,
        "version": version,
        "required": bool(raw.get("required", False)),
        "title": title,
        "author": str(raw.get("author", "")),
        "description": description,
        "size": len(payload),
        "sha256": digest,
        "urls": [base_url + name],
    }
    return entry, ""


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


def _zip_bytes(src: Path, files: list[Path], derive: dict | None = None) -> bytes:
    """A deterministic zip, in memory. See the module docstring."""
    import io
    buf = io.BytesIO()
    # No directory entries: the client creates parents as it writes each file, and a
    # directory entry is one more name to have to validate for path traversal.
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in files:
            # Forward slashes always -- a zip built on Windows must unpack on Android.
            info = zipfile.ZipInfo(rel.as_posix(), date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, _member_bytes(src, rel, derive))
    return buf.getvalue()


def _member_bytes(src: Path, rel: Path, derive: dict | None) -> bytes:
    """One file's bytes, with `derive`'s overrides applied to campaign.json only."""
    raw = (src / rel).read_bytes()
    if not derive or rel.as_posix() != "campaign.json":
        return raw

    data = json.loads(raw.decode("utf-8"))
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
