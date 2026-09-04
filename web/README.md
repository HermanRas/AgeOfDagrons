# Website source

Deployed to **https://aod.dragoon.co.za/**. This directory is the source; the live site is
whatever was last uploaded.

## `web/server/` IS A PICTURE OF `/opt/aod/`, AND THAT IS THE WHOLE LAYOUT

Reorganised by the owner on **2026-09-04**. Every path under `web/server/` is the path it
occupies on the box, so **a deploy is a recursive copy and there is no translation to get
wrong**. Before this, the site lived at `web/` and the config at `web/server/`, and every
publish command had to re-derive which local directory mapped to `/opt/aod/app/` — the kind
of arithmetic that is done correctly ninety-nine times.

```
web/
├── README.md                          -> not deployed. This file
└── server/                            -> /opt/aod/
    ├── docker-compose.yml             -> /opt/aod/docker-compose.yml
    ├── nginx.conf                     -> /opt/aod/nginx.conf
    └── app/                           -> /opt/aod/app/   THE DOCUMENT ROOT
        ├── index.html                 -> https://aod.dragoon.co.za/index.html
        ├── player-colour-ladder.html  -> /player-colour-ladder.html
        └── downloads/
            ├── index.html             -> /downloads/index.html
            ├── packs.json             -> /downloads/packs.json   (built, COMMITTED)
            └── *.zip / *.pck          -> /downloads/...          (built, gitignored)
```

⚠️ **`app/` IS THE DOCUMENT ROOT, SO A FILE'S PATH UNDER IT IS ITS URL PATH.** `nginx.conf`
and `docker-compose.yml` sit *beside* `app/` and are never served — that is what makes the
mirror safe. Anything dropped inside `app/` is public the moment it is copied up.

Both pages are placeholders right now.

## The server

`100.96.0.2`, at `/opt/aod`, behind nginx-proxy-manager on port 8081. `web/server/` is the
copy in git of what runs there — the version that exists only on a box is the version
nobody can review.

The box also holds `backup-2026-09-03/`, the php-cli image this replaced. It is **not**
mirrored into git: it is a rollback artefact, not source.

**It was `php -S` until 2026-09-03 and is now `nginx:alpine`.** Two reasons, and the first
is the one that mattered: PHP's built-in server is **single-threaded**, so one phone pulling
a 400 MB art pack would occupy the only worker and block the website and every other
client's `packs.json` until it finished. Its Range support is also partial, and Range is
what a resumed download is made of. Nothing on this site needs PHP; every page is static.

The second: `./app` is now **bind-mounted** rather than `COPY`-ed into an image, so
publishing a pack is an `scp` instead of an image rebuild carrying a 400 MB layer.

```powershell
# deploy EVERYTHING -- config and site in one copy, because the trees are identical
scp -r web\server\* 100.96.0.2:/opt/aod/
ssh 100.96.0.2 "cd /opt/aod && docker compose up -d"

# after a config-only change, a reload is enough and drops no connections
ssh 100.96.0.2 "docker exec ageOfDagons-web nginx -t && docker exec ageOfDagons-web nginx -s reload"
```

⚠️ **`scp -r web\server\*` WILL ALSO PUSH ANY BUILT ZIP SITTING IN `app/downloads/`**, which
is usually what you want but is not the publish order below — a manifest and its payloads
going up in one unordered copy is the race that order exists to avoid. For a pack publish,
use the two commands under *Publishing, in order*; use the recursive copy for the site and
the config.

## What the game itself fetches

Exactly one URL, and it is **not** a page:

```
https://aod.dragoon.co.za/downloads/packs.json
```

`AssetPacks` (phase 0.3) reads that manifest, compares each pack's version against what is
installed locally, downloads what is missing, verifies the SHA-256, and then either
**mounts** it (`load_resource_pack()`, for art and audio) or **installs** it into
`user://content/` (for campaigns and maps). Schema and flow: PLAN.md §3.2 and §3.3; the
client is `game/src/data/pack_*.gd` and `game/src/net/pack_installer.gd`.

