#!/usr/bin/env python
"""card_game.py -- the GAME-CODE agent's end of `card.py`. The board is the only truth.

    $py = "C:\\Users\\herman.ras\\Downloads\\AOD_game\\tools_env\\venv\\Scripts\\python.exe"

    & $py kanban\\card_game.py list --label game-code   # just mine
    & $py kanban\\card_game.py show 15.5                # one card, description and all
    & $py kanban\\card_game.py move 15.5 Doing          # scoped: this card, nothing else
    & $py kanban\\card_game.py append 15.5 notes.md     # ADD to the description
    & $py kanban\\card_game.py new 17.1 "Title"         # create a game-code card

WHY THIS IS TEN LINES AND NOT A SECOND COPY OF `card.py`.

`card.py` is the ART agent's tool and is theirs to change. It hard-codes
`MINE = "art"` / `THEIRS = "game-code"` at module scope, which is correct for them and
refuses every card of mine. Three ways to get a game-code equivalent, and only one of
them is cheap AND does not rot:

  * Add a `--side` flag to `card.py`. **Rejected: it is not my file.** The fence the
    owner set on 2026-09-01 is exactly about not reaching across, and reaching across
    to widen the tool that enforces the fence would be a poor place to start.
  * Copy the 400 lines. **Rejected**, and `MapMaker`'s decision 3 is the argument this
    repo already makes: *a copy nobody diffs is a copy that has drifted*. Two tools
    that must behave identically about a shared board is the same failure as two
    documents that must agree about status.
  * Import it and swap the two constants, which is this file. One implementation, one
    place to fix a bug, and the art side's default behaviour is untouched.

⚠️ **THE CONSTANTS ARE CHECKED BEFORE THEY ARE OVERRIDDEN, and that check is the whole
reason this is safe.** Setting an attribute on a module always succeeds, so if `card.py`
ever renames `MINE` this wrapper would silently stop swapping anything -- and silently
mean I was running with the ART side's fence, free to write their cards and refused on
my own. That failure is invisible, so it is asserted rather than trusted. Same shape as
MapMaker refusing to save when its copied format files stop matching the originals.

**A DUAL-LABELLED CARD IS UNWRITABLE FROM BOTH TOOLS, BY DESIGN.** `card.py`'s guard
refuses anything carrying the other side's label, so a card labelled both `art` and
`game-code` is refused here AND there. That is correct: two labels means two agents each
with a defensible claim. **A tag swap is the OWNER's**, done in the Vikunja UI, and
neither tool has a command for it on purpose.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import card  # noqa: E402  -- the path insert above has to happen first

# What `card.py` is expected to say before we swap it. Not a version check: these two
# names ARE the fence, so drifting away from them is the one change that matters here.
_EXPECT_MINE = "art"
_EXPECT_THEIRS = "game-code"

if getattr(card, "MINE", None) != _EXPECT_MINE or getattr(card, "THEIRS", None) != _EXPECT_THEIRS:
    sys.exit(
        "REFUSED -- kanban/card.py no longer declares "
        f"MINE={_EXPECT_MINE!r} / THEIRS={_EXPECT_THEIRS!r}.\n"
        f"It now says MINE={getattr(card, 'MINE', None)!r} / "
        f"THEIRS={getattr(card, 'THEIRS', None)!r}.\n\n"
        "This wrapper swaps those two constants to put the GAME-CODE side of the fence\n"
        "in force. If they have been renamed or re-valued, the swap silently stops\n"
        "happening and every write here would run under the ART side's fence instead --\n"
        "refused on my own cards and permitted on theirs. Fix this file, do not edit\n"
        "card.py, and raise it in asset_request.md."
    )

card.MINE = "game-code"
card.THEIRS = "art"


def main() -> int:
    argv = sys.argv[1:]
    # `append` stamps a note with who wrote it, and card.py's default is a literal
    # "art" rather than its MINE constant -- so it is the one thing the swap above
    # does not reach. Fill it in rather than leaving my notes signed by the art side.
    if argv and argv[0] == "append" and "--by" not in argv:
        argv = argv + ["--by", "game-code"]
    return card.main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
