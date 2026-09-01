# kanban/ — the Vikunja board

The project's **status layer**, on the owner's instruction of 2026-09-01: work is tracked as
cards moving **To-Do → Doing → Test → Blocked → Done** on
[projects.dragoon.co.za/projects/2](https://projects.dragoon.co.za/projects/2).

> ## ⚠️ NOTHING IN THIS REPO MIRRORS THE BOARD. THE SERVER IS THE ONLY TRUTH.
>
> The owner's ruling, 2026-09-01: *"nothing lives in repo, everything lives online, no
> board.json for sync"*. **`board.json` and `vikunja_sync.py` are deleted** — see
> *Why the sync went* below. Read a card with `show`; write one with `move`/`append`.

```
kanban/card.py        the ART agent's tool     -- writes `art` cards only
kanban/card_game.py   the GAME-CODE agent's    -- writes `game-code` cards only
```

```powershell
$py = "C:\Users\herman.ras\Downloads\AOD_game\tools_env\venv\Scripts\python.exe"

& $py kanban\card_game.py list --label game-code   # mine
& $py kanban\card_game.py show 15.5                # one card, description and all
& $py kanban\card_game.py move 15.5 Doing          # scoped: this card, nothing else
& $py kanban\card_game.py append 15.5 notes.md     # ADD to a description, clobber nothing
& $py kanban\card_game.py new 17.1 "Title"         # create
```

`card_game.py` is **ten lines wrapping `card.py`**, not a copy of it: it imports the module
and swaps the two constants that name the fence, so there is one implementation and one
place to fix a bug. It asserts what those constants say before overriding them, because
setting an attribute on a module always succeeds — a silent failure there would leave me
running under the *art* side's fence, refused on my own cards and free on theirs.

The five bucket titles and their order are **the owner's board as it already existed**, read
off the live view rather than chosen: **`To-Do` carries a hyphen** and **Test sits before
Blocked**. A board a human has already arranged wins over a list in a sentence.

---

## The workflow the tools are shaped for

The owner's words: *"ready the card. do the work, check the card for updated, add your
updated."*

```
show KEY      before starting -- read what the card says NOW, not what you remember
...do the work...
show KEY      again -- someone may have written to it while you worked
append KEY    add yours to the end
```

**`append` exists so that reading and writing cannot race into a clobber.** It stamps
`[game-code YYYY-MM-DD]` and adds to the end. `set` replaces a description outright and
demands `--replace` spelled out, because a card is a shared document and losing somebody's
note is silent.

## Why the sync went

**A sync is not a scoped write.** A bare `vikunja_sync.py` PATCHed the title, description,
priority, labels and done flag of **every** card in `board.json` — 65 of them, both agents'
alike. There was no way to touch one card, so every edit was a whole-board write. That is
most of what *"the two agents are updating over each other"* actually was, and it was not
carelessness: the tool offered no smaller unit.

**It nearly undid an owner's decision.** `9.5`'s `game-code` label was deliberately stripped
to mean *"this one is mine, and when we work on it is my call"*. The manifest still said
`game-code`, so the next bare sync would have put it straight back — silently, as one line
of a 64-card run.

**And `board.json` was a second source of truth.** It drifted, which is the same failure this
project has now had four times: `ASSET_MISSING.md`, `PROGRESS.md`, `UI_Design.md`, and the
board's own descriptions seeded from a PLAN.md that had already moved on.

**One thing the sync was wrongly suspected of, measured before it was retired**, and worth
keeping because the conclusion outlived the tool: a card hand-placed away from its seed
bucket **did** survive a bare sync, *including* one that genuinely changed its description —
the second half matters, because an unchanged PATCH answers 304 and proves nothing about the
case you care about. Probe: P5, seeded `To-Do`, parked in `Test`, description edited, synced;
it stayed in `Test`. **What moved cards was the other agent, not the script.** Both of us
write to this board, neither can see the other do it, and Vikunja shows no history — so a
card that moved on its own is far more likely to be a colleague than a bug.

---

## Which document is the authority for what

This repo has paid four times for a second list nobody kept in step, so:

| Document | Owns | Does not own |
|---|---|---|
| **PLAN.md** | architecture, phase order, the numbered rows, and every *why* | status |
| **asset_request.md** | the art conversation, request and answer in place | status |
| **BUGS.md** | the owner's playtest findings and the behaviour they want | status |
| **the Vikunja board** | **status, and only status** — which column a card is in | reasoning |
| ~~PROGRESS.md~~ | *deleted 2026-09-01* | |
| ~~board.json~~ | *deleted 2026-09-01* | |

**PLAN.md is no longer updated as work lands.** The owner asks for those updates themselves,
at a major commit — *"i will manually request updates to plan.md when we commit major
changes."* It stays the authority for architecture and reasoning, and **where the board and
PLAN.md disagree, PLAN.md wins and the board is the one to fix.**

**`PROGRESS.md` was deleted 2026-09-01.** Seven references survive and four are active false
claims rather than dead links: `README.md:33` and `Docs/README.md:18` still say *"PROGRESS.md
is the status document"*, `README.md:177` calls it *"the authoritative version"*, and
`asset_request.md:14` says its priority table is *"derived from PROGRESS.md"*. **Fix those
four first** if either README is opened: a wrong pointer costs more than a broken one.

## What a card's description is for

The **traps and measured figures that make the row expensive to start cold** — not a summary
of PLAN.md. A card says *"a pinned seed is not a pinned map"* because whoever picks up 15.1
needs that in front of them; it does not restate what 15.1 is, because PLAN.md does.

The rule: **if the sentence would be equally true a year from now and cost someone a day to
rediscover, it belongs on the card.**

## The key is the identity

A card's title is `<key> - <title>`, and both tools match on the key. **Renaming a card is
free; renumbering a key makes it a different card.** PLAN.md's §15 header records that its
numbered list has been renumbered twice and that cross-references drifted both times — which
is why the keys are the board's and not PLAN.md's line numbering.

## Labels are the fence, and the fence is enforced in code

`game-code` is the game agent's. `art` is the art agent's. Each tool refuses the other side
outright — column, description, title, all of it — and **there is no override flag in
either, deliberately**: `Diplomacy.is_enemy`'s required team argument is the precedent this
repo already argues from, that a rule which can be left out is a rule that is off somewhere.

`owner-decision` and `blocked-on-art` are **cross-cutting and say nothing about who may
write a card** — read the `game-code`/`art` label beside them.

⚠️ **A DUAL-LABELLED CARD IS UNWRITABLE FROM BOTH TOOLS, BY DESIGN.** Two labels means two
agents each with a defensible claim. **A tag swap is the OWNER's**, done in the Vikunja UI,
and neither tool has a command for it on purpose. `P7-footprint` was the one such card and
the owner resolved it to `game-code` on 2026-09-01.

One board rather than two projects, because *"5.7 is blocked on the art side's A.10"* is the
single most useful thing either agent can read here. **Read the whole board; write only your
own half of it.**

## Where this lives

`kanban/` belongs to neither side of `AGENT_GAME_CODER.md` §1 — not `game/`, not `tools/`.
It is project infrastructure added at the owner's request, and each agent owns its own tool
in it: `card.py` is the art agent's and is not the game agent's to edit, which is why
`card_game.py` wraps it rather than widening it.

## The token

`Vikunja_API_KEY` in `./.env`, **gitignored as of 2026-09-01** — it was not before, and
`origin` is a public GitHub repo, so it was one `git add -A` from a published credential. A
Vikunja token grants read+write on every project its issuing user can see; there is no
scoping it to one board.

Tokens carry a **mandatory expiry**, so re-minting is routine rather than a broken board:
*avatar → Settings → API Tokens → Create*, read+write on Projects, Tasks and Labels. Both
tools print those steps on a 401 rather than a stack trace.

## API notes, confirmed against this instance rather than remembered

Server is **Vikunja v2.6.0**; `/api/v1` and `/api/v2` are both live and the schema is at
`/api/v2/openapi.json`.

- ⚠️ **EVERY LIST RESPONSE IS WRAPPED IN A PAGINATION ENVELOPE** — `{"items": [...],
  "total": n, "page": 1}` — where v1 returned a bare array. **This one cost a duplicate
  project.** Testing `isinstance(payload, list)` is simply `False` for a dict, so a server
  holding three projects read as holding none and a second `AOD_Mobile` was created beside
  the owner's `AOD_mobile`. (Deleted; it was empty.) Never index a response directly.
- **v2 creates with `POST`**, but **updates with `PUT`/`PATCH` and there is no `POST` on the
  update routes at all.** v1 used `POST /tasks/{id}`, and most examples in the wild are v1.
  Use `PATCH` for a task: a `PUT` full-replace would restate `bucket_id` and `position`.
- **Buckets live under a view**, not a project: `POST /projects/{p}/views/{v}/buckets`.
- ⚠️ **`GET /projects/{p}/views/{v}/tasks` DOES NOT POPULATE `bucket_id`**, and
  `GET .../buckets` reports `count: 0` for every bucket. Both look exactly like an empty
  board. **`GET .../buckets/tasks` is the only authoritative bucket→task mapping.**
- **`done_bucket_id` and `default_bucket_id` are fields on the VIEW.** They are what make
  dragging a card into Done actually *complete* it. Without them the five columns look right
  and behave like five arbitrary lists. **Measured: they fire on an API bucket-move too**,
  not only on a drag — so a `move` into Done sets `done` without help.
- **Vikunja answers `304 Not Modified` to a PATCH whose fields already hold the values
  sent**, and urllib raises that as an error. It is a success; treat it as one.
- **A page is capped at 50** (`max_items_per_page`), so anything listing tasks must page or
  ask for more and check what it got.
- ⚠️ **DO NOT JUDGE THE BOARD'S TEXT THROUGH POWERSHELL.** `Invoke-RestMethod` decodes a
  charset-less response as ISO-8859-1, printing `campaign â scenario 3` for a card the
  server stores with a correct em dash — and it writes that corruption back on a PATCH.
  Both tools are Python for this reason. `AGENT_GAME_CODER.md` §2's *"a `Get-Content` dump
  is not evidence"* extends to every console dump of an HTTP response.
