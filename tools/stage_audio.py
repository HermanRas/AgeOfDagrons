#!/usr/bin/env python3
"""Stage 0 A.D. audio into the Godot project and generate the audio seam.

Audio needs no baking -- it is already 44.1 kHz Ogg Vorbis and ships as-is -- so
unlike `stage_atlases.py` there is no isobake step in front of this. What there
IS instead is a two-part obstacle that cost real time to work out, and the whole
reason this file exists rather than a one-line `copy`:

1. THE .ogg FILES IN THE 0 A.D. CHECKOUT ARE NOT AUDIO. Every one of the 1101 of
   them is a ~130-byte git-LFS pointer. `git lfs pull` does not fix it: that
   checkout's index carries ~30k staged deletions from how it was set up (see
   `restore_art_sources.sh`, which documents the same condition for meshes) and
   its `.gitattributes` is not in the working tree, so LFS has no idea which
   paths it owns and exits 0 having done nothing at all.

   We therefore DO NOT go through git. A pointer file already contains the
   sha256 (`oid`) and byte count of the real content, which is everything the
   LFS HTTP API needs. This script reads the pointer, asks the API for a
   download URL, fetches the bytes, and verifies them against the oid it asked
   for. Nothing is written into the art checkout -- not one byte -- which is the
   point: that tree is the art agent's, and git operations in it have destroyed
   art before.

2. gitea.wildfiregames.com IS BEHIND AN ANUBIS PROOF-OF-WORK BOT WALL. A normal
   HTTP client gets an HTML "Making sure you're not a bot!" challenge page with
   status 200, which reads exactly like a broken endpoint. A `git-lfs/...`
   User-Agent is allowed straight through. That single header is the difference,
   and it is why `_UA` below is not cosmetic.

`game/assets/audio/` is **gitignored on purpose**, the same call as
`game/assets/atlases/`: it is redistributable (0 A.D. is CC-BY-SA 3.0, unlike the
itch.io UI packs) but it is 20-odd MB of derived files that reach players through
the downloadable audio pack (PLAN.md 3.2, `pack_audio_v1.pck`), not through git.

WHAT THE MAPPING BELOW IS. `SFX`/`MUSIC` are the design record for PLAN.md A.7 --
one game sound id mapped to the best-matching 0 A.D. sound group. A 0 A.D.
"sound group" is an XML file listing interchangeable variations plus the gain and
pitch jitter its authors tuned, so taking the group rather than a single .ogg
inherits that tuning and the variety for free. Those numbers are carried into
`data/audio.json` so `AudioManager` does not re-invent them.

    python tools/stage_audio.py --dry-run   # report what would be fetched
    python tools/stage_audio.py             # fetch missing, write data/audio.json
    python tools/stage_audio.py --manifest-only   # regenerate audio.json only
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEST = REPO / "game" / "assets" / "audio"
MANIFEST = REPO / "game" / "data" / "audio.json"

# The two mod roots. `public` is the game's own content; `mod` is the small
# always-loaded mod, and the only thing we want from it is the GUI button click,
# which has no equivalent under public/.
ZEROAD = Path(
    r"C:\Users\herman.ras\Downloads\AOD_game\art_source\0ad\binaries\data\mods"
)
ROOTS = {"public": ZEROAD / "public", "mod": ZEROAD / "mod"}

LFS_BATCH = "https://gitea.wildfiregames.com/0ad/0ad.git/info/lfs/objects/batch"
# Not cosmetic -- see the header. Anubis lets git-lfs through and blocks generic
# clients, so this is what makes the fetch work at all.
_UA = "git-lfs/3.7.1 (GitHub; linux amd64; go 1.25.0)"
_LFS_CT = "application/vnd.git-lfs+json"
_BATCH_SIZE = 100

# HOW MANY VARIATIONS OF ONE SOUND TO TAKE, and why there is a cap at all.
#
# 0 A.D. is generous: `lumbering` has 22 chop samples, `gathering` 66, the impact
# groups 159 between them. Taking every one meant 490 files and 52 MB, and two
# things made that a bad trade. The honest one: nobody can tell a 6-way shuffle
# from a 22-way one -- the ear is listening for "not the same twice", and five is
# already past that. The practical one: the LFS endpoint rate-limits to roughly
# one object per 20 seconds after the first ~150, so the full set is a two-hour
# fetch against a volunteer project's server, and the audio pack has a 50-100 MB
# budget (PLAN.md 3.2) it would eat on chopping noises alone.
#
# Taken from the FRONT of the group's list rather than sampled across it, because
# 0 A.D. names them `lumber_tree_01..22` and the early ones are the ones its own
# authors put first. Raise it with --max-variations if a sound ever reads as
# repetitive; the tool is incremental, so raising it fetches only the difference.
_MAX_VARIATIONS = 5

# PITCH BOUNDS, because 0 A.D.'s own data goes outside anything Godot accepts.
#
# `actor/mounted/death/death_mounted.xml` declares `<PitchLower>0</PitchLower>`
# with `<PitchUpper>0.5</PitchUpper>` (and `<GainLower>0</GainLower>` beside it,
# which would be silence). A `pitch_scale` of 0 is rejected outright by Godot,
# and anything near it is a sound stretched to a hundred times its length -- so
# the range is clamped rather than trusted. 0.5 is the practical floor for a
# sample still recognisable as itself, and it happens to be what that group's
# own upper bound is.
_PITCH_FLOOR = 0.5
_PITCH_CEIL = 2.0

# ── the mapping (PLAN.md A.7) ───────────────────────────────────────────────
#
# id -> (group, bus, throttle_ms)
#
# `group` is a path under a mod root, without the `audio/` prefix or `.xml`
# suffix; a value ending in `.ogg` is a bare file with no group XML (0 A.D. has a
# few). Prefix `mod:` to read from the `mod` root instead of `public`.
#
# `throttle_ms` is OURS, not 0 A.D.'s -- the minimum gap between two plays of the
# same id. It is the difference between a woodcutting camp and a machine gun, and
# 0 A.D.'s own <Threshold> does not answer it (that field culls by gain, not by
# rate). 0 means "never throttle" and is right for one-shot events a player
# causes deliberately; the chatty per-tick gameplay sounds all carry one.
SFX: dict[str, tuple[str, str, int]] = {
    # ── UI and menus ────────────────────────────────────────────────────────
    # Every button in the game. `mod:` root because public/ has no plain click.
    "ui.click": ("mod:interface/ui/ui_button_click", "UI", 0),
    "ui.click_long": ("mod:interface/ui/ui_button_longclick", "UI", 0),
    # A refused order: too expensive, wrong age, illegal placement. 0 A.D. uses
    # its invalid-placement alarm for the same job.
    "ui.error": ("interface/alarm/alarm_invalid_building_placement", "UI", 120),
    "ui.no_resources": ("interface/alarm/alarm_noresources", "UI", 1500),
    "ui.no_idle_unit": ("interface/alarm/alarm_no_idle_unit", "UI", 500),
    "ui.chat": ("interface/ui/chat_alert.ogg", "UI", 0),
    # Selecting a thing. Buildings get a per-kind sound further down; these two
    # are the generic fallbacks the seam resolves to when a kind has none.
    "ui.select_unit": ("interface/select/building/sel_universal", "UI", 60),
    "ui.select_building": ("interface/select/building/sel_universal", "UI", 60),
    "ui.select_resource_tree": ("interface/select/resource/sel_tree", "UI", 60),
    "ui.select_resource_stone": ("interface/select/resource/sel_stone", "UI", 60),
    "ui.select_resource_gold": ("interface/select/resource/sel_metal", "UI", 60),
    "ui.select_resource_food": ("interface/select/resource/sel_fruit", "UI", 60),
    # Match-shaping announcements.
    "ui.age_advance": ("interface/alarm/alarm_phase", "UI", 0),
    "ui.tech_complete": ("interface/alarm/alarm_techcomplete", "UI", 0),
    "ui.under_attack": ("interface/alarm/alarm_attackplayer", "UI", 4000),
    "ui.victory": ("interface/alarm/alarm_victory", "UI", 0),
    "ui.defeat": ("interface/alarm/alarm_defeated", "UI", 0),
    # A trained unit reporting for duty, by broad class. 0 A.D. keys these by
    # role rather than by unit, which is exactly the granularity we want -- 28
    # unit defs do not need 28 sounds.
    "trained.worker": ("interface/alarm/alarm_create_worker", "UI", 0),
    "trained.female": ("interface/alarm/alarm_create_female", "UI", 0),
    "trained.infantry": ("interface/alarm/alarm_create_infantry", "UI", 0),
    "trained.cavalry": ("interface/alarm/alarm_create_cav", "UI", 0),
    "trained.priest": ("interface/alarm/alarm_create_priest", "UI", 0),
    "trained.warship": ("interface/alarm/alarm_create_warship", "UI", 0),
    "trained.siege": ("attack/siege/ram_trained", "UI", 0),
    # ── villager work ───────────────────────────────────────────────────────
    # Throttled hard: these fire per gather tick, and a dozen villagers on one
    # forest would otherwise stack into noise.
    "villager.chop": ("resource/lumbering/lumbering", "SFX", 180),
    "villager.mine_stone": ("resource/mining/mining", "SFX", 180),
    "villager.mine_gold": ("resource/mining/pickaxe", "SFX", 180),
    "villager.forage": ("resource/foraging/forage_leaves", "SFX", 220),
    "villager.farm": ("resource/farming/farm", "SFX", 220),
    "villager.hunt": ("resource/gathering/gather_meat", "SFX", 220),
    "villager.fish": ("resource/gathering/gathering", "SFX", 220),
    "villager.build_wood": ("resource/construction/con_wood", "SFX", 180),
    "villager.build_stone": ("resource/construction/con_stone", "SFX", 180),
    "villager.build_saw": ("resource/construction/con_saw", "SFX", 180),
    "tree.fall": ("resource/lumbering/treefall", "SFX", 0),
    # ── weapons ─────────────────────────────────────────────────────────────
    # One id per WEAPON, not per unit: `units.json` says what a unit swings and
    # the view maps that to one of these. A crossbow has no 0 A.D. equivalent,
    # so it borrows the bow -- the honest best match rather than silence.
    "attack.sword": ("attack/weapon/sword_attack", "SFX", 90),
    "attack.spear": ("attack/weapon/spear_attack", "SFX", 90),
    "attack.pike": ("attack/weapon/pike_attack", "SFX", 90),
    "attack.knife": ("attack/weapon/knife_attack", "SFX", 90),
    "attack.bow": ("attack/weapon/bow_attack", "SFX", 90),
    "attack.crossbow": ("attack/weapon/bow_attack", "SFX", 90),
    "attack.sling": ("attack/weapon/sling_attack", "SFX", 90),
    "attack.javelin": ("attack/weapon/javelin_attack", "SFX", 90),
    "attack.ram": ("attack/siege/ram_attack", "SFX", 0),
    "attack.ballista": ("attack/siege/ballist_attack", "SFX", 0),
    # Onager and trebuchet are both counterweight/torsion throwers; 0 A.D.'s
    # Roman ballista is the closest heavy release it has.
    "attack.catapult": ("attack/siege/ballist_rome_attack", "SFX", 0),
    # The dragon's breath. 0 A.D. has no dragon and no breath weapon, so this is
    # its spreading-fire loop -- the nearest thing it owns to a gout of flame,
    # and better than the arrow twang any rule reading `attack_type: pierce`
    # would have picked (see UnitDef.attack_projectile's note on the same trap).
    "attack.fire": ("attack/fire/spreading_fire", "SFX", 300),
    "ambient.fire": ("attack/fire/crackling_fire", "AMBIENT", 0),
    "projectile.arrow_fly": ("attack/weapon/arrowfly", "SFX", 120),
    "impact.arrow": ("attack/impact/arrow_impact", "SFX", 90),
    "impact.metal": ("attack/impact/shield_metal", "SFX", 90),
    "impact.wood": ("attack/impact/shield_wood", "SFX", 90),
    "impact.siege": ("attack/impact/siegeprojectilehit", "SFX", 0),
    # ── death ───────────────────────────────────────────────────────────────
    "die.male": ("actor/human/death/male_death", "VOICE", 60),
    "die.female": ("actor/human/death/female_death", "VOICE", 60),
    "die.mounted": ("actor/mounted/death/death_mounted", "VOICE", 60),
    "die.ship": ("actor/ship/warship_death", "SFX", 0),
    "die.animal": ("actor/fauna/death/death_animal_gen", "SFX", 60),
    "die.horse": ("actor/fauna/death/death_horse", "SFX", 60),
    "die.predator": ("actor/fauna/animal/lion_death", "SFX", 60),
    "die.pig": ("actor/fauna/animal/pig_death", "SFX", 60),
    # ── wildlife ────────────────────────────────────────────────────────────
    # Lion is 0 A.D.'s only fauna attack clip, so wolf and bear share it.
    "animal.predator_attack": ("actor/fauna/attack/lion", "SFX", 200),
    "animal.sheep": ("actor/fauna/animal/sheep", "SFX", 900),
    "animal.cattle": ("actor/fauna/animal/cattle_select", "SFX", 900),
    "animal.boar": ("actor/fauna/animal/pig", "SFX", 900),
    # ── buildings ───────────────────────────────────────────────────────────
    "building.destroyed": ("attack/destruction/building_collapse_large", "SFX", 0),
    "building.debris": ("attack/destruction/explode_debris", "SFX", 0),
    "gate.open": ("actor/gate/stonegate_open", "SFX", 0),
    "gate.close": ("actor/gate/stonegate_close", "SFX", 0),
    "ship.move": ("actor/ship/ship_move", "SFX", 400),
    # Completion, per building kind. Our 19 non-wall buildings against 0 A.D.'s
    # complete_* set; the walls and the three gates share one each.
    "complete.town_center": ("interface/complete/building/complete_civ_center", "UI", 0),
    "complete.house": ("interface/complete/building/complete_house", "UI", 0),
    "complete.mill": ("interface/complete/building/complete_farmstead", "UI", 0),
    "complete.lumber_camp": ("interface/complete/building/complete_storehouse", "UI", 0),
    "complete.mining_camp": ("interface/complete/building/complete_storehouse", "UI", 0),
    "complete.barracks": ("interface/complete/building/complete_barracks", "UI", 0),
    "complete.market": ("interface/complete/building/complete_market", "UI", 0),
    "complete.blacksmith": ("interface/complete/building/complete_forge", "UI", 0),
    "complete.stable": ("interface/complete/building/complete_stable", "UI", 0),
    "complete.archery_range": ("interface/complete/building/complete_range", "UI", 0),
    "complete.dock": ("interface/complete/building/complete_dock", "UI", 0),
    "complete.field": ("interface/complete/building/complete_field", "UI", 0),
    "complete.tower": ("interface/complete/building/complete_tower", "UI", 0),
    "complete.castle": ("interface/complete/building/complete_fortress", "UI", 0),
    "complete.monastery": ("interface/complete/building/complete_temple", "UI", 0),
    "complete.university": ("interface/complete/building/complete_library", "UI", 0),
    "complete.siege_workshop": ("interface/complete/building/complete_ffactri", "UI", 0),
    "complete.wonder": ("interface/complete/building/complete_wonder", "UI", 0),
    "complete.wall": ("interface/complete/building/complete_wall", "UI", 0),
    "complete.gate": ("interface/complete/building/complete_gate", "UI", 0),
    "complete.universal": ("interface/complete/building/complete_universal", "UI", 0),
    # Selection, per building kind -- the same mapping as completion. Only the
    # kinds whose sound is actually distinctive; the rest fall back to
    # `ui.select_building`, which is why that is `sel_universal`.
    "select.town_center": ("interface/select/building/sel_civ_center", "UI", 60),
    "select.house": ("interface/select/building/sel_house", "UI", 60),
    "select.mill": ("interface/select/building/sel_farmstead", "UI", 60),
    "select.storehouse": ("interface/select/building/sel_storehouse", "UI", 60),
    "select.barracks": ("interface/select/building/sel_barracks", "UI", 60),
    "select.market": ("interface/select/building/sel_market", "UI", 60),
    "select.blacksmith": ("interface/select/building/sel_forge", "UI", 60),
    "select.stable": ("interface/select/building/sel_stable", "UI", 60),
    "select.dock": ("interface/select/building/sel_dock", "UI", 60),
    "select.field": ("interface/select/building/sel_field", "UI", 60),
    "select.tower": ("interface/select/building/sel_tower", "UI", 60),
    "select.castle": ("interface/select/building/sel_fortress", "UI", 60),
    "select.monastery": ("interface/select/building/sel_temple", "UI", 60),
    "select.university": ("interface/select/building/sel_library", "UI", 60),
    "select.wonder": ("interface/select/building/sel_wonder", "UI", 60),
    "select.wall": ("interface/select/building/sel_wall", "UI", 60),
    "select.gate": ("interface/select/building/sel_gate", "UI", 60),
    # ── unit voices ─────────────────────────────────────────────────────────
    # LATIN ONLY, per PLAN.md 9.2.1 and A.7 -- 0 A.D.'s voices are
    # civilisation-specific and taking all four would be four accents in one
    # army. Latin covers the age-4 Roman skin and is the least wrong for the
    # Celtic ages, which have no Celtic voice set in 0 A.D. at all.
    "voice.male.select": ("voice/latin/civ/civ_male_select", "VOICE", 80),
    "voice.male.move": ("voice/latin/civ/civ_male_walk", "VOICE", 80),
    "voice.male.attack": ("voice/latin/civ/civ_male_attack", "VOICE", 80),
    "voice.male.build": ("voice/latin/civ/civ_male_build", "VOICE", 80),
    "voice.male.gather": ("voice/latin/civ/civ_male_gather", "VOICE", 80),
    "voice.male.repair": ("voice/latin/civ/civ_male_repair", "VOICE", 80),
    "voice.male.garrison": ("voice/latin/civ/civ_male_garrison", "VOICE", 80),
    "voice.male.retreat": ("voice/latin/civ/civ_male_retreat", "VOICE", 80),
    "voice.male.trade": ("voice/latin/civ/civ_male_trade", "VOICE", 80),
    "voice.female.select": ("voice/latin/civ/civ_female_select", "VOICE", 80),
    "voice.female.move": ("voice/latin/civ/civ_female_walk", "VOICE", 80),
    "voice.female.attack": ("voice/latin/civ/civ_female_attack", "VOICE", 80),
    "voice.female.build": ("voice/latin/civ/civ_female_build", "VOICE", 80),
    "voice.female.gather": ("voice/latin/civ/civ_female_gather", "VOICE", 80),
    "voice.female.herd": ("voice/latin/civ/civ_female_herd", "VOICE", 80),
    "voice.female.hunt": ("voice/latin/civ/civ_female_hunt", "VOICE", 80),
    "voice.female.work_land": ("voice/latin/civ/civ_female_work_land", "VOICE", 80),
    # ── ambient ─────────────────────────────────────────────────────────────
    "ambient.day": ("ambient/dayscape/day_temperate", "AMBIENT", 0),
    "ambient.wind": ("ambient/weather/wind_reg", "AMBIENT", 0),
    "ambient.farm": ("ambient/building/amb_farm", "AMBIENT", 0),
    "ambient.port": ("ambient/building/amb_port", "AMBIENT", 0),
    "ambient.market": ("ambient/building/amb_trade", "AMBIENT", 0),
    "ambient.shore": ("ambient/water/coastline_beach", "AMBIENT", 0),
}

# Music is single files, not groups -- there is nothing to vary and nothing to
# jitter. Eight of 0 A.D.'s 62 tracks, chosen against our age ladder
# (Briton -> Gaulish -> Iberian/Achaemenid -> Roman, PLAN.md 2.7): two Celtic for
# ages 1-2, an Iberian-flavoured one for age 3, a Roman one for age 4. Taking the
# other 54 would be 219 MB for tracks nothing selects.
MUSIC: dict[str, str] = {
    "menu.theme": "music/Highland_Mist.ogg",
    "match.age1": "music/Celtica.ogg",
    "match.age2": "music/Celtic_Pride.ogg",
    "match.age3": "music/Peaks_of_Atlas.ogg",
    "match.age4": "music/Roman_Ingenuity.ogg",
    "match.combat": "music/Tale_of_Warriors.ogg",
    "match.victory": "music/You_are_Victorious!.ogg",
    "match.defeat": "music/Epitaph.ogg",
}

_POINTER_OID = re.compile(rb"^oid sha256:([0-9a-f]{64})$", re.MULTILINE)
_POINTER_SIZE = re.compile(rb"^size (\d+)$", re.MULTILINE)


class Fetcher:
    """Resolves LFS pointers to real bytes via the LFS HTTP API."""

    def __init__(self) -> None:
        self.downloaded = 0
        self.bytes = 0

    @staticmethod
    def pointer(path: Path) -> tuple[str, int] | None:
        """(oid, size) if `path` is an LFS pointer, else None (already real)."""
        # A pointer is a tiny text file; a real ogg starts with b"OggS". Read a
        # bounded prefix so this stays cheap on a 4 MB track.
        head = path.read_bytes()[:512]
        if head.startswith(b"OggS"):
            return None
        oid = _POINTER_OID.search(head)
        size = _POINTER_SIZE.search(head)
        if not oid or not size:
            return None
        return oid.group(1).decode(), int(size.group(1))

    def _post(self, payload: dict) -> dict:
        req = urllib.request.Request(
            LFS_BATCH,
            data=json.dumps(payload).encode(),
            headers={
                "Accept": _LFS_CT,
                "Content-Type": _LFS_CT,
                "User-Agent": _UA,
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())

    def hrefs(self, wanted: list[tuple[str, int]]) -> dict[str, str]:
        """oid -> download URL, for every oid the server will serve."""
        out: dict[str, str] = {}
        for i in range(0, len(wanted), _BATCH_SIZE):
            chunk = wanted[i : i + _BATCH_SIZE]
            body = self._post(
                {
                    "operation": "download",
                    "transfers": ["basic"],
                    "objects": [{"oid": o, "size": s} for o, s in chunk],
                }
            )
            for obj in body.get("objects", []):
                href = obj.get("actions", {}).get("download", {}).get("href")
                if href:
                    out[obj["oid"]] = href
                else:
                    err = obj.get("error", {}).get("message", "no download action")
                    print(f"  ! {obj.get('oid', '?')[:12]} refused: {err}")
        return out

    def get(self, oid: str, href: str, dest: Path, attempts: int = 4) -> bool:
        """Fetch, verify against the oid, and write. False if it did not verify.

        RETRIES, because this endpoint drops connections under its own rate
        limit rather than answering 429: measured behaviour is a burst of fast
        responses, then ~20 s per object with an occasional
        "connection forcibly closed". A reset is not a missing object, and
        treating it as one would leave holes in the pack that look like an
        unmapped sound.
        """
        for attempt in range(attempts):
            try:
                req = urllib.request.Request(href, headers={"User-Agent": _UA})
                with urllib.request.urlopen(req, timeout=180) as resp:
                    blob = resp.read()
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                if attempt == attempts - 1:
                    print(f"  ! {dest.name}: {exc}")
                    return False
                time.sleep(2 ** attempt)      # 1, 2, 4 s
                continue

            got = hashlib.sha256(blob).hexdigest()
            if got != oid:
                # Not retried: a wrong hash is the wrong object, not a flaky
                # connection, and asking again would get the same bytes.
                print(f"  ! CHECKSUM {dest.name}: wanted {oid[:12]}, got {got[:12]}")
                return False
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(blob)
            self.downloaded += 1
            self.bytes += len(blob)
            return True
        return False


def _split_root(spec: str) -> tuple[Path, str]:
    if spec.startswith("mod:"):
        return ROOTS["mod"], spec[4:]
    return ROOTS["public"], spec


def read_group(spec: str, max_variations: int = _MAX_VARIATIONS) -> dict | None:
    """Parse a 0 A.D. sound group into the fields our seam keeps.

    Returns None and reports if the group is missing. `<Path>` is honoured
    rather than assumed to be the XML's own directory -- `gathering.xml` lives in
    resource/gathering and points at resource/farming, and guessing would have
    silently produced an empty variation list.
    """
    root, rel = _split_root(spec)

    if rel.endswith(".ogg"):  # bare file, no group XML
        src = root / "audio" / rel
        if not src.is_file():
            print(f"  MISSING FILE  {spec}")
            return None
        return {"sources": [src], "gain": 1.0, "pitch": (1.0, 1.0), "looping": False}

    xml = root / "audio" / (rel + ".xml")
    if not xml.is_file():
        print(f"  MISSING GROUP {spec}")
        return None

    tree = ET.parse(xml)
    node = tree.getroot()

    def num(tag: str, default: float) -> float:
        el = node.find(tag)
        if el is None or el.text is None:
            return default
        try:
            return float(el.text.strip())
        except ValueError:
            return default

    # <Path> is relative to the mod root and includes the leading "audio/".
    path_el = node.find("Path")
    base = (path_el.text or "").strip() if path_el is not None else ""
    sources: list[Path] = []
    for snd in node.findall("Sound"):
        name = (snd.text or "").strip()
        if not name:
            continue
        src = root / base / name
        if src.is_file():
            sources.append(src)
        else:
            print(f"  missing variation {base}{name} (group {rel})")

    if not sources:
        print(f"  EMPTY GROUP   {spec}")
        return None

    # Keep what is ALREADY STAGED ahead of the cap, so lowering the cap does not
    # orphan files on disk and raising it does not re-shuffle which five an id
    # uses. Staged-first, then the rest in the group's own order.
    staged = [s for s in sources if res_path(s)[0].is_file()]
    fresh = [s for s in sources if s not in staged]
    sources = (staged + fresh)[:max_variations]

    gain = num("Gain", 1.0)
    # RandGain/RandPitch are 0/1 switches gating the Upper/Lower pairs. When the
    # switch is off the range collapses to a point, which is what pitch 1..1 means
    # downstream -- AudioManager needs no separate "jitter off" flag.
    if num("RandGain", 0.0) >= 1.0:
        gain = (num("GainLower", gain) + num("GainUpper", gain)) * 0.5
    if num("RandPitch", 0.0) >= 1.0:
        pitch = (num("PitchLower", 1.0), num("PitchUpper", 1.0))
    else:
        pitch = (1.0, 1.0)
    if pitch[0] > pitch[1]:
        pitch = (pitch[1], pitch[0])
    pitch = (
        min(max(pitch[0], _PITCH_FLOOR), _PITCH_CEIL),
        min(max(pitch[1], _PITCH_FLOOR), _PITCH_CEIL),
    )

    return {
        "sources": sources,
        "gain": max(gain, 0.0001),
        "pitch": pitch,
        "looping": num("Looping", 0.0) >= 1.0,
    }


def res_path(src: Path) -> tuple[Path, str]:
    """Map a source file to its staged destination and its res:// path.

    Keyed off `audio/` in the source path, so `public` and `mod` land in one tree
    and the res:// path mirrors 0 A.D.'s own layout -- which keeps the mapping
    above readable against the staged files.
    """
    parts = src.parts
    rel = Path(*parts[parts.index("audio") + 1 :])
    return DEST / rel, "res://assets/audio/" + rel.as_posix()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="report, write nothing")
    ap.add_argument(
        "--manifest-only",
        action="store_true",
        help="regenerate data/audio.json from files already staged",
    )
    ap.add_argument(
        "--prune",
        action="store_true",
        help="delete staged .ogg files no sound id references any more "
        "(lowering --max-variations orphans the ones it stops using; the "
        "licence audit reports them, because a packed file with no provenance "
        "is a licence problem and not untidiness)",
    )
    ap.add_argument(
        "--max-variations",
        type=int,
        default=_MAX_VARIATIONS,
        metavar="N",
        help=f"variations to take per sound group (default {_MAX_VARIATIONS}); "
        "raising it fetches only the difference",
    )
    args = ap.parse_args()

    for name, root in ROOTS.items():
        if not (root / "audio").is_dir():
            print(f"0 A.D. '{name}' audio root not found: {root / 'audio'}")
            return 2

    # ── resolve every id to its sources ─────────────────────────────────────
    resolved: dict[str, dict] = {}
    missing_groups: list[str] = []
    for sound_id, (spec, bus, throttle) in SFX.items():
        group = read_group(spec, args.max_variations)
        if group is None:
            missing_groups.append(sound_id)
            continue
        group.update({"bus": bus, "throttle": throttle, "spec": spec})
        resolved[sound_id] = group

    music: dict[str, dict] = {}
    for music_id, rel in MUSIC.items():
        src = ROOTS["public"] / "audio" / rel
        if not src.is_file():
            print(f"  MISSING TRACK {rel}")
            missing_groups.append(music_id)
            continue
        music[music_id] = {"sources": [src], "spec": rel}

    # ── work out which bytes we still need ──────────────────────────────────
    every_source: list[Path] = []
    for entry in list(resolved.values()) + list(music.values()):
        every_source.extend(entry["sources"])
    unique = sorted(set(every_source))

    need: dict[str, list[Path]] = {}       # oid -> destinations
    sizes: dict[str, int] = {}
    already = 0
    for src in unique:
        dest, _ = res_path(src)
        if dest.is_file() and dest.stat().st_size > 512:
            already += 1
            continue
        ptr = Fetcher.pointer(src)
        if ptr is None:
            # Real audio sitting in the checkout: a plain copy, no LFS needed.
            if not args.dry_run and not args.manifest_only:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(src.read_bytes())
            continue
        oid, size = ptr
        need.setdefault(oid, []).append(dest)
        sizes[oid] = size

    total_mb = sum(sizes.values()) / (1024 * 1024)
    print(
        f"\n{len(SFX)} sfx ids + {len(MUSIC)} music ids -> "
        f"{len(unique)} files; {already} already staged, "
        f"{len(need)} to fetch ({total_mb:.1f} MB)"
    )
    if missing_groups:
        print(f"unmapped ({len(missing_groups)}): {', '.join(missing_groups)}")

    if args.dry_run:
        print("(dry run -- nothing written)")
        return 0

    # ── fetch ───────────────────────────────────────────────────────────────
    fetcher = Fetcher()
    failed = 0
    if need and not args.manifest_only:
        print(f"fetching {len(need)} objects from the LFS API ...")
        hrefs = fetcher.hrefs([(oid, sizes[oid]) for oid in need])
        for n, (oid, dests) in enumerate(sorted(need.items()), 1):
            href = hrefs.get(oid)
            if href is None:
                failed += 1
                continue
            first = dests[0]
            if not fetcher.get(oid, href, first):
                failed += 1
                continue
            for extra in dests[1:]:   # same oid wanted at two paths
                extra.parent.mkdir(parents=True, exist_ok=True)
                extra.write_bytes(first.read_bytes())
            if n % 10 == 0 or n == len(need):
                # flush=True or nothing is visible until the run ends -- this can
                # be a long fetch and a silent one is indistinguishable from hung.
                print(f"  {n}/{len(need)}  ({fetcher.bytes / (1024*1024):.1f} MB)",
                      flush=True)

    # ── write the seam ──────────────────────────────────────────────────────
    #
    # A stream is listed only if its bytes are actually on disk. That is what
    # keeps `audio.json` honest: an id with an empty `streams` list is SILENCE,
    # which AudioManager treats as a legitimate state, where an id listing a
    # file that is not there would be a load error at runtime.
    def streams_of(entry: dict) -> list[str]:
        out = []
        for src in entry["sources"]:
            dest, res = res_path(src)
            if dest.is_file() and dest.stat().st_size > 512:
                out.append(res)
        return out

    sfx_out: dict[str, dict] = {}
    for sound_id in sorted(resolved):
        entry = resolved[sound_id]
        sfx_out[sound_id] = {
            "streams": streams_of(entry),
            "bus": entry["bus"],
            "gain_db": round(20.0 * math.log10(entry["gain"]), 2),
            "pitch_min": round(entry["pitch"][0], 3),
            "pitch_max": round(entry["pitch"][1], 3),
            "throttle_ms": entry["throttle"],
            "source_group": entry["spec"],
        }
    # Ids whose group is missing entirely still get an entry, with no streams.
    # The vocabulary is the contract (PLAN.md 7.5): a declared id that is silent
    # and an id that was never declared have to stay distinguishable.
    for sound_id, (spec, bus, throttle) in SFX.items():
        sfx_out.setdefault(
            sound_id,
            {
                "streams": [],
                "bus": bus,
                "gain_db": 0.0,
                "pitch_min": 1.0,
                "pitch_max": 1.0,
                "throttle_ms": throttle,
                "source_group": spec,
            },
        )

    music_out: dict[str, dict] = {}
    for music_id in sorted(MUSIC):
        entry = music.get(music_id)
        music_out[music_id] = {
            "streams": streams_of(entry) if entry else [],
            "bus": "MUSIC",
            "gain_db": 0.0,
            "pitch_min": 1.0,
            "pitch_max": 1.0,
            "throttle_ms": 0,
            "source_group": MUSIC[music_id],
        }

    payload = {
        "_note": [
            "ASSET SEAM for audio (PLAN.md 2.1, 7.5). Same contract as",
            "visuals.json: the only file mapping a sound ID to a path, and no",
            "filename appears in gameplay code -- callers say",
            "AudioManager.play_sfx(&\"villager.chop\") and nothing else.",
            "",
            "GENERATED by tools/stage_audio.py. Do not hand-edit: the id ->",
            "0 A.D. sound-group mapping lives in that script, which is also",
            "where the reasoning for each choice is written down. Re-run it to",
            "change anything here.",
            "",
            "AN EMPTY `streams` LIST IS SILENCE, AND THAT IS A LEGITIMATE",
            "STATE. The audio pack is optional (PLAN.md 3.2), so a build with",
            "no staged audio must play nothing rather than fail to boot -- the",
            "same totality rule atlas_for() follows. What is NOT legitimate is",
            "an id that was never declared: GameDataRegistry.has_sfx() answers",
            "false for it and AudioManager reports it, because that is a",
            "caller bug and silence would hide it.",
            "",
            "`gain_db` and the pitch range are 0 A.D.'s own tuning, converted",
            "from the sound group's <Gain>/<RandGain>/<PitchLower|Upper>. A",
            "pitch range of 1..1 means that group asked for no jitter.",
            "",
            "`throttle_ms` is OURS, not 0 A.D.'s -- the minimum gap between two",
            "plays of one id. Gather and melee sounds fire per tick and a dozen",
            "villagers on one forest would stack into noise without it.",
            "",
            "`source_group` is provenance, for game/assets/LICENCES.md and the",
            "licence audit. 0 A.D. is CC-BY-SA 3.0.",
        ],
        "sfx": sfx_out,
        "music": music_out,
    }

    if not args.dry_run:
        # newline="\n" explicitly: Python's text mode would write CRLF on Windows
        # and every regeneration would show up as a whole-file diff. The rest of
        # the repo's JSON is LF.
        with MANIFEST.open("w", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")

    # ── orphans ─────────────────────────────────────────────────────────────
    referenced: set[Path] = set()
    for entry in list(sfx_out.values()) + list(music_out.values()):
        for res in entry["streams"]:
            referenced.add(DEST / str(res).removeprefix("res://assets/audio/"))
    orphans = [p for p in DEST.rglob("*.ogg") if p not in referenced] if DEST.is_dir() else []
    if orphans:
        if args.prune:
            for p in orphans:
                p.unlink()
            print(f"pruned {len(orphans)} orphaned file(s)")
        else:
            print(
                f"\n{len(orphans)} staged file(s) are no longer referenced "
                f"(--prune to delete; the licence audit will report them)"
            )

    staged = sum(1 for e in sfx_out.values() if e["streams"])
    print(
        f"\nstaged {fetcher.downloaded} new file(s), "
        f"{fetcher.bytes / (1024*1024):.1f} MB"
    )
    print(f"audio.json: {staged}/{len(sfx_out)} sfx ids have streams, "
          f"{sum(1 for e in music_out.values() if e['streams'])}/{len(music_out)} music")
    if failed:
        print(f"FAILED to fetch {failed} object(s)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
