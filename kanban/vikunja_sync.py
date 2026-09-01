#!/usr/bin/env python3
"""Seed and re-sync the AOD_Mobile Vikunja board from kanban/board.json.

    python kanban/vikunja_sync.py --check          # auth + what exists, writes nothing
    python kanban/vikunja_sync.py --dry-run        # every call it WOULD make
    python kanban/vikunja_sync.py                  # do it
    python kanban/vikunja_sync.py --force-bucket   # also drag cards back to board.json's bucket

Stdlib only. Reads Vikunja_API_KEY / Vikunja_API_URL out of ./.env and never prints the key.

--- WHY IT IS SHAPED LIKE THIS -------------------------------------------------

IDEMPOTENT BY THE CARD'S `key`, NOT BY ITS TITLE TEXT. A task is matched on the
literal prefix "<key> - ", so re-running rewrites the card the owner is already
looking at rather than filing a second one beside it. Renaming a card is free;
renumbering a `key` is what creates a duplicate. PLAN.md's own header records that
its numbered list has been renumbered twice and that cross-references drifted both
times, so the keys are deliberately not PLAN.md's authority — they are ours.

AN EXISTING CARD NEVER MOVES BUCKET. If the owner drags 15.2 to Doing, a sync that
shoved it back to ToDo would make the board lie about the work in flight, and the
board would be the least trustworthy document in the project by the second run.
So bucket placement is a SEED, applied once at creation. --force-bucket is the
opt-in, and it is not the default for that reason.

DESCRIPTIONS ARE OVERWRITTEN, BUCKETS ARE NOT. The description is derived from
PLAN.md and asset_request.md, which are the authority; the bucket is derived from
what a human is doing, which they are not.

VIKUNJA v2 CREATES WITH POST, WHERE v1 USED PUT, AND BUCKETS LIVE UNDER A VIEW
(POST /projects/{p}/views/{v}/buckets). Both were confirmed against this
instance's own /api/v2/openapi.json rather than remembered. `done_bucket_id` and
`default_bucket_id` are fields on the VIEW, which is what makes dragging a card
into Done actually complete it instead of just relocating it.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
ENV = ROOT / ".env"
BOARD = Path(__file__).resolve().parent / "board.json"

SEP = " - "  # the delimiter between a card's key and its title


# --------------------------------------------------------------------------- env


def read_env() -> tuple[str, str]:
    if not ENV.exists():
        sys.exit(f"no .env at {ENV}")
    vals: dict[str, str] = {}
    for line in ENV.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        vals[k.strip().lower()] = v.strip().strip('"').strip("'")

    key = vals.get("vikunja_api_key", "")
    url = vals.get("vikunja_api_url", "")
    if not key:
        sys.exit("Vikunja_API_KEY missing from .env")
    if not url:
        sys.exit("Vikunja_API_URL missing from .env")

    # .env points at the human docs page; derive the API base from its origin.
    m = re.match(r"(https?://[^/]+)", url)
    if not m:
        sys.exit(f"could not read a host out of Vikunja_API_URL: {url}")
    return key, m.group(1).rstrip("/") + "/api/v2"


# --------------------------------------------------------------------------- http


class Api:
    def __init__(self, base: str, token: str, dry: bool) -> None:
        self.base, self.token, self.dry = base, token, dry
        self.calls = 0

    def _do(self, method: str, path: str, body: Any = None) -> Any:
        self.calls += 1
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                raw = r.read().decode() or "null"
        except urllib.error.HTTPError as e:
            # 304 IS A SUCCESS HERE AND urllib RAISES IT AS AN ERROR. Vikunja answers
            # 304 Not Modified to a PATCH whose fields already hold the values sent,
            # which is exactly what the belt-and-braces `done` write below produces.
            # Letting it fall through killed the script on a move that had worked.
            if e.code == 304:
                return None
            detail = e.read().decode(errors="replace")[:500]
            if e.code == 401:
                sys.exit(
                    "\n401 from Vikunja: 'missing, malformed, expired or otherwise "
                    "invalid token provided'.\n"
                    "The token in .env is the right SHAPE (tk_ + 40 hex is exactly what\n"
                    "Vikunja mints) but this server does not recognise it. It is expired,\n"
                    "revoked, or from another instance -- Vikunja API tokens carry a\n"
                    "mandatory expiry date.\n\n"
                    "Mint a new one: Vikunja -> avatar -> Settings -> API Tokens -> Create.\n"
                    "It needs read+write on Projects, Tasks and Labels.\n"
                    "Paste it into .env as Vikunja_API_KEY and re-run.\n"
                )
            sys.exit(f"{method} {path} -> HTTP {e.code}: {detail}")
        except urllib.error.URLError as e:
            sys.exit(f"{method} {path} -> cannot reach {self.base}: {e.reason}")
        return json.loads(raw)

    def get(self, path: str) -> Any:
        return self._do("GET", path)

    def write(self, method: str, path: str, body: Any) -> Any:
        if self.dry:
            title = body.get("title") if isinstance(body, dict) else body
            print(f"    [dry-run] {method} {path}  {title!r}")
            return {"id": 0, "title": body.get("title", "") if isinstance(body, dict) else ""}
        return self._do(method, path, body)

    @staticmethod
    def unwrap(payload: Any) -> list[dict]:
        """v2 wraps EVERY list response in a pagination envelope.

            {"$schema": ..., "items": [...], "total": 3, "page": 1, "total_pages": 1}

        v1 returned a bare array, which is what most Vikunja examples in the wild
        show and what the first version of this script assumed.

        THE COST OF THAT ASSUMPTION WAS NOT AN ERROR, WHICH IS WHY IT IS WORTH A
        COMMENT. `isinstance({...}, list)` is simply False, so the old code read a
        server holding three projects as holding none, --check reported
        "0 project(s) visible / project ABSENT", and the run then created a
        DUPLICATE project beside the one that was already there. An envelope that
        degrades to a silent empty list is worse than one that raises, so this
        raises on a shape it does not recognise.
        """
        if isinstance(payload, list):
            return payload
        if isinstance(payload, dict):
            if isinstance(payload.get("items"), list):
                return payload["items"]
            if not payload:
                return []
        if payload is None:
            return []
        raise SystemExit(f"unexpected list-response shape: {str(payload)[:200]}")

    def paged(self, path: str) -> list[dict]:
        """Vikunja caps a page at 50 (max_items_per_page); walk total_pages."""
        out: list[dict] = []
        page = 1
        while True:
            joiner = "&" if "?" in path else "?"
            raw = self.get(f"{path}{joiner}page={page}&per_page=50")
            got = self.unwrap(raw)
            out.extend(got)
            total = raw.get("total_pages") or 1 if isinstance(raw, dict) else 1
            if page >= total or not got:
                return out
            page += 1
            if page > 40:  # a board this size cannot be 2000 tasks; stop rather than spin
                return out


# --------------------------------------------------------------------------- sync


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print every write, make none")
    ap.add_argument("--check", action="store_true", help="auth + inventory only")
    ap.add_argument(
        "--force-bucket",
        action="store_true",
        help="also move EXISTING cards back to board.json's bucket (destroys hand placement)",
    )
    ap.add_argument("--show", action="store_true", help="print the live board, bucket by bucket")
    ap.add_argument(
        "--move",
        nargs=2,
        metavar=("KEY", "BUCKET"),
        help="move one card, e.g. --move 15.1 Doing. THIS is how progress is reported: "
        "board.json's `bucket` is only a seed and a re-sync will not move an existing card.",
    )
    args = ap.parse_args()
    readonly = args.check or args.show

    token, base = read_env()
    board = json.loads(BOARD.read_text(encoding="utf-8"))
    api = Api(base, token, args.dry_run)

    print(f"api      {base}")
    print(f"manifest {BOARD.relative_to(ROOT)}  ({len(board['cards'])} cards)")

    # -- project ------------------------------------------------------------
    want = board["project"]["title"]
    projects = api.paged("/projects")
    print(f"auth     OK -- {len(projects)} project(s) visible")

    project = next((p for p in projects if p.get("title") == want), None)
    if not project:
        # NEVER CREATE A SECOND BOARD OVER A NAME THAT DIFFERS BY CASE. This script
        # already did that once -- 'AOD_Mobile' beside the owner's 'AOD_mobile' --
        # and deleting a project takes its tasks with it, so the failure is not free.
        near = [p for p in projects if (p.get("title") or "").strip().lower() == want.strip().lower()]
        if len(near) == 1:
            project = near[0]
            print(f"project  matched {project['title']!r} (manifest says {want!r} -- case only)")
        elif len(near) > 1:
            sys.exit(f"{len(near)} projects differ from {want!r} by case only; disambiguate by hand")

    if project:
        print(f"project  found  #{project['id']} {want!r}")
    elif args.check:
        print(f"project  ABSENT {want!r} -- a real run would create it")
        return 0
    else:
        project = api.write("POST", "/projects", board["project"])
        print(f"project  created #{project.get('id')} {want!r}")
    pid = project["id"]

    # -- the kanban view ----------------------------------------------------
    views = api.unwrap(api.get(f"/projects/{pid}/views"))
    view = next((v for v in views if v.get("view_kind") == "kanban"), None)
    if not view:
        sys.exit(f"project #{pid} has no kanban view; create one in the UI first")
    vid = view["id"]
    print(f"view     kanban #{vid}")

    # -- buckets ------------------------------------------------------------
    # A fresh Vikunja project ships with a default bucket ("Backlog" or "To-Do").
    # Rename it into the first wanted bucket rather than leaving a sixth column
    # nothing routes to.
    existing = api.unwrap(api.get(f"/projects/{pid}/views/{vid}/buckets"))
    by_title = {b["title"]: b for b in existing}
    buckets: dict[str, int] = {}

    for i, title in enumerate(board["buckets"]):
        if title in by_title:
            buckets[title] = by_title[title]["id"]
            print(f"bucket   have   {title}")
            continue
        spare = next(
            (b for b in existing if b["title"] not in board["buckets"] and b["id"] not in buckets.values()),
            None,
        )
        if spare and i == 0:
            api.write("PUT", f"/projects/{pid}/views/{vid}/buckets/{spare['id']}", {"title": title})
            buckets[title] = spare["id"]
            print(f"bucket   renamed {spare['title']!r} -> {title}")
        else:
            made = api.write("POST", f"/projects/{pid}/views/{vid}/buckets", {"title": title, "position": i + 1})
            buckets[title] = made.get("id", 0)
            print(f"bucket   created {title}")

    # done_bucket_id / default_bucket_id are what make the columns BEHAVE:
    # without them, dragging into Done relocates a card without completing it.
    done_id = buckets.get(board["done_bucket"])
    dflt_id = buckets.get(board["default_bucket"])
    if not args.dry_run and (view.get("done_bucket_id") != done_id or view.get("default_bucket_id") != dflt_id):
        # PATCH, not PUT: a full replace would have to restate filter, position and
        # bucket_configuration, and getting one of those wrong silently reshapes the
        # view. Only two fields are ours to set.
        api.write(
            "PATCH",
            f"/projects/{pid}/views/{vid}",
            {"done_bucket_id": done_id, "default_bucket_id": dflt_id},
        )
        print(f"view     done_bucket={board['done_bucket']} default_bucket={board['default_bucket']}")

    # -- labels -------------------------------------------------------------
    have_labels = {l["title"]: l["id"] for l in api.paged("/labels")}
    labels: dict[str, int] = {}
    for title, colour in board["labels"].items():
        if title in have_labels:
            labels[title] = have_labels[title]
        elif readonly:
            # --check promises to write nothing, and creating five labels is a write.
            # It did exactly that on the first run against a real board.
            print(f"label    ABSENT  {title} -- a real run would create it")
        else:
            made = api.write("POST", "/labels", {"title": title, "hex_color": colour})
            labels[title] = made.get("id", 0)
            print(f"label    created {title}")

    # -- tasks --------------------------------------------------------------
    tasks = api.paged(f"/projects/{pid}/views/{vid}/tasks")
    index: dict[str, dict] = {}
    for t in tasks:
        key = (t.get("title") or "").split(SEP, 1)[0].strip()
        if key:
            index[key] = t
    print(f"tasks    {len(tasks)} on the board, {len(index)} keyed")

    # -- --show / --move ----------------------------------------------------
    # These read the LIVE board. `/views/{v}/tasks` does not populate bucket_id and
    # `/buckets` reports count 0 for everything, so both of those look exactly like
    # an empty board; `/buckets/tasks` is the only endpoint that answers the question.
    if args.show or args.move:
        placed = api.unwrap(api.get(f"/projects/{pid}/views/{vid}/buckets/tasks?per_page=50"))
        where: dict[str, str] = {}
        for b in placed:
            for t in b.get("tasks") or []:
                where[(t.get("title") or "").split(SEP, 1)[0].strip()] = b["title"]

        if args.show:
            for name in board["buckets"]:
                rows = [k for k, v in where.items() if v == name]
                print(f"\n{name}  ({len(rows)})")
                for b in placed:
                    if b["title"] != name:
                        continue
                    for t in sorted(b.get("tasks") or [], key=lambda x: -(x.get("priority") or 0)):
                        flag = "x" if t.get("done") else " "
                        print(f"  [{flag}] p{t.get('priority') or 0}  {t.get('title')}")
            return 0

        key, bucket = args.move
        if bucket not in buckets:
            sys.exit(f"no bucket {bucket!r}; have {', '.join(board['buckets'])}")
        task = index.get(key)
        if not task:
            sys.exit(f"no card keyed {key!r} on the board (try --show)")
        was = where.get(key, "?")
        if was == bucket:
            print(f"{key} is already in {bucket}; nothing to do")
            return 0
        api.write(
            "PUT",
            f"/projects/{pid}/views/{vid}/buckets/{buckets[bucket]}/tasks",
            {"task_id": task["id"], "bucket_id": buckets[bucket], "project_view_id": vid},
        )
        # MEASURED, NOT ASSUMED: the view's `done_bucket_id` DOES fire on an API
        # bucket-move, not only on a drag in the UI -- moving card `10` out of Done and
        # back flipped `done` False then True with no help from here. So this write is
        # a belt-and-braces no-op today (Vikunja answers it 304), kept only because the
        # board's honesty rests on the flag and a card sitting in Done reading as not
        # done is the one failure nobody would look for.
        want_done = bucket == board["done_bucket"]
        if bool(task.get("done")) != want_done:
            api.write("PATCH", f"/tasks/{task['id']}", {"done": want_done})
        print(f"moved {key}: {was} -> {bucket}" + ("  (done=true)" if want_done else ""))
        return 0

    if args.check:
        missing = [c["key"] for c in board["cards"] if c["key"] not in index]
        extra = sorted(set(index) - {c["key"] for c in board["cards"]})
        print(f"\nwould create {len(missing)}: {' '.join(missing) or '-'}")
        print(f"on board but not in the manifest ({len(extra)}): {' '.join(extra) or '-'}")
        return 0

    created = updated = moved = 0
    for card in board["cards"]:
        key, bucket = card["key"], card["bucket"]
        title = f"{key}{SEP}{card['title']}"
        payload = {
            "title": title,
            "description": card["description"].replace("\n", "<br>"),
            "priority": card.get("priority", 0),
            "done": bucket == board["done_bucket"],
        }
        found = index.get(key)

        if found:
            # PATCH, not PUT. A full replace would restate every field of the task,
            # including `bucket_id` and `position` -- which is precisely the hand
            # placement this script promises not to disturb. PATCH touches four fields.
            api.write("PATCH", f"/tasks/{found['id']}", payload)
            task_id = found["id"]
            updated += 1
            place = args.force_bucket
        else:
            made = api.write("POST", f"/projects/{pid}/tasks", payload)
            task_id = made.get("id", 0)
            created += 1
            place = True

        wanted = [labels[n] for n in card.get("labels", []) if n in labels]
        if wanted and task_id:
            api.write("PUT", f"/tasks/{task_id}/labels/bulk", {"labels": [{"id": i} for i in wanted]})

        if place and task_id and bucket in buckets:
            api.write(
                "PUT",
                f"/projects/{pid}/views/{vid}/buckets/{buckets[bucket]}/tasks",
                {"task_id": task_id, "bucket_id": buckets[bucket], "project_view_id": vid},
            )
            moved += 1

    print(f"\ncreated {created}  updated {updated}  placed {moved}  ({api.calls} api calls)")
    if updated and not args.force_bucket:
        print("existing cards kept the bucket they were in -- --force-bucket overrides")
    print(f"\n{base.rsplit('/api/', 1)[0]}/projects/{pid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
