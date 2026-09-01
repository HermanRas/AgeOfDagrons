# kanban/ — the Vikunja board

The project's **status layer**, on the owner's instruction of 2026-09-01: work is tracked as
cards moving **To-Do → Doing → Test → Blocked → Done** on
[projects.dragoon.co.za/projects/2](https://projects.dragoon.co.za/projects/2) instead of as
prose in a markdown table.

**Seeded 2026-09-01: 64 cards** — 40 To-Do, 1 Doing, 6 Blocked, 17 Done, 0 Test.

The five bucket titles and their order are **the owner's board as it already existed**, read
off the live view rather than chosen here. Two differences from the request are the board's,
not this directory's: **`To-Do` carries a hyphen** (Vikunja's own default first bucket, and
renaming it would only move the discrepancy into the UI), and **Test sits before Blocked**.
A board a human has already arranged wins over a list in a sentence.

```
kanban/board.json       the cards, and the only place they are authored
kanban/vikunja_sync.py  pushes board.json at the board. Idempotent. Stdlib only.
```

```powershell
$py = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe"

& $py kanban\vikunja_sync.py --check     # auth, inventory, what it would create. Writes nothing
& $py kanban\vikunja_sync.py --dry-run   # every call it would make
& $py kanban\vikunja_sync.py             # do it
```

---

## Which document is the authority for what

This is the part worth reading, because this repo has paid twice for a second list nobody
kept in step — `ASSET_MISSING.md`, deleted 2026-08-16 for drifting out of step with the
tracker it claimed to mirror, and `PROGRESS.md`'s own header, which admits it *"goes stale
first"* and that its two headline figures were overtaken within hours of being written.

**A board full of copied reasoning would be the third.** So:

| Document | Owns | Does not own |
|---|---|---|
| **PLAN.md** | architecture, phase order, the numbered rows, and every *why* | status |
| **asset_request.md** | the art conversation, request and answer in place | status |
| **BUGS.md** | the owner's playtest findings and the behaviour they want | status |
| **the Vikunja board** | **status, and only status** — which column a card is in | reasoning |
| ~~PROGRESS.md~~ | *deleted 2026-09-01.* See below | |

**PROGRESS.md is what the board replaced, and it was DELETED on 2026-09-01** (the owner's
call) rather than kept as a snapshot — the third tracker this repo has removed instead of
keeping in step, after `ASSET_MISSING.md` and `UI_Design.md`. It is in git;
`git show HEAD~1:PROGRESS.md` if the old phase table is ever wanted.

**Seven references to it survive and four are active false claims**, not merely dead links:
`README.md:33` and `Docs/README.md:18` say *"PROGRESS.md is the status document"*,
`README.md:177` calls it *"the authoritative version"*, and `asset_request.md:14` says its
priority table is *"derived from PROGRESS.md"* — which now derives from the board. Left
rather than churned, in this repo's idiom for a superseded citation, but **fix those four
first** if either README is opened: a wrong pointer costs more than a broken one.

**PLAN.md is no longer updated as work lands either.** The owner asks for those updates
themselves, at a major commit — *"i will manually request updates to plan.md when we commit
major changes."* It stays the authority for architecture and reasoning, and **where the
board and PLAN.md disagree, PLAN.md wins and the board is the one to fix.** That was
PROGRESS.md's own rule and it is worth keeping, because PLAN.md is the document read next
to the code.

---

## What a card's description is for

Each card carries the **traps and measured figures that make the row expensive to start
cold** — not a summary of PLAN.md. A card says *"a pinned seed is not a pinned map"* and
*"the objective vocabulary is integer-only"* because whoever picks up 15.1 needs those in
front of them; it does not restate what 15.1 is, because PLAN.md 15.1 does that and is one
click away.

The rule for adding one: **if the sentence would be equally true a year from now and cost
someone a day to rediscover, it belongs on the card.** Everything else belongs in PLAN.md.

## Card granularity

A card is a **numbered PLAN.md row** — 15.1, 16.4, 2.4c — because that is the unit PLAN.md
itself calls *"a place you can stop"*. Art cards use `asset_request.md`'s own P-numbers.
Three phases that closed whole and list no open rows (6, 7, 10) get one card each.

## The `key` is the identity

`board.json`'s `key` becomes the card's title prefix (`15.1 - Scenario and campaign data`)
and is what the sync matches on. **Renaming a card is free; renumbering a `key` files a
second card beside the first.** PLAN.md's §15 header records that its numbered list has been
renumbered twice and that cross-references drifted both times — which is exactly why the
keys are ours and not PLAN.md's line numbering.

## An existing card never changes bucket

Bucket placement in `board.json` is a **seed**, applied once when the card is created. A
re-sync rewrites descriptions and labels but leaves the column alone, because the column is
what a human is doing and the description is what PLAN.md says. A sync that dragged 15.2
back to ToDo every time it ran would make the board the least trustworthy document in the
project by its second run.

`--force-bucket` overrides this. It is not the default for that reason.

**MEASURED 2026-09-01, because the art agent suspected the script of exactly this and spent
real time on it.** A card hand-placed away from its seed bucket survives a bare sync, *and
it survives one that genuinely changes its description* — the second half matters, because
an unchanged PATCH answers 304 and proves nothing about the case you care about. Probe: P5,
seeded `To-Do`, parked in `Test`, description edited, synced; it stayed in `Test`.

