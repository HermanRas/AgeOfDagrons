#!/usr/bin/env python
"""card.py -- talk to ONE Vikunja card at a time. The board is the only truth.

    $py = "C:\\Users\\herman.ras\\Downloads\\AOD_game\\tools_env\\venv\\Scripts\\python.exe"

    & $py kanban\\card.py list                 # the whole board
    & $py kanban\\card.py list --label art     # just mine
    & $py kanban\\card.py show P6              # one card, description and all
    & $py kanban\\card.py move P6 Doing        # scoped: this card, nothing else
    & $py kanban\\card.py append P6 notes.md   # ADD to the description, clobber nothing
    & $py kanban\\card.py new P10 "ART -- title" --bucket To-Do

THE POINT OF THIS FILE, and why it replaced `vikunja_sync.py` for day-to-day work
(owner, 2026-09-01: "nothing lives in repo, everything lives online, no board.json
for sync"):

  * A SYNC IS NOT A SCOPED WRITE. A bare `vikunja_sync.py` PATCHes the title,
    description, labels and done flag of EVERY card from `board.json` -- 65 of
    them, both agents' alike. There was no way to touch one card, so every edit
    was a whole-board write and the two agents overwrote each other.
  * `board.json` WAS A SECOND SOURCE OF TRUTH and it drifted, which is the same
    failure this project has now had four times (ASSET_MISSING.md, PROGRESS.md,
    UI_Design.md, and the board's own seeded-from-stale-PLAN.md descriptions).
    The server holds the cards; nothing here mirrors them.

THE WORKFLOW THIS IS SHAPED FOR, in the owner's words: "ready the card. do the
work, check the card for updated, add your updated."

    show KEY        before starting -- read what the card actually says now
    ...do the work...
    show KEY        again -- someone may have written to it while you worked
    append KEY      add yours to the end; never overwrite what you just read

`append` exists so that reading and writing cannot race into a clobber. `set`
replaces a description outright and needs --replace spelled out, because a card
is a shared document and losing someone's note is silent.

THE FENCE IS ENFORCED HERE, NOT REMEMBERED. Owner, 2026-09-01: the art agent
touches `art`-labelled cards only. Every write checks the card's labels first and
refuses a `game-code` card outright -- column, description, title, all of it. If
one of my cards belongs to the other side, the OWNER swaps the label; --i-am
does not exist as an override and is not going to.

⚠️ `kanban/card_game.py` IMPORTS THIS MODULE AND SWAPS `MINE`/`THEIRS` to put the
game-code side of the fence in force -- ten lines rather than a second copy, which is
the right call and keeps one implementation. Two consequences for whoever edits here:

  * **`MINE` and `THEIRS` are a published interface now, not private constants.** The
    wrapper asserts their exact values before overriding and exits loudly if they have
    changed, so a rename cannot silently leave the game side running under the ART
    fence -- but it WILL stop their tool dead. Renaming is allowed; doing it without
    telling them in `asset_request.md` is not.
  * **Anything that should follow the fence must read `MINE`/`THEIRS` at call time,
    never bake the string "art" in.** `--by` did exactly that and had to be worked
    around in their wrapper; it now defaults to `MINE`. That is the shape of bug to
    look for when adding a flag here.

ENCODING: this is Python on purpose. PowerShell 5.1's Invoke-RestMethod decodes a
charset-less response as ISO-8859-1, which turns the em dash every card title
carries into `ART â roster` -- observed against this very board, and it writes the
corruption back on a PATCH. json.dumps().encode() is UTF-8 by construction.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path
from typing import Any

ENV = Path(__file__).resolve().parent.parent / ".env"
PROJECT_NAME = "AOD_mobile"
SEP = " - "  # delimiter between a card's key and its title
MINE = "art"  # the label this tool is allowed to write
THEIRS = "game-code"  # the label it must never write


# --------------------------------------------------------------------------- env


def read_env() -> tuple[str, str]:
    if not ENV.exists():
        sys.exit(f"no .env at {ENV}")
    vals: dict[str, str] = {}
    for line in ENV.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            vals[k.strip().lower()] = v.strip().strip('"').strip("'")
    key, url = vals.get("vikunja_api_key", ""), vals.get("vikunja_api_url", "")
    if not key or not url:
        sys.exit("Vikunja_API_KEY / Vikunja_API_URL missing from .env")
    m = re.match(r"(https?://[^/]+)", url)
    if not m:
        sys.exit(f"could not read a host out of Vikunja_API_URL: {url}")
    return key, m.group(1).rstrip("/") + "/api/v2"


# --------------------------------------------------------------------------- http


class Api:
    def __init__(self, base: str, token: str) -> None:
        self.base, self.token = base, token

    def _call(self, method: str, path: str, body: Any = None) -> Any:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Content-Type", "application/json; charset=utf-8")
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read().decode("utf-8") or "null")
        except urllib.error.HTTPError as e:
            # 304 means "every field you sent already holds that value". urllib
            # raises it as an error; it is a success and must not kill a run.
            if e.code == 304:
                return None
            if e.code == 401:
                sys.exit(
                    "\n401 -- the .env token is expired, revoked, or from another "
                    "instance.\nVikunja enforces an expiry on API tokens.\n"
                    "Mint a new one: avatar -> Settings -> API Tokens -> Create,\n"
                    "with read+write on Projects, Tasks and Labels, and paste it\n"
                    "into .env as Vikunja_API_KEY.\n"
                )
            sys.exit(f"{e.code} {method} {path}\n{e.read().decode(errors='replace')[:600]}")

    def get(self, path: str) -> Any:
        return self._call("GET", path)

    def post(self, path: str, body: Any) -> Any:
        return self._call("POST", path, body)

    def patch(self, path: str, body: Any) -> Any:
        return self._call("PATCH", path, body)

    def put(self, path: str, body: Any) -> Any:
        return self._call("PUT", path, body)


def items(resp: Any) -> list:
    """Vikunja v2 wraps list results in {items: [...]}; v1 returned a bare array.

    Both shapes are in play depending on the endpoint, so never index a response
    directly -- that is how this cost an afternoon the first time.
    """
    if resp is None:
        return []
    if isinstance(resp, list):
        return resp
    return resp.get("items") or []


# --------------------------------------------------------------------------- board


class Board:
    """The live board. Nothing is cached to disk -- the server IS the manifest."""

    def __init__(self, api: Api) -> None:
        self.api = api
        projects = items(api.get("/projects"))
        match = [p for p in projects if p.get("title") == PROJECT_NAME]
        if not match:
            have = ", ".join(sorted(p.get("title", "?") for p in projects))
            sys.exit(f"no project {PROJECT_NAME!r}; visible: {have}")
        self.pid = match[0]["id"]

        views = items(api.get(f"/projects/{self.pid}/views"))
        kanban = [v for v in views if v.get("view_kind") in ("kanban", 3)]
        if not kanban:
            sys.exit(f"project {self.pid} has no kanban view")
        self.vid = kanban[0]["id"]

        # GET /views/{v}/tasks leaves bucket_id empty and GET .../buckets reports
        # count 0 for everything -- both read as an empty board. This endpoint is
        # the only one that actually maps a task to its column.
        self.buckets: dict[str, int] = {}
        self.where: dict[int, str] = {}
        self.cards: dict[str, dict] = {}
        for b in items(api.get(f"/projects/{self.pid}/views/{self.vid}/buckets/tasks?per_page=100")):
            self.buckets[b["title"]] = b["id"]
            for t in b.get("tasks") or []:
                self.where[t["id"]] = b["title"]

        for t in items(api.get(f"/projects/{self.pid}/tasks?per_page=200")):
            key = t.get("title", "").split(SEP, 1)[0].strip()
            if key:
                self.cards[key] = t

    def card(self, key: str) -> dict:
        t = self.cards.get(key)
        if not t:
            near = [k for k in self.cards if k.lower().startswith(key.lower()[:3])]
            hint = ("  did you mean: " + ", ".join(sorted(near)[:6])) if near else ""
            sys.exit(f"no card with key {key!r}.{hint}")
        return t

    @staticmethod
    def labels(t: dict) -> list[str]:
        return [lb.get("title", "") for lb in (t.get("labels") or [])]

    def guard(self, t: dict) -> None:
        """The owner's fence, enforced rather than remembered."""
        labs = self.labels(t)
        if THEIRS in labs:
            sys.exit(
                f"\nREFUSED -- {t['title']!r} carries the {THEIRS!r} label.\n"
                f"The art agent updates and moves {MINE!r} cards only (owner, 2026-09-01).\n"
                "Say it in asset_request.md and leave the card alone. If this card\n"
                "should be mine, the OWNER swaps the label -- not this tool.\n"
            )
        if MINE not in labs:
            sys.exit(
                f"\nREFUSED -- {t['title']!r} carries no {MINE!r} label (has: "
                f"{', '.join(labs) or 'none'}).\nOnly {MINE!r} cards are writable here.\n"
            )