**The manifest URL must stay stable and unversioned.** Versions live *inside* the file. A
shipped APK has that URL baked in, so moving or renaming it strands every copy already
installed. `test_packs` asserts the shape of that constant for this reason.

### Two classes of content

The owner's split, 2026-09-03. `required` is a field on each pack:

| | Means | Where a player meets it |
|---|---|---|
| `"required": true` | the game expects it — How To Play is the tutorial | fetched at boot, nobody asked. `BootScreen` checks during the title hold and routes to `Download.tscn` only if something is missing |
| `"required": false` | optional and community content | listed under **DOWNLOAD MORE** on the campaign screen, fetched when picked |

A required pack that fails to download is **not fatal** — PLAN.md §3.2's placeholder rule.
It also appears in DOWNLOAD MORE, which is the manual retry.

## Building and publishing

```powershell
$py = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe"

& $py tools\build_packs.py --dry-run     # what would change
& $py tools\build_packs.py               # build into web/server/app/downloads/
& $py tools\build_packs.py --only howtoplay
```

What to publish is `tools/packs.source.json`; a campaign's **title and description come out
of its own `campaign.json`**, so the store listing cannot drift from the content.

**The zips are deterministic** — fixed timestamps, sorted names — so rebuilding unchanged
content produces the same SHA-256. Without that, every publish would re-download every pack.

⚠️ **`version` IS BUMPED BY HAND.** A client that has v2 will not look again until it sees
v3, so the number is a decision rather than a side effect. `build_packs.py` **refuses to
write a manifest whose bytes changed under an unchanged version** — that guard is the one
that stops "content edited, script re-run, every existing install silently stale".

### Publishing, in order

```powershell
scp web\server\app\downloads\campaign_*.zip 100.96.0.2:/opt/aod/app/downloads/   # 1. payloads
scp web\server\app\downloads\packs.json     100.96.0.2:/opt/aod/app/downloads/   # 2. manifest LAST
```

The local and remote halves of each line are now the same path, which is the mirror doing
its job: `web\server\` + the rest is `/opt/aod/` + the rest.

**Step 2 last matters.** The manifest is what tells clients a pack exists; publishing it
before the file is uploaded is a download failure for every client that checks in between,
and a checksum recorded before the final upload is a checksum for the wrong file.

No automation — uploaded by hand, like everything else here (there is no CI, PLAN.md §1.2).

### Files served from downloads/

| File | Fetched by | Notes |
|---|---|---|
| `packs.json` | the game | Must never move. Served `no-cache` — a stale copy means the publish did not happen |
| `campaign_howtoplay_v1.zip` | the game | The tutorial. `required` |
| `campaign_howtoplay_dummy_v1.zip` | the game | **A TEST PACK.** Optional content that exists only so the browse-and-pick path has something to exercise on a device; delete it once there is a real optional campaign |
| `pack_art_v1.pck` | the game | **Not built yet** — `build_packs.py` does zips only; see `asset_request.md` |
| `AoD_v*.apk` / `.exe` | humans | Game builds |

The `.pck` and `.zip` files are **not** committed (`.gitignore`), and neither are the
builds. They are upload artefacts, rebuildable from `tools/build_packs.py`.

Packs are served `immutable` with a one-year cache, which is safe **because the version is
in the filename** — a new version is a new URL. That is also why a pack is not named after
the game version: every code-only release would otherwise force a full art re-download.

## Checking it by hand

```powershell
# the manifest, and that it is not being cached
curl.exe -si https://aod.dragoon.co.za/downloads/packs.json | Select-Object -First 12

# Range support, which is what makes a resumed download possible. 206 = working.
curl.exe -s -o NUL -w "%{http_code}`n" -H "Range: bytes=0-99" `
    https://aod.dragoon.co.za/downloads/campaign_howtoplay_v1.zip
```

The end-to-end check is not a curl, though — it is
`godot --path game res://dev_preview/preview_content_browser.tscn`, which fetches the real
manifest, downloads the real pack, verifies it, installs it, and asserts that `Campaigns`
can then load it. **It exits non-zero if any of that fails**, and it is the only thing that
tests the server rather than the client.
