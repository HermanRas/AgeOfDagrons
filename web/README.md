# Website source

Deployed to **https://aod.dragoon.co.za/**. This directory is the source; the live site is
whatever was last uploaded.

```
web/
├── index.html              -> https://aod.dragoon.co.za/index.html
└── downloads/
    └── index.html          -> https://aod.dragoon.co.za/downloads/index.html
```

Both pages are placeholders right now.

## What the game itself fetches

Exactly one URL, and it is **not** a page:

```
https://aod.dragoon.co.za/downloads/packs.json
```

`AssetPacks` (phase 0.3) reads that manifest, compares each pack's version against what is
installed locally, downloads what is missing or outdated, verifies the SHA-256, and mounts
it with `load_resource_pack()`. Schema and flow: PLAN.md §3.2.

**The manifest URL must stay stable and unversioned.** Versions live *inside* the file. A
shipped APK has that URL baked in, so moving or renaming it strands every copy already
installed.

## Files served from downloads/

| File | Fetched by | Notes |
|---|---|---|
| `packs.json` | the game | Must never move. Small, so cache headers should be short |
| `pack_art_v1.pck` | the game | Built from the staged atlases by phase 0.3's packager |
| `AoD_v0.0.4.apk` | humans | Android build |
| `AoD_v0.0.4.exe` | humans | Windows build |

The `.pck` files are **not** committed to this repo (`.gitignore`), and neither are the
builds. They are upload artefacts.

### Why the pack is not named after the game version

The example layout had `AoD_v0.0.4.pck` alongside the `.exe` and `.apk`, which reads
naturally but couples the art to the build. Every code-only release would then force a
full art re-download — currently 6.7 MB, but growing once audio (A.7) and the military
roster (A.8) land. So packs carry their own version (`pack_art_v1.pck`) and the manifest
is what ties a game build to the pack versions it accepts. The `.apk`/`.exe` keep the
game version; only the packs differ.

## Deploying

No automation — uploaded by hand, like everything else here (there is no CI, PLAN.md §1.2).
When publishing a new pack:

1. Rebake or restage as needed — `python tools/stage_atlases.py`
2. Build the pack (phase 0.3's packager)
3. Upload the `.pck`
4. **Update `packs.json` last** — version, `size`, and `sha256`

Step 4 last matters: the manifest is what tells clients a pack exists. Publishing it
before the file is uploaded means every client that checks in between gets a download
failure, and a checksum recorded before the final upload is a checksum for the wrong file.
