# AI PLayer difficulty

## Passive
 - Focus on building and defending.
 - never attack or builds military units.
 - never builds defense buildings (towers).
 - can build gates and walls.
 - never ages up past age 2.

## Easy (default)
 - Focus on building and defending.
 - can attacks after 5min game time followed by random follow-up attacks.
 - can age up to age 2.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers max 1).

## Normal
 - Focus on building and defending.
 - can attacks after 3.5min game time followed by random follow-up attacks.
 - can age up to age 3.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers max 5).

## Hard
 - Focus on strong economy followed by continues attacks.
 - can attacks after eco has been established.
 - can age up to age 4.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers, castles).

## Unfair
 - starts with 8 villagers and 2 swordsmen and 1 scout.
 - Focus on strong economy followed by continues attacks.
 - can attacks after eco has been established.
 - can age up to age 4.
 - can use tech tree upgrades.
 - can build gates and walls.
 - can build defense buildings (towers, castles).

# Game type — where the army is sent

Difficulty decides **when** a bot commits its army and how big that army has to be
first. The game type decides **where** that army goes. Every difficulty follows the
same blueprint, and no difficulty has its own copy of it — the bot asks the world
what match this is.

| Game type | The army is sent to | It is doing |
|---|---|---|
| Last Man Standing | the nearest enemy | attacking |
| Trophy | its own dragon | guarding |
| King of the Hill | the hill | occupying |
| Scenario | the nearest enemy | attacking |

 - **Trophy is a turtle.** There is no separate guard order and none is needed: a
   military unit defaults to Defensive stance, which makes it fight anything within
   5 tiles of where it stands and walk back afterwards. So standing on the dragon
   *is* guarding it.
 - **King of the Hill is an occupation, not a fight.** Standing inside the zone is
   exactly what scores, so the move order and the win condition are the same act.
 - A bot guards **its own** dragon, never somebody else's.
 - Idle soldiers are sent back to the station, not back at the enemy — otherwise the
   bot would walk away from what it is holding and never come back. Soldiers already
   on station are left alone.
 - If a match failed to place a trophy or a hill, that bot **attacks instead**: an
   unarmed match is decided by elimination, so turtling would mean standing still in
   a match being settled by a rule it was ignoring.

## When the army commits — two gates, both per game type

The army is committed by the attack rule, and **two** conditions stand in front of it:
a clock, and an army size. Both were written for conquest, and three of the four game
types are not conquest, so a difficulty may give a game type its own value for each.

| Difficulty | Last Man Standing / Scenario | Trophy | King of the Hill |
|---|---|---|---|
| Passive | never — no attack rule, and it never trains a soldier | — | — |
| Easy (default) | 5 min **and** 5 swordsmen | at once, with anything | 1.5 min, with anything |
| Normal | 3.5 min **and** 4 swordsmen | at once, with anything | 1 min, with anything |
| Hard | 12 villagers, mill, barracks, 8 swordsmen | at once, with anything | at once, with anything |
| Unfair | 10 villagers, barracks, 6 swordsmen | at once, with anything | at once, with anything |

 - Each game-type value **replaces** the difficulty's own rather than adding to it — a
   game type is allowed to commit *earlier* and *lighter* than the opening, which is
   the whole reason both knobs exist.
 - **"With anything" cannot mean "with nothing".** The floor is that the bot must have
   a military unit to send at all; with none, no order is issued and the rule simply
   has not fired yet.
 - Hard and Unfair have no clock to move — they commit when the economy gate lands —
   so they set only the army size.
 - Both knobs move **aggression only**. Gathering, building and ageing are untouched
   by the game type.

**Why holding ground is not attacking.** Five swordsmen is a number about surviving a
fight at somebody's base. The hill is empty ground that pays by the tick, so a lone
scout standing on it out-scores an army still in the barracks — and unlike a committed
attack, it can walk away again. The same sentence covers Trophy: the thing it guards
can be killed in the first minute, so *"leaves its dragon alone for five minutes"* is
not a difficulty, it is a different loss condition. Guarding is defending, which is
the stated focus of every level on this page.

**The measurements this came from, both on 2026-09-11.** A hill match is won at 9,000
points and a side holding the hill alone scores 3 a tick, so **the fastest possible
match is 5 minutes.**

| | bot first on the hill |
|---|---|
| conquest clock, conquest army | **never** — a playtest ended 9,000 to 0 |
| hill clock, conquest army | **t5621 — 9.4 min** (barracks t4030, 5th swordsman t5540) |
| hill clock, hill army | **t941 — 1.6 min**, and the match resolved at t4084 |

The middle row is the one worth remembering: the clock was fixed, nothing visibly
changed, and the reason was the *other* gate. A bot whose gates outlast the match
cannot lose the hill — it can only fail to turn up.

*Ruled by the project owner on 2026-09-11: halve every attack clock, then per-mode
values in each profile for granular tuning. The knobs are `mode_after_ticks` and
`mode_at_least` in `game/data/ai_<level>.json`; tests refuse a clock that would let a
bot arrive after its own hill match can be over, refuse any level that waits for an
army before holding ground, and refuse any level that would attack a base with
nothing.*

*To watch it yourself:* `preview_ai_match.tscn -- --mode koth --levels easy,easy`