# --------------------------------------------------------------------------- text


def to_html(text: str) -> str:
    return text.replace("\r\n", "\n").rstrip("\n").replace("\n", "<br>")


def to_text(html: str) -> str:
    return re.sub(r"<br\s*/?>", "\n", html or "").strip()


def read_input(src: str) -> str:
    if src == "-":
        return sys.stdin.read()
    p = Path(src)
    if p.exists():
        return p.read_text(encoding="utf-8")
    return src  # a literal string is fine for a one-liner


# --------------------------------------------------------------------------- commands


def cmd_list(board: Board, args) -> int:
    rows = []
    for key, t in board.cards.items():
        labs = board.labels(t)
        if args.label and args.label not in labs:
            continue
        bucket = board.where.get(t["id"], "?")
        if args.bucket and bucket != args.bucket:
            continue
        if args.pattern and not re.search(args.pattern, t.get("title", ""), re.I):
            continue
        rows.append((bucket, -(t.get("priority") or 0), key, t, labs))

    order = {b: i for i, b in enumerate(board.buckets)}
    rows.sort(key=lambda r: (order.get(r[0], 99), r[1], r[2]))
    for bucket, _, key, t, labs in rows:
        flag = "x" if t.get("done") else " "
        mine = "*" if MINE in labs else " "
        print(f"{bucket:<8}[{flag}]{mine} {key:<18}#{t['id']:<4} {t['title'].split(SEP, 1)[-1]}")
    print(f"\n{len(rows)} card(s).  * = {MINE!r}, writable here.  [x] = done.")
    return 0


