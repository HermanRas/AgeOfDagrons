# Mobile Deploy — quick reference

Day-to-day "build and push to my phone" steps, in PowerShell. This is **not** the
one-time toolchain setup — for installing the JDK, Android SDK, export templates, and
pointing Godot at them the first time, see [`Docs/README.md` §2](Docs/README.md).

This assumes that setup is already done on this machine (it is, per `Docs/README.md`):
Godot 4.7.1-stable, Android export templates installed, `adb` available, and the debug
keystore Godot generated for you.

## Overview

1. **Export** the project to an APK via Godot's CLI (`--export-debug`).
2. **Confirm** the phone is connected and authorized (`adb devices`).
3. **Install** the APK (`adb install -r`), which also reinstalls over a previous build.

No Android Studio, no Gradle — the project exports through Godot's prebuilt Android
template (`gradle_build/use_gradle_build=false` in `game/export_presets.cfg`).

## One-time paths on this machine

```powershell
$godot = "C:\Users\herman.ras\Downloads\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe"
$adb   = "C:\Users\herman.ras\AppData\Local\Android\platform-tools\adb.exe"
$apk   = "c:\Users\herman.ras\GoogleDrive\DEV\Godot\DEV\AOD_Mobile\AgeOfDragons.apk"
```

Use the `_console.exe` variant (not the plain `.exe`) so export output prints to the
terminal instead of vanishing into a GUI window.

## Deploy

```powershell
# 1. Export a debug APK. Exit code 0 = success; the export path is already set in
#    export_presets.cfg, so the destination argument is only needed if you want to
#    override it.
& $godot --headless --path "c:\Users\herman.ras\GoogleDrive\DEV\Godot\DEV\AOD_Mobile\game" `
    --export-debug "Android"

# 2. Confirm the phone is connected and authorized -- must say "device", not
#    "unauthorized" and not an empty list.
& $adb devices

# 3. Install (or reinstall over whatever build is already on the phone).
& $adb install -r $apk

# 4. Launch it without touching the phone. The package is com.example.ageofdragons
#    -- from `package/unique_name="com.example.$genname"` in export_presets.cfg, NOT
#    from package/name, which is the display name "AgeOfDragons". Guessing the latter
#    gets "No activities found to run, monkey aborted".
& $adb shell monkey -p com.example.ageofdragons -c android.intent.category.LAUNCHER 1
```

The phone must be **unlocked** for the app to come to the foreground: on a locked
phone the launch reports success and a screencap shows the lock screen.

Or as one line once the phone is already confirmed connected:

```powershell
& $godot --headless --path "c:\Users\herman.ras\GoogleDrive\DEV\Godot\DEV\AOD_Mobile\game" --export-debug "Android"; & $adb install -r $apk
```

For a release build, swap `--export-debug` for `--export-release` — this needs a real
release keystore configured under **Project → Export → Android → Keystore → Release**
first (never commit it or its passwords).

## Campaign content on the phone

An exported build reads campaigns from **`user://content/scenarios/` and nowhere else** —
the repo-root `scenarios/` override is gated on `OS.has_feature("editor")`, which is false
in an APK (`game/src/data/campaigns.gd`, [`PLAN.md` §3.3](../PLAN.md)).

**Since 0.3 landed (2026-09-03) the phone fetches its own content and there is normally
nothing to stage.** A fresh install boots, checks
`https://aod.dragoon.co.za/downloads/packs.json` during the title hold, and downloads
whatever is marked `required` — today that is How To Play. Optional content is picked by
hand from **DOWNLOAD MORE** on the campaign screen. See [`web/README.md`](../web/README.md)
for publishing and `tools/build_packs.py` for building a pack.

So the two sections below are for the cases the download path does not cover:

