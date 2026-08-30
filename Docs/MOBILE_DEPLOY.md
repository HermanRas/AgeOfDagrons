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

## Known gotcha

**Reconnecting the USB cable can silently turn off the phone's "USB debugging"
developer-options toggle.** If `adb devices` shows nothing at all — not even
`unauthorized` — check that toggle before suspecting a driver or cable problem.

If the device shows `unauthorized`, accept the RSA fingerprint prompt on the phone's
screen. If the prompt never appears: `& $adb kill-server; & $adb start-server`.

For anything else — export failing, signing errors, black screen on launch — see
[`Docs/README.md` §2.9](Docs/README.md) (troubleshooting table) and §2.8 (what's
configured in `export_presets.cfg` and why `permissions/internet` must stay `true`).
