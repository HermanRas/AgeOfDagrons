"""Copy the game's own art and fonts into the website (web/server/app/assets/).

The site reuses the game's UI rather than drawing its own, so the page and the game cannot
drift apart on what Age of Dragon looks like. Re-run after the UI art or the screenshots
change; everything under web/server/app/assets/ is output of this script.

    python tools/stage_site_assets.py

The map-type pictures come from the game's own generator preview, which writes to user://:

    godot --headless --path game res://dev_preview/preview_mapgen.tscn

Photos are re-encoded at a web size -- two How To Play pages are ~900 KB each in the game,
which is right for a phone's texture and wrong for a page that loads six of them. Chrome and
icons are copied byte for byte: they are transparent PNGs and already small.
"""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
GAME = REPO / "game"
OUT = REPO / "web" / "server" / "app" / "assets"
USER_DIR = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "AgeOfDragons"

FONTS = ["NewRocker-Regular.ttf", "CinzelDecorative-Bold.ttf", "CinzelDecorative-Black.ttf",
         # The OFL requires its text to travel with the font, on a website as in the game.
         "OFL-NewRocker.txt", "OFL-CinzelDecorative.txt"]

CHROME = ["panel_ornate.png", "panel_hud.png", "button_normal.png", "button_pressed.png",
          "badge_round.png", "portrait_frame.png"]

ICONS = ["res_food.png", "res_wood.png", "res_gold.png", "res_stone.png", "res_villagers.png",
         "age_1.png", "age_2.png", "age_3.png", "age_4.png", "abil_fire_breath.png",
         "net_host.png", "net_join.png", "pack_download.png", "victory_trophy.png",
         "victory_regicide.png", "lobby_gametype.png", "lobby_mapsize.png", "lobby_team.png",
         "hud_techtree.png", "act_build.png", "act_attack.png", "form_vee.png",
         "stance_defensive.png", "hud_alert.png", "file_save.png"]

# (source, published name, max width)
PHOTOS = [
    (REPO / "assets" / "Splash.jpg", "splash.jpg", 1600),
    (REPO / "Screenshot_HUD.jpg", "shot_hud.jpg", 1600),
    (REPO / "Screenshot_Menu.jpg", "shot_menu.jpg", 1200),
] + [(GAME / "assets" / "ui" / "help" / f"{n}.jpg", f"help_{n}.jpg", 1100) for n in
     ("move_and_gather", "drag_select", "control_groups", "age_up", "zoom_and_pan",
      "minimap_and_panels")]

MAP_TYPES = ["island_2p", "river_2p", "desert_2p", "forest_2p", "archipelago_2p",
             "archipelago_8p", "island_8p"]


def main() -> int:
    problems = []
    for sub in ("fonts", "img", "img/maps"):
        (OUT / sub).mkdir(parents=True, exist_ok=True)

    for name in FONTS:
        _copy(GAME / "assets" / "ui" / "fonts" / name, OUT / "fonts" / name, problems)
    for name in CHROME:
        _copy(GAME / "assets" / "ui" / "chrome" / name, OUT / "img" / name, problems)
    for name in ICONS:
        _copy(GAME / "assets" / "ui" / "icons" / name, OUT / "img" / name, problems)
    _copy(GAME / "assets" / "icons" / "icon_256x256.png", OUT / "img" / "icon.png", problems)

    for src, name, width in PHOTOS:
        if not src.is_file():
            problems.append(f"missing {src}")
            continue
        im = Image.open(src).convert("RGB")
        if im.width > width:
            im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
        im.save(OUT / "img" / name, "JPEG", quality=84, optimize=True, progressive=True)

    for t in MAP_TYPES:
        # One pixel per tile x3 already; the page scales them up with `pixelated`, so they
        # are copied rather than resampled -- resampling would blur the tile edges.
        _copy(USER_DIR / f"mapgen_{t}.png", OUT / "img" / "maps" / f"{t}.png", problems)

    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    total = sum(p.stat().st_size for p in OUT.rglob("*") if p.is_file())
    print(f"staged {OUT.relative_to(REPO)}  {total / 1e6:.1f} MB")
    return 0


def _copy(src: Path, dest: Path, problems: list[str]) -> None:
    if not src.is_file():
        problems.append(f"missing {src}")
        return
    shutil.copyfile(src, dest)


if __name__ == "__main__":
    sys.exit(main())