- **[Resetting the download state](#resetting-the-download-state)** — how to make a phone
  behave like a fresh install again, which is the only way to re-test the boot download.
- **[Hand-staging content](#hand-staging-content-the-run-as-route)** — pushing a campaign
  that is **not published**, so it can be tried before it goes on the server.

### Resetting the download state

Three pieces of state, and forgetting any one of them makes the next test lie:

```powershell
$adb = "C:\Users\herman.ras\AppData\Local\Android\platform-tools\adb.exe"
$pkg = "com.example.ageofdragons"

& $adb shell am force-stop $pkg

# 1. What the game believes is installed. Leave this and the boot check decides there is
#    nothing to download, however empty the content directory is.
& $adb shell "run-as $pkg rm -f files/packs_installed.json"

# 2. The installed content itself.
& $adb shell "run-as $pkg rm -rf files/content"

# 3. Campaign PROGRESS, which is separate on purpose and survives a re-install
#    (PLAN.md 3.3). Only wipe this if you want the locked state back.
& $adb shell "run-as $pkg rm -f files/campaign_progress.json"

& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1
```

⚠️ **`packs_installed.json` IS THE ONE PEOPLE FORGET.** It is a record of versions, not of
files, and nothing reconciles it against the disk — so a phone with that file and no
content boots straight to a front door whose campaign list is empty, and the download
screen never appears. That is not a bug in the boot check; it is the check being told a lie.

To watch what the fetch actually did:

```powershell
& $adb logcat -c; & $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1
Start-Sleep -Seconds 12; & $adb logcat -d -s godot:V
```

### Hand-staging content (the `run-as` route)

For content that is **not on the server yet**. Publishing is the real route; this is the
one that needs no server round trip.

⚠️ **`campaigns.gd` and PLAN.md §3.3 both say `user://` on Android "is not `adb push`-able"
and name two escapes. There is a third, and it needs no code and no re-export: a
`--export-debug` APK is `android:debuggable`, so `adb shell run-as <pkg>` reaches the app's
own files directory.** Debug builds only — a release APK is not debuggable and none of this
works against one.

**Content staged this way is invisible to `PackIndex`**, which means the boot check does not
know it exists. That is usually what you want (it will not be overwritten), but a *published*
pack of the same `id` will replace it on the next boot if the manifest names a version the
phone has not recorded.

`user://` on this device is `/data/data/com.example.ageofdragons/files/` — confirmed, not
assumed, by finding `audio.cfg` there (`AudioManager._CONFIG_PATH` is `user://audio.cfg`).

```powershell
$adb = "C:\Users\herman.ras\AppData\Local\Android\platform-tools\adb.exe"
$pkg = "com.example.ageofdragons"
$src = "c:\Users\herman.ras\GoogleDrive\DEV\Godot\DEV\AOD_Mobile\scenarios\HowToPlay"

# 1. Push to a staging dir the shell user owns. `run-as` CANNOT read your PC's disk, so
#    the copy has to land on the device first.
& $adb shell rm -rf /data/local/tmp/aod_stage
& $adb shell mkdir -p /data/local/tmp/aod_stage
& $adb push $src /data/local/tmp/aod_stage/

# 2. Make the staged copy world-readable. /data/local/tmp is `drwxrwx--x root shell`, so
#    the app uid can TRAVERSE it but reads nothing inside it that is not `o+r`. Skip this
#    and step 3 fails with "Permission denied" on every file.
& $adb shell chmod -R a+rX /data/local/tmp/aod_stage

# 3. Copy it in as the app itself. `rm -rf` first, so a re-stage replaces rather than
#    merges -- a deleted scenario folder would otherwise linger and still be loaded.
& $adb shell "run-as $pkg mkdir -p files/content/scenarios"
& $adb shell "run-as $pkg rm -rf files/content/scenarios/HowToPlay"
& $adb shell "run-as $pkg cp -r /data/local/tmp/aod_stage/HowToPlay files/content/scenarios/"
& $adb shell "run-as $pkg ls -la files/content/scenarios/HowToPlay"

# 4. `force-stop` before relaunching. `Campaigns.discover()` runs when the front door is
#    built, so a process that is already up will not see the new content.
& $adb shell am force-stop $pkg
& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1
```

**A campaign that loads but shows nothing is usually a `campaign.json` order problem, not a
staging problem.** `Campaigns` reports a scenario folder the order list does not name; read
the log (`& $adb logcat -d -s godot:V`) before re-pushing. Progress is a separate file — see
[Resetting the download state](#resetting-the-download-state).

## Testing the download path end to end

The APK is the last thing to check, not the first. Two cheaper checks fail earlier and say
more:

```powershell
# 1. The SERVER: does the published manifest match the published bytes? Fetches for real,
#    verifies, installs, and asserts `Campaigns` can then load it. Exits non-zero.
& $godot --path game res://dev_preview/preview_content_browser.tscn

# 2. The CLIENT rules, offline: manifest refusals, zip path traversal, the row states.
& $godot --headless --path game res://tests/run_tests.tscn --quit
```

Only then the phone, which is the only thing that can answer *"does a thumb reach the GET
button"* and *"is a 2 MB download over mobile data tolerable"*:

1. Export and install as above.
2. Reset the download state, so the phone is a fresh install.
3. Launch. **How To Play should arrive on its own** — the boot check fetches `required`
   content during the title hold.
4. Campaign → **DOWNLOAD MORE** → *How To Play (Dummy)* → GET. That row is a **test pack**
   published only so the optional path has something to exercise; it installs to
   `HowToPlayDummy`, so it cannot collide with the real campaign or inherit its progress.
5. DELETE on that row, and confirm it leaves the campaign list.

⚠️ **A required pack that fails to download is NOT fatal and must not be**
([`PLAN.md` §3.2](../PLAN.md)) — the game reaches the front door with an empty campaign list
and DOWNLOAD MORE is the retry. Worth testing deliberately: turn the phone's data off and
launch. A dead splash screen there would be a bug; a menu is correct.

## Known gotcha

**Reconnecting the USB cable can silently turn off the phone's "USB debugging"
developer-options toggle.** If `adb devices` shows nothing at all — not even
`unauthorized` — check that toggle before suspecting a driver or cable problem.

If the device shows `unauthorized`, accept the RSA fingerprint prompt on the phone's
screen. If the prompt never appears: `& $adb kill-server; & $adb start-server`.

For anything else — export failing, signing errors, black screen on launch — see
[`Docs/README.md` §2.9](Docs/README.md) (troubleshooting table) and §2.8 (what's
configured in `export_presets.cfg` and why `permissions/internet` must stay `true`).