**What actually moved the card was the other agent.** Both of us write to this board and
neither can see the other do it, and Vikunja shows no history — so a card that moved on its
own is far more likely to be a colleague than a bug. **Say so in `asset_request.md` when you
move a card that is not yours.** That costs one line and saves the next person this probe.

**A `done` write DOES relocate a card, and that one is deliberate.** Changing a card's seed
to the done bucket and re-syncing lands it in `Done` without a `--move`, because the PATCH
carries `done: true` and the view's `done_bucket_id` acts on it. Do not read that as the
bucket seed working — it is the done flag, and it only has this effect in that one
direction.

## Labels

`game-code` · `art` — the two-agent fence of `AGENT_GAME_CODER.md` §1 and
`AGENT_ASSET.md`, on one board. One board rather than two projects because the fence is
about *who edits which directory*, not about who can see the work: 5.7 being blocked on the
art side's A.10 is the single most useful thing either agent can read off this board, and
two projects hide it.

`owner-decision` — a card that cannot move without the project owner. There are four.

`blocked-on-art` — on the Blocked column's cards, so "why" survives a filter that drops the
column.

---

## Where this lives, and the ownership fence

`kanban/` is a new top level directory and belongs to neither agent's side of
`AGENT_GAME_CODER.md` §1: it is not `game/` (the game-code agent's) and not `tools/` (the
art agent's). It is project infrastructure, added at the owner's request, and **both agents
write to it** — the art agent maintains the `art`-labelled cards the way it answers in
`asset_request.md` today.

## The token

`Vikunja_API_KEY` in `./.env`, which is **gitignored as of 2026-09-01** — it was not before,
and `origin` is a public GitHub repo, so it was one `git add -A` from a published
credential. A Vikunja token grants read+write on every project its issuing user can see;
there is no scoping it down to one board.

Vikunja API tokens carry a **mandatory expiry date**, so this will need re-minting on a
schedule rather than once: *avatar → Settings → API Tokens → Create*, with read+write on
Projects, Tasks and Labels. `--check` is the cheap way to find out whether it is still good,
and `vikunja_sync.py` prints those instructions on any 401 rather than a stack trace.

## API notes, confirmed against this instance rather than remembered

Server is **Vikunja v2.6.0**; `/api/v1` and `/api/v2` are both live and the schema is at
`/api/v2/openapi.json`.

- ⚠️ **EVERY LIST RESPONSE IS WRAPPED IN A PAGINATION ENVELOPE** — `{"items": [...],
  "total": n, "page": 1, "total_pages": n}` — where v1 returned a bare array. **This one cost
  a duplicate project.** The first version of the sync tested `isinstance(payload, list)`,
  which is simply `False` for a dict, so a server holding three projects read as holding
  none, `--check` reported *"0 project(s) visible / project ABSENT"*, and the run created a
  second `AOD_Mobile` beside the owner's `AOD_mobile`. (Deleted; it was empty.) An envelope
  that degrades to a silent empty list is worse than one that raises, so `Api.unwrap` raises
  on any shape it does not recognise, and the project lookup now also matches
  case-insensitively rather than creating a near-twin.
- **v2 creates with `POST`**, but **updates with `PUT`/`PATCH` and there is no `POST` on the
  update routes at all.** v1 used `POST /tasks/{id}`, and most Vikunja examples in the wild
  are v1. This script uses **`PATCH`** for tasks and views deliberately: a `PUT` full-replace
  would restate `bucket_id` and `position`, which is exactly the hand placement it promises
  not to disturb.
- **Buckets live under a view**, not under a project:
  `POST /projects/{p}/views/{v}/buckets`, and a rename is `PUT` on `.../buckets/{id}`.
- ⚠️ **`GET /projects/{p}/views/{v}/tasks` DOES NOT POPULATE `bucket_id`**, and
  `GET .../buckets` reports `count: 0` for every bucket. Both look exactly like placement
  having failed. **`GET /projects/{p}/views/{v}/buckets/tasks` is the authoritative
  bucket→task mapping** — verify placement there and nowhere else.
- **`done_bucket_id` and `default_bucket_id` are fields on the VIEW.** Setting them is what
  makes dragging a card into Done actually *complete* it, and what makes a card created in
  the UI land in ToDo. Without them the five columns look right and behave like five
  arbitrary lists.
- **A page is capped at 50** (`max_items_per_page`), so anything listing tasks pages. At 65
  cards the board is already over one page, which is how the envelope bug stayed invisible
  for one run and then was not.
- **Do not judge the board's text through PowerShell.** `Invoke-RestMethod` piped to the
  console printed `campaign â scenario 3` for a card the server stores as a correct
  `campaign — scenario 3` (U+2014, verified by reading the API from Python with an explicit
  `.decode("utf-8")`). This is `AGENT_GAME_CODER.md` §2's trap wearing a new hat: a console
  dump is not evidence about encoding. All 64 cards are clean; the one card holding a real
  U+00A0 is the owner's own `phase_5.1` test card.