def cmd_show(board: Board, args) -> int:
    t = board.card(args.key)
    labs = board.labels(t)
    print(f"key       {args.key}")
    print(f"id        {t['id']}")
    print(f"title     {t['title']}")
    print(f"bucket    {board.where.get(t['id'], '?')}")
    print(f"done      {t.get('done')}")
    print(f"priority  {t.get('priority')}")
    print(f"labels    {', '.join(labs) or '-'}")
    print(f"writable  {'yes' if MINE in labs and THEIRS not in labs else 'NO -- not mine'}")
    print(f"updated   {t.get('updated', '?')}")
    print("\n--- description ---")
    print(to_text(t.get("description", "")) or "(empty)")
    return 0


def cmd_move(board: Board, args) -> int:
    t = board.card(args.key)
    board.guard(t)
    if args.bucket not in board.buckets:
        sys.exit(f"no bucket {args.bucket!r}; have {', '.join(board.buckets)}")
    was = board.where.get(t["id"], "?")
    if was == args.bucket:
        print(f"{args.key} is already in {args.bucket}; nothing to do")
        return 0
    board.api.put(
        f"/projects/{board.pid}/views/{board.vid}/buckets/{board.buckets[args.bucket]}/tasks",
        {"task_id": t["id"], "bucket_id": board.buckets[args.bucket], "project_view_id": board.vid},
    )
    # MEASURED, not assumed: the view's done_bucket_id does fire on an API move,
    # so this is belt and braces -- but a card sitting in Done reading as not done
    # is the one inconsistency nobody would think to look for.
    want = args.bucket == "Done"
    if bool(t.get("done")) != want:
        board.api.patch(f"/tasks/{t['id']}", {"done": want})
    print(f"moved {args.key}: {was} -> {args.bucket}" + ("  (done=true)" if want else ""))
    return 0


def cmd_append(board: Board, args) -> int:
    t = board.card(args.key)
    board.guard(t)
    body = read_input(args.text).strip()
    if not body:
        sys.exit("nothing to append")
    stamp = f"[{args.by} {date.today().isoformat()}]"
    old = t.get("description", "") or ""
    new = (old + "<br><br>" if old.strip() else "") + to_html(f"{stamp} {body}")
    board.api.patch(f"/tasks/{t['id']}", {"description": new})
    print(f"appended {len(body)} chars to {args.key} (description now {len(new)} chars)")
    print("re-read it with `show` if anyone else may have written while you worked")
    return 0


def cmd_set(board: Board, args) -> int:
    t = board.card(args.key)
    board.guard(t)
    if not args.replace:
        sys.exit(
            "REFUSED -- `set` overwrites the whole description, including anything\n"
            "the owner or the other agent wrote there. Pass --replace if you mean it,\n"
            "or use `append`, which cannot clobber."
        )
    body = read_input(args.text)
    board.api.patch(f"/tasks/{t['id']}", {"description": to_html(body)})
    print(f"replaced the description of {args.key} ({len(body)} chars)")
    return 0


def cmd_new(board: Board, args) -> int:
    if args.key in board.cards:
        sys.exit(f"key {args.key!r} already exists (#{board.cards[args.key]['id']}); use append/move")
    if MINE not in args.labels:
        sys.exit(f"REFUSED -- a card made here must carry the {MINE!r} label; got {args.labels}")
    if THEIRS in args.labels:
        sys.exit(f"REFUSED -- this tool does not create {THEIRS!r} cards")
    if args.bucket not in board.buckets:
        sys.exit(f"no bucket {args.bucket!r}; have {', '.join(board.buckets)}")

    desc = to_html(read_input(args.desc)) if args.desc else ""
    made = board.api.post(
        f"/projects/{board.pid}/tasks",
        {"title": f"{args.key}{SEP}{args.title}", "description": desc,
         "priority": args.priority, "done": args.bucket == "Done"},
    )
    tid = made.get("id")

    have = {lb["title"]: lb["id"] for lb in items(board.api.get("/labels?per_page=100"))}
    missing = [n for n in args.labels if n not in have]
    if missing:
        sys.exit(f"created #{tid} but these labels do not exist: {', '.join(missing)}")
    board.api.put(f"/tasks/{tid}/labels/bulk", {"labels": [{"id": have[n]} for n in args.labels]})
    board.api.put(
        f"/projects/{board.pid}/views/{board.vid}/buckets/{board.buckets[args.bucket]}/tasks",
        {"task_id": tid, "bucket_id": board.buckets[args.bucket], "project_view_id": board.vid},
    )
    print(f"created {args.key} as #{tid} in {args.bucket}, labels {', '.join(args.labels)}")
    return 0


# --------------------------------------------------------------------------- cli


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list", help="the live board")
    p.add_argument("pattern", nargs="?", help="regex against the title")
    p.add_argument("--label", help=f"only cards with this label, e.g. {MINE}")
    p.add_argument("--bucket")
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("show", help="one card in full, description included")
    p.add_argument("key")
    p.set_defaults(fn=cmd_show)

    p = sub.add_parser("move", help="move one card to a bucket")
    p.add_argument("key")
    p.add_argument("bucket")
    p.set_defaults(fn=cmd_move)

    p = sub.add_parser("append", help="add to a description without clobbering it")
    p.add_argument("key")
    p.add_argument("text", help="a file path, a literal string, or - for stdin")
    # default=MINE, NOT the literal "art". The parser is built inside main(), after a
    # wrapper has had its chance to swap the constants, so this follows the fence
    # rather than the file. card_game.py had to pass --by explicitly to work around
    # the literal; it no longer needs to, and its explicit flag still wins if kept.
    p.add_argument("--by", default=MINE, help="who is writing (stamped on the note)")
    p.set_defaults(fn=cmd_append)

    p = sub.add_parser("set", help="REPLACE a description (needs --replace)")
    p.add_argument("key")
    p.add_argument("text", help="a file path, a literal string, or - for stdin")
    p.add_argument("--replace", action="store_true")
    p.set_defaults(fn=cmd_set)

    p = sub.add_parser("new", help=f"create a {MINE!r} card")
    p.add_argument("key")
    p.add_argument("title")
    p.add_argument("--bucket", default="To-Do")
    p.add_argument("--priority", type=int, default=2)
    p.add_argument("--labels", nargs="+", default=[MINE])
    p.add_argument("--desc", help="a file path, a literal string, or - for stdin")
    p.set_defaults(fn=cmd_new)

    args = ap.parse_args(argv)
    token, base = read_env()
    return args.fn(Board(Api(base, token)), args)


if __name__ == "__main__":
    raise SystemExit(main())
